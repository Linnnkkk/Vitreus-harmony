import { common, wantAgent } from '@kit.AbilityKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { BusinessError } from '@kit.BasicServicesKit';

export class BackgroundLease {
  private static pending: Promise<void> = Promise.resolve();
  private static active: boolean = false;

  static forget(): void {
    BackgroundLease.active = false;
  }

  static reapply(context: common.UIAbilityContext): Promise<boolean> {
    return new Promise<boolean>((resolve) => {
      BackgroundLease.pending = BackgroundLease.pending.then(async () => {
        try {
          await backgroundTaskManager.stopBackgroundRunning(context);
        } catch (error) {
        }
        BackgroundLease.active = false;
        const required = AppStorage.get<boolean>('srvRunning') === true ||
          AppStorage.get<boolean>('aiRunning') === true;
        if (!required) {
          resolve(true);
          return;
        }
        try {
          const agent = await wantAgent.getWantAgent({
            wants: [{ bundleName: 'com.vitreus.app', abilityName: 'EntryAbility' }],
            operationType: wantAgent.OperationType.START_ABILITY,
            requestCode: 0
          });
          if (AppStorage.get<boolean>('srvRunning') !== true && AppStorage.get<boolean>('aiRunning') !== true) {
            resolve(true);
            return;
          }
          await backgroundTaskManager.startBackgroundRunning(
            context, backgroundTaskManager.BackgroundMode.DATA_TRANSFER, agent);
          BackgroundLease.active = true;
          resolve(true);
        } catch (error) {
          const err = error as BusinessError;
          console.error('[BackgroundLease] reapply failed: ' + err.code + ' ' + err.message);
          resolve(false);
        }
      }).catch(() => {
        resolve(false);
      });
    });
  }

  static reconcile(context: common.UIAbilityContext): Promise<boolean> {
    return new Promise<boolean>((resolve) => {
      BackgroundLease.pending = BackgroundLease.pending.then(async () => {
        const required = AppStorage.get<boolean>('srvRunning') === true ||
          AppStorage.get<boolean>('aiRunning') === true;
        try {
          if (required) {
            if (BackgroundLease.active) {
              resolve(true);
              return;
            }
            const agent = await wantAgent.getWantAgent({
              wants: [{ bundleName: 'com.vitreus.app', abilityName: 'EntryAbility' }],
              operationType: wantAgent.OperationType.START_ABILITY,
              requestCode: 0
            });
            if (AppStorage.get<boolean>('srvRunning') !== true && AppStorage.get<boolean>('aiRunning') !== true) {
              resolve(true);
              return;
            }
            await backgroundTaskManager.startBackgroundRunning(
              context, backgroundTaskManager.BackgroundMode.DATA_TRANSFER, agent);
            BackgroundLease.active = true;
          } else {
            if (BackgroundLease.active) {
              await backgroundTaskManager.stopBackgroundRunning(context);
              BackgroundLease.active = false;
            }
          }
          resolve(true);
        } catch (error) {
          const err = error as BusinessError;
          console.error('[BackgroundLease] reconcile failed: ' + err.code + ' ' + err.message);
          resolve(false);
        }
      }).catch(() => {
        resolve(false);
      });
    });
  }
}
