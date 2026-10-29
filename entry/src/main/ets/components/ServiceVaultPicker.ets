import { ServiceVaultApi, ServiceVaultStatus, ServiceVault } from '../common/ServiceVaultApi';
import { AiLanApi } from '../common/AiLanApi';

@Component
export struct ServiceVaultPicker {
  @Prop kind: string = 'srv';
  @Prop @Watch('onVisibilityChanged') visible: boolean = true;
  @State private status: ServiceVaultStatus | null = null;
  @State private vaults: ServiceVault[] = [];
  @State private busy: boolean = false;
  @State private expanded: boolean = false;
  @State private message: string = '';
  private alive: boolean = false;
  private epoch: number = 0;
  // Keep the actual request lock across hide/show, including a POST already in flight.
  private requestBusy: boolean = false;

  aboutToAppear(): void {
    this.alive = true;
    if (this.visible) { this.load(); }
  }

  aboutToDisappear(): void {
    this.alive = false;
    this.epoch++;
  }

  private onVisibilityChanged(): void {
    this.epoch++;
    this.expanded = false;
    if (this.visible && this.alive) { this.load(); }
  }

  private current(epoch: number): boolean {
    return this.alive && this.visible && epoch === this.epoch;
  }

  private defaultVault(): string {
    if (this.status === null) { return ''; }
    return this.kind === 'ai' ? this.status.aiDefaultVault : this.status.srvDefaultVault;
  }

  private summary(): string {
    if (this.status === null) { return this.busy ? '正在读取默认库…' : '默认库待确认'; }
    const configured = this.defaultVault();
    const resolved = this.kind === 'ai' ? this.status.aiResolvedVault : this.status.srvResolvedVault;
    return (configured === '' ? '跟随上次激活' : '默认库：' + configured) + ' · 当前 ' + (resolved === '' ? '无可用库' : resolved);
  }

  private async load(): Promise<void> {
    if (!this.alive || !this.visible || this.requestBusy) { return; }
    this.requestBusy = true;
    this.busy = true;
    const epoch = this.epoch;
    try {
      const status = await ServiceVaultApi.status();
      if (!this.current(epoch)) { return; }
      this.status = status;
      this.vaults = [];
      if (status === null) {
        this.message = '无法读取默认库，请重试。';
        return;
      }
      if (this.kind === 'ai') {
        const ai = await AiLanApi.status();
        if (!this.current(epoch)) { return; }
        if (!AiLanApi.hasAccessPolicy(ai) || ai === null || ai.access === undefined) {
          this.message = '无法确认 AI 授权，请先刷新下方笔记库授权。';
          return;
        }
        const ids = ai.access.vaultIds;
        this.vaults = status.availableVaults.filter((vault: ServiceVault) => ids.indexOf(vault.id) >= 0);
      } else {
        this.vaults = status.availableVaults.slice();
      }
      this.message = this.vaults.length === 0 ? (this.kind === 'ai' ? '请先在下方授权笔记库，再选择 AI 默认库。' : '暂无可选笔记库，请先创建或导入。') : '';
    } catch (error) {
      if (this.current(epoch)) { this.status = null; this.vaults = []; this.message = '无法读取默认库，请重试。'; }
    } finally {
      this.requestBusy = false;
      if (this.current(epoch)) { this.busy = false; }
      else if (this.alive && this.visible) { this.load(); }
    }
  }

  private async toggleExpanded(): Promise<void> {
    if (!this.alive || !this.visible || this.requestBusy) { return; }
    this.getUIContext().animateTo({ duration: 240, curve: Curve.EaseInOut }, () => {
      this.expanded = !this.expanded;
    });
    if (this.expanded) { await this.load(); }
  }

  private async save(vault: string): Promise<void> {
    if (!this.alive || !this.visible || this.requestBusy || this.status === null || this.vaults.length === 0) { return; }
    this.requestBusy = true;
    this.busy = true;
    const epoch = this.epoch;
    try {
      if (this.kind === 'ai') {
        const ai = await AiLanApi.status();
        if (!this.current(epoch)) { return; }
        if (!AiLanApi.hasAccessPolicy(ai) || ai === null || ai.access === undefined) {
          this.vaults = [];
          this.message = '无法确认 AI 授权，请先刷新下方笔记库授权。';
          return;
        }
        const ids = ai.access.vaultIds;
        this.vaults = this.status.availableVaults.filter((item: ServiceVault) => ids.indexOf(item.id) >= 0);
        if (this.vaults.length === 0 || (vault !== '' && ids.indexOf(vault) < 0)) {
          this.message = '该笔记库尚未授权，请先在下方授权后重试。';
          return;
        }
      }
      const result = await ServiceVaultApi.set(this.kind, vault);
      if (!this.current(epoch)) { return; }
      if (result === null) {
        this.status = null;
        this.vaults = [];
        this.message = '保存结果未确认，请重新展开刷新后再试。';
        return;
      }
      this.status = result;
      if (this.defaultVault() !== vault) {
        this.message = '默认库未按选择保存，请刷新后重试。';
        return;
      }
      this.message = '默认库已保存。';
      this.expanded = false;
    } catch (error) {
      if (this.current(epoch)) { this.status = null; this.vaults = []; this.message = '保存结果未确认，请重新展开刷新后再试。'; }
    } finally {
      this.requestBusy = false;
      if (this.current(epoch)) { this.busy = false; }
      else if (this.alive && this.visible) { this.load(); }
    }
  }

  @Builder
  private choice(vault: string, label: string, marker: string) {
    Row() {
      Button({ type: ButtonType.Normal, stateEffect: false }) {
        Row({ space: 8 }) {
          Text(this.defaultVault() === vault ? '✓' : '○').fontSize(14).fontColor('#9FD4DD')
          Text(label).fontSize(13).fontColor('#E2E6F8').layoutWeight(1).textAlign(TextAlign.Start)
          Text(marker).fontSize(11).fontColor('#9EADC7')
        }.width('100%')
      }.width('100%').height(44).padding({ left: 12, right: 12 }).backgroundColor(Color.Transparent)
        .enabled(!this.busy && this.vaults.length > 0).onClick(() => this.save(vault))
    }.width('100%').backgroundColor('rgba(255,255,255,0.04)').borderRadius(10).clip(true)
  }

  build() {
    Column({ space: 12 }) {
      Button({ type: ButtonType.Normal, stateEffect: false }) {
        Row({ space: 8 }) {
          Column({ space: 5 }) {
            Text(this.kind === 'ai' ? 'AI 默认笔记库' : '伺服器默认笔记库')
              .fontSize(16).fontWeight(FontWeight.Medium).fontColor('#F0F3FF').width('100%')
            Text(this.summary()).fontSize(12).lineHeight(18).fontColor('#AEB8DF').width('100%')
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
          Text(this.busy ? '…' : (this.expanded ? '−' : '+')).fontSize(20).fontColor('#B7C8E2')
        }.width('100%')
      }.width('100%').constraintSize({ minHeight: 66 }).padding(0).backgroundColor(Color.Transparent).enabled(!this.busy)
        .onClick(() => this.toggleExpanded())
      if (this.message !== '') {
        Text(this.message).fontSize(12).lineHeight(18).fontColor('#E8C997').width('100%')
      }
      if (this.expanded) {
        if (this.status === null) {
          Button('重新读取').height(34).fontSize(12).enabled(!this.busy).onClick(() => this.load())
        } else {
          this.choice('', '跟随上次激活', '自动')
          ForEach(this.vaults, (vault: ServiceVault) => {
            this.choice(vault.id, vault.id, vault.remote ? 'WebDAV' : '本地')
          }, (vault: ServiceVault) => vault.id)
        }
      }
    }.width('100%').padding(22).borderRadius(18)
      .alignItems(HorizontalAlign.Start)
      .backgroundEffect({ radius: 5, saturation: 1.1, brightness: 1.0, color: 'rgba(255,255,255,0)', adaptiveColor: AdaptiveColor.AVERAGE })
      .linearGradient({ angle: 180, colors: [['rgba(255,255,255,0)', 0], ['rgba(255,255,255,0.03)', 0.45], ['rgba(255,255,255,0)', 1]] })
      .shadow({ radius: 22, color: 'rgba(0,0,0,0.22)', offsetY: 6 })
      .border({ width: 1, color: 'rgba(255,255,255,0.32)' })
  }
}
