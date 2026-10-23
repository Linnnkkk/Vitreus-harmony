# Synthetic TLS fixtures

`synthetic-key.pem` and `synthetic-cert.pem` are deliberately public, disposable test fixtures for the loopback HTTPS server in `connector.test.js`. They do not identify any user device and must never be used in a deployed server. Production device keys and pairing credentials are generated at runtime and must not be committed.

These files are excluded from the npm package by its explicit `files` allowlist.
