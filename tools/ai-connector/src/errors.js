// Only errors created here may cross the CLI/MCP boundary. Never reflect remote text.
const messages = Object.freeze({
  CONNECTOR_ERROR: 'Connection failed. Check the phone service and connector configuration.',
  CONFIG_INVALID: 'Connection configuration is invalid. Pair again using trusted phone details.',
  CONFIG_UNAVAILABLE: 'Connection configuration could not be read. Check that pairing is configured.',
  PAIRING_INVALID: 'Pairing details are invalid. Use the trusted pairing details from the phone.',
  TOKEN_INVALID: 'invalid bearer token; pair again using trusted phone details.',
  ENDPOINT_INVALID: 'Invalid LAN endpoint.',
  PIN_MISMATCH: 'TLS certificate fingerprint mismatch. Verify the trusted phone identity; pairing was not changed.',
  DEVICE_UNAVAILABLE: 'Device unavailable; no RPC was sent. Check the phone service and LAN connection.',
  RESPONSE_INVALID: 'The phone returned an invalid or incomplete response.',
  RESPONSE_TOO_LARGE: 'The phone response exceeds the connector size limit.',
  TIMEOUT: 'The phone connection timed out.',
  REDIRECT_REJECTED: 'Redirects are not allowed.',
  USAGE: 'usage: vitreus-ai [serve|pair|endpoint|status] [--config PATH]',
});
const serviceMessages = Object.freeze({
  BAD_REQUEST: 'The phone rejected the request parameters.',
  INVALID_ARGUMENT: 'The phone rejected the request arguments.',
  UNAUTHORIZED: 'Authorization is no longer valid. Check pairing on the phone.',
  FORBIDDEN: 'Access denied. Check the phone owner vault and write permissions.',
  NOT_FOUND: 'The requested vault, note or resource was not found.',
  CONFLICT: 'The note changed or the patch is not unique. Read it again before writing.',
  REVISION_CONFLICT: 'The note revision changed. Read it again before writing.',
  LIMIT_EXCEEDED: 'The phone operation exceeded its safety limit. Narrow the request.',
  PAYLOAD_TOO_LARGE: 'The request exceeds the phone size limit.',
  METHOD_NOT_FOUND: 'The phone does not support this operation.',
  UNAVAILABLE: 'The phone service is disabled or unavailable.',
  RATE_LIMITED: 'Too many pairing attempts. Try again later.',
  PAIRING_EXPIRED: 'The pairing code expired. Obtain a new code from the phone.',
  INVALID_PAIRING: 'The pairing code is invalid.',
  LAN_REQUIRED: 'The phone requires a local network connection.',
  ORIGIN_REJECTED: 'The phone rejected the request origin.',
  BACKUP_STORE_UNSAFE: 'The phone backup store is unsafe. Check it on the phone.',
  BACKUP_STORE_BUSY: 'The phone backup store is busy. Try again later.',
  BACKUP_STORE_FULL: 'The phone backup store is full.',
  BACKUP_TOO_LARGE: 'The note exceeds the phone backup size limit.',
  BACKUP_NOT_FOUND: 'The requested backup was not found.',
  INTERNAL: 'The phone could not complete the operation.',
  INTERNAL_ERROR: 'The phone could not complete the operation.',
});
const trusted = new WeakMap();
function make(code, message) {
  const error = Object.assign(new Error(message), { code });
  trusted.set(error, Object.freeze({ code, message }));
  return error;
}
export function connectorError(code) {
  return Object.hasOwn(messages, code) ? make(code, messages[code]) : make('CONNECTOR_ERROR', messages.CONNECTOR_ERROR);
}
export function serviceError(code) {
  return typeof code === 'string' && Object.hasOwn(serviceMessages, code)
    ? make(code, serviceMessages[code]) : connectorError('CONNECTOR_ERROR');
}
export function publicError(error) {
  // Even a forged {code,message}, or a mutated trusted Error, is not reflected.
  if (error && trusted.has(error)) return { ...trusted.get(error) };
  return { code: 'CONNECTOR_ERROR', message: messages.CONNECTOR_ERROR };
}
