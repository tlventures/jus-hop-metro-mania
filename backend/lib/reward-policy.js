'use strict';

const crypto = require('crypto');

function rewardLedgerId(userId, commuteSessionId, activityType, entityId) {
  return crypto.createHash('sha256').update(
    `${userId}:${commuteSessionId}:${activityType}:${entityId}`,
  ).digest('hex');
}

function rewardAttemptId(userId, commuteSessionId, activityType, entityId) {
  const hex = crypto.createHash('sha256').update(
    `attempt:${userId}:${commuteSessionId}:${activityType}:${entityId}`,
  ).digest('hex').slice(0, 32);
  return [
    hex.slice(0, 8),
    hex.slice(8, 12),
    `4${hex.slice(13, 16)}`,
    `8${hex.slice(17, 20)}`,
    hex.slice(20, 32),
  ].join('-');
}

function isRewardAttemptValid(
  attempt,
  { userId, commuteSessionId, activityType, entityId, nowMs = Date.now() },
) {
  return Boolean(
    doesRewardAttemptMatch(
      attempt,
      { userId, commuteSessionId, activityType, entityId },
    ) &&
    attempt.status === 'issued' &&
    Date.parse(attempt.expiresAt || '') > nowMs,
  );
}

function doesRewardAttemptMatch(
  attempt,
  { userId, commuteSessionId, activityType, entityId },
) {
  return Boolean(
    attempt &&
    attempt.userId === userId &&
    attempt.commuteSessionId === commuteSessionId &&
    attempt.activityType === activityType &&
    attempt.entityId === entityId,
  );
}

module.exports = {
  doesRewardAttemptMatch,
  isRewardAttemptValid,
  rewardAttemptId,
  rewardLedgerId,
};
