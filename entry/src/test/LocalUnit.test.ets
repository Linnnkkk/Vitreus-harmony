import { describe, it, expect } from '@ohos/hypium';
import { CapturePathTemplate, CaptureTemplateValues } from '../main/ets/common/CapturePathTemplate';

export default function localUnitTest() {
  describe('capturePathTemplate', () => {
    const values: CaptureTemplateValues = CapturePathTemplate.makeValues(
      new Date(2026, 8, 22, 4, 5, 6).getTime(), '首行标题', 'example.com', 'vault');

    it('expands all variables with zero padding', 0, () => {
      const result = CapturePathTemplate.expand(
        '剪藏/{{年}}/{{月}}/{{日}}/{{今天}}-{{时间}}-{{标题}}-{{站点}}-{{库名}}.md', values);
      expect(result.valid).assertEqual(true);
      expect(result.path).assertEqual('剪藏/2026/09/22/2026-09-22-040506-首行标题-example.com-vault.md');
    });

    it('rejects unknown and unclosed variables', 0, () => {
      const unknown = CapturePathTemplate.validateTemplate('a/{{未知}}.md');
      const unclosed = CapturePathTemplate.validateTemplate('a/{{标题.md');
      expect(unknown.valid).assertEqual(false);
      expect(unclosed.valid).assertEqual(false);
    });

    it('rejects empty and non markdown templates', 0, () => {
      expect(CapturePathTemplate.validateTemplate('').empty).assertEqual(true);
      expect(CapturePathTemplate.validateTemplate('剪藏').valid).assertEqual(false);
      expect(CapturePathTemplate.validateTemplate('剪藏/').valid).assertEqual(false);
    });

    it('rejects absolute traversal and unsafe static paths', 0, () => {
      expect(CapturePathTemplate.validateTemplate('/剪藏/{{今天}}.md').valid).assertEqual(false);
      expect(CapturePathTemplate.validateTemplate('C:/剪藏/{{今天}}.md').valid).assertEqual(false);
      expect(CapturePathTemplate.validateTemplate('../剪藏/{{今天}}.md').valid).assertEqual(false);
      expect(CapturePathTemplate.validateTemplate('剪藏/../{{今天}}.md').valid).assertEqual(false);
      expect(CapturePathTemplate.validateTemplate('剪藏\\{{今天}}.md').valid).assertEqual(false);
      expect(CapturePathTemplate.validateTemplate('剪藏/[标题].md').valid).assertEqual(false);
      expect(CapturePathTemplate.validateTemplate('.obsidian/windows.json').valid).assertEqual(false);
      expect(CapturePathTemplate.validateTemplate('剪藏/ {{今天}}.md').valid).assertEqual(false);
    });

    it('cleans dangerous dynamic title without creating path components', 0, () => {
      const dangerous: CaptureTemplateValues = {
        year: '2026', month: '09', day: '22', today: '2026-09-22', time: '040506',
        title: '../含/emoji😀与生僻字𠀀', site: 'example.com', vault: 'vault'
      };
      const result = CapturePathTemplate.expand('剪藏/{{标题}}.md', dangerous);
      expect(result.valid).assertEqual(true);
      expect(result.path.indexOf('/')).assertEqual(2);
      expect(result.path).assertContain('含');
      expect(result.path).assertContain('😀');
    });

    it('accepts nested markdown path and derives host', 0, () => {
      expect(CapturePathTemplate.validateTemplate('剪藏/{{年}}/{{标题}}.md').valid).assertEqual(true);
      expect(CapturePathTemplate.hostFromUrl('https://user:pass@example.com:8443/a?q=1').toString())
        .assertEqual('example.com:8443');
      expect(CapturePathTemplate.hostFromUrl('not a url')).assertEqual('');
    });

    it('validates markdown headings', 0, () => {
      const heading = CapturePathTemplate.validateHeading('## 收件箱');
      expect(heading.valid).assertEqual(true);
      expect(heading.level).assertEqual(2);
      expect(heading.text).assertEqual('收件箱');
      expect(CapturePathTemplate.validateHeading('### 标题 ###').text).assertEqual('标题');
      expect(CapturePathTemplate.validateHeading('#\t标题').valid).assertEqual(true);
      expect(CapturePathTemplate.validateHeading('####### 太深').valid).assertEqual(false);
      expect(CapturePathTemplate.validateHeading('标题').valid).assertEqual(false);
      expect(CapturePathTemplate.validateHeading('##').valid).assertEqual(false);
      expect(CapturePathTemplate.validateHeading('').empty).assertEqual(true);
    });

    it('inserts below a heading before the next section', 0, () => {
      const source = '# 日记\n\n## 收件箱\n\n旧内容\n\n## 已完成\n\n完成内容\n';
      const result = CapturePathTemplate.insertUnderHeading(source, '- 新速记', '## 收件箱');
      expect(result).assertEqual('# 日记\n\n## 收件箱\n\n旧内容\n\n- 新速记\n\n## 已完成\n\n完成内容\n');
    });

    it('creates a missing heading and ignores fenced headings', 0, () => {
      const source = '```markdown\n## 收件箱\n```\n\n正文\n';
      const result = CapturePathTemplate.insertUnderHeading(source, '- 新速记', '## 收件箱');
      expect(result).assertContain('## 收件箱\n\n- 新速记');
      expect(result.indexOf('```markdown\n## 收件箱\n```')).assertEqual(0);
    });

    it('preserves CRLF when inserting', 0, () => {
      const source = '# 日记\r\n\r\n## 收件箱\r\n\r\n## 完成\r\n';
      const result = CapturePathTemplate.insertUnderHeading(source, '- 新速记', '## 收件箱');
      expect(result.indexOf('\r\n')).assertGreater(0);
      expect(result.indexOf('\r\n## 完成')).assertGreater(0);
      expect(result.indexOf('\r\n\n## 完成')).assertEqual(-1);
    });
  });
}
