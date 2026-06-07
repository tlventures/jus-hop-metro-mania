'use strict';

// Secret must be set BEFORE requiring the module (it reads env at load time).
process.env.QR_HMAC_SECRET =
  process.env.QR_HMAC_SECRET ||
  '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

const { test } = require('node:test');
const assert = require('node:assert/strict');

const { generateStationToken, validateStationToken } = require('../lib/qr-tokens');

test('a freshly generated token validates and returns the station id', () => {
  const token = generateStationToken('hyd_ameerpet');
  const result = validateStationToken(token);
  assert.equal(result.valid, true);
  assert.equal(result.stationId, 'hyd_ameerpet');
});

test('a tampered signature is rejected', () => {
  const token = generateStationToken('hyd_ameerpet');
  const [stationId, bucket] = token.split(':');
  const forged = `${stationId}:${bucket}:deadbeefdeadbeef`;
  const result = validateStationToken(forged);
  assert.equal(result.valid, false);
  assert.equal(result.reason, 'bad_sig');
});

test('a token from an old bucket is expired', () => {
  const token = generateStationToken('hyd_ameerpet');
  const [stationId, bucketStr, sig] = token.split(':');
  // Two buckets in the past is outside the one-bucket grace window.
  const stale = `${stationId}:${Number(bucketStr) - 5}:${sig}`;
  const result = validateStationToken(stale);
  assert.equal(result.valid, false);
  assert.equal(result.reason, 'expired');
});

test('malformed tokens are rejected', () => {
  assert.equal(validateStationToken('').reason, 'missing_token');
  assert.equal(validateStationToken('only:two').reason, 'malformed');
  assert.equal(validateStationToken(null).reason, 'missing_token');
});
