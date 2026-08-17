'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

const {
  COMMUTE_SESSION_MAX_MS,
  gameRewardClaimKey,
  hasRewardEvidence,
  hasVerifiedCompletionEvidence,
  haversineMeters,
  isCommuteSessionExpired,
} = require('../lib/commute-policy');

test('active commute expires after the maximum session duration', () => {
  const now = Date.parse('2026-06-10T12:00:00.000Z');
  assert.equal(
    isCommuteSessionExpired({
      startedAt: new Date(now - COMMUTE_SESSION_MAX_MS - 1).toISOString(),
    }, now),
    true,
  );
  assert.equal(
    isCommuteSessionExpired({
      startedAt: new Date(now - COMMUTE_SESSION_MAX_MS + 1).toISOString(),
    }, now),
    false,
  );
});

test('invalid and future commute timestamps are rejected', () => {
  const now = Date.parse('2026-06-10T12:00:00.000Z');
  assert.equal(isCommuteSessionExpired({ startedAt: 'invalid' }, now), true);
  assert.equal(
    isCommuteSessionExpired({
      startedAt: new Date(now + 60_001).toISOString(),
    }, now),
    true,
  );
});

test('game reward claims are scoped to both ride and game', () => {
  assert.equal(gameRewardClaimKey('ride_1', 'trivia'), 'ride_1:trivia');
  assert.notEqual(
    gameRewardClaimKey('ride_1', 'trivia'),
    gameRewardClaimKey('ride_2', 'trivia'),
  );
});

test('reward evidence requires a recent accepted heartbeat', () => {
  const now = Date.parse('2026-06-10T12:00:00.000Z');
  assert.equal(hasRewardEvidence({
    validHeartbeatCount: 1,
    lastHeartbeatAt: new Date(now - 60_000).toISOString(),
  }, now), true);
  assert.equal(hasRewardEvidence({
    validHeartbeatCount: 1,
    lastHeartbeatAt: new Date(now - 91_000).toISOString(),
  }, now), false);
  assert.equal(hasRewardEvidence({
    validHeartbeatCount: 0,
    lastHeartbeatAt: new Date(now).toISOString(),
  }, now), false);
});

test('completion evidence needs two heartbeats and destination proximity', () => {
  const now = Date.parse('2026-06-10T12:00:00.000Z');
  const destination = { lat: 17.4375, lng: 78.4489 };
  const session = {
    validHeartbeatCount: 2,
    lastHeartbeatAt: new Date(now - 10_000).toISOString(),
    lastHeartbeat: { lat: 17.4376, lng: 78.4490 },
  };
  assert.equal(
    hasVerifiedCompletionEvidence(session, destination, now),
    true,
  );
  assert.equal(
    hasVerifiedCompletionEvidence({
      ...session,
      lastHeartbeat: { lat: 17.5, lng: 78.5 },
    }, destination, now),
    false,
  );
});

test('haversine distance is stable for nearby coordinates', () => {
  const meters = haversineMeters(
    { lat: 17.4375, lng: 78.4489 },
    { lat: 17.4376, lng: 78.4490 },
  );
  assert.ok(meters > 10 && meters < 20);
});
