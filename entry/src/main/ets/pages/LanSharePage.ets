// 局域网共享（VIP 预备役）——暂无入口，等 IAP 接通后放行
// 设计（用户拍板）：
//   ① 首次开启时用户自己设账号密码（Digest Auth，密码挑战应答、永不裸传）
//   ② 开启才后台常驻（DATA_TRANSFER 长时任务随开关起停），不开共享绝不多耗一滴电
//   ③ 开启后大屏展示 IP:端口，家人设备浏览器输入即达
// 服务端配套：ignis-study digest-auth.js（IGNIS_AUTH_USER/PASS env 注入，回环放行）
// TODO(IAP)：开启时以 LISTEN_HOST=0.0.0.0 重启本地 server 并注入凭证 env；关闭时回落 127.0.0.1 重启
import { common, wantAgent } from '@kit.AbilityKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { wifiManager } from '@kit.ConnectivityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hapticSelect, hapticSuccess } from '../common/Haptics';

const LAN_PORT = 6791;

@Entry
@Component
struct LanSharePage {
  @State private user: string = '';
  @State private pass: string = '';
  @State private configured: boolean = false;
  @State private sharing: boolean = false;
  @State private lanIp: string = '';

  aboutToAppear() {
    PersistentStorage.persistProp('lanShareUser', '');
    PersistentStorage.persistProp('lanSharePass', '');
    this.user = AppStorage.get<string>('lanShareUser') ?? '';
    this.pass = AppStorage.get<string>('lanSharePass') ?? '';
    this.configured = this.user !== '' && this.pass !== '';
  }

  // Wi-Fi 本机 IP（wifiManager.getIpInfo 返回整数，转点分）
  private getLanIp(): string {
    try {
      const info = wifiManager.getIpInfo();
      const n = info.ipAddress >>> 0;
      if (n === 0) {
        return '';
      }
      return ((n >>> 24) & 0xff) + '.' + ((n >>> 16) & 0xff) + '.' + ((n >>> 8) & 0xff) + '.' + (n & 0xff);
    } catch (e) {
      return '';
    }
  }

  private saveCredentials() {
    if (this.user === '' || this.pass === '' || this.pass.length < 4) {
      return;
    }
    AppStorage.setOrCreate('lanShareUser', this.user);
    AppStorage.setOrCreate('lanSharePass', this.pass);
    this.configured = true;
    hapticSuccess();
  }

  private async startShare() {
    // TODO(IAP)：此处先做 VIP 票据校验，再以 0.0.0.0 + 凭证 env 重启本地 server
    this.lanIp = this.getLanIp();
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    try {
      const agent = await wantAgent.getWantAgent({
        wants: [{ bundleName: 'com.vitreus.app', abilityName: 'EntryAbility' }],
        operationType: wantAgent.OperationType.START_ABILITY,
        requestCode: 0
      });
      await backgroundTaskManager.startBackgroundRunning(ctx, backgroundTaskManager.BackgroundMode.DATA_TRANSFER, agent);
      this.sharing = true;
      hapticSuccess();
    } catch (e) {
      const err = e as BusinessError;
      console.error('[lanshare] start failed: ' + err.code + ' ' + err.message);
    }
  }

  private async stopShare() {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    try {
      await backgroundTaskManager.stopBackgroundRunning(ctx);
    } catch (e) {
      // 已停/系统回收时静默
    }
    // TODO(IAP)：回落 127.0.0.1 重启本地 server
    this.sharing = false;
    hapticSelect();
  }

  build() {
    Column({ space: 18 }) {
      Text('局域网共享')
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor('#E2E6F8')
        .margin({ top: 56 })

      if (!this.configured) {
        // ── 首次：设账号密码 ──
        Text('开启前先设一个账号和密码，家里其他设备连接时会要求输入')
          .fontSize(13)
          .fontColor('#8F9BD8')
          .textAlign(TextAlign.Center)
          .padding({ left: 30, right: 30 })

        TextInput({ placeholder: '账号', text: this.user })
          .onChange((v: string) => { this.user = v; })
          .width('78%')
          .height(48)
          .fontColor('#E2E6F8')
          .backgroundColor('#1A1E4A')

        TextInput({ placeholder: '密码（至少 4 位）', text: this.pass })
          .type(InputType.Password)
          .onChange((v: string) => { this.pass = v; })
          .width('78%')
          .height(48)
          .fontColor('#E2E6F8')
          .backgroundColor('#1A1E4A')

        Button('保存并开启')
          .width('78%')
          .height(48)
          .backgroundColor('#5F6BD8')
          .enabled(this.user !== '' && this.pass.length >= 4)
          .onClick(() => {
            this.saveCredentials();
            this.startShare();
          })
      } else if (!this.sharing) {
        // ── 已配置未开启 ──
        Text('账号：' + this.user)
          .fontSize(14)
          .fontColor('#B8C0E4')
        Button('开启共享')
          .width('78%')
          .height(48)
          .backgroundColor('#5F6BD8')
          .onClick(() => { this.startShare(); })
      } else {
        // ── 共享中 ──
        Column({ space: 8 }) {
          Text('在家人设备的浏览器里输入')
            .fontSize(13)
            .fontColor('#8F9BD8')
          Text(this.lanIp !== '' ? 'http://' + this.lanIp + ':' + LAN_PORT : '获取 IP 失败（是否已连 Wi-Fi？）')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor('#9BE8B4')
          Text('首次访问输入你设置的账号密码即可')
            .fontSize(12)
            .fontColor('#6A74A8')
        }
        .width('86%')
        .padding(28)
        .borderRadius(16)
        .backgroundColor('#161A3E')
        .border({ width: 1, color: '#2A2E5E' })

        Button('停止共享')
          .width('78%')
          .height(48)
          .backgroundColor('#3A4078')
          .onClick(() => { this.stopShare(); })
      }
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Center)
    .backgroundColor('#141736')
  }
}
