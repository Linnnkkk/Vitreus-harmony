// 捕获类页面统一设计令牌：颜色 / 字号 / 圆角 / 动效时长
// 目标：新增界面不再现场配色，全部从这里取
export class Theme {
  // 品牌色（棱镜靛蓝）
  static readonly ACCENT: string = '#7A88E8';
  static readonly ACCENT_DEEP: string = '#5F6BD8';
  static readonly SUCCESS: string = '#9BE8B4';
  static readonly WARN: string = '#F2C66D';
  static readonly DANGER: string = '#FF8D8D';

  // 文字
  static readonly TEXT_PRIMARY: string = '#F2F3FF';
  static readonly TEXT_SECONDARY: string = '#B8C0E4';
  static readonly TEXT_TERTIARY: string = '#7F89C4';

  // 表面
  static readonly CARD: string = 'rgba(23,26,51,0.80)';
  static readonly CARD_SOLID: string = '#171A33';
  static readonly FIELD: string = 'rgba(13,16,39,0.70)';
  static readonly CHIP: string = 'rgba(255,255,255,0.10)';
  static readonly HAIRLINE: string = 'rgba(255,255,255,0.14)';
  static readonly SCRIM: string = 'rgba(6,8,18,0.35)';

  // 字号：标题 / 正文 / 辅助 / 注脚
  static readonly FS_TITLE: number = 20;
  static readonly FS_BODY: number = 15;
  static readonly FS_CAPTION: number = 13;
  static readonly FS_FOOT: number = 11;

  // 圆角：卡片 / 控件 / 胶囊
  static readonly R_CARD: number = 28;
  static readonly R_CONTROL: number = 16;
  static readonly R_PILL: number = 16;

  // 动效
  static readonly MS_ENTER: number = 280;
  static readonly MS_SWAP: number = 220;
  static readonly MS_LEAVE: number = 180;
}
