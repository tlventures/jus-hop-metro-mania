/**
 * lib/redis.js
 * ------------
 * Shared Redis connection factory.
 *
 * Exports:
 *   getRedis()         → the singleton ioredis client (or null if Redis is unconfigured)
 *   getPubClient()     → dedicated publish connection for socket.io adapter
 *   getSubClient()     → dedicated subscribe connection for socket.io adapter
 *   cacheGet(key)      → get + JSON.parse (returns null on miss/error)
 *   cacheSet(key, val, ttlSec) → JSON.stringify + SET EX (fire-and-forget on error)
 *   cacheDel(key)      → DEL (fire-and-forget on error)
 *
 * Graceful degradation: if REDIS_HOST is not set, all functions return
 * null / no-op so the app runs unchanged without Redis.
 */

'use strict';

const Redis = require('ioredis');

const REDIS_HOST = process.env.REDIS_HOST;
const REDIS_PORT = Number(process.env.REDIS_PORT || 6379);
const REDIS_PASSWORD = process.env.REDIS_PASSWORD;

let _client = null;
let _pubClient = null;
let _subClient = null;

function makeClient(name = 'main') {
  if (!REDIS_HOST) return null;

  const client = new Redis({
    host: REDIS_HOST,
    port: REDIS_PORT,
    ...(REDIS_PASSWORD ? { password: REDIS_PASSWORD } : {}),
    enableOfflineQueue: false,   // don't buffer when disconnected — degrade gracefully
    maxRetriesPerRequest: 1,     // fast fail on overloaded Redis, not hanging requests
    lazyConnect: true,
    connectTimeout: 3000,
    commandTimeout: 2000,
  });

  client.on('error', (err) => {
    // Log but never crash — Redis is an optimisation, not a hard dep.
    console.warn(`[redis:${name}] error:`, err.message);
  });

  client.connect().catch(() => {
    console.warn(`[redis:${name}] initial connect failed — degrading to no-cache`);
  });

  return client;
}

/**
 * Returns the singleton command client, or null if Redis is not configured.
 */
function getRedis() {
  if (!REDIS_HOST) return null;
  if (!_client) _client = makeClient('cmd');
  return _client;
}

/**
 * Dedicated publish client for socket.io Redis adapter.
 */
function getPubClient() {
  if (!REDIS_HOST) return null;
  if (!_pubClient) _pubClient = makeClient('pub');
  return _pubClient;
}

/**
 * Dedicated subscribe client for socket.io Redis adapter.
 * socket.io requires pub and sub to be separate connections.
 */
function getSubClient() {
  if (!REDIS_HOST) return null;
  if (!_subClient) _subClient = makeClient('sub');
  return _subClient;
}

// ---------------------------------------------------------------------------
// Convenience helpers
// ---------------------------------------------------------------------------

/**
 * Get a cached value. Returns parsed JSON, or null on miss / error / no Redis.
 */
async function cacheGet(key) {
  const redis = getRedis();
  if (!redis || redis.status !== 'ready') return null;
  try {
    const val = await redis.get(key);
    return val ? JSON.parse(val) : null;
  } catch {
    return null;
  }
}

/**
 * Set a cached value with a TTL in seconds. Fire-and-forget; never throws.
 */
async function cacheSet(key, value, ttlSec = 5) {
  const redis = getRedis();
  if (!redis || redis.status !== 'ready') return;
  try {
    await redis.set(key, JSON.stringify(value), 'EX', ttlSec);
  } catch {
    // ignore
  }
}

/**
 * Delete a cached key. Fire-and-forget; never throws.
 */
async function cacheDel(...keys) {
  const redis = getRedis();
  if (!redis || redis.status !== 'ready') return;
  try {
    if (keys.length > 0) await redis.del(...keys);
  } catch {
    // ignore
  }
}

module.exports = { getRedis, getPubClient, getSubClient, cacheGet, cacheSet, cacheDel };
