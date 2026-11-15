// Runs the production CapturePathTemplate source for the {{星期}} / {{周几}} variables.
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

test('{{周几}} matches Obsidian zh-cn "YYYY-MM-DD ddd", {{星期}} matches "dddd"', () => {
  const r = expand('日记/{{今天}} {{周几}}.md');
  assert.deepEqual([r.valid, r.path, r.error], [true, '日记/2026-11-14 周六.md', '']);
  assert.equal(expand('日记/{{今天}} {{周几}}.md', SUN).path, '日记/2026-03-01 周日.md');
  assert.equal(expand('日记/{{今天}} {{星期}}.md').path, '日记/2026-11-14 星期六.md');
  assert.equal(expand('日记/{{今天}} {{星期}}.md', SUN).path, '日记/2026-03-01 星期日.md');
  assert.equal(T.validateTemplate('{{年}}/{{星期}}/{{周几}}-{{标题}}.md').valid, true);
});

test('every weekday maps to 星期日..星期六 and 周日..周六', () => {
  const long = [], short = [];
  for (let i = 0; i < 7; i++) {
    const v = T.makeValues(new Date(2026, 2, 1 + i).getTime(), '', '', '');
    long.push(v.weekday); short.push(v.weekdayShort);
  }
  assert.deepEqual(long, ['星期日', '星期一', '星期二', '星期三', '星期四', '星期五', '星期六']);
  assert.deepEqual(short, ['周日', '周一', '周二', '周三', '周四', '周五', '周六']);
});

test('existing variables are unchanged', () => {
  assert.equal(expand('速记/{{今天}}.md').path, '速记/2026-11-14.md');
  assert.equal(expand('{{年}}/{{月}}/{{日}}-{{时间}}.md').path, '2026/11/14-090507.md');
  assert.match(T.validateTemplate('{{日期}}.md').error, /未知变量/);
});
