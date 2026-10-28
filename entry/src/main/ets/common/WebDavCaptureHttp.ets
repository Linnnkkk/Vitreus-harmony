import { rcp } from '@kit.RemoteCommunicationKit';
import { util } from '@kit.ArkTS';
import url from '@ohos.url';
import { RemoteRequester, RemoteResponse, RemoteWriteBody } from './RemoteCapture';
import { CapturePathTemplate } from './CapturePathTemplate';
import { WebDavConfig, WebDavSettings } from './WebDavSettings';
import { WebDavProbe } from './WebDavProbe';
import { VipService } from './VipService';

interface DavResponse extends RemoteResponse {
  etag: string;
}

interface ReadProof {
  exists: boolean;
  etag: string;
  content: string;
}

const COLLECTION_QUERY = '<?xml version="1.0" encoding="utf-8"?>' +
  '<d:propfind xmlns:d="DAV:"><d:prop><d:resourcetype/></d:prop></d:propfind>';

// A requester owns its credentials and read proofs in memory only. Serial requests prevent
// two engine operations from consuming the same proof while a DAV mutation is in flight.
class WebDavCaptureRequester {
  private base: string = '';
  private authorization: string = '';
  private vault: string;
  private name: string;
  private proofs: Map<string, ReadProof> = new Map<string, ReadProof>();
  private queue: Promise<void> = Promise.resolve();

  constructor(config: WebDavConfig, user: string, pwd: string, vaultId: string) {
    this.vault = vaultId;
    this.name = config.vaultName;
    try {
      const normalized = WebDavSettings.normalizeUrl(config.url);
      const parsed = new url.URL(normalized);
      if (config.enabled && vaultId !== '' && parsed.username === '' && parsed.password === '' &&
        parsed.search === '' && parsed.hash === '' && (parsed.protocol === 'http:' || parsed.protocol === 'https:')) {
        this.base = normalized;
        this.authorization = 'Basic ' + new util.Base64Helper().encodeToStringSync(
          new util.TextEncoder().encode(user + ':' + pwd));
      }
    } catch (e) {
      // Never expose URL parsing errors, which may include the configured address.
    }
  }

  request(method: string, route: string, body: string): Promise<RemoteResponse> {
    const result = this.queue.then(() => this.requestSerial(method, route, body));
    this.queue = result.then(() => {}, () => {});
    return result;
  }

  private async requestSerial(method: string, route: string, body: string): Promise<RemoteResponse> {
    try {
      if (this.base === '') { return WebDavCaptureRequester.failure('WebDAV 配置无效'); }
      if (method === 'GET' && route === '/api/version') {
        return WebDavCaptureRequester.json(200, JSON.stringify({ version: 'webdav' }));
      }
      if (method === 'GET' && route === '/api/vault/list') {
        const checked = await this.collection('');
        if (checked.status !== 200 || checked.error !== '') { return checked; }
        return WebDavCaptureRequester.json(200, JSON.stringify([{ id: this.vault, name: this.name }]));
      }
      if (method === 'GET' && route.startsWith('/api/fs/readFile?')) {
        const query = this.query(route);
        if (!this.validQuery(query) || query['encoding'] !== 'utf8' ||
          !CapturePathTemplate.validateRelativePath(query['path']).valid) {
          return WebDavCaptureRequester.rejected();
        }
        return await this.read(query['path']);
      }
      if (method === 'DELETE' && route.startsWith('/api/fs/unlink?')) {
        const query = this.query(route);
        if (!this.validQuery(query) || query['encoding'] !== 'utf8' ||
          !CapturePathTemplate.validateRelativePath(query['path']).valid) {
          return WebDavCaptureRequester.rejected();
        }
        if (body !== '') {
          const value = JSON.parse(body) as RemoteWriteBody;
          if (value.vault !== this.vault || value.path !== query['path']) {
            return WebDavCaptureRequester.rejected();
          }
        }
        return await this.mutate(query['path'], '', true, false);
      }
      if (method === 'POST' && (route === '/api/fs/mkdir' || route === '/api/fs/writeFile' ||
        route === '/api/fs/appendFile')) {
        const value = JSON.parse(body) as RemoteWriteBody;
        if (value === null || typeof value.vault !== 'string' || value.vault !== this.vault ||
          typeof value.path !== 'string') { return WebDavCaptureRequester.rejected(); }
        if (route === '/api/fs/mkdir') {
          if (typeof value.recursive !== 'boolean' || !WebDavCaptureRequester.directoryPath(value.path)) {
            return WebDavCaptureRequester.rejected();
          }
          return await this.mkdir(value.path, value.recursive);
        }
        if (typeof value.content !== 'string' || value.encoding !== 'utf8' ||
          !CapturePathTemplate.validateRelativePath(value.path).valid) {
          return WebDavCaptureRequester.rejected();
        }
        return await this.mutate(value.path, value.content, false, route === '/api/fs/appendFile');
      }
      return WebDavCaptureRequester.json(400, '{"error":"Unsupported capture request"}');
    } catch (e) {
      return WebDavCaptureRequester.failure('WebDAV 请求失败，请检查连接和配置');
    }
  }

  private query(route: string): Record<string, string> {
    const values: Record<string, string> = {};
    const parts = route.substring(route.indexOf('?') + 1).split('&');
    for (const part of parts) {
      const at = part.indexOf('=');
      if (at < 1) { throw new Error('Invalid query'); }
      const key = decodeURIComponent(part.substring(0, at).replace(/\+/g, ' '));
      if (key !== 'vault' && key !== 'path' && key !== 'encoding') { throw new Error('Invalid query'); }
      if (values[key] !== undefined) { throw new Error('Duplicate query'); }
      values[key] = decodeURIComponent(part.substring(at + 1).replace(/\+/g, ' '));
    }
    return values;
  }

  private validQuery(query: Record<string, string>): boolean {
    return query['vault'] === this.vault && typeof query['path'] === 'string';
  }

  private static directoryPath(path: string): boolean {
    if (path === '' || path.length > 500 || path.startsWith('/') || path.indexOf('\\') >= 0 ||
      /^[A-Za-z]:/.test(path) || path.indexOf('://') >= 0) { return false; }
    const parts = path.split('/');
    if (parts.length > 32) { return false; }
    for (const part of parts) {
      if (part === '' || part.startsWith('.') || part !== part.trim() || part.length > 120 ||
        /[\x00-\x1f\x7f:*?"<>|\[\]#^{}]/.test(part)) { return false; }
    }
    return true;
  }

  private target(path: string, directory: boolean = false): string {
    const encoded = path.split('/').map((part: string) => encodeURIComponent(part)).join('/');
    return this.base + '/' + encoded + (directory && path !== '' ? '/' : '');
  }

  private async collection(path: string): Promise<RemoteResponse> {
    const headers: rcp.RequestHeaders = { 'Depth': '0', 'Content-Type': 'application/xml; charset=utf-8' };
    const response = await this.send('PROPFIND', this.target(path, true), COLLECTION_QUERY, headers);
    if (response.error !== '') { return response; }
    const checked = WebDavProbe.inspect(response.status, response.body);
    if (!checked.ok) {
      // A malformed 207 must never look like successful directory creation to the engine.
      return WebDavCaptureRequester.json(response.status >= 400 ? response.status : 502,
        JSON.stringify({ error: checked.message }));
    }
    return WebDavCaptureRequester.json(200, '{"ok":true}');
  }

  private async mkdir(path: string, recursive: boolean): Promise<RemoteResponse> {
    const parts = path.split('/');
    const paths: string[] = [];
    if (recursive) {
      for (let i = 1; i <= parts.length; i++) { paths.push(parts.slice(0, i).join('/')); }
    } else { paths.push(path); }
    for (const directory of paths) {
      const response = await this.send('MKCOL', this.target(directory, true), '', {});
      if (response.error !== '') { return response; }
      if (response.status === 405) {
        const checked = await this.collection(directory);
        if (checked.status !== 200 || checked.error !== '') { return checked; }
      } else if (response.status !== 201) {
        return WebDavCaptureRequester.httpFailure(response);
      }
    }
    return WebDavCaptureRequester.json(200, '{"ok":true}');
  }

  private async read(path: string): Promise<RemoteResponse> {
    this.proofs.delete(path);
    const response = await this.send('GET', this.target(path), '', {});
    if (response.error !== '') { return response; }
    if (response.status === 404) {
      this.proofs.set(path, { exists: false, etag: '', content: '' });
      return WebDavCaptureRequester.json(404, '{"code":"ENOENT"}');
    }
    if (response.status !== 200) { return WebDavCaptureRequester.httpFailure(response); }
    this.proofs.set(path, { exists: true, etag: response.etag, content: response.body });
    return { status: 200, body: response.body, contentType: 'text/plain; charset=utf-8', error: '' };
  }

  private async mutate(path: string, content: string, removing: boolean, append: boolean): Promise<RemoteResponse> {
    const proof = this.proofs.get(path);
    // Consume before any await; an unsuccessful/unknown mutation requires a fresh engine read.
    this.proofs.delete(path);
    if (proof === undefined || (removing && !proof.exists) || (append && !proof.exists)) {
      return WebDavCaptureRequester.conflict();
    }
    const headers: rcp.RequestHeaders = {};
    if (!proof.exists) {
      headers['If-None-Match'] = '*';
    } else if (WebDavCaptureRequester.strongEtag(proof.etag)) {
      headers['If-Match'] = proof.etag;
    } else {
      const current = await this.send('GET', this.target(path), '', {});
      if (current.error !== '') { return current; }
      if (current.status !== 200 || current.body !== proof.content) {
        return WebDavCaptureRequester.conflict();
      }
      if (WebDavCaptureRequester.strongEtag(current.etag)) { headers['If-Match'] = current.etag; }
      // Without a strong ETag, equality is a best-effort check, NOT atomic CAS: another
      // client can still edit between this GET and PUT/DELETE. No WebDAV lock is claimed.
    }
    if (!removing) { headers['Content-Type'] = 'text/markdown; charset=utf-8'; }
    const value = append ? proof.content + content : content;
    const response = await this.send(removing ? 'DELETE' : 'PUT', this.target(path), value, headers);
    if (response.error !== '') { return response; }
    // 202/207 do not prove a completed file mutation. Require ordinary DAV completion codes.
    const accepted = removing ? response.status === 200 || response.status === 204 :
      response.status === 200 || response.status === 201 || response.status === 204;
    if (!accepted) { return WebDavCaptureRequester.httpFailure(response); }
    return WebDavCaptureRequester.json(200, '{"ok":true}');
  }

  private async send(method: string, target: string, body: string, headers: rcp.RequestHeaders): Promise<DavResponse> {
    // WebDAV is a member feature; check every real request, including read preflight.
    if (!VipService.isVip()) {
      return { status: 403, body: '{"error":"WebDAV requires membership"}', contentType: 'application/json',
        error: '', etag: '' };
    }
    let session: rcp.Session | undefined = undefined;
    try {
      headers['Authorization'] = this.authorization;
      const request = new rcp.Request(target, method, headers);
      request.configuration = { transfer: { autoRedirect: false,
        timeout: { connectMs: 8000, transferMs: 15000 } } };
      if (body !== '' && method !== 'DELETE') { request.content = body; }
      // An empty PUT still has an explicit UTF-8 string entity.
      if (method === 'PUT') { request.content = body; }
      session = rcp.createSession();
      const response = await session.fetch(request);
      const text = response.toString() ?? '';
      const type = WebDavCaptureRequester.header(response.headers, 'content-type');
      if ((response.statusCode >= 300 && response.statusCode < 400) ||
        /text\/html|application\/xhtml\+xml/i.test(type) ||
        /^\s*(?:<\?xml[^>]*>\s*)?(?:<!doctype\s+html\b|<html\b)/i.test(text)) {
        return { status: response.statusCode, body: '', contentType: '',
          error: 'WebDAV 返回网页或重定向，已停止请求', etag: '' };
      }
      return { status: response.statusCode, body: text, contentType: type, error: '',
        etag: WebDavCaptureRequester.header(response.headers, 'etag') };
    } catch (e) {
      return { status: 0, body: '', contentType: '', error: 'WebDAV 网络请求失败，请检查连接后重试', etag: '' };
    } finally {
      if (session !== undefined) { session.close(); }
    }
  }

  private static header(headers: rcp.ResponseHeaders, name: string): string {
    for (const key of Object.keys(headers)) {
      if (key.toLowerCase() === name) {
        const value = headers[key];
        return Array.isArray(value) ? value.join(', ') : (value ?? '');
      }
    }
    return '';
  }

  private static strongEtag(etag: string): boolean {
    return /^"[\x21\x23-\x7e\x80-\xff]*"$/.test(etag);
  }

  private static json(status: number, body: string): RemoteResponse {
    return { status: status, body: body, contentType: 'application/json', error: '' };
  }

  private static failure(message: string): RemoteResponse {
    return { status: 0, body: '', contentType: '', error: message };
  }

  private static rejected(): RemoteResponse {
    return WebDavCaptureRequester.json(403, '{"error":"Path traversal rejected"}');
  }

  private static conflict(): RemoteResponse {
    return WebDavCaptureRequester.json(412, '{"code":"ESTALE","error":"Read proof missing or changed"}');
  }

  private static httpFailure(response: RemoteResponse): RemoteResponse {
    // Do not pass DAV error documents through to capture records or UI. Unexpected success
    // statuses are failures here, not success-shaped {ok:true} payloads.
    return WebDavCaptureRequester.json(response.status >= 400 ? response.status : 502,
      '{"error":"WebDAV request rejected"}');
  }
}

export function createWebDavCaptureRequester(config: WebDavConfig, user: string, pwd: string,
  vaultId: string): RemoteRequester {
  const requester = new WebDavCaptureRequester(config, user, pwd, vaultId);
  return (method: string, route: string, body: string): Promise<RemoteResponse> =>
    requester.request(method, route, body);
}
