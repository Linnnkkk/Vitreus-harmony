import { fileIo as fs } from '@kit.CoreFileKit';

// 一次性版本公告的可靠持久化。不要依赖 PersistentStorage：部分设备/进程重启场景下它可能只保留内存值。
export class NoticeState {
  private static filePath(filesDir: string): string {
    return filesDir + '/notice-state.json';
  }

  static isSeen(filesDir: string, noticeId: string): boolean {
    try {
      const path = NoticeState.filePath(filesDir);
      if (!fs.accessSync(path)) {
        return false;
      }
      const raw = fs.readTextSync(path);
      const record = JSON.parse(raw) as Record<string, Object>;
      return record['lastSeenNoticeId'] === noticeId;
    } catch (e) {
      return false;
    }
  }

  static markSeen(filesDir: string, noticeId: string): boolean {
    const path = NoticeState.filePath(filesDir);
    const tmp = path + '.tmp';
    const body = JSON.stringify({ lastSeenNoticeId: noticeId });
    try {
      const file = fs.openSync(tmp, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, body);
      fs.closeSync(file);
      fs.renameSync(tmp, path);
      return true;
    } catch (e) {
      try {
        if (fs.accessSync(tmp)) {
          fs.unlinkSync(tmp);
        }
      } catch (cleanup) {
        // 清理失败不覆盖原始保存错误。
      }
      return false;
    }
  }
}
