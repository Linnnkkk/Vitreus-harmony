import { rcp } from '@kit.RemoteCommunicationKit';
import { webview } from '@kit.ArkWeb';
import { util } from '@kit.ArkTS';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import url from '@ohos.url';
import { RemoteResponse, RemoteRequester } from './RemoteCapture';

interface DigestChallenge {
  realm: string;
  nonce: string;
  opaque: string;
  stale: boolean;
}

// 系统请求通道。RCP 的 autoRedirect:false（API11）阻止 Authorization/Cookie
// 被自动转发至其他源；NetworkKit 的 maxRedirects 直到 API23 才可用。
// 每个 requester 复用已协商认证；Cookie 登录仍优先于首次口令协商。
export class NativeRemoteRequester {
  private serverURL: string;
  private origin: string;
  private user: string;
  private pwd: string;
  private basic: boolean = false;
  private digest: DigestChallenge | undefined = undefined;
  private nonceCount: number = 0;
  // ignis 对同一 nonce 要求 nc 严格递增，串行化避免请求抵达顺序相反。
  private queue: Promise<void> = Promise.resolve();

  constructor(serverURL: string, user: string, pwd: string) {
    this.serverURL = serverURL.trim().replace(/\/+$/, '');
    this.origin = '';
    try {
      const parsed = new url.URL(this.serverURL);
      if ((parsed.protocol === 'http:' || parsed.protocol === 'https:') &&
        parsed.username === '' && parsed.password === '' && parsed.search === '' && parsed.hash === '') {
        this.origin = parsed.origin;
      }
    } catch (e) {
      // 无效地址在发送前拒绝，不读取 Cookie、不发送凭据。
    }
    this.user = user;
    this.pwd = pwd;
  }

  request(method: string, route: string, body: string): Promise<RemoteResponse> {
    const result = this.queue.then(() => this.requestSerial(method, route, body));
    this.queue = result.then(() => {}, () => {});
    return result;
  }

  private async requestSerial(method: string, route: string, body: string): Promise<RemoteResponse> {
    try {
      // route 必须为本服务器的绝对路径，不接受 URL、协议相对地址或反斜杠。
      if (this.origin === '' || route.charAt(0) !== '/' || route.indexOf('//') === 0 ||
        route.indexOf('\\') >= 0 || /[\r\n#]/.test(route)) {
        return NativeRemoteRequester.failure('无效的远程请求地址');
      }
      const target = new url.URL(this.serverURL + route);
      if (target.origin !== this.origin) {
        return NativeRemoteRequester.failure('已阻止跨源远程请求');
      }
      const uri = target.pathname + target.search;
      let authorization = this.authorization(method, uri);
      let response = await this.send(method, target.toString(), body, authorization);
      if (response.status !== 401 || this.user === '' || this.pwd === '') {
        return response;
      }
      const challenge = response.authChallenge ?? '';
      const digest = NativeRemoteRequester.parseDigest(challenge);
      // 已带认证仍被拒绝时只允许一次 stale 刷新，不反复试错以免触发服务器锁定。
      if (authorization !== '' && (digest === undefined || !digest.stale)) {
        this.basic = false;
        this.digest = undefined;
        return response;
      }
      if (digest !== undefined) {
        this.digest = digest;
        this.basic = false;
        this.nonceCount = 0;
      } else if (authorization === '' && /^Basic\s/i.test(challenge.trim())) {
        this.basic = true;
        this.digest = undefined;
      } else {
        return response;
      }
      authorization = this.authorization(method, uri);
      response = await this.send(method, target.toString(), body, authorization);
      // 首次协商后也至多再刷新一次 stale；全程最多三次发送。
      const refreshed = NativeRemoteRequester.parseDigest(response.authChallenge ?? '');
      if (response.status === 401 && refreshed !== undefined && refreshed.stale && digest !== undefined && !digest.stale) {
        this.digest = refreshed;
        this.nonceCount = 0;
        response = await this.send(method, target.toString(), body, this.authorization(method, uri));
      }
      if (response.status === 401) {
        this.basic = false;
        this.digest = undefined;
      }
      return response;
    } catch (e) {
      return NativeRemoteRequester.failure('远程请求失败：' + String(e));
    }
  }

  private authorization(method: string, uri: string): string {
    if (this.user === '' || this.pwd === '') {
      return '';
    }
    if (this.basic) {
      return 'Basic ' + new util.Base64Helper().encodeToStringSync(
        new util.TextEncoder().encode(this.user + ':' + this.pwd));
    }
    const d = this.digest;
    if (d === undefined) {
      return '';
    }
    this.nonceCount += 1;
    const nc = this.nonceCount.toString(16).padStart(8, '0');
    const cnonce = NativeRemoteRequester.hex(cryptoFramework.createRandom().generateRandomSync(16).data);
    // ignis digest-auth.js 用 Node UTF-8 md5(user:realm:pwd)，头用户名也发 UTF-8。
    const ha1 = NativeRemoteRequester.md5(this.user + ':' + d.realm + ':' + this.pwd);
    const ha2 = NativeRemoteRequester.md5(method + ':' + uri);
    const response = NativeRemoteRequester.md5(ha1 + ':' + d.nonce + ':' + nc + ':' + cnonce + ':auth:' + ha2);
    let value = 'Digest username=' + NativeRemoteRequester.quoted(this.user) +
      ', realm=' + NativeRemoteRequester.quoted(d.realm) + ', nonce=' + NativeRemoteRequester.quoted(d.nonce) +
      ', uri=' + NativeRemoteRequester.quoted(uri) + ', algorithm=MD5, qop=auth, nc=' + nc +
      ', cnonce=' + NativeRemoteRequester.quoted(cnonce) + ', response="' + response + '"';
    if (d.opaque !== '') {
      value += ', opaque=' + NativeRemoteRequester.quoted(d.opaque);
    }
    return value;
  }

  private static parseDigest(challenge: string): DigestChallenge | undefined {
    if (!/^Digest\s/i.test(challenge.trim())) {
      return undefined;
    }
    const fields: Record<string, string> = {};
    const re = /(\w+)\s*=\s*(?:"((?:\\.|[^"\\])*)"|([^\s,]+))/g;
    let match: RegExpExecArray | null = re.exec(challenge);
    while (match !== null) {
      fields[match[1].toLowerCase()] = match[2] !== undefined ? match[2].replace(/\\(.)/g, '$1') : match[3];
      match = re.exec(challenge);
    }
    const qops = (fields['qop'] ?? '').toLowerCase().split(',').map((q: string) => q.trim());
    if (fields['realm'] === undefined || !fields['nonce'] ||
      (fields['algorithm'] ?? 'MD5').toUpperCase() !== 'MD5' || qops.indexOf('auth') < 0) {
      return undefined;
    }
    return { realm: fields['realm'], nonce: fields['nonce'], opaque: fields['opaque'] ?? '',
      stale: (fields['stale'] ?? '').toLowerCase() === 'true' };
  }

  private static quoted(value: string): string {
    if (/[\r\n]/.test(value)) {
      throw new Error('认证字段包含非法换行');
    }
    return '"' + value.replace(/\\/g, '\\\\').replace(/"/g, '\\"') + '"';
  }

  private static md5(value: string): string {
    const md = cryptoFramework.createMd('MD5');
    md.updateSync({ data: new util.TextEncoder().encode(value) });
    return NativeRemoteRequester.hex(md.digestSync().data);
  }

  private static hex(bytes: Uint8Array): string {
    let text = '';
    for (let i = 0; i < bytes.length; i++) {
      text += bytes[i].toString(16).padStart(2, '0');
    }
    return text;
  }

  private async send(method: string, target: string, body: string, authorization: string): Promise<RemoteResponse> {
    const headers: rcp.RequestHeaders = {};
    if (method === 'POST') {
      headers['Content-Type'] = 'application/json';
    }
    if (authorization !== '') {
      headers['Authorization'] = authorization;
    }
    const cookie = await NativeRemoteRequester.cookieFor(target);
    if (cookie !== '') {
      headers['Cookie'] = cookie;
    }
    const session = rcp.createSession();
    try {
      const request = new rcp.Request(target, method, headers);
      request.configuration = { transfer: { autoRedirect: false,
        timeout: { connectMs: 8000, transferMs: 15000 } } };
      if (body !== '') {
        request.content = body;
      }
      const response = await session.fetch(request);
      const out: RemoteResponse = {
        status: response.statusCode,
        body: response.toString() ?? '',
        contentType: NativeRemoteRequester.headerValue(response.headers, 'content-type'),
        error: response.statusCode >= 300 && response.statusCode < 400 ? '服务器返回重定向；为保护凭据已停止跟随' : '',
        authChallenge: NativeRemoteRequester.headerValue(response.headers, 'www-authenticate')
      };
      return out;
    } catch (e) {
      return NativeRemoteRequester.failure(String(e));
    } finally {
      session.close();
    }
  }

  private static failure(error: string): RemoteResponse {
    return { status: 0, body: '', contentType: '', error: error, authChallenge: '' };
  }

  private static headerValue(headers: rcp.ResponseHeaders, name: string): string {
    for (const key of Object.keys(headers)) {
      if (key.toLowerCase() === name) {
        const value = headers[key];
        return Array.isArray(value) ? value.join(', ') : (value ?? '');
      }
    }
    return '';
  }

  // 复用主界面 WebView 登录态；无账号密码也照常发送 Cookie，401 原样交给上层。
  private static async cookieFor(target: string): Promise<string> {
    try {
      return (await webview.WebCookieManager.fetchCookie(target)) ?? '';
    } catch (e) {
      return '';
    }
  }
}

export function createNativeRemoteRequester(serverURL: string, user: string, pwd: string): RemoteRequester {
  const requester = new NativeRemoteRequester(serverURL, user, pwd);
  return (method: string, route: string, body: string): Promise<RemoteResponse> =>
    requester.request(method, route, body);
}
