// Runs the production CapturePathTemplate source for the {{日期:格式}} variable.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { stripTypeScriptTypes } = require('node:module');

const source = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/common/CapturePathTemplate.ets'), 'utf8')
  .replace(/^import .*$/mg, '').replace(/^export /mg, '');
const sandbox = { Date };
vm.createContext(sandbox);
vm.runInContext(stripTypeScriptTypes(source) + ';globalThis.T = CapturePathTemplate;', sandbox);
const T = sandbox.T;

// 2026-11-14 is a Saturday; 2026-03-01 is a Sunday.
const SAT = new Date(2026, 10, 14, 9, 5, 7).getTime();
const SUN = new Date(2026, 2, 1, 23, 59, 0).getTime();
const expand = (template, at = SAT) => T.expand(template, T.makeValues(at, '标题', '站点', 'vault'));

test('YYYY-MM-DD ddd matches Obsidian zh-cn daily note names', () => {
  const r = expand('日记/{{日期:YYYY-MM-DD ddd}}.md');
  assert.deepEqual([r.valid, r.path, r.error], [true, '日记/2026-11-14 周六.md', '']);
  assert.equal(expand('日记/{{日期:YYYY-MM-DD dddd}}.md').path, '日记/2026-11-14 星期六.md');
  assert.equal(expand('日记/{{日期:YYYY-MM-DD ddd}}.md', SUN).path, '日记/2026-03-01 周日.md');
  assert.equal(expand('{{日期:dd}}.md', SUN).path, '日.md');
});

test('numeric tokens, padding and bracket literals', () => {
  assert.equal(expand('{{日期:YY.M.D H-m-s}}.md').path, '26.11.14 9-5-7.md');
  assert.equal(expand('{{日期:YYYY年MM月DD日 HHmmss}}.md').path, '2026年11月14日 090507.md');
  assert.equal(expand('{{日期:YYYY [第]M[月] dddd}}.md', SUN).path, '2026 第3月 星期日.md');
  assert.equal(expand('{{日期:[Daily] YYYY}}.md').path, 'Daily 2026.md');
});

test('full-width colon works and can be combined with other variables and folders', () => {
  assert.equal(expand('{{年}}/{{日期：MM-DD ddd}}/{{标题}}.md').path, '2026/11-14 周六/标题.md');
});

test('invalid date formats are rejected with a readable error', () => {
  assert.match(T.validateTemplate('{{日期:}}.md').error, /不能为空/);
  assert.match(T.validateTemplate('{{日期:HH:mm}}.md').error, /不允许的字符/);
  assert.match(T.validateTemplate('{{日期:YYYY [x}}.md').error, /没有闭合/);
  assert.match(T.validateTemplate('{{日期:YYYY ]}}.md').error, /不允许的字符/);
  assert.match(T.validateTemplate('{{星期}}.md').error, /未知变量/);
});

test('existing variables are unchanged', () => {
  assert.equal(expand('速记/{{今天}}.md').path, '速记/2026-11-14.md');
  assert.equal(expand('{{年}}/{{月}}/{{日}}-{{时间}}.md').path, '2026/11/14-090507.md');
});
