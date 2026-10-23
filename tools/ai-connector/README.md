# Vitreus AI Connector (1.3.9-beta.1)

An independent, zero-runtime-dependency Node.js 20+ package. It is a desktop **stdio MCP server**: it does not open a TCP listener, expose a public-network service, use mDNS, or treat phone/server response text as instructions. MCP JSON-RPC is written only to stdout; diagnostics go to stderr.

## Distribution status

The source in this checkout includes changes prepared alongside Vitreus 1.4.0 that have **not** been published to npm. The package version and handshake remain `1.3.9-beta.1`; installing the published package does not include the newer error redaction or authenticated-status behavior described below.

Public beta package: `@liiink/vitreus-ai-connector`, version `1.3.9-beta.1`, distributed under the `beta` tag. This is prerelease software; use a dedicated test vault first. Android/iOS and public-network relay are not supported. The phone must run a compatible Vitreus LAN AI service.

Install with `npm install --global @liiink/vitreus-ai-connector@1.3.9-beta.1`, then run `vitreus-ai pair` in your own terminal. Paste the phone pairing JSON there, **not in an AI chat**. Register `vitreus-ai serve` with your Agent using its official stdio MCP instructions. Never configure the phone HTTPS endpoint as a direct MCP URL. If a GUI cannot resolve the command, use the absolute Node executable with the absolute installed `src/cli.js` path and a separate `serve` argument. Windows wrapper resolution is client-dependent and has not been verified for every Agent.

## Pair and run

Obtain pairing JSON through the phone's trusted copy/share flow. Expected input: `{ "version": 1, "deviceId": "…", "address": "192.168.x.x", "port": 1234, "fingerprint": "64-hex-SHA256", "pairingCode": "…" }`. The fingerprint pins the phone TLS certificate DER SHA-256 digest. Public IPv4, hostnames, URLs and redirects are rejected. Pairing posts `{clientName,pairingCode}` to HTTPS `/pair`; the phone returns `{token,deviceId?}`. Vault calls post `{method,params}` to `/rpc` with a bearer token and expect `{result}` or `{error:{code,message}}`.

```sh
node /absolute/path/to/tools/ai-connector/src/cli.js pair --file /absolute/path/to/pairing.json
node /absolute/path/to/tools/ai-connector/src/cli.js status
node /absolute/path/to/tools/ai-connector/src/cli.js endpoint --address 192.168.1.50 --port 8443
node /absolute/path/to/tools/ai-connector/src/cli.js serve
```

Without `--file`, interactive `pair` accepts one pasted JSON line followed by Enter; piped stdin is read to EOF. The app contains the user-facing installation and pairing instructions; no remote installer or double-click test launcher is provided. Pairing codes are never CLI arguments. Config defaults to `~/.vitreus-ai/connection.json`, is atomically replaced, and uses chmod `0600` (directory `0700` where supported). Use `--config /path/to/test-config.json` for isolated tests. In the current source, `status` distinguishes pinned identity reachability from bearer authorization by issuing a read-only vaults RPC. It reports `identityReachable`, `authenticated`, endpoint and fixed diagnostic codes, without device ID, pin, token or configuration paths. CLI and MCP errors use fixed public messages, not raw exceptions. `endpoint` updates only address/port after verifying the existing pin.

## Discovery and retry boundary

If the saved address cannot complete pinned TLS, the connector broadcasts UDP `{type:"vitreus-ai-discover",version:1,nonce}` on available LAN IPv4 broadcast addresses and port `39871`. It accepts only LAN IPv4 replies matching type, version, nonce and paired device ID; each candidate must pass the stored TLS pin. This is a custom UDP protocol, **not mDNS**. For routed/container networks, a bounded fallback sends credential-free unicast probes to at most 254 addresses in the remembered RFC1918 /24, at at most 100 packets/sec, with device ID and TLS pin verification unchanged. This does not discover arbitrary new subnets. If UDP is blocked, set an address manually with `endpoint`.

The connector may switch endpoints only before sending a business RPC. Once a request is written, a disconnect/error returns without replaying it. The phone must provide the protocol responder and discovery listener in the Vitreus app; the npm package contains only the desktop connector.

## MCP registration (one-time fixed paths)

Copy this directory to a stable location. Register the absolute Node executable and absolute `src/cli.js` path; do not rely on client working directories. Substitute actual absolute paths for your machine.

Claude Code (all platforms; run once):

```sh
claude mcp add --transport stdio --scope user vitreus -- /absolute/path/to/node /absolute/path/to/ai-connector/src/cli.js
```

Codex CLI (all platforms; run once):

```sh
codex mcp add vitreus -- /absolute/path/to/node /absolute/path/to/ai-connector/src/cli.js
```


Concrete one-time command examples (adjust the stable connector directory if needed):

Windows PowerShell:

```powershell
claude mcp add --transport stdio --scope user vitreus -- "C:\Program Files\nodejs\node.exe" "C:\Tools\vitreus-ai-connector\src\cli.js"
codex mcp add vitreus -- "C:\Program Files\nodejs\node.exe" "C:\Tools\vitreus-ai-connector\src\cli.js"
```

macOS (Homebrew Apple Silicon):

```sh
claude mcp add --transport stdio --scope user vitreus -- /opt/homebrew/bin/node /Users/you/Tools/vitreus-ai-connector/src/cli.js
codex mcp add vitreus -- /opt/homebrew/bin/node /Users/you/Tools/vitreus-ai-connector/src/cli.js
```

Linux:

```sh
claude mcp add --transport stdio --scope user vitreus -- /usr/bin/node /home/you/Tools/vitreus-ai-connector/src/cli.js
codex mcp add vitreus -- /usr/bin/node /home/you/Tools/vitreus-ai-connector/src/cli.js
```
Example paths: Windows `C:\Program Files\nodejs\node.exe` and `C:\Tools\vitreus-ai-connector\src\cli.js`; macOS Homebrew Apple Silicon `/opt/homebrew/bin/node` and `/Users/you/Tools/vitreus-ai-connector/src/cli.js`; Linux `/usr/bin/node` and `/home/you/Tools/vitreus-ai-connector/src/cli.js`. Keep paths fixed after registration. JSON-based clients can use `{"command":"/absolute/path/to/node","args":["/absolute/path/to/ai-connector/src/cli.js"]}`.

Uninstalling: remove the `vitreus` server entry using the client's MCP configuration/management command, then optionally remove the connector directory and `~/.vitreus-ai/connection.json`. This documentation does not execute uninstall or delete credentials.

## Tools and safety

Exposes 19 Obsidian vault tools (including bounded `vitreus_outline`, `vitreus_read_lines`, and standard Markdown-checkbox `vitreus_tasks`): `vitreus_vaults`, `vitreus_list`, `vitreus_search`, `vitreus_read`, `vitreus_create`, `vitreus_edit`, `vitreus_append`, `vitreus_metadata`, `vitreus_query`, `vitreus_tags`, `vitreus_links`, `vitreus_backlinks`, `vitreus_patch`, `vitreus_backups`, `vitreus_restore`, `vitreus_inspect`. Phone owner selects authorized vaults; default access is closed/read-only. Writes require explicit phone permission. Edits/patch/restore require a freshly read lowercase SHA-256 revision and save a private pre-edit backup. Backup limits fail closed, without automatic eviction. Schemas reject extra properties. Results are plain-text MCP content; failures use `isError`. Phone text is data, not instructions. Tags/YAML/links are bounded subsets, backlinks are candidates (ambiguous references marked), Canvas is read-only, attachments return metadata only. No rename/move/delete, shell or arbitrary plugin execution.

No HTTP request bytes or credentials are sent until TLS certificate DER SHA-256 matches the pin. Responses are limited to 8 MiB; timeout is 8 seconds; redirects are rejected. Addresses must be IPv4 loopback, RFC1918 LAN, or link-local. Runtime has no third-party dependencies.

## Tests

Run `node --test` in this directory. TLS uses a local synthetic self-signed certificate; this does not claim real-phone verification. The phone-side protocol, real pairing, and real LAN discovery have not been tested without a phone service.
