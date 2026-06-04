/**
 * MetroSafar — Station QR token generator / validator.
 *
 * Physical station QR codes encode:
 *   metrosafar://verify/<stationId>:<hourBucket>:<hmac>
 *
 * Tokens rotate every ROTATION_HOURS (default: 24) so a photographed/shared
 * QR becomes useless at the next rotation boundary.  The validator accepts
 * the current bucket AND the previous one to handle clock skew / edge-of-hour
 * scanning.
 *
 * For dynamic displays (platform screen doors) use ROTATION_HOURS=1.
 * For printed stickers use ROTATION_HOURS=24 (set via QR_TOKEN_ROTATION_HOURS env).
 *
 * Required env var: QR_HMAC_SECRET (32-byte hex string)
 *   Generate: openssl rand -hex 32
 */

'use strict';

const crypto = require('crypto');

const SECRET = process.env.QR_HMAC_SECRET || '';
const ROTATION_HOURS = Math.max(1, Number(process.env.QR_TOKEN_ROTATION_HOURS) || 24);

function _bucket() {
  return Math.floor(Date.now() / (ROTATION_HOURS * 3600 * 1000));
}

function _sig(stationId, bucket) {
  if (!SECRET) {
    // No secret configured — used in tests / dev. Return a fixed placeholder.
    return 'devmode00000000';
  }
  return crypto
    .createHmac('sha256', SECRET)
    .update(`${stationId}:${bucket}`)
    .digest('hex')
    .slice(0, 16);
}

/**
 * Generate a station verification token for use in a QR code.
 * Returns the path component only (caller prepends metrosafar://verify/).
 *
 * @param {string} stationId
 * @returns {string}  e.g. "hyd_ameerpet:17614:a3f9c2e1b0d47f82"
 */
function generateStationToken(stationId) {
  const bucket = _bucket();
  return `${stationId}:${bucket}:${_sig(stationId, bucket)}`;
}

/**
 * Validate a scanned token.
 * Accepts current bucket and previous bucket (clock-skew grace window).
 *
 * @param {string} token  Raw token string from scanned QR.
 * @returns {{ valid: boolean, stationId?: string, reason?: string }}
 */
function validateStationToken(token) {
  if (!token || typeof token !== 'string') {
    return { valid: false, reason: 'missing_token' };
  }
  const parts = token.split(':');
  if (parts.length !== 3) {
    return { valid: false, reason: 'malformed' };
  }
  const [stationId, bucketStr, sig] = parts;
  const bucket = Number(bucketStr);
  if (!stationId || isNaN(bucket) || !sig) {
    return { valid: false, reason: 'malformed' };
  }
  const now = _bucket();
  // Accept current and one previous bucket (grace window).
  if (bucket !== now && bucket !== now - 1) {
    return { valid: false, reason: 'expired' };
  }
  if (_sig(stationId, bucket) !== sig) {
    return { valid: false, reason: 'bad_sig' };
  }
  return { valid: true, stationId };
}

module.exports = { generateStationToken, validateStationToken };
