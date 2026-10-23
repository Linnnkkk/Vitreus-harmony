// Synthetic integration only: real connector + service, temporary test vault, no phone.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { pathToFileURL } = require('node:url');

test('connector and embedded AI service share an executable protocol', async () => {
  const serverRoot = process.env.VITREUS_IGNIS_SOURCE;
  assert.ok(serverRoot, 'Set VITREUS_IGNIS_SOURCE to the ignis checkout');
  const { createAiLanService } = require(path.join(serverRoot, 'apps/ignis-server/server/ai-lan'));
  const connector = await import(pathToFileURL(path.join(__dirname, 'ai-connector/src/connector.js')));
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'vitreus-integration-'));
  const vault = path.join(root, 'vault');
  fs.mkdirSync(vault);
  const config = { dataRoot: path.join(root, 'data'), vaults: { notes: vault },
    getVaultPath: id => id === 'notes' ? vault : null };
  const service = createAiLanService({ config,
    writeCoalescer: { flushPending: async () => false, getPending: () => null },
    bootstrapCache: { applyMutation: async () => {} } });
  try {
    service.setAccess({ vaultIds: ['notes'], allowWrite: true });
    await service.enable({ ips: ['127.0.0.1'] });
    const pairing = service.createPairing();
    const connection = await connector.pair(pairing);
    const configFile = path.join(root, 'connection.json');
    await connector.writeConfig(configFile, connection);
    assert.ok((await connector.rpc(connection, 'vaults', {}, configFile)).some(v => v.id === 'notes'));
    const content = '中文笔记🙂\n';
    await connector.rpc(connection, 'create', { vaultId: 'notes', path: 'test.md', content }, configFile);
    const note = await connector.rpc(connection, 'read', { vaultId: 'notes', path: 'test.md' }, configFile);
    assert.equal(note.content, content);
    await connector.rpc(connection, 'append', { vaultId: 'notes', path: 'test.md', content: '追加', expectedRevision: note.revision }, configFile);
    await assert.rejects(() => connector.rpc(connection, 'edit', { vaultId: 'notes', path: 'test.md', content: 'stale', expectedRevision: note.revision }, configFile), /Revision|CONFLICT|409/i);
    assert.equal(fs.readFileSync(path.join(vault, 'test.md'), 'utf8'), content + '追加');
    await connector.rpc(connection, 'create', { vaultId: 'notes', path: 'context.md', content: '# Outline\n- [ ] Pending task\n- [x] Completed task\n' }, configFile);
    const outline = await connector.rpc(connection, 'outline', { vaultId: 'notes', path: 'context.md' }, configFile);
    assert.equal(outline.headings[0].title, 'Outline');
    const partial = await connector.rpc(connection, 'read_lines', { vaultId: 'notes', path: 'context.md', startLine: 2, lineCount: 1 }, configFile);
    assert.equal(partial.partial, true);
    assert.equal(partial.content, '- [ ] Pending task');
    const tasks = await connector.rpc(connection, 'tasks', { vaultId: 'notes', status: 'open' }, configFile);
    assert.equal(tasks.items[0].text, 'Pending task');
    const pin = connection.fingerprint;
    await service.disable();
    await service.enable({ ips: ['127.0.0.1'] });
    assert.equal(service.status().fingerprint.replaceAll(':', '').toLowerCase(), pin.replaceAll(':', '').toLowerCase());
  } finally {
    await service.disable();
    // Only this test's freshly-created temporary directory is removed.
    assert.ok(root.startsWith(path.join(os.tmpdir(), 'vitreus-integration-')));
    fs.rmSync(root, { recursive: true, force: true });
  }
});
