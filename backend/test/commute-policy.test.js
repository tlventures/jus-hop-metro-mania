'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

const {
  COMMUTE_SESSION_MAX_MS,
  gameRewardClaimKey,
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
