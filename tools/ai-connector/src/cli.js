#!/usr/bin/env node
import { readFile } from 'node:fs/promises';
import { stdin, stderr } from 'node:process';
import { createInterface } from 'node:readline/promises';
import { DEFAULT_CONFIG, discover, pair, readConfig, validatePairing, verifyPin, writeConfig } from './connector.js';
import { runServer } from './server.js';

function option(args, name, fallback) {
  const index = args.indexOf(name);
  return index < 0 ? fallback : args[index + 1];
}

async function readPairing(file) {
  const text = file ? await readFile(file, 'utf8') : await (async () => {
    if (stdin.isTTY) {
      const reader = createInterface({ input: stdin, output: stderr });
      try { return await reader.question('Paste trusted pairing JSON and press Enter: '); }
      finally { reader.close(); }
    }
    let value = '';
    for await (const chunk of stdin) {
      value += chunk;
      if (value.length > 16384) throw new Error('pairing JSON exceeds limit');
    }
    return value;
  })();
  return validatePairing(JSON.parse(text));
}

async function main() {
  const args = process.argv.slice(2);
  const command = args[0] === 'serve' || !args[0] || args[0].startsWith('--') ? 'serve' : args[0];
  const configFile = option(args, '--config', DEFAULT_CONFIG);
  if (command === 'pair') {
    const pairing = await readPairing(option(args, '--file'));
    const config = await pair(pairing, option(args, '--client-name', 'Vitreus AI Connector'));
    await writeConfig(configFile, config);
    stderr.write(`Paired with ${config.deviceId}; config saved to ${configFile}\n`);
  } else if (command === 'endpoint') {
    const config = await readConfig(configFile);
    const address = option(args, '--address');
    const port = Number(option(args, '--port'));
    if (address) config.address = address;
    if (Number.isInteger(port) && port > 0 && port <= 65535) config.port = port;
    await verifyPin(config);
    await writeConfig(configFile, config);
    stderr.write(`Endpoint updated: ${config.address}:${config.port}\n`);
  } else if (command === 'status') {
    try {
      let config = await readConfig(configFile);
      let connected = false;
      try { await verifyPin(config); connected = true; }
      catch {
        const found = await discover(config);
        connected = Boolean(found);
        if (found) { config = found; await writeConfig(configFile, config); }
      }
      stderr.write(JSON.stringify({ connected, deviceId: config.deviceId, address: config.address, port: config.port, fingerprint: config.fingerprint }) + '\n');
    } catch (error) { stderr.write(JSON.stringify({ connected: false, error: error.message }) + '\n'); process.exitCode = 1; }
  } else if (command === 'serve') {
    await runServer({ configFile });
  } else {
    throw new Error('usage: vitreus-ai [serve|pair|endpoint|status] [--config PATH]');
  }
}

main().catch(error => { stderr.write(`vitreus-ai: ${error.message}\n`); process.exitCode = 1; });
