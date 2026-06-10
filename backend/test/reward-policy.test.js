'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

const {
  doesRewardAttemptMatch,
  isRewardAttemptValid,
  rewardAttemptId,
  rewardLedgerId,
} = require('../lib/reward-policy');

test('ledger identity is stable and scoped to ride and entity', () => {
  const first = rewardLedgerId('user', 'ride-1', 'game', 'trivia');
  assert.equal(first, rewardLedgerId('user', 'ride-1', 'game', 'trivia'));
  assert.notEqual(first, rewardLedgerId('user', 'ride-2', 'game', 'trivia'));
  assert.notEqual(first, rewardLedgerId('user', 'ride-1', 'game', 'sudoku'));
});

test('attempt identity is deterministic and UUID-shaped', () => {
  const attemptId = rewardAttemptId('user', 'ride-1', 'game', 'trivia');
  assert.match(
    attemptId,
    /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-8[0-9a-f]{3}-[0-9a-f]{12}$/,
  );
  assert.equal(
    attemptId,
    rewardAttemptId('user', 'ride-1', 'game', 'trivia'),
  );
});

test('attempt must match user, ride, activity, entity, status, and expiry', () => {
  const now = Date.parse('2026-06-10T12:00:00.000Z');
  const attempt = {
    userId: 'user',
    commuteSessionId: 'ride-1',
    activityType: 'game',
    entityId: 'trivia',
    status: 'issued',
    expiresAt: new Date(now + 60_000).toISOString(),
  };
  const expected = {
    userId: 'user',
    commuteSessionId: 'ride-1',
    activityType: 'game',
    entityId: 'trivia',
    nowMs: now,
  };
  assert.equal(isRewardAttemptValid(attempt, expected), true);
  assert.equal(isRewardAttemptValid(
    { ...attempt, commuteSessionId: 'ride-2' },
    expected,
  ), false);
  assert.equal(isRewardAttemptValid(
    { ...attempt, expiresAt: new Date(now - 1).toISOString() },
    expected,
  ), false);
  assert.equal(doesRewardAttemptMatch(
    { ...attempt, status: 'consumed' },
    expected,
  ), true);
  assert.equal(doesRewardAttemptMatch(
    { ...attempt, entityId: 'sudoku' },
    expected,
  ), false);
});
