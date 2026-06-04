/**
 * AdMob Server-Side Verification (SSV) signature verification.
 *
 * When a user completes a rewarded ad, Google's servers call:
 *   GET /api/rewards/admob-ssv?ad_network=...&key_id=...&signature=...&...
 *
 * This module fetches Google's public keys (cached in memory, refreshed every
 * 24h) and verifies the ECDSA P-256 signature of the callback payload.
 *
 * Reference: https://developers.google.com/admob/android/ssv
 */

'use strict';

const https = require('https');
const crypto = require('crypto');

const PUBLIC_KEY_URL = 'https://gstatic.com/admob/reward/verifier-keys.json';
const KEY_CACHE_TTL_MS = 24 * 60 * 60 * 1000; // 24 hours

let _keyCache = null;
let _keyCachedAt = 0;

async function _fetchPublicKeys() {
  const now = Date.now();
  if (_keyCache && now - _keyCachedAt < KEY_CACHE_TTL_MS) return _keyCache;

  return new Promise((resolve, reject) => {
    https.get(PUBLIC_KEY_URL, (res) => {
      let body = '';
      res.on('data', (chunk) => (body += chunk));
      res.on('end', () => {
        try {
          const parsed = JSON.parse(body);
          _keyCache = parsed.keys; // Array of { keyId, pem }
          _keyCachedAt = Date.now();
          resolve(_keyCache);
        } catch (e) {
          reject(new Error(`Failed to parse AdMob key response: ${e.message}`));
        }
      });
      res.on('error', reject);
    }).on('error', reject);
  });
}

/**
 * Verify the ECDSA signature on an AdMob SSV callback.
 *
 * @param {object} query  The raw query-string params from the GET request.
 * @returns {Promise<boolean>}
 */
async function verifyAdMobSSV(query) {
  const { key_id, signature } = query;
  if (!key_id || !signature) return false;

  // The signed message is the full query string EXCLUDING key_id and signature,
  // in the order AdMob sends them.
  const EXCLUDED = new Set(['key_id', 'signature']);
  const signedStr = Object.keys(query)
    .filter((k) => !EXCLUDED.has(k))
    .map((k) => `${k}=${query[k]}`)
    .join('&');

  try {
    const keys = await _fetchPublicKeys();
    const keyEntry = keys.find((k) => String(k.keyId) === String(key_id));
    if (!keyEntry) {
      return false; // unknown key_id
    }

    const verify = crypto.createVerify('SHA256');
    verify.update(signedStr);
    verify.end();

    // signature is base64url-encoded DER
    const sigBuf = Buffer.from(
      signature.replace(/-/g, '+').replace(/_/g, '/'),
      'base64',
    );
    return verify.verify(keyEntry.pem, sigBuf);
  } catch (e) {
    return false;
  }
}

module.exports = { verifyAdMobSSV };
