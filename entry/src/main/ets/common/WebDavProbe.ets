import { rcp } from '@kit.RemoteCommunicationKit';
import util from '@ohos.util';
import { BusinessError } from '@kit.BasicServicesKit';

export interface WebDavProbeResult {
  ok: boolean;
  message: string;
}

// Only fixed messages leave this boundary: server bodies, URLs and credentials are never logged or displayed.
export class WebDavProbe {
  static inspect(code: number, body: string): WebDavProbeResult {
    if (code === 401) { return { ok: false, message: '认证失败，请检查账号和密码（HTTP 401）' }; }
    if (code === 403) { return { ok: false, message: '账号没有访问此目录的权限（HTTP 403）' }; }
    if (code === 404) { return { ok: false, message: '目录不存在，请检查 WebDAV 地址（HTTP 404）' }; }
    if (code === 405 || code === 501) { return { ok: false, message: '服务器不支持 PROPFIND，请填写 WebDAV 目录地址' }; }
    if (code >= 300 && code < 400) { return { ok: false, message: '服务器要求跳转，请填写最终的 WebDAV 目录地址' }; }
    if (code !== 207) { return { ok: false, message: 'WebDAV 验证失败（HTTP ' + code.toString() + '），需要 207 响应' }; }
    // Depth:0 must describe exactly the requested directory. A collection in an unsuccessful propstat is not evidence.
    if (/<!DOCTYPE|<!ENTITY/i.test(body) || !/<(?:[\w.-]+:)?multistatus\b/i.test(body)) {
      return { ok: false, message: '服务器返回的不是有效 WebDAV 目录信息' };
    }
    const responses = body.match(/<(?:[\w.-]+:)?response\b[^>]*>[\s\S]*?<\/(?:[\w.-]+:)?response\s*>/gi);
    if (responses === null || responses.length !== 1) {
      return { ok: false, message: '服务器没有返回所请求目录的 Depth:0 信息' };
    }
    const props = responses[0].match(/<(?:[\w.-]+:)?propstat\b[^>]*>[\s\S]*?<\/(?:[\w.-]+:)?propstat\s*>/gi);
    if (props !== null) {
      for (let i = 0; i < props.length; i++) {
        if (/<(?:[\w.-]+:)?status\b[^>]*>\s*HTTP\/\d(?:\.\d)?\s+200\b/i.test(props[i]) &&
          /<(?:[\w.-]+:)?resourcetype\b[^>]*>\s*<(?:[\w.-]+:)?collection\b[^>]*\/?\s*>\s*(?:<\/(?:[\w.-]+:)?collection\s*>\s*)?<\/(?:[\w.-]+:)?resourcetype\s*>/i.test(props[i])) {
          return { ok: true, message: '连接成功：账号已认证，目标是可访问的 WebDAV 目录' };
        }
      }
    }
    return { ok: false, message: '目标不是可访问的目录，或服务器未提供目录属性' };
  }

  static async test(url: string, user: string, pwd: string): Promise<WebDavProbeResult> {
    const client = rcp.createSession({ requestConfiguration: {
      transfer: { timeout: { connectMs: 8000, transferMs: 10000 } }
    } });
    try {
      const auth = new util.Base64Helper().encodeToStringSync(new util.TextEncoder().encode(user + ':' + pwd));
      const headers: rcp.RequestHeaders = { 'Authorization': 'Basic ' + auth, 'Depth': '0',
        'Content-Type': 'application/xml; charset=utf-8' };
      const request = new rcp.Request(url + '/', 'PROPFIND', headers,
        '<?xml version="1.0" encoding="utf-8"?><d:propfind xmlns:d="DAV:"><d:prop><d:resourcetype/></d:prop></d:propfind>');
      const response = await client.fetch(request);
      return WebDavProbe.inspect(response.statusCode, response.toString() ?? '');
    } catch (e) {
      const error = e as BusinessError;
      if (error.code === 2300028) { return { ok: false, message: '连接超时，请检查网络和服务器后重试' }; }
      return { ok: false, message: '连接失败，请检查网络、服务器地址和 HTTPS 证书；当前系统须支持 PROPFIND 请求' };
    } finally {
      client.close();
    }
  }
}
