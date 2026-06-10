'use strict';

const COMMUTE_SESSION_MAX_MS = 3 * 60 * 60 * 1000;

function isCommuteSessionExpired(session, nowMs = Date.now()) {
  const startedAtMs = Date.parse(session?.startedAt || '');
  return !Number.isFinite(startedAtMs) ||
    startedAtMs > nowMs + 60_000 ||
    nowMs - startedAtMs > COMMUTE_SESSION_MAX_MS;
}

function gameRewardClaimKey(sessionId, gameId) {
  return `${sessionId}:${gameId}`;
}

module.exports = {
  COMMUTE_SESSION_MAX_MS,
  gameRewardClaimKey,
  isCommuteSessionExpired,
};
