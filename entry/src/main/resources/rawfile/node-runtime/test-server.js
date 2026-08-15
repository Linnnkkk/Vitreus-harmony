// Vitreus Node 运行时自检脚本
// 状态文件路径从环境变量 VITREUS_STATUS_FILE 读（C++ 侧 setenv 传入）
const fs = require("fs");
const path = process.env.VITREUS_STATUS_FILE || "/data/storage/el2/base/files/node-status.txt";

function log(msg) {
  const line = `[js ${new Date().toISOString()}] ${msg}\n`;
  try { fs.appendFileSync(path, line); } catch (e) { /* 写不进就算了 */ }
}

// 捕获放最前：脚本主体任何异常都写进状态文件（C++ 侧还有 SetProcessExitHandler 兜底）
process.on("uncaughtException", (e) => {
  log("uncaughtException: " + (e && e.stack ? e.stack : String(e)));
});
process.on("unhandledRejection", (e) => {
  log("unhandledRejection: " + (e && e.stack ? e.stack : String(e)));
});

log("=== Node 进程已启动 ===");
log("node " + process.version + " | " + process.arch + " | " + process.platform);
log("argv: " + JSON.stringify(process.argv));
log("cwd: " + process.cwd());
log("env VITREUS_STATUS_FILE: " + process.env.VITREUS_STATUS_FILE);

// 列一下沙箱里能看到的目录，排查路径问题
try {
  log("files dir 内容: " + fs.readdirSync("/data/storage/el2/base/haps/entry/files").join(", "));
} catch (e) {
  log("列目录失败: " + e.message);
}

// 试一下核心模块
try {
  require("http");
  log("require http OK");
} catch (e) {
  log("require http 失败: " + e.message);
}

// 起 http server
try {
  const http = require("http");
  const srv = http.createServer((req, res) => {
    log("收到请求: " + req.url);
    res.writeHead(200, {"Content-Type": "text/plain"});
    res.end("Vitreus local node server: " + process.version);
  });
  srv.listen(6790, "127.0.0.1", () => {
    log("http server 已监听 127.0.0.1:6790");
  });
  srv.on("error", (e) => {
    log("http server 错误: " + e.message);
  });
} catch (e) {
  log("http server 启动异常: " + e.message);
}

log("=== 脚本同步部分执行完毕，进入事件循环 ===");

setInterval(() => {}, 1000);
