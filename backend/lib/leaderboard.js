/**
 * lib/leaderboard.js
 * ------------------
 * Materialised leaderboard system.
 *
 * Problem: getTriviaRank() was doing a 500-doc scan on EVERY request.
 * At 10k concurrent users during a live event this becomes millions of
 * reads/min and unpredictable tail latency.
 *
 * Solution:
 *   1. A background job (refreshLeaderboard) runs every 30 s per active city,
 *      reads the 500 top scores once, writes ONE materialized summary doc.
 *   2. Read endpoints serve the materialized doc (1 read, CDN-cacheable).
 *   3. Per-user rank is cached in Redis with a 60-second TTL; on miss we
 *      use a Firestore count() aggregation (cheap) instead of scanning.
 *
 * The materializer is started by calling startLeaderboardRefresher(firestore,
 * logger). It runs in-process on a setInterval; no extra infra needed.
 * For production, move it to a Cloud Function triggered by Pub/Sub for
 * true isolation and guaranteed exactly-once execution.
 */

'use strict';

const { cacheGet, cacheSet, getRedis } = require('./redis');

const REFRESH_INTERVAL_MS = 30_000; // 30 seconds
const MATERIALIZED_COL    = 'leaderboard_materialized';
const SCORES_COL          = 'metrosafar_trivia_scores';
const TOP_N               = 50;
const SCAN_LIMIT          = 500;   // still needed for materializer, but runs once per 30s not per request
const RANK_CACHE_TTL      = 60;    // seconds
// Per-tick leader lock: on each interval every Cloud Run instance races to set
// this key with NX. Only the winner materializes that cycle, so N instances do
// the work of one (no duplicated 500-doc scans / write contention). The lock
// TTL is just under the interval so the next tick re-elects a (possibly
// different) leader — no long-lived leadership, no failover gap.
const LEADER_LOCK_KEY     = 'leaderboard:materializer:lock';
const LEADER_LOCK_TTL_MS  = REFRESH_INTERVAL_MS - 5_000;

let _firestore = null;
let _logger    = null;
let _interval  = null;

// Active city IDs to refresh (populated from cityRegistry by the caller)
const activeCities = new Set();

/**
 * Trigger the materializer to also cover this city.
 */
function trackCity(cityId) {
  if (cityId) activeCities.add(cityId);
}

/**
 * Rebuild the materialized leaderboard for one city.
 * Reads up to SCAN_LIMIT score docs, writes one summary doc.
 */
async function refreshLeaderboard(cityId) {
  if (!_firestore) return;
  try {
    const scoresRef = _firestore
      .collection(SCORES_COL)
      .doc(cityId)
      .collection('scores');

    const snap = await scoresRef
      .orderBy('score', 'desc')
      .orderBy('completedAt', 'asc')
      .limit(SCAN_LIMIT)
      .get();

    if (snap.empty) return;

    const entries = snap.docs.map((doc, i) => ({
      uid:         doc.id,
      rank:        i + 1,
      score:       doc.data().score || 0,
      name:        doc.data().name  || 'Player',
      completedAt: doc.data().completedAt || null,
    }));

    const topScores    = entries.slice(0, TOP_N);
    const playerCount  = snap.size; // accurate up to SCAN_LIMIT
    const updatedAt    = new Date().toISOString();

    await _firestore
      .collection(MATERIALIZED_COL)
      .doc(`trivia_${cityId}`)
      .set({ cityId, topScores, playerCount, updatedAt }, { merge: false });

    if (_logger) _logger.debug({ cityId, playerCount }, 'Leaderboard materialized');
  } catch (err) {
    if (_logger) _logger.warn({ err, cityId }, 'Leaderboard refresh failed');
  }
}

/**
 * Get the materialized leaderboard for a city (1 Firestore read).
 * Returns null if not yet materialized.
 */
async function getMaterializedLeaderboard(cityId) {
  if (!_firestore) return null;
  try {
    const snap = await _firestore
      .collection(MATERIALIZED_COL)
      .doc(`trivia_${cityId}`)
      .get();
    return snap.exists ? snap.data() : null;
  } catch {
    return null;
  }
}

/**
 * Get a user's rank for a city.
 * Uses Redis cache first, then a Firestore count() aggregation on miss.
 * Falls back to scanning if count() is unavailable.
 */
async function getUserRank(cityId, clientId) {
  if (!_firestore) return null;
  const cacheKey = `rank:${cityId}:${clientId}`;

  // 1. Redis cache hit
  const cached = await cacheGet(cacheKey);
  if (cached !== null) return cached;

  // 2. Get user's own score
  const myRef  = _firestore.collection(SCORES_COL).doc(cityId).collection('scores').doc(clientId);
  const mySnap = await myRef.get();
  if (!mySnap.exists) return null;

  const myScore = mySnap.data().score || 0;

  // 3. Count how many players score strictly higher (rank = that count + 1)
  try {
    const countSnap = await _firestore
      .collection(SCORES_COL)
      .doc(cityId)
      .collection('scores')
      .where('score', '>', myScore)
      .count()
      .get();

    const rank = (countSnap.data().count || 0) + 1;
    const result = { rank, score: myScore, uid: clientId };
    await cacheSet(cacheKey, result, RANK_CACHE_TTL);
    return result;
  } catch {
    // count() not available (e.g. emulator) — fall back to materialized leaderboard
    const mat = await getMaterializedLeaderboard(cityId);
    if (mat) {
      const entry = mat.topScores.find(e => e.uid === clientId);
      return entry || { rank: mat.playerCount + 1, score: myScore, uid: clientId };
    }
    return { rank: '?', score: myScore, uid: clientId };
  }
}

/**
 * Start the background refresh loop.
 * Safe to call multiple times (idempotent).
 */
function startLeaderboardRefresher(firestore, logger) {
  if (_interval) return; // already running
  _firestore = firestore;
  _logger    = logger;

  _interval = setInterval(async () => {
    // Only one instance per tick does the work (see LEADER_LOCK_KEY).
    if (!(await _acquireTickLock())) return;
    for (const cityId of activeCities) {
      await refreshLeaderboard(cityId);
    }
  }, REFRESH_INTERVAL_MS);

  // Unref so the interval does not prevent clean process exit
  if (_interval.unref) _interval.unref();

  if (logger) logger.info({ intervalMs: REFRESH_INTERVAL_MS }, 'Leaderboard refresher started');
}

/**
 * Try to become this tick's materialization leader.
 * Returns true if this instance won the lock (or if Redis isn't configured —
 * single-instance / local dev, where running unconditionally is correct).
 */
async function _acquireTickLock() {
  const redis = getRedis();
  if (!redis || redis.status !== 'ready') return true; // no Redis → run locally
  try {
    // SET key value NX PX ttl → returns 'OK' only if the key was unset.
    const res = await redis.set(
      LEADER_LOCK_KEY,
      `${process.pid}:${Date.now()}`,
      'PX',
      LEADER_LOCK_TTL_MS,
      'NX',
    );
    return res === 'OK';
  } catch (err) {
    if (_logger) _logger.warn({ err }, 'Leader lock acquire failed — skipping tick');
    return false; // on Redis error, don't risk duplicated work this tick
  }
}

module.exports = {
  trackCity,
  refreshLeaderboard,
  getMaterializedLeaderboard,
  getUserRank,
  startLeaderboardRefresher,
};
