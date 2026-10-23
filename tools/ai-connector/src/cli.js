#!/usr/bin/env node
import { readFile } from 'node:fs/promises';
import { stdin, stderr } from 'node:process';
import { createInterface } from 'node:readline/promises';
import { DEFAULT_CONFIG, connectionStatus, pair, readConfig, validatePairing, verifyPin, writeConfig } from './connector.js';
import { runServer } from './server.js';
import { connectorError, publicError } from './errors.js';

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
      if (value.length > 16384) throw connectorError('PAIRING_INVALID');
    }
    return value;
  })();
  try { return validatePairing(JSON.parse(text)); }
  catch { throw connectorError('PAIRING_INVALID'); }
}

async function main() {
  const args = process.argv.slice(2);
  const command = args[0] === 'serve' || !args[0] || args[0].startsWith('--') ? 'serve' : args[0];
  const configFile = option(args, '--config', DEFAULT_CONFIG);
  if (command === 'pair') {
    const pairing = await readPairing(option(args, '--file'));
    const config = await pair(pairing, option(args, '--client-name', 'Vitreus AI Connector'));
    await writeConfig(configFile, config);
    stderr.write('Paired successfully; connection configuration saved.\n');
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
      const status = await connectionStatus(await readConfig(configFile), configFile);
      const { error, ...result } = status;
      stderr.write(JSON.stringify({ ...result, ...(error ? { error: publicError(error) } : {}) }) + '\n');
      if (!result.authenticated) process.exitCode = 1;
    } catch (error) {
      stderr.write(JSON.stringify({ identityReachable: false, authenticated: false, error: publicError(error) }) + '\n');
      process.exitCode = 1;
    }
  } else if (command === 'serve') {
    await runServer({ configFile });
  } else {
    throw connectorError('USAGE');
  }
}

main().catch(error => { stderr.write(`vitreus-ai: ${publicError(error).message}\n`); process.exitCode = 1; });
