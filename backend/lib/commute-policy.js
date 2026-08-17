'use strict';

const COMMUTE_SESSION_MAX_MS = 3 * 60 * 60 * 1000;
const HEARTBEAT_FRESH_MS = 90 * 1000;
const HEARTBEAT_MIN_INTERVAL_MS = 15 * 1000;
const MAX_LOCATION_ACCURACY_METERS = 100;
const MAX_NETWORK_DISTANCE_METERS = 1500;
const MAX_START_STATION_DISTANCE_METERS = 500;
const MAX_END_STATION_DISTANCE_METERS = 750;

function isCommuteSessionExpired(session, nowMs = Date.now()) {
  const startedAtMs = Date.parse(session?.startedAt || '');
  return !Number.isFinite(startedAtMs) ||
    startedAtMs > nowMs + 60_000 ||
    nowMs - startedAtMs > COMMUTE_SESSION_MAX_MS;
}

function gameRewardClaimKey(sessionId, gameId) {
  return `${sessionId}:${gameId}`;
}

function haversineMeters(a, b) {
  const toRad = (degrees) => degrees * Math.PI / 180;
  const lat1 = toRad(Number(a.lat));
  const lat2 = toRad(Number(b.lat));
  const deltaLat = lat2 - lat1;
  const deltaLng = toRad(Number(b.lng) - Number(a.lng));
  const value = Math.sin(deltaLat / 2) ** 2 +
    Math.cos(lat1) * Math.cos(lat2) * Math.sin(deltaLng / 2) ** 2;
  return 6371000 * 2 * Math.atan2(Math.sqrt(value), Math.sqrt(1 - value));
}

function isFreshHeartbeat(session, nowMs = Date.now()) {
  const heartbeatAt = Date.parse(session?.lastHeartbeatAt || '');
  return Number.isFinite(heartbeatAt) &&
    heartbeatAt <= nowMs + 30_000 &&
    nowMs - heartbeatAt <= HEARTBEAT_FRESH_MS;
}

function hasRewardEvidence(session, nowMs = Date.now()) {
  return Number(session?.validHeartbeatCount || 0) >= 1 &&
    isFreshHeartbeat(session, nowMs);
}

function hasVerifiedCompletionEvidence(session, endStation, nowMs = Date.now()) {
  if (Number(session?.validHeartbeatCount || 0) < 2 ||
      !isFreshHeartbeat(session, nowMs) ||
      !session?.lastHeartbeat ||
      !endStation) {
    return false;
  }
  return haversineMeters(session.lastHeartbeat, endStation) <=
    MAX_END_STATION_DISTANCE_METERS;
}

module.exports = {
  COMMUTE_SESSION_MAX_MS,
  HEARTBEAT_FRESH_MS,
  HEARTBEAT_MIN_INTERVAL_MS,
  MAX_LOCATION_ACCURACY_METERS,
  MAX_NETWORK_DISTANCE_METERS,
  MAX_START_STATION_DISTANCE_METERS,
  gameRewardClaimKey,
  hasRewardEvidence,
  hasVerifiedCompletionEvidence,
  haversineMeters,
  isFreshHeartbeat,
  isCommuteSessionExpired,
};
