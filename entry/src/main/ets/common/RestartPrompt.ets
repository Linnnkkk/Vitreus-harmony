import common from '@ohos.app.ability.common';

// Resource imports and connection changes share the same exit/reopen interaction.
export class RestartPrompt {
  static show(context: common.UIAbilityContext, title: string, message: string,
    beforeExit: () => void, onFailure: () => void): void {
    AlertDialog.show({
      title: title,
      message: message + '\n\n请退出后重新打开应用。',
      autoCancel: false,
      alignment: DialogAlignment.Center,
      primaryButton: { value: '稍后', action: () => {} },
      secondaryButton: {
        value: '退出应用',
        action: () => {
          beforeExit();
          context.terminateSelf().catch(() => { onFailure(); });
        }
      }
    });
  }
}
