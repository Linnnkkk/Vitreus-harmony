import { webview } from '@kit.ArkWeb';
import { common } from '@kit.AbilityKit';
import { fileIo as fs, picker } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';

interface PdfMargins { top?: number; bottom?: number; left?: number; right?: number; }
interface PdfPageSize { width: number; height: number; }
interface PdfOptions {
  pageSize?: string | PdfPageSize;
  landscape?: boolean;
  margins?: PdfMargins;
  printBackground?: boolean;
  scale?: number;
}
interface PdfPayload { html: string; baseUrl: string; filename: string; options?: PdfOptions; }
interface PdfResult { ok: boolean; path: string; error: string; canceled: boolean; }
interface PdfJob {
  id: number;
  token: number;
  documentUrl: string;
  filename: string;
  config: webview.PdfConfiguration;
  rendering: boolean;
}

// One instance per main Web. The helper Web must remain laid out behind it.
export class PdfExport {
  readonly controller: webview.WebviewController = new webview.WebviewController();
  private main: webview.WebviewController;
  private context: () => common.UIAbilityContext;
  private available: () => boolean;
  private trusted: (url: string) => boolean;
  private job: PdfJob | null = null;
  private serial: number = 0;
  private deadline: number = -1;
  private pollTimer: number = -1;
  private polling: boolean = false;
  private saving: boolean = false;

  constructor(main: webview.WebviewController, context: () => common.UIAbilityContext,
    available: () => boolean, trusted: (url: string) => boolean) {
    this.main = main;
    this.context = context;
    this.available = available;
    this.trusted = trusted;
  }

  export(id: number, payload: string): void {
    if (!Number.isSafeInteger(id) || id < 0) { return; }
    let documentUrl = '';
    try {
      documentUrl = this.main.getUrl();
      // Read synchronously while inside the proxy call: a later call can replace this value.
      const caller = this.main.getLastJavascriptProxyCallingFrameUrl();
      if (!this.available() || !this.trusted(documentUrl) || caller !== documentUrl) {
        this.reply(id, documentUrl, { ok: false, path: '', error: 'PDF export source is not trusted', canceled: false });
        return;
      }
    } catch (e) {
      this.reply(id, documentUrl, { ok: false, path: '', error: 'Cannot verify PDF export source', canceled: false });
      return;
    }
    if (this.job !== null || this.saving) {
      this.reply(id, documentUrl, { ok: false, path: '', error: 'Another PDF export is in progress', canceled: false });
      return;
    }
    try {
      const data = JSON.parse(payload) as PdfPayload;
      if (data === null || typeof data.html !== 'string' || data.html.trim() === '' ||
        typeof data.baseUrl !== 'string' || !this.trusted(data.baseUrl) || typeof data.filename !== 'string') {
        throw new Error('Invalid PDF document');
      }
      const config = this.configuration(data.options);
      const token = ++this.serial;
      const filename = data.filename.replace(/[\\/\u0000-\u001f:*?"<>|]/g, '_').replace(/\.pdf$/i, '').trim() || 'document';
      this.job = { id: id, token: token, documentUrl: documentUrl, filename: filename + '.pdf', config: config, rendering: false };
      this.deadline = setTimeout(() => { this.fail(token, 'PDF export timed out'); }, 120000);
      const marker = '<meta name="vitreus-pdf-job" content="' + token.toString() + '">';
      const html = /<head(?:\s[^>]*)?>/i.test(data.html) ?
        data.html.replace(/<head(?:\s[^>]*)?>/i, (head: string): string => head + marker) : marker + data.html;
      this.controller.loadData(html, 'text/html', 'UTF-8', data.baseUrl);
    } catch (e) {
      if (this.job !== null) { this.fail(this.job.token, (e as Error).message); }
      else { this.reply(id, documentUrl, { ok: false, path: '', error: (e as Error).message, canceled: false }); }
    }
  }

  onPageEnd(): void {
    const job = this.job;
    if (job === null || job.rendering || this.pollTimer !== -1) { return; }
    // Store readiness in the document; runJavaScript does not await a JS Promise on every ArkWeb version.
    const script = `(function(){var m=document.querySelector('meta[name="vitreus-pdf-job"]');if(!m||m.content!==${JSON.stringify(job.token.toString())})return;window.__vtPdfReady='waiting';var images=Array.from(document.images);images.forEach(function(i){i.loading='eager';});var timer=setTimeout(function(){window.__vtPdfReady='error:PDF resources timed out';},25000);Promise.all([document.fonts.ready,Promise.all(images.map(function(i){return new Promise(function(resolve,reject){if(i.complete){i.naturalWidth>0?resolve():reject(new Error('Image failed to load'));return;}i.addEventListener('load',function(){i.naturalWidth>0?resolve():reject(new Error('Empty image'));},{once:true});i.addEventListener('error',function(){reject(new Error('Image failed to load'));},{once:true});});}))]).then(function(){if(window.__vtPdfReady!=='waiting')return;document.fonts.forEach(function(font){if(font.status==='error')throw new Error('Font failed to load');});if(!document.body||(!document.body.innerText.trim()&&!document.querySelector('img,svg,canvas,video'))){throw new Error('PDF document is empty');}requestAnimationFrame(function(){requestAnimationFrame(function(){if(window.__vtPdfReady==='waiting'){clearTimeout(timer);window.__vtPdfReady='ready';}});});}).catch(function(e){clearTimeout(timer);window.__vtPdfReady='error:'+e.message;});})()`;
    this.controller.runJavaScript(script).then(() => {
      if (!this.current(job.token)) { return; }
      if (this.pollTimer === -1) { this.pollTimer = setInterval(() => { this.poll(job.token); }, 150); }
    }).catch(() => { this.fail(job.token, 'Cannot prepare PDF document'); });
  }

  cancel(reason: string): void {
    if (this.job !== null) { this.fail(this.job.token, reason, true); }
  }

  private current(token: number): boolean {
    if (this.job === null || this.job.token !== token) { return false; }
    try { return this.available() && this.main.getUrl() === this.job.documentUrl; }
    catch (e) { return false; }
  }

  private async poll(token: number): Promise<void> {
    if (this.polling) { return; }
    if (!this.current(token)) { this.fail(token, 'PDF page is no longer active', true); return; }
    this.polling = true;
    try {
      const state = await this.controller.runJavaScript('(function(){var m=document.querySelector(\'meta[name="vitreus-pdf-job"]\');return m&&m.content===' + JSON.stringify(token.toString()) + '?String(window.__vtPdfReady||"waiting"):"waiting";})()');
      if (!this.current(token)) { return; }
      const value = state.replace(/^"|"$/g, '');
      if (value.indexOf('error:') === 0) { this.fail(token, value.substring(6)); }
      else if (value === 'ready') {
        this.stopPolling();
        this.save(token);
      }
    } catch (e) { this.fail(token, 'PDF renderer is unavailable'); }
    finally { this.polling = false; }
  }

  private async save(token: number): Promise<void> {
    const job = this.job;
    if (job === null || job.token !== token || job.rendering) { return; }
    job.rendering = true;
    this.saving = true;
    try {
      const result = await this.controller.createPdf(job.config);
      if (!this.current(token)) { return; }
      const bytes = result.pdfArrayBuffer();
      if (bytes.byteLength < 8 || bytes[0] !== 37 || bytes[1] !== 80 || bytes[2] !== 68 || bytes[3] !== 70 || bytes[4] !== 45) {
        throw new Error('PDF renderer returned invalid or empty data');
      }
      const options = new picker.DocumentSaveOptions();
      options.newFileNames = [job.filename];
      const uris = await new picker.DocumentViewPicker(this.context()).save(options);
      if (!this.current(token)) { return; }
      if (uris.length === 0 || uris[0] === '') { this.fail(token, 'PDF save canceled', true); return; }
      const uri = uris[0];
      // Write only the view's bytes, then close successfully before reporting completion.
      const buffer = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength);
      const file = fs.openSync(uri, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      try {
        const written = fs.writeSync(file.fd, buffer);
        if (written !== bytes.byteLength || fs.statSync(file.fd).size !== bytes.byteLength) {
          throw new Error('PDF write was incomplete');
        }
        fs.fsyncSync(file.fd);
      } finally { fs.closeSync(file); }
      if (this.current(token)) { this.finish(token, { ok: true, path: uri, error: '', canceled: false }); }
    } catch (e) {
      const error = e as BusinessError;
      this.fail(token, error.message || 'PDF export failed', error.code === 13900042);
    } finally { this.saving = false; }
  }

  private stopPolling(): void {
    if (this.pollTimer !== -1) { clearInterval(this.pollTimer); this.pollTimer = -1; }
  }

  private fail(token: number, error: string, canceled: boolean = false): void {
    this.finish(token, { ok: false, path: '', error: error || 'PDF export failed', canceled: canceled });
  }

  private finish(token: number, result: PdfResult): void {
    const job = this.job;
    if (job === null || job.token !== token) { return; }
    this.job = null;
    this.stopPolling();
    if (this.deadline !== -1) { clearTimeout(this.deadline); this.deadline = -1; }
    this.reply(job.id, job.documentUrl, result);
    try { this.controller.loadUrl('about:blank'); } catch (e) { /* Already detached. */ }
  }

  private reply(id: number, documentUrl: string, result: PdfResult): void {
    try {
      if (!this.trusted(documentUrl) || this.main.getUrl() !== documentUrl) { return; }
      this.main.runJavaScript('window.__vitreusPdfResult&&window.__vitreusPdfResult(' + id.toString() + ',' + JSON.stringify(result) + ')').catch(() => {});
    } catch (e) { /* The originating document has been destroyed. */ }
  }

  private configuration(options: PdfOptions | undefined): webview.PdfConfiguration {
    const config: webview.PdfConfiguration = { width: 8.27, height: 11.69,
      marginTop: 0.4, marginBottom: 0.4, marginLeft: 0.4, marginRight: 0.4, shouldPrintBackground: true };
    if (options === undefined || options === null) { return config; }
    const size = options.pageSize;
    if (typeof size === 'string') {
      switch (size.toLowerCase()) {
        case 'a3': config.width = 11.69; config.height = 16.54; break;
        case 'a4': break;
        case 'a5': config.width = 5.83; config.height = 8.27; break;
        case 'letter': config.width = 8.5; config.height = 11; break;
        case 'legal': config.width = 8.5; config.height = 14; break;
        case 'tabloid': config.width = 11; config.height = 17; break;
        case 'ledger': config.width = 17; config.height = 11; break;
        case 'a6': config.width = 4.13; config.height = 5.83; break;
        default: throw new Error('Unsupported PDF page size: ' + size);
      }
    } else if (size !== undefined && size !== null) {
      // Electron custom page sizes are microns; ArkWeb uses inches.
      config.width = size.width / 25400;
      config.height = size.height / 25400;
    }
    if (options.landscape === true) { const width = config.width; config.width = config.height; config.height = width; }
    if (!Number.isFinite(config.width) || !Number.isFinite(config.height) || config.width <= 0 || config.height <= 0) {
      throw new Error('Invalid PDF page dimensions');
    }
    const margins = options.margins;
    if (margins !== undefined && margins !== null) {
      config.marginTop = margins.top ?? 0.4; config.marginBottom = margins.bottom ?? 0.4;
      config.marginLeft = margins.left ?? 0.4; config.marginRight = margins.right ?? 0.4;
    }
    const vertical: number[] = [config.marginTop, config.marginBottom];
    const horizontal: number[] = [config.marginLeft, config.marginRight];
    if (vertical.some((n: number): boolean => !Number.isFinite(n) || n < 0 || n >= config.height / 2) ||
      horizontal.some((n: number): boolean => !Number.isFinite(n) || n < 0 || n >= config.width / 2)) {
      throw new Error('Invalid PDF margins');
    }
    if (options.scale !== undefined) {
      if (!Number.isFinite(options.scale) || options.scale <= 0 || options.scale > 2) { throw new Error('Invalid PDF scale'); }
      config.scale = options.scale;
    }
    config.shouldPrintBackground = options.printBackground !== false;
    return config;
  }
}
