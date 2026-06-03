const express = require('express');
const cors = require('cors');
const fs = require('fs');
const http = require('http');
const path = require('path');
const crypto = require('crypto');
const { Firestore } = require('@google-cloud/firestore');
const admin = require('firebase-admin');
const helmet = require('helmet');
const rateLimit = require('express-rate-limit');
const { ipKeyGenerator } = require('express-rate-limit');
const { RedisStore } = require('rate-limit-redis');
const pino = require('pino');
const pinoHttp = require('pino-http');
const { z } = require('zod');
const { createAdapter } = require('@socket.io/redis-adapter');
const { getRedis, getPubClient, getSubClient, cacheGet, cacheSet, cacheDel } = require('./lib/redis');
const {
  trackCity,
  startLeaderboardRefresher,
  getMaterializedLeaderboard,
  getUserRank,
} = require('./lib/leaderboard');
const {
  installPhase56Middleware,
  installPhase56Routes,
  createPhase56Realtime,
  startEventOrchestrator,
  _installConvenienceSubscribes,
} = require('./phase56');

// Firebase Admin uses Cloud Run ADC for credentials. Firebase Auth tokens are
// issued by the FlutterFire project, which may be different from the Cloud Run
// project that owns Firestore.
admin.initializeApp({
  projectId: process.env.FIREBASE_PROJECT_ID || process.env.GOOGLE_CLOUD_PROJECT,
});

const PORT = Number(process.env.PORT || 8080);
const DB_PATH = path.join(__dirname, 'db.json');
const STATIONS_PATH = path.join(__dirname, 'stations.json');
const CONTENT_DIR = path.join(__dirname, 'content');
const firestore = new Firestore();

const logger = pino({ level: process.env.LOG_LEVEL || 'info' });

const staticData = JSON.parse(fs.readFileSync(DB_PATH, 'utf8'));
const stations = JSON.parse(fs.readFileSync(STATIONS_PATH, 'utf8'));
const stationWords = stations.slice(0, 18).map((station) => station.name);

// ---------------------------------------------------------------------------
// Live catalog — loaded from Firestore at startup, kept current via
// onSnapshot listeners so any admin write is reflected across all instances
// without a redeploy.  Falls back to staticData if Firestore is empty.
// ---------------------------------------------------------------------------

const CATALOG_TYPES = ['rewards', 'games', 'articles', 'surveys', 'quests', 'videos'];

/** In-memory catalog: { rewards:[], games:[], articles:[], surveys:[], quests:[], videos:[] } */
const catalog = {
  rewards:  staticData.rewards  || [],
  games:    staticData.games    || [],
  articles: staticData.articles || [],
  surveys:  staticData.surveys  || [],
  quests:   [
    { id: 'start_ride',     title: 'Start Ride Mode',       description: 'Begin a metro commute session',        points: 30, type: 'ride_started',          active: true },
    { id: 'play_game',      title: 'Play a game',           description: 'Complete any game during your ride',   points: 20, type: 'game_completed',         active: true },
    { id: 'read_article',   title: 'Read an article',       description: 'Read any article in Learn',            points: 15, type: 'article_read',           active: true },
    { id: 'station_quiz',   title: 'Answer a station quiz', description: 'Test your metro knowledge',            points: 25, type: 'station_quiz_completed', active: true },
    { id: 'check_passport', title: 'Check your passport',   description: 'View your station passport progress',  points: 10, type: 'passport_viewed',        active: true },
  ],
  videos:   staticData.videos   || [],
};

/**
 * Replace a catalog type from a Firestore QuerySnapshot.
 * Keeps the staticData fallback if Firestore returned nothing.
 */
function applyCatalogSnapshot(type, snapshot) {
  if (snapshot.empty) return; // keep current (seed-file) data
  const docs = snapshot.docs
    .map(d => ({ id: d.id, ...d.data() }))
    .filter(d => d.active !== false)
    .sort((a, b) => (a.sortOrder ?? 0) - (b.sortOrder ?? 0));
  if (docs.length > 0) catalog[type] = docs;
}

/** Subscribe to live updates for one catalog type.  Called once at startup. */
function subscribeCatalog(type) {
  firestore.collection(`catalog_${type}`)
    .onSnapshot(
      snap => applyCatalogSnapshot(type, snap),
      err  => logger.warn({ err, type }, 'Catalog snapshot error — using cached data'),
    );
}

/** Load all catalog types from Firestore once (initial read). */
async function loadCatalogFromFirestore() {
  for (const type of CATALOG_TYPES) {
    try {
      const snap = await firestore.collection(`catalog_${type}`).get();
      applyCatalogSnapshot(type, snap);
      logger.info({ type, count: catalog[type].length }, 'Catalog loaded');
    } catch (err) {
      logger.warn({ type, err }, 'Catalog initial load failed — using staticData fallback');
    }
  }
}

/** Re-read a single catalog type (called after an admin write). */
async function reloadCatalogType(type) {
  try {
    const snap = await firestore.collection(`catalog_${type}`).get();
    applyCatalogSnapshot(type, snap);
    logger.info({ type, count: catalog[type].length }, 'Catalog reloaded');
  } catch (err) {
    logger.warn({ type, err }, 'Catalog reload failed');
  }
}

// ---------------------------------------------------------------------------
// Multi-city data — loaded from content/<cityId>/ seed files at startup,
// then kept in sync with Firestore via the admin API.
// ---------------------------------------------------------------------------

/** In-memory city registry: { [cityId]: cityBundle } */
const cityRegistry = {};

// ---------------------------------------------------------------------------
// In-process metrics — tracks request counts, errors and latency in memory.
// Resets on redeploy but gives the admin a live view of backend health.
// ---------------------------------------------------------------------------
const metrics = {
  startedAt: new Date(),
  requests: { total: 0, success: 0, error4xx: 0, error5xx: 0 },
  latencyBuckets: [],      // last 1000 request durations (ms)
  recentErrors: [],        // last 50 errors [{ts, method, path, status, msg}]
  routeHits: {},           // { "GET /api/profile": count }
};

function recordMetrics(req, res, durationMs) {
  metrics.requests.total++;
  const status = res.statusCode;
  if (status >= 500) metrics.requests.error5xx++;
  else if (status >= 400) metrics.requests.error4xx++;
  else metrics.requests.success++;

  metrics.latencyBuckets.push(durationMs);
  if (metrics.latencyBuckets.length > 1000) metrics.latencyBuckets.shift();

  const key = `${req.method} ${req.path.replace(/\/[a-f0-9-]{20,}/g, '/:id')}`;
  metrics.routeHits[key] = (metrics.routeHits[key] || 0) + 1;

  if (status >= 400) {
    metrics.recentErrors.unshift({ ts: new Date().toISOString(), method: req.method, path: req.path, status, msg: res._errorMessage || '' });
    if (metrics.recentErrors.length > 50) metrics.recentErrors.pop();
  }
}


function loadCitySeedFiles() {
  if (!fs.existsSync(CONTENT_DIR)) return;
  const cityDirs = fs.readdirSync(CONTENT_DIR, { withFileTypes: true })
    .filter(d => d.isDirectory())
    .map(d => d.name);

  for (const cityId of cityDirs) {
    try {
      const cityPath     = path.join(CONTENT_DIR, cityId, 'city.json');
      const stationsPath = path.join(CONTENT_DIR, cityId, 'stations.json');
      if (!fs.existsSync(cityPath)) continue;

      const city     = JSON.parse(fs.readFileSync(cityPath, 'utf8'));
      const cityStations = fs.existsSync(stationsPath)
        ? JSON.parse(fs.readFileSync(stationsPath, 'utf8'))
        : [];

      // Load any content packs alongside the city (trivia, landmarks, stamps, sudoku_icons, …)
      const content = {};
      const contentTypes = ['trivia', 'landmarks', 'stamps', 'sudoku_icons', 'phrases', 'themes', 'audio', 'festival_windows'];
      for (const type of contentTypes) {
        const p = path.join(CONTENT_DIR, cityId, `${type}.json`);
        if (fs.existsSync(p)) {
          try { content[type] = JSON.parse(fs.readFileSync(p, 'utf8')); }
          catch (e) { logger.warn({ cityId, type, e }, 'Bad content pack JSON, skipping'); }
        }
      }

      cityRegistry[cityId] = { ...city, stations: cityStations, content };
      logger.info({
        cityId,
        stationCount: cityStations.length,
        contentPacks: Object.keys(content),
      }, 'Loaded city seed');
    } catch (err) {
      logger.warn({ cityId, err }, 'Failed to load city seed');
    }
  }
}
loadCitySeedFiles();

/** Resolve which city a lat/lng belongs to. Returns cityId or null. */
function resolveCityFromCoords(lat, lng) {
  for (const [cityId, city] of Object.entries(cityRegistry)) {
    const { bbox } = city;
    if (
      lat >= bbox.minLat && lat <= bbox.maxLat &&
      lng >= bbox.minLng && lng <= bbox.maxLng
    ) return cityId;
  }
  // Fall back to nearest city center within 75 km
  let nearest = null;
  let nearestDist = Infinity;
  for (const [cityId, city] of Object.entries(cityRegistry)) {
    const dlat = city.center.lat - lat;
    const dlng = city.center.lng - lng;
    const dist = Math.sqrt(dlat * dlat + dlng * dlng) * 111; // rough km
    if (dist < nearestDist) { nearestDist = dist; nearest = cityId; }
  }
  return nearestDist <= 75 ? nearest : null;
}

/** Seed Firestore with city data if not already present (runs async on startup). */
async function seedFirestoreCities() {
  for (const [cityId, bundle] of Object.entries(cityRegistry)) {
    try {
      const ref = firestore.collection('cities').doc(cityId);
      const snap = await ref.get();
      if (!snap.exists) {
        const { stations: cityStations, ...cityMeta } = bundle;
        await ref.set({ ...cityMeta, _seededAt: new Date() });
        // Write stations as a subcollection
        const batch = firestore.batch();
        for (const s of cityStations) {
          batch.set(ref.collection('stations').doc(s.id), s);
        }
        await batch.commit();
        logger.info({ cityId }, 'Seeded city to Firestore');
      }
    } catch (err) {
      logger.warn({ cityId, err }, 'Firestore city seed failed (non-fatal)');
    }
  }
}
seedFirestoreCities().catch(() => {}); // non-blocking

// Load catalog from Firestore, then subscribe to live updates.
loadCatalogFromFirestore().then(() => {
  for (const type of CATALOG_TYPES) subscribeCatalog(type);
}).catch(() => {
  logger.warn('Catalog Firestore load failed at startup — using staticData fallback');
  for (const type of CATALOG_TYPES) subscribeCatalog(type);
});

// ---------------------------------------------------------------------------
// Validation middleware helper
// ---------------------------------------------------------------------------

function validate(schema) {
  return (req, res, next) => {
    const result = schema.safeParse(req.body);
    if (!result.success) {
      res.status(400).json({ error: 'Validation error', detail: result.error.flatten() });
      return;
    }
    req.body = result.data;
    next();
  };
}

// ---------------------------------------------------------------------------
// Validation schemas
// ---------------------------------------------------------------------------

const profilePatchSchema = z.object({
  name: z.string().trim().min(1).max(80).optional(),
  email: z.string().trim().email().max(120).optional(),
  phone: z.string().trim().max(30).optional(),
  notificationsEnabled: z.boolean().optional(),
  digestNotificationsEnabled: z.boolean().optional(),
});

const gameCompleteSchema = z.object({
  score: z.number().int().min(0).max(100000).default(0),
  timeSpent: z.number().int().min(0).max(86400).optional(),
  cityId: z.string().trim().min(1).max(80).optional(),
  questionsAnswered: z.number().int().min(0).max(100).optional(),
  streak: z.number().int().min(0).max(100).optional(),
});

const triviaScoreSchema = z.object({
  score: z.number().int().min(0).max(100000),
  cityId: z.string().trim().min(1).max(80).optional(),
  questionsAnswered: z.number().int().min(0).max(100).optional(),
  streak: z.number().int().min(0).max(100).optional(),
  timeSpent: z.number().int().min(0).max(86400).optional(),
});

const friendAddSchema = z.object({
  friendUid: z.string().trim().min(1).max(128).optional(),
  token: z.string().trim().min(4).max(32).optional(),
}).refine((value) => value.friendUid || value.token, {
  message: 'friendUid or token is required',
});

const referralApplySchema = z.object({
  token: z.string().trim().min(4).max(32),
});

const ticketVerificationSchema = z.object({
  method: z.enum(['qr', 'manual']),
  code: z.string().trim().min(6).max(512),
});

const commuteSessionSchema = z.object({
  confidenceScore: z.number().min(0).max(1),
  vibrationScore: z.number().min(0).max(1).optional(),
  speedKmh: z.number().min(0).max(180).optional(),
  stationId: z.string().trim().max(120).optional(),
  cityId: z.string().trim().min(1).max(80).optional(),
  phase: z.enum(['detecting', 'confirmed', 'active']).optional(),
  ticketVerification: ticketVerificationSchema.optional(),
  detectedAt: z.string().optional(),
});

const commuteEndSchema = z.object({
  endStationId: z.string().trim().max(120).optional(),
  endedAt: z.string().optional(),
});

const activityEventSchema = z.object({
  type: z.string().min(1).max(80),
  entityId: z.string().max(120).optional().nullable(),
  metadata: z.object({ points: z.number().int().min(0).max(1000).optional() }).optional(),
});

const surveySubmitSchema = z.object({
  answers: z.array(z.unknown()).optional(),
});

const storyCompleteSchema = z.object({
  timeSpent: z.number().int().min(0).max(86400).optional(),
});

// ---------------------------------------------------------------------------
// Rate limiters
// ---------------------------------------------------------------------------

// Build a Redis-backed store for rate-limit-redis if Redis is available.
// Falls back to the default in-memory store so local dev is unaffected.
function makeRateLimitStore(prefix) {
  const redis = getRedis();
  if (!redis) return undefined; // use default MemoryStore
  return new RedisStore({
    prefix,
    // rate-limit-redis v4 sendCommand API
    sendCommand: (...args) => redis.call(...args),
  });
}

// Build a per-class rate limiter. Each class gets its own store key prefix
// so budgets DON'T share — gameplay can't be starved by, say, social calls.
function buildLimiter(prefix, max, windowMs = 60_000) {
  return rateLimit({
    windowMs,
    max,
    // Authenticated users key by clientId; anonymous fall back to IP.
    keyGenerator: (req) => req.clientId && req.clientId !== 'anonymous'
      ? req.clientId
      : ipKeyGenerator(req.ip),
    standardHeaders: true,
    legacyHeaders: false,
    store: makeRateLimitStore(prefix),
    message: { error: 'Too many requests', retryAfterSeconds: Math.ceil(windowMs / 1000) },
  });
}

// Gameplay / content earning — cheap, capped by the daily point cap anyway,
// so the limiter only needs to stop abuse, not normal play. Generous.
const gameLimiter    = buildLimiter('rl:game:', 60);     // games, trivia, quests
const contentLimiter = buildLimiter('rl:content:', 40);  // articles, surveys, stories, scratch, activity-events
const tripLimiter    = buildLimiter('rl:trip:', 30);     // commute sessions
const socialLimiter  = buildLimiter('rl:social:', 20);   // friends, referral

// Sensitive actions — keep tight.
const redeemLimiter  = buildLimiter('rl:redeem:', 12);   // reward redemption / watch
const accountLimiter = buildLimiter('rl:account:', 5);   // account deletion

// Backwards-compatible alias (kept so existing references still resolve);
// prefer the specific limiters above for new routes.
const claimLimiter = contentLimiter;

const generalLimiter = buildLimiter('rl:general:', 200);

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function normalizeClientId(value) {
  if (!value || typeof value !== 'string') {
    return 'anonymous';
  }

  return value.trim().toLowerCase().replace(/[^a-z0-9_-]/g, '').slice(0, 80) || 'anonymous';
}

// Tiers: Bronze (0-299) → Silver (300-599) → Gold (600-999) → Platinum (1000+)
function getTier(points) {
  if (points >= 1000) return 'Platinum';
  if (points >= 600) return 'Gold';
  if (points >= 300) return 'Silver';
  return 'Bronze';
}

function getNextTier(points) {
  if (points < 300) return { name: 'Silver', pointsNeeded: 300 - points };
  if (points < 600) return { name: 'Gold', pointsNeeded: 600 - points };
  if (points < 1000) return { name: 'Platinum', pointsNeeded: 1000 - points };
  return { name: null, pointsNeeded: 0 };
}

// Average CO₂ saved per metro ride vs. a car trip (kg).
const CO2_PER_RIDE_KG = 0.4;

function buildDerivedProfile(state) {
  const points = Number(state.points || 0);
  // CO₂ reflects ACTUAL rides taken, not points — a user who only earned
  // streak/game points has saved no CO₂ yet.
  const ridesCompleted = Number(state.ridesCompleted || 0);
  const co2SavedKg = Number((ridesCompleted * CO2_PER_RIDE_KG).toFixed(1));
  const treesEquivalent = Math.max(0, Math.round(co2SavedKg / 25));
  const nextTier = getNextTier(points);

  return {
    ...state,
    points,
    ridesCompleted,
    membershipTier: getTier(points),
    nextTierName: nextTier.name,
    pointsToNextTier: nextTier.pointsNeeded,
    co2SavedKg,
    treesEquivalent,
  };
}

function isGenericProfileName(value) {
  const normalized = String(value || '').trim().toLowerCase();
  return !normalized ||
    normalized === 'metro' ||
    normalized === 'member' ||
    normalized === 'traveler' ||
    normalized === 'metro member' ||
    normalized === 'metro traveler';
}

function isGeneratedProfileEmail(value) {
  const normalized = String(value || '').trim().toLowerCase();
  return normalized.startsWith('member-') && normalized.endsWith('@metrosafar.app');
}

function defaultUserState(clientId, firebaseUser = null) {
  const safeSuffix = clientId.slice(-6) || 'member';

  return buildDerivedProfile({
    clientId,
    name: firebaseUser?.name || 'Metro Member',
    email: firebaseUser?.email || `member-${safeSuffix}@metrosafar.app`,
    phone: firebaseUser?.phone_number || '',
    notificationsEnabled: true,
    digestNotificationsEnabled: true,
    points: 0,
    watchedVideoIds: [],
    redeemedRewardIds: [],
    visitedLandmarkIds: [],
    gameScores: {
      daily_spin: { score: 0, completions: 0 },
      trivia: { score: 0, completions: 0 },
      sudoku: { score: 0, completions: 0 },
      word_puzzle: { score: 0, completions: 0 },
      city_explorer: { score: 0, completions: 0 },
    },
    streakDay: 0,
    longestStreak: 0,
    lastStreakClaimAt: null,
    completedQuests: [],
    scratchCardWins: [],
    readArticleIds: [],
    completedSurveys: [],
    completedStories: [],
    lastUpdated: new Date().toISOString(),
  });
}

// ---------------------------------------------------------------------------
// User-state helpers with Redis cache layer
// Cache key: user:<clientId>  TTL: 5 s
// The cache is bypassed (and invalidated) whenever firebaseUser is provided
// (profile-repair path) or after any mutation.
// ---------------------------------------------------------------------------

const USER_CACHE_TTL = 5; // seconds

async function _readUserStateFromFirestore(clientId, firebaseUser = null) {
  const ref = firestore.collection('metrosafar_users').doc(clientId);
  const snapshot = await ref.get();

  if (!snapshot.exists) {
    const created = defaultUserState(clientId, firebaseUser);
    await ref.set(created);
    return created;
  }

  const existing = snapshot.data();
  const repair = {};
  if (firebaseUser?.name && isGenericProfileName(existing.name)) {
    repair.name = firebaseUser.name;
  }
  if (firebaseUser?.email && isGeneratedProfileEmail(existing.email)) {
    repair.email = firebaseUser.email;
  }

  if (Object.keys(repair).length > 0) {
    repair.lastUpdated = new Date().toISOString();
    await ref.set(repair, { merge: true });
  }

  return buildDerivedProfile({ ...existing, ...repair });
}

async function getUserState(clientId, firebaseUser = null) {
  // Skip cache on the profile-repair path (firebaseUser supplied)
  if (!firebaseUser) {
    const cached = await cacheGet(`user:${clientId}`);
    if (cached) return cached;
  }

  const state = await _readUserStateFromFirestore(clientId, firebaseUser);
  // Only cache when there was no repair write (to avoid stale-after-write)
  if (!firebaseUser) {
    await cacheSet(`user:${clientId}`, state, USER_CACHE_TTL);
  }
  return state;
}

async function saveUserState(clientId, nextState) {
  const ref = firestore.collection('metrosafar_users').doc(clientId);
  const payload = buildDerivedProfile({
    ...nextState,
    lastUpdated: new Date().toISOString(),
  });
  await ref.set(payload, { merge: true });
  // Invalidate cache so the next read sees fresh state
  await cacheDel(`user:${clientId}`);
  return payload;
}

// Run a Firestore transaction and return [result, alreadyClaimedResponse|null].
// The callback receives (txn, state) and must return { next, response }.
// Throws an error with statusCode if the transaction fails.
async function claimTransaction(clientId, cb) {
  const ref = firestore.collection('metrosafar_users').doc(clientId);
  const result = await firestore.runTransaction(async (txn) => {
    // Always read from Firestore inside a transaction — never the cache.
    const snapshot = await txn.get(ref);
    const state = snapshot.exists
      ? buildDerivedProfile(snapshot.data())
      : defaultUserState(clientId);

    const { next, response } = await cb(txn, state, ref);
    if (next) {
      const payload = buildDerivedProfile({ ...next, lastUpdated: new Date().toISOString() });
      txn.set(ref, payload, { merge: true });
    }
    return response;
  });
  // Invalidate user cache after any committed transaction
  await cacheDel(`user:${clientId}`);
  return result;
}

function withRewardState(userState) {
  const watched = new Set(userState.watchedVideoIds || []);
  const redeemed = new Set(userState.redeemedRewardIds || []);

  return {
    points: userState.points,
    membershipTier: userState.membershipTier,
    videos: catalog.videos.map((video) => ({
      ...video,
      watched: watched.has(video.id),
    })),
    rewards: catalog.rewards.map((reward) => ({
      ...reward,
      redeemed: redeemed.has(reward.id),
    })),
  };
}

function withGameState(userState) {
  const visited = new Set(userState.visitedLandmarkIds || []);

  return {
    games: catalog.games,
    explorerLandmarks: (staticData.explorerLandmarks || []).map((landmark) => ({
      ...landmark,
      visited: visited.has(landmark.id),
    })),
    stationWords,
  };
}

/**
 * Build the quest list for a given user state without a second Firestore read.
 * Also handles the daily-reset side-effect detection (but does NOT write —
 * writing is the caller's responsibility to avoid double-saves).
 */
function buildQuestsForState(userState) {
  const today = new Date().toDateString();
  const lastReset = userState.lastQuestResetAt;
  const needsReset = !lastReset || new Date(lastReset).toDateString() !== today;
  const midnight = new Date();
  midnight.setHours(23, 59, 59, 999);
  const effectiveCompleted = needsReset ? new Set() : new Set(userState.completedQuests || []);
  return {
    quests: catalog.quests.map(q => ({
      ...q,
      isCompleted: effectiveCompleted.has(q.id),
      resetAt: midnight.toISOString(),
    })),
    needsReset,
  };
}

/**
 * Returns the full home-screen payload from a single user-state object.
 * Covers: profile, streak, quests (with reset detection), wallet summary,
 * games catalog, and featured videos — eliminating 4 separate API calls.
 */
function getHomePayload(userState) {
  const rewards = withRewardState(userState);
  const { quests } = buildQuestsForState(userState);

  return {
    profile: {
      name: userState.name,
      points: userState.points,
      membershipTier: userState.membershipTier,
      nextTierName: userState.nextTierName,
      pointsToNextTier: userState.pointsToNextTier,
      co2SavedKg: userState.co2SavedKg,
      treesEquivalent: userState.treesEquivalent,
    },
    streak: {
      currentDay: userState.streakDay || 0,
      longestStreak: userState.longestStreak || 0,
      lastClaimedAt: userState.lastStreakClaimAt || null,
      totalPoints: userState.points || 0,
    },
    quests,
    wallet: {
      points: userState.points || 0,
      membershipTier: userState.membershipTier || 'Bronze',
      transactions: (userState.walletTransactions || []).slice(0, 20),
    },
    games: catalog.games,
    featuredVideos: rewards.videos.slice(0, 2),
  };
}

function sanitizeCityId(value) {
  const normalized = String(value || '').trim().toLowerCase().replace(/[^a-z0-9_-]/g, '');
  return normalized || 'hyd';
}

function getIstWeekId(date = new Date()) {
  const ist = new Date(date.getTime() + 330 * 60 * 1000);
  const dayIndex = (ist.getUTCDay() + 6) % 7; // Monday = 0
  const monday = new Date(Date.UTC(
    ist.getUTCFullYear(),
    ist.getUTCMonth(),
    ist.getUTCDate() - dayIndex,
  ));
  const yearStart = new Date(Date.UTC(monday.getUTCFullYear(), 0, 1));
  const week = Math.floor((monday - yearStart) / (7 * 24 * 60 * 60 * 1000)) + 1;
  return `${monday.getUTCFullYear()}-W${String(week).padStart(2, '0')}`;
}

function getNextIstWeekResetIso(date = new Date()) {
  const ist = new Date(date.getTime() + 330 * 60 * 1000);
  const dayIndex = (ist.getUTCDay() + 6) % 7; // Monday = 0
  const nextMondayIstMidnight = new Date(Date.UTC(
    ist.getUTCFullYear(),
    ist.getUTCMonth(),
    ist.getUTCDate() - dayIndex + 7,
    0, 0, 0, 0,
  ));
  return new Date(nextMondayIstMidnight.getTime() - 330 * 60 * 1000).toISOString();
}

function currentMonthId(date = new Date()) {
  const ist = new Date(date.getTime() + 330 * 60 * 1000);
  return `${ist.getUTCFullYear()}-${String(ist.getUTCMonth() + 1).padStart(2, '0')}`;
}

function profileDisplayName(profile) {
  const name = String(profile?.name || '').trim();
  if (name && !isGenericProfileName(name)) return name;
  const email = String(profile?.email || '').trim();
  if (email && !isGeneratedProfileEmail(email)) return email.split('@')[0];
  return 'Metro Rider';
}

function weeklyStatsBase({ clientId, profile, cityId }) {
  return {
    userId: clientId,
    cityId: sanitizeCityId(cityId || profile?.activeCityId),
    name: profileDisplayName(profile),
    updatedAt: new Date().toISOString(),
  };
}

async function incrementWeeklyStats(clientId, deltas, options = {}) {
  const weekId = options.weekId || getIstWeekId();
  const profile = options.profile || await getUserState(clientId);
  const cityId = sanitizeCityId(options.cityId || profile.activeCityId);
  const base = weeklyStatsBase({ clientId, profile, cityId });
  const inc = admin.firestore.FieldValue.increment;
  const increments = {};
  for (const [key, value] of Object.entries(deltas || {})) {
    const amount = Number(value || 0);
    if (Number.isFinite(amount) && amount !== 0) {
      increments[key] = inc(amount);
    }
  }
  if (Object.keys(increments).length === 0) return;

  const userWeekRef = firestore
    .collection('metrosafar_user_weekly_stats')
    .doc(clientId)
    .collection('weeks')
    .doc(weekId);
  const leaderboardRef = firestore
    .collection('metrosafar_weekly_leaderboards')
    .doc(weekId)
    .collection('users')
    .doc(clientId);

  await Promise.all([
    userWeekRef.set({ ...base, weekId, ...increments }, { merge: true }),
    leaderboardRef.set({ ...base, weekId, ...increments }, { merge: true }),
  ]);
}

async function getActiveCommuteSession(clientId) {
  const snap = await firestore.collection('metrosafar_commute_sessions')
    .where('userId', '==', clientId)
    .where('status', '==', 'active')
    .orderBy('updatedAt', 'desc')
    .limit(1)
    .get();
  if (snap.empty) return null;
  return { id: snap.docs[0].id, ...snap.docs[0].data() };
}

async function maybeGetCommuteMultiplier(clientId) {
  try {
    const session = await getActiveCommuteSession(clientId);
    return session ? { multiplier: 1.5, session } : { multiplier: 1, session: null };
  } catch (error) {
    logger.warn({ err: error, clientId }, 'Commute multiplier lookup failed');
    return { multiplier: 1, session: null };
  }
}

async function getTriviaRank(cityId, clientId, limit = 10) {
  const safeCityId = sanitizeCityId(cityId);
  const scoresRef = firestore.collection('metrosafar_trivia_scores').doc(safeCityId).collection('scores');
  const snap = await scoresRef.orderBy('score', 'desc').orderBy('completedAt', 'asc').limit(500).get();
  const entries = snap.docs.map((doc, index) => ({
    uid: doc.id,
    rank: index + 1,
    ...doc.data(),
  }));
  const me = entries.find((entry) => entry.uid === clientId) || null;
  return {
    cityId: safeCityId,
    rank: me?.rank || null,
    score: me?.score || 0,
    personalRecord: me?.personalRecord || 0,
    bestToday: me?.bestToday || 0,
    playerCount: entries.length,
    topScores: entries.slice(0, Math.max(1, Math.min(Number(limit) || 10, 50))),
  };
}

async function recordTriviaScore(clientId, payload) {
  const profile = await getUserState(clientId);
  const cityId = sanitizeCityId(payload.cityId || profile.activeCityId);
  const score = Number(payload.score || 0);
  const todayKey = new Date(Date.now() + 330 * 60 * 1000).toISOString().slice(0, 10);
  const ref = firestore.collection('metrosafar_trivia_scores').doc(cityId).collection('scores').doc(clientId);
  const snap = await ref.get();
  const before = snap.exists ? snap.data() : {};
  const sameDay = before.todayKey === todayKey;
  const bestToday = sameDay ? Math.max(Number(before.bestToday || 0), score) : score;
  const personalRecord = Math.max(Number(before.personalRecord || 0), score);
  const record = {
    uid: clientId,
    cityId,
    name: profileDisplayName(profile),
    score: bestToday,
    bestToday,
    personalRecord,
    todayKey,
    questionsAnswered: Number(payload.questionsAnswered || before.questionsAnswered || 0),
    streak: Number(payload.streak || before.streak || 0),
    completedAt: new Date().toISOString(),
  };
  await ref.set(record, { merge: true });
  return getTriviaRank(cityId, clientId);
}

async function createFriendship(clientId, friendUid) {
  if (!friendUid || friendUid === clientId) {
    const err = new Error('Friend must be a different user');
    err.statusCode = 400;
    throw err;
  }

  const [me, friend] = await Promise.all([
    getUserState(clientId),
    getUserState(friendUid),
  ]);
  const now = new Date().toISOString();
  const batch = firestore.batch();
  batch.set(
    firestore.collection('metrosafar_user_friends').doc(clientId).collection('friends').doc(friendUid),
    {
      friendUid,
      displayName: profileDisplayName(friend),
      photoUrl: friend.photoUrl || '',
      cityId: sanitizeCityId(friend.activeCityId || me.activeCityId),
      addedAt: now,
    },
    { merge: true },
  );
  batch.set(
    firestore.collection('metrosafar_user_friends').doc(friendUid).collection('friends').doc(clientId),
    {
      friendUid: clientId,
      displayName: profileDisplayName(me),
      photoUrl: me.photoUrl || '',
      cityId: sanitizeCityId(me.activeCityId || friend.activeCityId),
      addedAt: now,
    },
    { merge: true },
  );
  await batch.commit();
}

function makeReferralToken() {
  const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  const bytes = require('crypto').randomBytes(6);
  let suffix = '';
  for (let i = 0; i < 6; i++) suffix += alphabet[bytes[i] % alphabet.length];
  return `METRO-${suffix}`;
}

async function getOrCreateReferralCode(clientId) {
  const existing = await firestore.collection('metrosafar_referral_codes')
    .where('ownerUid', '==', clientId)
    .where('active', '==', true)
    .limit(1)
    .get();
  if (!existing.empty) {
    return { token: existing.docs[0].id, ...existing.docs[0].data() };
  }

  for (let attempt = 0; attempt < 5; attempt++) {
    const token = makeReferralToken();
    const ref = firestore.collection('metrosafar_referral_codes').doc(token);
    const snap = await ref.get();
    if (snap.exists) continue;
    const payload = {
      ownerUid: clientId,
      createdAt: new Date().toISOString(),
      active: true,
      maxUses: 10,
      usedCount: 0,
      rewardedCount: 0,
    };
    await ref.set(payload);
    return { token, ...payload };
  }
  const err = new Error('Could not generate referral code');
  err.statusCode = 500;
  throw err;
}

async function applyReferralToken(clientId, token) {
  const normalized = String(token || '').trim().toUpperCase();
  const codeRef = firestore.collection('metrosafar_referral_codes').doc(normalized);
  const codeSnap = await codeRef.get();
  if (!codeSnap.exists || codeSnap.data().active === false) {
    const err = new Error('Invalid referral code');
    err.statusCode = 404;
    throw err;
  }
  const code = codeSnap.data();
  if (code.ownerUid === clientId) {
    const err = new Error('You cannot apply your own referral code');
    err.statusCode = 400;
    throw err;
  }

  const referralId = `${code.ownerUid}_${clientId}`;
  const referralRef = firestore.collection('metrosafar_referrals').doc(referralId);
  const existing = await referralRef.get();
  if (!existing.exists) {
    await referralRef.set({
      referrerUid: code.ownerUid,
      referredUid: clientId,
      token: normalized,
      status: 'pending',
      createdAt: new Date().toISOString(),
      qualifiedAt: null,
      rewardedAt: null,
    });
    await codeRef.set({ usedCount: admin.firestore.FieldValue.increment(1) }, { merge: true });
  }

  await createFriendship(clientId, code.ownerUid);
  return { referralId, referrerUid: code.ownerUid, status: existing.exists ? existing.data().status : 'pending' };
}

async function addWalletTransaction(clientId, state, type, pointsAwarded, description) {
  const txnId = `txn_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
  const transaction = {
    id: txnId,
    type,
    entityId: type,
    pointsAwarded,
    description,
    createdAt: new Date().toISOString(),
  };
  return [transaction, ...(state.walletTransactions || [])].slice(0, 100);
}

async function qualifyReferralForUser(clientId, trigger) {
  const snap = await firestore.collection('metrosafar_referrals')
    .where('referredUid', '==', clientId)
    .where('status', '==', 'pending')
    .limit(1)
    .get();
  if (snap.empty) return null;

  const referralDoc = snap.docs[0];
  const referral = referralDoc.data();
  const monthId = currentMonthId();
  const monthSnap = await firestore.collection('metrosafar_referrals')
    .where('referrerUid', '==', referral.referrerUid)
    .where('status', '==', 'rewarded')
    .where('rewardMonth', '==', monthId)
    .limit(10)
    .get();

  if (monthSnap.size >= 10) {
    await referralDoc.ref.set({
      status: 'qualified',
      qualifiedAt: new Date().toISOString(),
      qualificationTrigger: trigger,
      rewardBlockedReason: 'monthly_cap_reached',
    }, { merge: true });
    return { status: 'qualified', rewardBlockedReason: 'monthly_cap_reached' };
  }

  const referrerState = await getUserState(referral.referrerUid);
  const referredState = await getUserState(clientId);
  const referrerTransactions = await addWalletTransaction(
    referral.referrerUid,
    referrerState,
    'referral_reward',
    150,
    'Friend completed their first activity',
  );
  const referredTransactions = await addWalletTransaction(
    clientId,
    referredState,
    'referral_welcome',
    100,
    'Referral welcome bonus',
  );

  await Promise.all([
    saveUserState(referral.referrerUid, {
      ...referrerState,
      points: referrerState.points + 150,
      walletTransactions: referrerTransactions,
    }),
    saveUserState(clientId, {
      ...referredState,
      points: referredState.points + 100,
      walletTransactions: referredTransactions,
    }),
    referralDoc.ref.set({
      status: 'rewarded',
      qualifiedAt: new Date().toISOString(),
      rewardedAt: new Date().toISOString(),
      rewardMonth: monthId,
      qualificationTrigger: trigger,
      referrerPointsAwarded: 150,
      referredPointsAwarded: 100,
    }, { merge: true }),
    firestore.collection('metrosafar_referral_codes').doc(referral.token).set({
      rewardedCount: admin.firestore.FieldValue.increment(1),
    }, { merge: true }),
  ]);

  await Promise.all([
    incrementWeeklyStats(referral.referrerUid, { pointsEarned: 150 }),
    incrementWeeklyStats(clientId, { pointsEarned: 100 }),
  ]);

  return { status: 'rewarded', referrerPointsAwarded: 150, referredPointsAwarded: 100 };
}

// ALLOWED_ORIGINS env var: comma-separated list.
// ADMIN_ORIGINS env var: comma-separated admin SPA origins (always appended).
// Default admin origins are included for local dev and Firebase Hosting.
const ADMIN_DEFAULT_ORIGINS = [
  'http://localhost:3000',
  'http://localhost:3001',
  'https://admin.metrosafar.app',
];
const ALLOWED_ORIGINS = [
  ...(process.env.ALLOWED_ORIGINS || '').split(',').map(o => o.trim()).filter(Boolean),
  ...(process.env.ADMIN_ORIGINS    || '').split(',').map(o => o.trim()).filter(Boolean),
  ...ADMIN_DEFAULT_ORIGINS,
];

function resolveCorsOrigin(origin, cb) {
  if (!origin) {
    cb(null, true);
    return;
  }

  if (ALLOWED_ORIGINS.includes(origin)) {
    cb(null, true);
    return;
  }

  if (process.env.NODE_ENV !== 'production' && ALLOWED_ORIGINS.length === 0) {
    cb(null, true);
    return;
  }

  const error = new Error('Not allowed by CORS');
  error.statusCode = 403;
  cb(error);
}

const PUBLIC_API_ROUTES = [
  { method: 'GET',  pattern: /^\/feature-flags$/ },
  { method: 'GET',  pattern: /^\/stations$/ },
  { method: 'GET',  pattern: /^\/support$/ },
  { method: 'GET',  pattern: /^\/legal\/(privacy-policy|terms)$/ },
  { method: 'GET',  pattern: /^\/tickets$/ },
  { method: 'POST', pattern: /^\/tickets$/ },
  { method: 'PATCH',pattern: /^\/tickets\/[^/]+\/cancel$/ },
  // v2 city endpoints — public (no auth needed to resolve or browse cities)
  { method: 'GET',  pattern: /^\/v2\/cities/ },
  { method: 'POST', pattern: /^\/v2\/waitlist$/ },
  { method: 'POST', pattern: /^\/internal\/weekly-digest\/run$/ },
  // Static catalog endpoints — CDN-cacheable, no auth needed (B4)
  { method: 'GET',  pattern: /^\/catalog\/(rewards|games|articles|surveys|quests|videos)$/ },
];

function isPublicApiRoute(req) {
  return PUBLIC_API_ROUTES.some((route) => (
    route.method === req.method && route.pattern.test(req.path)
  ));
}

const app = express();

app.use(helmet());

// Metrics collection — attach start time and capture on finish
app.use((req, res, next) => {
  const start = Date.now();
  res.on('finish', () => recordMetrics(req, res, Date.now() - start));
  next();
});

app.use(cors({
  origin: resolveCorsOrigin,
  credentials: true,
}));

app.use(pinoHttp({ logger }));
app.use(express.json({ limit: '1mb' }));
app.use(generalLimiter);

// Verify Firebase ID token and populate req.uid / req.firebaseUser
app.use(async (req, _res, next) => {
  const authHeader = req.header('Authorization');
  if (authHeader?.startsWith('Bearer ')) {
    const token = authHeader.slice(7);
    // Static ADMIN_API_KEY bypass (CI / bootstrap) — let it through the /api
    // auth gate so requireAdmin's key fallback can grant admin access.
    if (process.env.ADMIN_API_KEY && token === process.env.ADMIN_API_KEY) {
      req.uid = 'api-key';
    } else {
      try {
        const decoded = await admin.auth().verifyIdToken(token);
        req.uid = decoded.uid;
        req.firebaseUser = { uid: decoded.uid, email: decoded.email, name: decoded.name, phone_number: decoded.phone_number };
      } catch (_e) {
        req.authError = 'Invalid or expired authentication token';
      }
    }
  }
  req.clientId = req.uid || 'anonymous';
  next();
});

// Reject unauthenticated requests to all /api/* routes except public ones
app.use('/api', (req, res, next) => {
  if (isPublicApiRoute(req)) {
    next();
    return;
  }
  if (req.authError) {
    res.status(401).json({ error: req.authError });
    return;
  }
  if (req.clientId === 'anonymous') {
    res.status(401).json({ error: 'Authentication required' });
    return;
  }
  next();
});

const phase56Context = {
  firestore,
  stations,
  getUserState,
  saveUserState,
  logger,
};

installPhase56Middleware(app, phase56Context);

// ---------------------------------------------------------------------------
// Health / readiness
// ---------------------------------------------------------------------------

app.get('/health', (_req, res) => {
  res.json({ status: 'ok', service: 'metrosafar-backend', timestamp: new Date().toISOString() });
});

app.get('/healthz', async (_req, res) => {
  try {
    await firestore.collection('metrosafar_users').limit(1).get();
    res.json({ status: 'ready', firestore: 'ok', timestamp: new Date().toISOString() });
  } catch {
    res.status(503).json({ status: 'unavailable', firestore: 'error' });
  }
});

app.get('/readyz', async (_req, res) => {
  try {
    await firestore.collection('metrosafar_users').limit(1).get();
    res.json({
      status: 'ready',
      firestore: 'ok',
      firebaseProjectId: process.env.FIREBASE_PROJECT_ID || null,
      corsConfigured: ALLOWED_ORIGINS.length > 0,
      timestamp: new Date().toISOString(),
    });
  } catch (error) {
    logger.error({ err: error }, 'readiness check failed');
    res.status(503).json({ status: 'unavailable', firestore: 'error' });
  }
});

// ---------------------------------------------------------------------------
// Profile
// ---------------------------------------------------------------------------

app.get('/api/home', async (req, res, next) => {
  try {
    const userState = await getUserState(req.clientId, req.firebaseUser);
    const payload = getHomePayload(userState);

    // Reset completed quests at day boundary (fire-and-forget, non-blocking)
    const { needsReset } = buildQuestsForState(userState);
    if (needsReset) {
      saveUserState(req.clientId, {
        ...userState,
        completedQuests: [],
        lastQuestResetAt: new Date().toISOString(),
      }).catch(err => logger.warn({ err }, '/api/home quest-reset write failed'));
    }

    res.json(payload);
  } catch (error) {
    next(error);
  }
});

app.get('/api/profile', async (req, res, next) => {
  try {
    // Pass firebaseUser so first-time profile is seeded with real name/email
    const userState = await getUserState(req.clientId, req.firebaseUser);
    res.json(userState);
  } catch (error) {
    next(error);
  }
});

app.patch('/api/profile', validate(profilePatchSchema), async (req, res, next) => {
  try {
    const current = await getUserState(req.clientId);
    const updated = await saveUserState(req.clientId, {
      ...current,
      name: (req.body.name ?? current.name).trim().slice(0, 80) || current.name,
      email: (req.body.email ?? current.email).trim().slice(0, 120),
      phone: (req.body.phone ?? current.phone).trim().slice(0, 30),
      notificationsEnabled:
        typeof req.body.notificationsEnabled === 'boolean'
          ? req.body.notificationsEnabled
          : current.notificationsEnabled,
      digestNotificationsEnabled:
        typeof req.body.digestNotificationsEnabled === 'boolean'
          ? req.body.digestNotificationsEnabled
          : current.digestNotificationsEnabled,
    });
    res.json(updated);
  } catch (error) {
    next(error);
  }
});

app.post('/api/devices/token', validate(z.object({
  token: z.string().trim().min(16).max(4096),
  platform: z.enum(['android', 'ios', 'web', 'unknown']).default('unknown'),
})), async (req, res, next) => {
  try {
    const tokenHash = require('crypto')
      .createHash('sha256')
      .update(req.body.token)
      .digest('hex');
    await firestore
      .collection('metrosafar_users')
      .doc(req.clientId)
      .collection('devices')
      .doc(tokenHash)
      .set({
        token: req.body.token,
        platform: req.body.platform,
        updatedAt: new Date().toISOString(),
      }, { merge: true });
    res.json({ registered: true });
  } catch (error) {
    next(error);
  }
});

// ---------------------------------------------------------------------------
// Account deletion (required by Apple + Play)
// ---------------------------------------------------------------------------

app.delete('/api/account', accountLimiter, async (req, res, next) => {
  try {
    const ref = firestore.collection('metrosafar_users').doc(req.clientId);

    // Delete subcollections: stamps, episode_positions
    const stampDocs = await ref.collection('stamps').listDocuments();
    const posDocs = await ref.collection('episode_positions').listDocuments();
    const batch = firestore.batch();
    [...stampDocs, ...posDocs].forEach((docRef) => batch.delete(docRef));
    batch.delete(ref);
    await batch.commit();

    // Also clean up active trip if any
    const tripSnap = await firestore.collection('metrosafar_trips')
      .where('userId', '==', req.clientId)
      .where('status', '==', 'in_progress')
      .limit(1)
      .get();
    if (!tripSnap.empty) {
      await tripSnap.docs[0].ref.set({ status: 'abandoned', completedAt: new Date().toISOString() }, { merge: true });
    }

    // Also delete the Firebase Auth user
    try {
      await admin.auth().deleteUser(req.clientId);
    } catch (_e) {
      // Non-fatal — Firestore data already deleted
    }

    req.log.info({ clientId: req.clientId }, 'account deleted');
    res.json({ deleted: true });
  } catch (error) {
    next(error);
  }
});

// ---------------------------------------------------------------------------
// Stations / tickets
// ---------------------------------------------------------------------------

app.get('/api/stations', (_req, res) => {
  res.json({ stations });
});

app.get('/api/tickets', (_req, res) => {
  res.status(410).json({ error: 'Ticketing is not available in this release.' });
});

app.post('/api/tickets', (_req, res) => {
  res.status(410).json({ error: 'Ticketing is not available in this release.' });
});

app.patch('/api/tickets/:ticketId/cancel', (_req, res) => {
  res.status(410).json({ error: 'Ticketing is not available in this release.' });
});

// ---------------------------------------------------------------------------
// Rewards / videos
// ---------------------------------------------------------------------------

app.get('/api/rewards', async (req, res, next) => {
  try {
    const userState = await getUserState(req.clientId);
    res.json(withRewardState(userState));
  } catch (error) {
    next(error);
  }
});

app.post('/api/rewards/watch/:videoId', redeemLimiter, async (req, res, next) => {
  try {
    const video = catalog.videos.find((item) => item.id === req.params.videoId);
    if (!video) { res.status(404).json({ error: 'Video not found' }); return; }

    const response = await claimTransaction(req.clientId, async (txn, state) => {
      const watched = new Set(state.watchedVideoIds || []);
      let nextPoints = state.points;
      if (!watched.has(video.id)) {
        watched.add(video.id);
        nextPoints += Number(video.points || 0);
      }
      return {
        next: { ...state, points: nextPoints, watchedVideoIds: [...watched] },
        response: { points: nextPoints, video: { ...video, watched: true } },
      };
    });

    res.json(response);
  } catch (error) {
    next(error);
  }
});

app.post('/api/rewards/redeem/:rewardId', redeemLimiter, async (req, res, next) => {
  try {
    // Re-read directly from Firestore so we get the freshest stock/active state
    const rewardDoc = await firestore.collection('catalog_rewards').doc(req.params.rewardId).get();
    // Fall back to in-memory catalog for non-Firestore environments
    const reward = rewardDoc.exists
      ? { id: rewardDoc.id, ...rewardDoc.data() }
      : catalog.rewards.find((item) => item.id === req.params.rewardId);

    if (!reward) { res.status(404).json({ error: 'Reward not found' }); return; }
    if (reward.active === false) { res.status(400).json({ error: 'Reward is no longer available' }); return; }

    const rewardRef = rewardDoc.exists ? rewardDoc.ref : null;
    const cost = Number(reward.points || 0);
    const perUserLimit = Number(reward.perUserLimit ?? 1);  // default once per user
    const globalStock  = reward.stock != null ? Number(reward.stock) : null; // null = unlimited
    // Fulfillment type: how the user actually receives the reward.
    //   instant_code  → pull a pre-loaded voucher code from the pool (instant)
    //   affiliate_link→ deliver a link immediately (instant)
    //   manual        → admin fulfills later via the queue (default / legacy)
    const fulfillmentType = reward.fulfillmentType || 'manual';

    if (globalStock !== null && globalStock <= 0) {
      res.status(400).json({ error: 'Reward is out of stock' }); return;
    }

    const redemptionId  = `rdm_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
    const redemptionRef = firestore.collection('redemptions').doc(redemptionId);

    // Query for one available code up-front (used only for instant_code).
    const codesQuery = rewardRef
      ? rewardRef.collection('codes').where('assigned', '==', false).limit(1)
      : null;

    const response = await claimTransaction(req.clientId, async (txn, state) => {
      // ---- ALL READS FIRST (Firestore requires reads before writes) ----
      const redemptions = state.rewardRedemptions || {};
      const userCount   = Number(redemptions[reward.id] || 0);

      let stockSnap = null;
      if (rewardRef && globalStock !== null) stockSnap = await txn.get(rewardRef);

      let codeSnap = null;
      if (fulfillmentType === 'instant_code' && codesQuery) {
        codeSnap = await txn.get(codesQuery);
      }

      // ---- VALIDATION ----
      if (userCount >= perUserLimit) {
        const msg = perUserLimit === 1
          ? 'You have already redeemed this reward'
          : `You can only redeem this reward ${perUserLimit} times`;
        const err = new Error(msg); err.statusCode = 400; throw err;
      }
      if (state.points < cost) {
        const err = new Error('Not enough points'); err.statusCode = 400; throw err;
      }
      if (stockSnap && Number(stockSnap.data()?.stock ?? 0) <= 0) {
        const err = new Error('Reward is out of stock'); err.statusCode = 400; throw err;
      }

      // Resolve instant fulfillment
      let status = 'pending';
      let fulfillmentCode = null;
      let assignedCodeRef = null;
      if (fulfillmentType === 'instant_code') {
        if (!codeSnap || codeSnap.empty) {
          const err = new Error('This reward is temporarily unavailable — please try again soon.');
          err.statusCode = 409; throw err;   // no code in pool → roll back, no points lost
        }
        assignedCodeRef = codeSnap.docs[0].ref;
        fulfillmentCode = codeSnap.docs[0].data().code;
        status = 'fulfilled';
      } else if (fulfillmentType === 'affiliate_link') {
        fulfillmentCode = reward.affiliateUrl || reward.fulfillmentCode || null;
        status = fulfillmentCode ? 'fulfilled' : 'pending';
      }

      // ---- WRITES ----
      if (stockSnap) {
        txn.update(rewardRef, { stock: admin.firestore.FieldValue.increment(-1), _updatedAt: new Date() });
      }
      if (assignedCodeRef) {
        txn.update(assignedCodeRef, {
          assigned: true, assignedTo: req.clientId,
          assignedAt: new Date().toISOString(), redemptionId,
        });
      }

      const nowIso = new Date().toISOString();
      txn.set(redemptionRef, {
        id: redemptionId,
        rewardId: reward.id,
        rewardTitle: reward.title || '',
        rewardCategory: reward.category || '',
        discount: reward.discount || '',
        userId: req.clientId,
        userName: state.name || '',
        userEmail: state.email || '',
        pointsCost: cost,
        fulfillmentType,
        status,
        fulfillmentCode,
        fulfillmentNote: null,
        createdAt: nowIso,
        fulfilledAt: status === 'fulfilled' ? nowIso : null,
        fulfilledBy: status === 'fulfilled' ? 'auto' : null,
      });

      const nextRedemptions = { ...redemptions, [reward.id]: userCount + 1 };
      const redeemed = new Set(state.redeemedRewardIds || []);
      if (perUserLimit === 1) redeemed.add(reward.id);

      const next = {
        ...state,
        points: state.points - cost,
        redeemedRewardIds: [...redeemed],
        rewardRedemptions: nextRedemptions,
      };
      return {
        next,
        response: {
          points: next.points,
          redemptionId,
          status,
          fulfillmentType,
          fulfillmentCode,           // present immediately for instant types
          reward: { ...reward, redeemed: true, redemptionCount: userCount + 1 },
        },
      };
    });

    res.json(response);
  } catch (error) {
    if (error.statusCode) { res.status(error.statusCode).json({ error: error.message }); return; }
    next(error);
  }
});

// ---------------------------------------------------------------------------
// Games
// ---------------------------------------------------------------------------

app.get('/api/games', async (req, res, next) => {
  try {
    const userState = await getUserState(req.clientId);
    res.json(withGameState(userState));
  } catch (error) {
    next(error);
  }
});

app.patch('/api/games/explorer/:landmarkId', async (req, res, next) => {
  try {
    const userState = await getUserState(req.clientId);
    const landmark = (staticData.explorerLandmarks || []).find((item) => item.id === req.params.landmarkId);
    if (!landmark) { res.status(404).json({ error: 'Landmark not found' }); return; }

    const visited = new Set(userState.visitedLandmarkIds || []);
    if (visited.has(landmark.id)) { visited.delete(landmark.id); } else { visited.add(landmark.id); }
    await saveUserState(req.clientId, { ...userState, visitedLandmarkIds: [...visited] });
    res.json({
      landmark: { ...landmark, visited: visited.has(landmark.id) },
      explorerLandmarks: (staticData.explorerLandmarks || []).map((item) => ({ ...item, visited: visited.has(item.id) })),
    });
  } catch (error) {
    next(error);
  }
});

app.get('/api/legal/privacy-policy', (_req, res) => res.json(staticData.legal.privacyPolicy));
app.get('/api/legal/terms', (_req, res) => res.json(staticData.legal.terms));
app.get('/api/support', (_req, res) => res.json(staticData.support));

app.post('/api/games/:gameId/complete', gameLimiter, validate(gameCompleteSchema), async (req, res, next) => {
  try {
    const validGames = ['daily_spin', 'trivia', 'sudoku', 'word_puzzle', 'city_explorer'];
    if (!validGames.includes(req.params.gameId)) {
      res.status(404).json({ error: 'Game not found' }); return;
    }

    const commute = await maybeGetCommuteMultiplier(req.clientId);
    const response = await claimTransaction(req.clientId, async (txn, state) => {
      const now = new Date();
      const isDailySpin = req.params.gameId === 'daily_spin';
      const lastDailySpinAt = state.lastDailySpinAt ? new Date(state.lastDailySpinAt) : null;
      if (isDailySpin && lastDailySpinAt?.toDateString() === now.toDateString()) {
        return {
          next: null,
          response: {
            alreadyPlayedToday: true,
            pointsEarned: 0,
            totalPoints: state.points,
            gameScore: state.gameScores?.daily_spin || { score: 0, completions: 0 },
          },
        };
      }

      const gameScores = state.gameScores || {};
      const current = gameScores[req.params.gameId] || { score: 0, completions: 0 };
      const newScore = Math.max(current.score, Number(req.body.score) || 0);
      const basePoints = Math.min(50, Math.max(15, Math.floor(Number(req.body.score) / 2)));
      const pointsEarned = Math.round(basePoints * commute.multiplier);

      // Auto-complete the 'play_game' daily quest in the SAME transaction so
      // the client doesn't need a separate /quests/.../complete round-trip.
      const completed = new Set(state.completedQuests || []);
      let questPointsEarned = 0;
      if (!completed.has('play_game') && QUEST_POINTS['play_game']) {
        completed.add('play_game');
        questPointsEarned = QUEST_POINTS['play_game'];
      }

      const next = {
        ...state,
        points: state.points + pointsEarned + questPointsEarned,
        completedQuests: [...completed],
        gameScores: { ...gameScores, [req.params.gameId]: { score: newScore, completions: current.completions + 1 } },
        ...(isDailySpin ? { lastDailySpinAt: now.toISOString() } : {}),
      };
      return {
        next,
        response: {
          pointsEarned,
          questCompleted: questPointsEarned > 0,
          questPointsEarned,
          totalPoints: next.points,
          commuteMultiplier: commute.multiplier,
          commuteSessionId: commute.session?.id || null,
          gameScore: next.gameScores[req.params.gameId],
          completedQuests: next.completedQuests,
        },
      };
    });

    if (!response.alreadyPlayedToday && response.pointsEarned > 0) {
      try {
        await incrementWeeklyStats(req.clientId, {
          gamesPlayed: 1,
          pointsEarned: response.pointsEarned,
        }, { cityId: req.body.cityId });
        const referral = await qualifyReferralForUser(req.clientId, 'first_game');
        if (referral) response.referral = referral;
      } catch (error) {
        logger.warn({ err: error, clientId: req.clientId }, 'Post-game retention hooks failed');
      }
    }

    if (!response.alreadyPlayedToday && req.params.gameId === 'trivia') {
      try {
        response.trivia = await recordTriviaScore(req.clientId, req.body);
      } catch (error) {
        logger.warn({ err: error, clientId: req.clientId }, 'Trivia score recording failed');
      }
    }

    res.json(response);
  } catch (error) {
    next(error);
  }
});

// ---------------------------------------------------------------------------
// Streak (transactional)
// ---------------------------------------------------------------------------

app.post('/api/streak/claim', gameLimiter, async (req, res, next) => {
  try {
    const response = await claimTransaction(req.clientId, async (txn, state) => {
      const now = new Date();
      const lastClaim = state.lastStreakClaimAt ? new Date(state.lastStreakClaimAt) : null;
      const msSince = lastClaim ? (now - lastClaim) : Infinity;
      if (msSince < 24 * 60 * 60 * 1000) {
        const err = new Error('Streak can only be claimed once per 24 hours'); err.statusCode = 400; throw err;
      }
      // Reset the streak if a full day was missed (>48h since last claim).
      const continuing = msSince <= 48 * 60 * 60 * 1000;
      const newDay = continuing ? (state.streakDay || 0) + 1 : 1;
      const newLongest = Math.max(state.longestStreak || 0, newDay);
      const pointsEarned = 5 * newDay;
      const next = { ...state, points: state.points + pointsEarned, streakDay: newDay, longestStreak: newLongest, lastStreakClaimAt: now.toISOString() };
      return { next, response: { streakDay: newDay, longestStreak: newLongest, pointsEarned, totalPoints: next.points, reset: !continuing } };
    });

    res.json(response);
  } catch (error) {
    if (error.statusCode) { res.status(error.statusCode).json({ error: error.message }); return; }
    next(error);
  }
});

// ---------------------------------------------------------------------------
// Quests (transactional)
// ---------------------------------------------------------------------------

const QUEST_POINTS = {
  'play_game': 20, 'watch_video': 15, 'read_article': 15,
  'start_ride': 30, 'station_quiz': 25, 'check_passport': 10,
};

app.post('/api/quests/:questId/complete', gameLimiter, async (req, res, next) => {
  try {
    if (!QUEST_POINTS[req.params.questId]) { res.status(404).json({ error: 'Quest not found' }); return; }

    const response = await claimTransaction(req.clientId, async (txn, state) => {
      const completed = new Set(state.completedQuests || []);
      if (completed.has(req.params.questId)) {
        const err = new Error('Quest already completed today'); err.statusCode = 400; throw err;
      }
      completed.add(req.params.questId);
      const pointsEarned = QUEST_POINTS[req.params.questId];
      const next = { ...state, points: state.points + pointsEarned, completedQuests: [...completed] };
      return { next, response: { questId: req.params.questId, pointsEarned, totalPoints: next.points, completedQuests: next.completedQuests } };
    });

    res.json(response);
  } catch (error) {
    if (error.statusCode) { res.status(error.statusCode).json({ error: error.message }); return; }
    next(error);
  }
});

app.get('/api/games/leaderboard', async (req, res, next) => {
  try {
    const period = req.query.period || 'week';
    const mockLeaderboard = [
      { rank: 1, name: 'Pro Player', score: 2450, tier: 'Platinum' },
      { rank: 2, name: 'City Explorer', score: 2100, tier: 'Gold' },
      { rank: 3, name: 'Word Master', score: 1950, tier: 'Gold' },
      { rank: 4, name: 'Trivia King', score: 1800, tier: 'Silver' },
      { rank: 5, name: 'Puzzle Solver', score: 1650, tier: 'Silver' },
    ];
    const userState = await getUserState(req.clientId);
    const totalScore = Object.values(userState.gameScores || {}).reduce((sum, g) => sum + (g.score || 0), 0);
    res.json({ period, topPlayers: mockLeaderboard, yourScore: totalScore, yourRank: Math.floor(Math.random() * 10) + 1 });
  } catch (error) {
    next(error);
  }
});

// ---------------------------------------------------------------------------
// Scratch cards (transactional — one scratch per card per user)
// ---------------------------------------------------------------------------

app.post('/api/scratch-cards/:cardId/scratch', contentLimiter, async (req, res, next) => {
  try {
    const cardId = req.params.cardId;
    const response = await claimTransaction(req.clientId, async (txn, state) => {
      const wins = state.scratchCardWins || [];
      const alreadyScratched = wins.some((w) => w.cardId === cardId);
      if (alreadyScratched) {
        const err = new Error('Card already scratched'); err.statusCode = 400; throw err;
      }
      const rewards = [25, 50, 75, 100, 150, 200];
      const reward = rewards[Math.floor(Math.random() * rewards.length)];
      const next = {
        ...state,
        points: state.points + reward,
        scratchCardWins: [...wins, { cardId, reward, timestamp: new Date().toISOString() }],
      };
      return { next, response: { reward, totalPoints: next.points, message: `You won ${reward} points!` } };
    });

    res.json(response);
  } catch (error) {
    if (error.statusCode) { res.status(error.statusCode).json({ error: error.message }); return; }
    next(error);
  }
});

// ---------------------------------------------------------------------------
// Articles
// ---------------------------------------------------------------------------

app.get('/api/articles', async (req, res, next) => {
  try {
    const userState = await getUserState(req.clientId);
    const read = new Set(userState.readArticleIds || []);
    res.json({
      articles: catalog.articles.map((article) => ({ ...article, isRead: read.has(article.id) })),
      totalPoints: userState.points,
    });
  } catch (error) {
    next(error);
  }
});

app.post('/api/articles/:articleId/read', contentLimiter, async (req, res, next) => {
  try {
    const article = catalog.articles.find((a) => a.id === req.params.articleId);
    if (!article) { res.status(404).json({ error: 'Article not found' }); return; }

    const response = await claimTransaction(req.clientId, async (txn, state) => {
      const read = new Set(state.readArticleIds || []);
      let pointsEarned = 0;
      if (!read.has(article.id)) { read.add(article.id); pointsEarned = article.points || 0; }
      const next = { ...state, points: state.points + pointsEarned, readArticleIds: [...read] };
      return { next, response: { pointsEarned, totalPoints: next.points, article: { ...article, isRead: true } } };
    });

    if (response.pointsEarned > 0) {
      await incrementWeeklyStats(req.clientId, {
        articlesRead: 1,
        pointsEarned: response.pointsEarned,
      }).catch((error) => logger.warn({ err: error, clientId: req.clientId }, 'Article weekly stats failed'));
    }

    res.json(response);
  } catch (error) {
    next(error);
  }
});

// ---------------------------------------------------------------------------
// Surveys (transactional)
// ---------------------------------------------------------------------------

app.get('/api/surveys', async (req, res, next) => {
  try {
    const userState = await getUserState(req.clientId);
    const completed = new Set(userState.completedSurveys || []);
    res.json({
      surveys: catalog.surveys.map((survey) => ({ ...survey, isCompleted: completed.has(survey.id) })),
      totalPoints: userState.points,
    });
  } catch (error) {
    next(error);
  }
});

app.post('/api/surveys/:surveyId/submit', contentLimiter, validate(surveySubmitSchema), async (req, res, next) => {
  try {
    const survey = catalog.surveys.find((s) => s.id === req.params.surveyId);
    if (!survey) { res.status(404).json({ error: 'Survey not found' }); return; }

    const response = await claimTransaction(req.clientId, async (txn, state) => {
      const completed = new Set(state.completedSurveys || []);
      if (completed.has(survey.id)) {
        const err = new Error('Survey already completed'); err.statusCode = 400; throw err;
      }
      completed.add(survey.id);
      const pointsEarned = survey.points || 0;
      const next = { ...state, points: state.points + pointsEarned, completedSurveys: [...completed] };
      return { next, response: { pointsEarned, totalPoints: next.points, survey: { ...survey, isCompleted: true } } };
    });

    if (response.pointsEarned > 0) {
      await incrementWeeklyStats(req.clientId, {
        surveysCompleted: 1,
        pointsEarned: response.pointsEarned,
      }).catch((error) => logger.warn({ err: error, clientId: req.clientId }, 'Survey weekly stats failed'));
    }

    res.json(response);
  } catch (error) {
    if (error.statusCode) { res.status(error.statusCode).json({ error: error.message }); return; }
    next(error);
  }
});

// ---------------------------------------------------------------------------
// Stories (transactional)
// ---------------------------------------------------------------------------

app.get('/api/stories', async (req, res, next) => {
  try {
    const userState = await getUserState(req.clientId);
    const completed = new Set(userState.completedStories || []);
    res.json({
      stories: (staticData.stories || []).map((story) => ({ ...story, isCompleted: completed.has(story.id) })),
      totalPoints: userState.points,
    });
  } catch (error) {
    next(error);
  }
});

app.post('/api/stories/:storyId/complete', contentLimiter, validate(storyCompleteSchema), async (req, res, next) => {
  try {
    const story = (staticData.stories || []).find((s) => s.id === req.params.storyId);
    if (!story) { res.status(404).json({ error: 'Story not found' }); return; }

    const response = await claimTransaction(req.clientId, async (txn, state) => {
      const completed = new Set(state.completedStories || []);
      let pointsEarned = 0;
      if (!completed.has(story.id)) { completed.add(story.id); pointsEarned = story.points || 25; }
      const next = { ...state, points: state.points + pointsEarned, completedStories: [...completed] };
      return { next, response: { pointsEarned, totalPoints: next.points, story: { ...story, isCompleted: true } } };
    });

    if (response.pointsEarned > 0) {
      await incrementWeeklyStats(req.clientId, {
        storiesRead: 1,
        pointsEarned: response.pointsEarned,
      }).catch((error) => logger.warn({ err: error, clientId: req.clientId }, 'Story weekly stats failed'));
    }

    res.json(response);
  } catch (error) {
    next(error);
  }
});

// ---------------------------------------------------------------------------
// Activity events — unified earning pipeline with daily cap (transactional)
// ---------------------------------------------------------------------------

const ACTIVITY_POINT_RULES = {
  game_completed:         { base: 20, max: 50 },
  quest_completed:        { base: 20, max: 30 },
  article_read:           { base: 15, max: 15 },
  survey_submitted:       { base: 20, max: 20 },
  story_completed:        { base: 25, max: 25 },
  ride_started:           { base: 30, max: 30 },
  ride_completed:         { base: 20, max: 20 },
  stamp_claimed:          { base: 10, max: 15 },
  station_quiz_completed: { base: 25, max: 25 },
  passport_viewed:        { base: 10, max: 10 },
};
const DAILY_POINT_CAP = 500;
const TOP_N = 50; // max leaderboard entries served to clients

function activityDescription(type, entityId) {
  const labels = {
    game_completed: `Completed ${entityId || 'game'}`,
    quest_completed: 'Quest completed',
    article_read: 'Read article',
    survey_submitted: 'Survey completed',
    story_completed: 'Station story completed',
    ride_started: 'Started metro ride',
    ride_completed: 'Completed metro ride',
    stamp_claimed: `Stamp: ${entityId || 'station'}`,
    station_quiz_completed: 'Station quiz answered',
    passport_viewed: 'Checked passport',
  };
  return labels[type] || type;
}

app.get('/api/quests/today', async (req, res, next) => {
  try {
    const userState = await getUserState(req.clientId);
    const { quests, needsReset } = buildQuestsForState(userState);

    if (needsReset) {
      await saveUserState(req.clientId, {
        ...userState,
        completedQuests: [],
        lastQuestResetAt: new Date().toISOString(),
      });
    }

    res.json({ quests });
  } catch (error) {
    next(error);
  }
});

app.post('/api/activity-events', contentLimiter, validate(activityEventSchema), async (req, res, next) => {
  try {
    const { type, entityId, metadata } = req.body;
    if (!ACTIVITY_POINT_RULES[type]) { res.status(400).json({ error: `Unknown activity type: ${type}` }); return; }

    const commute = await maybeGetCommuteMultiplier(req.clientId);
    const response = await claimTransaction(req.clientId, async (txn, state) => {
      const today = new Date().toDateString();
      const isNewDay = !state.lastDailyEarnDate || new Date(state.lastDailyEarnDate).toDateString() !== today;
      const currentDailyEarned = isNewDay ? 0 : (state.dailyPointsEarned || 0);

      if (currentDailyEarned >= DAILY_POINT_CAP) {
        return {
          next: null,
          response: { pointsAwarded: 0, reason: 'daily_cap_reached', totalPoints: state.points, dailyEarned: currentDailyEarned, dailyCap: DAILY_POINT_CAP },
        };
      }

      const rule = ACTIVITY_POINT_RULES[type];
      const requested = metadata?.points ? Math.min(Number(metadata.points), rule.max) : rule.base;
      const boosted = Math.round(requested * commute.multiplier);
      const pointsAwarded = Math.min(boosted, DAILY_POINT_CAP - currentDailyEarned);
      const txnId = `txn_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
      const txnRecord = {
        id: txnId, type, entityId: entityId || null, pointsAwarded,
        description: activityDescription(type, entityId), createdAt: new Date().toISOString(),
      };
      const transactions = [txnRecord, ...(state.walletTransactions || [])].slice(0, 100);
      const next = {
        ...state,
        points: state.points + pointsAwarded,
        dailyPointsEarned: currentDailyEarned + pointsAwarded,
        lastDailyEarnDate: new Date().toISOString(),
        walletTransactions: transactions,
        // Lifetime ride counter drives the CO₂ estimate.
        ...(type === 'ride_completed'
            ? { ridesCompleted: (state.ridesCompleted || 0) + 1 }
            : {}),
      };
      return {
        next,
        response: {
          transactionId: txnId,
          pointsAwarded,
          commuteMultiplier: commute.multiplier,
          commuteSessionId: commute.session?.id || null,
          totalPoints: next.points,
          dailyEarned: currentDailyEarned + pointsAwarded,
          dailyCap: DAILY_POINT_CAP,
        },
      };
    });

    if (response.pointsAwarded > 0) {
      try {
        const deltas = { pointsEarned: response.pointsAwarded };
        if (type === 'article_read') deltas.articlesRead = 1;
        if (type === 'survey_submitted') deltas.surveysCompleted = 1;
        if (type === 'story_completed') deltas.storiesRead = 1;
        if (type === 'ride_completed') deltas.tripsCompleted = 1;
        await incrementWeeklyStats(req.clientId, deltas);
        if (type === 'ride_completed') {
          const referral = await qualifyReferralForUser(req.clientId, 'first_trip');
          if (referral) response.referral = referral;
        }
      } catch (error) {
        logger.warn({ err: error, clientId: req.clientId }, 'Activity retention hooks failed');
      }
    }

    res.json(response);
  } catch (error) {
    next(error);
  }
});

// ===========================================================================
// STATIC CATALOG ENDPOINTS (B4)
// Auth-free, CDN-cacheable.  No user state merged — clients fetch
// /api/me/catalog-state separately and merge locally.
// Listed in PUBLIC_API_ROUTES above so the auth gate is bypassed.
// ===========================================================================

const CATALOG_CACHE_SECONDS = 60;

function setCatalogCacheHeaders(res) {
  res.set('Cache-Control', `public, max-age=${CATALOG_CACHE_SECONDS}, s-maxage=${CATALOG_CACHE_SECONDS * 5}`);
  res.set('Vary', 'Accept-Encoding');
}

app.get('/api/catalog/:type', (req, res) => {
  const { type } = req.params;
  if (!CATALOG_TYPES.includes(type)) {
    return res.status(400).json({ error: `type must be one of: ${CATALOG_TYPES.join(', ')}` });
  }
  setCatalogCacheHeaders(res);
  res.json({ type, items: catalog[type], count: catalog[type].length });
});

// ---------------------------------------------------------------------------
// Per-user catalog state — the thin overlay the client merges onto the catalog
// (redeemed IDs, read IDs, watched IDs, etc.)
// ---------------------------------------------------------------------------

app.get('/api/me/catalog-state', async (req, res, next) => {
  try {
    const userState = await getUserState(req.clientId);
    res.json({
      redeemedRewardIds:    userState.redeemedRewardIds    || [],
      rewardRedemptions:    userState.rewardRedemptions    || {},
      readArticleIds:       userState.readArticleIds       || [],
      watchedVideoIds:      userState.watchedVideoIds      || [],
      completedSurveys:     userState.completedSurveys     || [],
      visitedLandmarkIds:   userState.visitedLandmarkIds   || [],
      completedQuests:      userState.completedQuests      || [],
    });
  } catch (error) {
    next(error);
  }
});

// GET /api/me/redemptions — the user's redemption history (My Redemptions screen)
app.get('/api/me/redemptions', async (req, res, next) => {
  try {
    const snap = await firestore.collection('redemptions')
      .where('userId', '==', req.clientId)
      .orderBy('createdAt', 'desc')
      .limit(100)
      .get();
    const items = snap.docs.map(d => {
      const r = d.data();
      return {
        id: r.id,
        rewardTitle: r.rewardTitle,
        rewardCategory: r.rewardCategory,
        discount: r.discount,
        pointsCost: r.pointsCost,
        status: r.status,
        fulfillmentType: r.fulfillmentType || 'manual',
        // Only expose the code once the redemption is fulfilled.
        fulfillmentCode: r.status === 'fulfilled' ? r.fulfillmentCode : null,
        fulfillmentNote: r.fulfillmentNote || null,
        createdAt: r.createdAt,
        fulfilledAt: r.fulfilledAt,
      };
    });
    res.json({ redemptions: items, count: items.length });
  } catch (error) {
    next(error);
  }
});

// GET /api/notifications/feed — in-app notification inbox (recent broadcasts)
app.get('/api/notifications/feed', async (req, res, next) => {
  try {
    const snap = await firestore.collection('app_notifications')
      .orderBy('createdAt', 'desc')
      .limit(50)
      .get();
    const items = snap.docs.map(d => ({ id: d.id, ...d.data() }));
    res.json({ notifications: items, count: items.length });
  } catch (error) {
    next(error);
  }
});

// POST /api/rewards/watch-ad — award points after a rewarded ad completes.
// Daily-capped to prevent abuse; the client only calls this on the SDK's
// verified userEarnedReward callback.
const AD_REWARD_POINTS = 15;
const AD_REWARD_DAILY_LIMIT = 5;

app.post('/api/rewards/watch-ad', redeemLimiter, async (req, res, next) => {
  try {
    const response = await claimTransaction(req.clientId, async (txn, state) => {
      const today = new Date().toDateString();
      const isNewDay = state.adWatchDate !== today;
      const watchesToday = isNewDay ? 0 : (state.adWatchesToday || 0);

      if (watchesToday >= AD_REWARD_DAILY_LIMIT) {
        return {
          next: null,
          response: {
            pointsAwarded: 0,
            reason: 'ad_daily_limit_reached',
            watchesToday,
            dailyLimit: AD_REWARD_DAILY_LIMIT,
            totalPoints: state.points,
          },
        };
      }

      const next = {
        ...state,
        points: state.points + AD_REWARD_POINTS,
        adWatchDate: today,
        adWatchesToday: watchesToday + 1,
      };
      return {
        next,
        response: {
          pointsAwarded: AD_REWARD_POINTS,
          watchesToday: watchesToday + 1,
          dailyLimit: AD_REWARD_DAILY_LIMIT,
          totalPoints: next.points,
        },
      };
    });
    res.json(response);
  } catch (error) {
    next(error);
  }
});

// ===========================================================================

app.get('/api/wallet/transactions', async (req, res, next) => {
  try {
    const userState = await getUserState(req.clientId);
    res.json({ transactions: (userState.walletTransactions || []).slice(0, 50), totalPoints: userState.points });
  } catch (error) {
    next(error);
  }
});

app.post('/api/waitlist', async (req, res, next) => {
  try {
    const userState = await getUserState(req.clientId);
    const alreadyJoined = userState.waitlistJoined || false;
    if (!alreadyJoined) { await saveUserState(req.clientId, { ...userState, waitlistJoined: true }); }
    res.json({ success: true, alreadyJoined });
  } catch (error) {
    next(error);
  }
});

// ---------------------------------------------------------------------------
// Retention: score-to-beat trivia
// ---------------------------------------------------------------------------

// ── GET /api/games/trivia/rank
// Returns caller's rank using Redis cache + Firestore count() aggregation.
// No 500-doc scan; sub-millisecond for cached users.
app.get('/api/games/trivia/rank', async (req, res, next) => {
  try {
    const profile = await getUserState(req.clientId);
    const cityId  = sanitizeCityId(req.query.cityId || profile.activeCityId);
    trackCity(cityId);

    const rankData = await getUserRank(cityId, req.clientId);
    if (!rankData) {
      return res.json({ cityId, rank: null, score: 0, message: 'No score recorded yet' });
    }
    res.json({ cityId, ...rankData });
  } catch (error) {
    next(error);
  }
});

// ── POST /api/games/trivia/score — records score and triggers async leaderboard refresh
app.post('/api/games/trivia/score', gameLimiter, validate(triviaScoreSchema), async (req, res, next) => {
  try {
    const rank = await recordTriviaScore(req.clientId, req.body);
    const cityId = sanitizeCityId(req.body.cityId || '');
    trackCity(cityId);
    // Trigger an immediate refresh for this city (non-blocking)
    if (cityId) getMaterializedLeaderboard(cityId).catch(() => {});
    res.json(rank);
  } catch (error) {
    next(error);
  }
});

// ── GET /api/games/trivia/leaderboard
// Serves the pre-materialized doc (1 read, CDN-cacheable to 30 s).
// Falls back to the legacy scan only if not yet materialized.
app.get('/api/games/trivia/leaderboard', async (req, res, next) => {
  try {
    const profile  = await getUserState(req.clientId);
    const cityId   = sanitizeCityId(req.query.cityId || profile.activeCityId);
    const limit    = Math.max(1, Math.min(Number(req.query.limit || 10), TOP_N));
    trackCity(cityId);

    const mat = await getMaterializedLeaderboard(cityId);
    if (mat) {
      const yourRank = await getUserRank(cityId, req.clientId);
      // Allow CDN / browser to cache for up to 30s (refresher interval)
      res.set('Cache-Control', 'public, max-age=30, s-maxage=30');
      return res.json({
        cityId,
        leaderboard:  mat.topScores.slice(0, limit),
        yourRank:     yourRank?.rank ?? null,
        playerCount:  mat.playerCount,
        updatedAt:    mat.updatedAt,
        source:       'materialized',
      });
    }

    // Fallback: legacy scan (first request before first materializer run)
    const rank = await getTriviaRank(cityId, req.clientId, limit);
    res.json({ cityId, leaderboard: rank.topScores, yourRank: rank.rank, playerCount: rank.playerCount, source: 'live' });
  } catch (error) {
    next(error);
  }
});

// ---------------------------------------------------------------------------
// Retention: referrals and friend leaderboard
// ---------------------------------------------------------------------------

app.post('/api/referral/generate', async (req, res, next) => {
  try {
    const code = await getOrCreateReferralCode(req.clientId);
    const link = `https://metrosafar.app/join?ref=${encodeURIComponent(code.token)}`;
    res.json({
      token: code.token,
      link,
      usedCount: code.usedCount || 0,
      rewardedCount: code.rewardedCount || 0,
      shareMessage: `Use my MetroSafar code ${code.token} or tap ${link}`,
    });
  } catch (error) {
    next(error);
  }
});

app.post('/api/referral/apply', socialLimiter, validate(referralApplySchema), async (req, res, next) => {
  try {
    const referral = await applyReferralToken(req.clientId, req.body.token);
    res.json({ applied: true, referral });
  } catch (error) {
    if (error.statusCode) { res.status(error.statusCode).json({ error: error.message }); return; }
    next(error);
  }
});

app.get('/api/referral/status', async (req, res, next) => {
  try {
    const [code, outgoing, incoming] = await Promise.all([
      getOrCreateReferralCode(req.clientId),
      firestore.collection('metrosafar_referrals').where('referrerUid', '==', req.clientId).limit(50).get(),
      firestore.collection('metrosafar_referrals').where('referredUid', '==', req.clientId).limit(10).get(),
    ]);
    res.json({
      code: code.token,
      usedCount: code.usedCount || 0,
      rewardedCount: code.rewardedCount || 0,
      outgoing: outgoing.docs.map((doc) => ({ id: doc.id, ...doc.data() })),
      incoming: incoming.docs.map((doc) => ({ id: doc.id, ...doc.data() })),
    });
  } catch (error) {
    next(error);
  }
});

app.post('/api/social/invite', async (req, res, next) => {
  try {
    const code = await getOrCreateReferralCode(req.clientId);
    const profile = await getUserState(req.clientId);
    const cityId = sanitizeCityId(profile.activeCityId || req.query.cityId);
    const rank = await getTriviaRank(cityId, req.clientId).catch(() => ({ rank: null }));
    const link = `https://metrosafar.app/join?ref=${encodeURIComponent(code.token)}`;
    const rankText = rank.rank ? `I'm ranked #${rank.rank} in MetroSafar.` : 'Join me on MetroSafar.';
    res.json({
      token: code.token,
      link,
      shareMessage: `${rankText} Use my code ${code.token} and beat me this week: ${link}`,
    });
  } catch (error) {
    next(error);
  }
});

app.get('/api/social/friends', async (req, res, next) => {
  try {
    const snap = await firestore.collection('metrosafar_user_friends').doc(req.clientId).collection('friends')
      .orderBy('addedAt', 'desc')
      .limit(100)
      .get();
    res.json({ friends: snap.docs.map((doc) => ({ id: doc.id, ...doc.data() })) });
  } catch (error) {
    next(error);
  }
});

app.post('/api/social/friends/add', socialLimiter, validate(friendAddSchema), async (req, res, next) => {
  try {
    let friendUid = req.body.friendUid;
    if (req.body.token) {
      const referral = await applyReferralToken(req.clientId, req.body.token);
      friendUid = referral.referrerUid;
    } else {
      await createFriendship(req.clientId, friendUid);
    }
    const friend = await getUserState(friendUid);
    res.json({ added: true, friend: { uid: friendUid, displayName: profileDisplayName(friend) } });
  } catch (error) {
    if (error.statusCode) { res.status(error.statusCode).json({ error: error.message }); return; }
    next(error);
  }
});

app.get('/api/social/leaderboard/weekly', async (req, res, next) => {
  try {
    const profile = await getUserState(req.clientId);
    const cityId = sanitizeCityId(req.query.cityId || profile.activeCityId);
    const weekId = req.query.weekId || getIstWeekId();
    const friendSnap = await firestore.collection('metrosafar_user_friends').doc(req.clientId).collection('friends').get();
    const ids = [req.clientId, ...friendSnap.docs.map((doc) => doc.id)];
    const stats = await Promise.all(ids.map(async (uid) => {
      const doc = await firestore.collection('metrosafar_user_weekly_stats').doc(uid).collection('weeks').doc(weekId).get();
      if (doc.exists) return { uid, ...doc.data() };
      const user = uid === req.clientId ? profile : await getUserState(uid).catch(() => null);
      return {
        uid,
        userId: uid,
        name: profileDisplayName(user),
        cityId: sanitizeCityId(user?.activeCityId || cityId),
        pointsEarned: 0,
        gamesPlayed: 0,
      };
    }));
    const friends = stats
      .sort((a, b) => Number(b.pointsEarned || 0) - Number(a.pointsEarned || 0))
      .map((entry, index) => ({
        rank: index + 1,
        uid: entry.uid || entry.userId,
        name: entry.name || 'Metro Rider',
        points: Number(entry.pointsEarned || 0),
        isYou: (entry.uid || entry.userId) === req.clientId,
      }));

    let cityTop = [];
    try {
      const citySnap = await firestore.collection('metrosafar_weekly_leaderboards').doc(weekId).collection('users')
        .where('cityId', '==', cityId)
        .orderBy('pointsEarned', 'desc')
        .limit(10)
        .get();
      cityTop = citySnap.docs.map((doc, index) => ({
        rank: index + 1,
        uid: doc.id,
        name: doc.data().name || 'Metro Rider',
        points: Number(doc.data().pointsEarned || 0),
      }));
    } catch (error) {
      logger.warn({ err: error, cityId, weekId }, 'City weekly leaderboard query failed');
    }

    res.json({
      weekId,
      cityId,
      resetsAt: getNextIstWeekResetIso(),
      friends,
      cityTop,
      yourRank: friends.find((entry) => entry.isYou)?.rank || null,
    });
  } catch (error) {
    next(error);
  }
});

// ---------------------------------------------------------------------------
// Retention: weekly digest
// ---------------------------------------------------------------------------

app.get('/api/weekly-digest/preview', async (req, res, next) => {
  try {
    const profile = await getUserState(req.clientId);
    const weekId = req.query.weekId || getIstWeekId();
    const cityId = sanitizeCityId(req.query.cityId || profile.activeCityId);
    const statsDoc = await firestore.collection('metrosafar_user_weekly_stats').doc(req.clientId).collection('weeks').doc(weekId).get();
    const stats = statsDoc.exists ? statsDoc.data() : {};
    const leaderboard = await firestore.collection('metrosafar_weekly_leaderboards').doc(weekId).collection('users')
      .where('cityId', '==', cityId)
      .orderBy('pointsEarned', 'desc')
      .limit(500)
      .get()
      .catch(() => ({ docs: [] }));
    const rank = leaderboard.docs.findIndex((doc) => doc.id === req.clientId) + 1 || null;
    const nextRankTarget = rank && rank > 10 ? `Top ${Math.max(10, rank - 10)}` : 'Top 10';
    res.json({
      weekId,
      cityId,
      gamesPlayed: Number(stats.gamesPlayed || 0),
      articlesRead: Number(stats.articlesRead || 0),
      surveysCompleted: Number(stats.surveysCompleted || 0),
      storiesRead: Number(stats.storiesRead || 0),
      pointsEarned: Number(stats.pointsEarned || 0),
      co2SavedKg: Number(((stats.pointsEarned || 0) * 0.05).toFixed(1)),
      weeklyRank: rank,
      nextRankTarget,
      digestNotificationsEnabled: profile.digestNotificationsEnabled !== false,
      notificationText: `Games played: ${Number(stats.gamesPlayed || 0)} | Articles: ${Number(stats.articlesRead || 0)} | CO₂ saved: ${Number(((stats.pointsEarned || 0) * 0.05).toFixed(1))}kg`,
    });
  } catch (error) {
    next(error);
  }
});

function requireInternalJobSecret(req, res, next) {
  const configured = process.env.INTERNAL_JOB_SECRET || process.env.ADMIN_API_KEY;
  const provided = req.header('X-Internal-Secret') || '';
  if (!configured && process.env.NODE_ENV !== 'production') return next();
  if (configured && provided === configured) return next();
  res.status(401).json({ error: 'Internal job secret required' });
}

app.post('/api/internal/weekly-digest/run', requireInternalJobSecret, async (req, res, next) => {
  try {
    const weekId = req.body?.weekId || getIstWeekId();
    const dryRun = req.body?.dryRun !== false;
    const leaderboardSnap = await firestore.collection('metrosafar_weekly_leaderboards').doc(weekId).collection('users')
      .orderBy('pointsEarned', 'desc')
      .limit(1000)
      .get();
    let considered = 0;
    let sent = 0;

    for (const doc of leaderboardSnap.docs) {
      considered++;
      const uid = doc.id;
      const profile = await getUserState(uid).catch(() => null);
      if (!profile || profile.notificationsEnabled === false || profile.digestNotificationsEnabled === false) continue;
      const devices = await firestore.collection('metrosafar_users').doc(uid).collection('devices').limit(10).get();
      const tokens = devices.docs.map((device) => device.data().token).filter(Boolean);
      if (tokens.length === 0) continue;
      if (!dryRun) {
        const points = Number(doc.data().pointsEarned || 0);
        const body = `Games: ${Number(doc.data().gamesPlayed || 0)} | Articles: ${Number(doc.data().articlesRead || 0)} | CO₂ saved: ${Number((points * 0.05).toFixed(1))}kg`;
        const result = await admin.messaging().sendEachForMulticast({
          tokens,
          notification: { title: 'Your MetroSafar Week', body },
          data: { type: 'weekly_digest', weekId },
        });
        sent += result.successCount;
      }
    }

    res.json({ weekId, dryRun, considered, sent });
  } catch (error) {
    next(error);
  }
});

// ---------------------------------------------------------------------------
// Retention: commute auto-mode
// ---------------------------------------------------------------------------

app.get('/api/trip/commute-session/active', async (req, res, next) => {
  try {
    const session = await getActiveCommuteSession(req.clientId);
    res.json({ session });
  } catch (error) {
    next(error);
  }
});

app.post('/api/trip/commute-session', tripLimiter, validate(commuteSessionSchema), async (req, res, next) => {
  try {
    const profile = await getUserState(req.clientId);
    const cityId = sanitizeCityId(req.body.cityId || profile.activeCityId);
    const now = new Date().toISOString();
    const highConfidence = req.body.confidenceScore >= 0.75;
    const existing = await getActiveCommuteSession(req.clientId);
    const hasTicketVerification = Boolean(req.body.ticketVerification || existing?.ticketVerification);
    if (req.body.phase === 'active' && !hasTicketVerification) {
      res.status(400).json({ error: 'Ticket verification is required before rewards can start.' });
      return;
    }
    const desiredStatus = hasTicketVerification && (req.body.phase === 'active' || highConfidence) ? 'active' : 'detecting';
    const ref = existing
      ? firestore.collection('metrosafar_commute_sessions').doc(existing.id)
      : firestore.collection('metrosafar_commute_sessions').doc();
    const ticketVerification = req.body.ticketVerification
      ? {
          method: req.body.ticketVerification.method,
          codeHash: crypto
            .createHash('sha256')
            .update(req.body.ticketVerification.code)
            .digest('hex'),
          status: 'client_verified',
          verifiedAt: now,
        }
      : existing?.ticketVerification || null;
    const payload = {
      userId: req.clientId,
      cityId,
      status: desiredStatus,
      confidenceScore: req.body.confidenceScore,
      vibrationScore: req.body.vibrationScore || 0,
      speedKmh: req.body.speedKmh || 0,
      stationId: req.body.stationId || existing?.stationId || null,
      startedAt: existing?.startedAt || req.body.detectedAt || now,
      updatedAt: now,
      multiplier: desiredStatus === 'active' ? 1.5 : 1,
      ticketVerification,
    };
    await ref.set(payload, { merge: true });

    if (!existing && desiredStatus === 'active') {
      await incrementWeeklyStats(req.clientId, { tripsStarted: 1 }, { cityId })
        .catch((error) => logger.warn({ err: error, clientId: req.clientId }, 'Commute weekly start stats failed'));
    }

    res.json({
      session: { id: ref.id, ...payload },
      confirmed: desiredStatus === 'active',
      multiplier: payload.multiplier,
    });
  } catch (error) {
    next(error);
  }
});

app.post('/api/trip/commute-session/:sessionId/end', tripLimiter, validate(commuteEndSchema), async (req, res, next) => {
  try {
    const ref = firestore.collection('metrosafar_commute_sessions').doc(req.params.sessionId);
    const snap = await ref.get();
    if (!snap.exists || snap.data().userId !== req.clientId) {
      res.status(404).json({ error: 'Commute session not found' });
      return;
    }
    const session = snap.data();
    const endedAt = req.body.endedAt || new Date().toISOString();
    await ref.set({
      status: 'completed',
      endStationId: req.body.endStationId || null,
      endedAt,
      updatedAt: endedAt,
    }, { merge: true });

    await incrementWeeklyStats(req.clientId, {
      tripsCompleted: 1,
      co2Kg: 0.4,
    }, { cityId: session.cityId }).catch((error) => logger.warn({ err: error, clientId: req.clientId }, 'Commute weekly end stats failed'));

    const referral = await qualifyReferralForUser(req.clientId, 'first_trip').catch((error) => {
      logger.warn({ err: error, clientId: req.clientId }, 'Commute referral qualification failed');
      return null;
    });

    res.json({
      session: { id: ref.id, ...session, status: 'completed', endedAt },
      pointsAwarded: 0,
      referral,
      summary: 'Commute complete. Activities during the session earned a 1.5x multiplier.',
    });
  } catch (error) {
    next(error);
  }
});

installPhase56Routes(app, phase56Context);

// ===========================================================================
// ADMIN AUTH MIDDLEWARE
// Verifies a Firebase ID token and checks for a custom claim `role` that
// must be one of the recognised admin roles.  Falls back to a static
// ADMIN_API_KEY for CI / local testing when Firebase Auth is unavailable.
// ===========================================================================

const ADMIN_ROLES = new Set(['superadmin', 'city_admin', 'content_editor', 'analyst', 'support']);

async function requireAdmin(req, res, next) {
  const authHeader = req.header('Authorization') || '';
  const token = authHeader.replace(/^Bearer\s+/i, '');

  if (!token) {
    return res.status(401).json({ error: 'Authorization header required' });
  }

  // Static API key fallback (CI / local dev)
  const adminKey = process.env.ADMIN_API_KEY;
  if (adminKey && token === adminKey) {
    req.admin = { uid: 'api-key', role: 'superadmin', cities: [], email: 'api-key@local' };
    return next();
  }

  // Firebase ID token verification
  try {
    const decoded = await admin.auth().verifyIdToken(token);
    const role = decoded.role;
    if (!role || !ADMIN_ROLES.has(role)) {
      return res.status(403).json({ error: 'Insufficient role — not an admin account' });
    }
    req.admin = {
      uid: decoded.uid,
      role,
      cities: decoded.cities || [],
      email: decoded.email || decoded.uid,
    };
    return next();
  } catch (err) {
    logger.warn({ err: err.message }, 'Admin token verification failed');
    return res.status(401).json({ error: 'Invalid or expired admin token' });
  }
}

// City-scoped guard — superadmin may access all cities; city_admin only their own
function requireCityAccess(req, res, next) {
  const { cityId } = req.params;
  if (!cityId) return next();
  const { role, cities } = req.admin;
  if (role === 'superadmin') return next();
  if (cities.includes(cityId)) return next();
  return res.status(403).json({ error: `No access to city '${cityId}'` });
}

// ---------------------------------------------------------------------------
// AUDIT LOG HELPER — appended on every mutating admin request
// ---------------------------------------------------------------------------

async function appendAudit({ actor, actorEmail, role, action, cityId, before, after, ip, ua }) {
  try {
    await firestore.collection('audit_log').add({
      actor, actorEmail, role, action,
      ...(cityId ? { cityId } : {}),
      ...(before !== undefined ? { before } : {}),
      ...(after !== undefined ? { after } : {}),
      ip: ip || null,
      ua: ua || null,
      at: new Date(),
    });
  } catch (err) {
    logger.warn({ err }, 'Audit log write failed (non-fatal)');
  }
}

function auditMiddleware(action) {
  return async (req, _res, next) => {
    req._auditAction = action;
    req._auditCityId = req.params?.cityId;
    next();
  };
}

// ===========================================================================
// v2 PUBLIC CITY ENDPOINTS
// ===========================================================================

/** GET /api/v2/cities — list all live cities */
app.get('/api/v2/cities', (_req, res) => {
  const list = Object.values(cityRegistry).map(({ stations: _s, ...meta }) => meta);
  res.json({ cities: list });
});

/** GET /api/v2/cities/resolve?lat=&lng= — detect city from coordinates */
app.get('/api/v2/cities/resolve', (req, res) => {
  const lat = parseFloat(req.query.lat);
  const lng = parseFloat(req.query.lng);
  if (isNaN(lat) || isNaN(lng)) {
    return res.status(400).json({ error: 'lat and lng query params required' });
  }

  // Exact bbox match
  for (const [cityId, city] of Object.entries(cityRegistry)) {
    const { bbox } = city;
    if (lat >= bbox.minLat && lat <= bbox.maxLat && lng >= bbox.minLng && lng <= bbox.maxLng) {
      return res.json({ status: 'found', cityId, city: city.name });
    }
  }

  // Nearest city within 75 km
  let nearest = null, nearestDist = Infinity;
  for (const [cityId, city] of Object.entries(cityRegistry)) {
    const dist = Math.sqrt(Math.pow(city.center.lat - lat, 2) + Math.pow(city.center.lng - lng, 2)) * 111;
    if (dist < nearestDist) { nearestDist = dist; nearest = { cityId, city }; }
  }

  if (nearest && nearestDist <= 75) {
    return res.json({ status: 'nearby', cityId: nearest.cityId, distanceKm: Math.round(nearestDist), city: nearest.city.name });
  }

  res.json({ status: 'unsupported', nearestCityId: nearest?.cityId || null });
});

/** GET /api/v2/cities/:cityId — full city bundle (no stations) */
app.get('/api/v2/cities/:cityId', (req, res) => {
  const bundle = cityRegistry[req.params.cityId];
  if (!bundle) return res.status(404).json({ error: 'City not found' });
  const { stations: _s, ...meta } = bundle;
  res.json({ city: meta });
});

/** GET /api/v2/cities/:cityId/stations — stations for a city */
app.get('/api/v2/cities/:cityId/stations', (req, res) => {
  const bundle = cityRegistry[req.params.cityId];
  if (!bundle) return res.status(404).json({ error: 'City not found' });
  res.json({ stations: bundle.stations || [] });
});

/** GET /api/v2/cities/:cityId/bundle — one-shot offline pack */
app.get('/api/v2/cities/:cityId/bundle', (req, res) => {
  const bundle = cityRegistry[req.params.cityId];
  if (!bundle) return res.status(404).json({ error: 'City not found' });
  res.json({ bundle, generatedAt: new Date().toISOString() });
});

/** GET /api/v2/cities/:cityId/content/:type — public content pack
 *  Types: trivia | landmarks | stamps | sudoku_icons | phrases | themes | audio | festival_windows
 *  Falls back to Firestore if not loaded from seed.
 */
app.get('/api/v2/cities/:cityId/content/:type', async (req, res, next) => {
  try {
    const { cityId, type } = req.params;
    const bundle = cityRegistry[cityId];
    if (!bundle) return res.status(404).json({ error: 'City not found' });

    const validTypes = ['trivia', 'landmarks', 'stamps', 'sudoku_icons', 'phrases', 'themes', 'audio', 'festival_windows'];
    if (!validTypes.includes(type)) {
      return res.status(400).json({ error: `type must be one of: ${validTypes.join(', ')}` });
    }

    // Try in-memory first (seed files or admin uploads cached during runtime)
    if (bundle.content && bundle.content[type]) {
      return res.json({ cityId, type, data: bundle.content[type] });
    }

    // Fall back to Firestore (admin may have uploaded post-startup)
    const snap = await firestore.collection('cities').doc(cityId).collection('content').doc(type).get();
    if (snap.exists) {
      const data = snap.data();
      // Cache for next time
      if (!bundle.content) bundle.content = {};
      bundle.content[type] = data;
      return res.json({ cityId, type, data });
    }

    res.status(404).json({ error: `Content type '${type}' not found for city '${cityId}'` });
  } catch (error) { next(error); }
});

/** POST /api/v2/users/:uid/city — set active city for user */
app.post('/api/v2/users/:uid/city', async (req, res, next) => {
  try {
    if (req.uid !== req.params.uid) return res.status(403).json({ error: 'Forbidden' });
    const { cityId } = req.body;
    if (!cityRegistry[cityId]) return res.status(404).json({ error: 'City not found' });
    const userState = await getUserState(req.uid);
    const history = userState.cityHistory || [];
    if (!history.includes(cityId)) history.push(cityId);
    await saveUserState(req.uid, { ...userState, activeCityId: cityId, cityHistory: history });
    res.json({ success: true, activeCityId: cityId });
  } catch (error) { next(error); }
});

/** GET /api/v2/leaderboards?cityId= — city-scoped leaderboards */
app.get('/api/v2/leaderboards', async (req, res, next) => {
  try {
    const { cityId, lineId, stationId } = req.query;
    let q = firestore.collection('leaderboard_entries').orderBy('points', 'desc').limit(50);
    if (cityId) q = firestore.collection(`cities/${cityId}/leaderboard`).orderBy('points', 'desc').limit(50);
    const snap = await q.get();
    const entries = snap.docs.map(d => ({ id: d.id, ...d.data() }));
    res.json({ entries, cityId: cityId || null, lineId: lineId || null, stationId: stationId || null });
  } catch (error) { next(error); }
});

/** POST /api/v2/waitlist — register for an unsupported city */
app.post('/api/v2/waitlist', async (req, res, next) => {
  try {
    const { cityId, email, lat, lng } = req.body;
    if (!email) return res.status(400).json({ error: 'email required' });
    await firestore.collection('city_waitlist').add({
      cityId: cityId || 'unknown', email, lat: lat || null, lng: lng || null,
      createdAt: new Date(), uid: req.uid || null,
    });
    res.json({ success: true, message: "You're on the list! We'll notify you when your city launches." });
  } catch (error) { next(error); }
});

// ===========================================================================
// CATALOG CRUD SCHEMAS
// ===========================================================================

const catalogRewardSchema = z.object({
  title:        z.string().trim().min(1).max(120),
  discount:     z.string().trim().max(80).optional().default(''),
  points:       z.number().int().min(0).max(100000),
  category:     z.string().trim().min(1).max(60),
  description:  z.string().trim().max(500).optional().default(''),
  active:       z.boolean().optional().default(true),
  sortOrder:    z.number().int().min(0).optional().default(0),
  stock:        z.number().int().min(0).nullable().optional().default(null),
  perUserLimit: z.number().int().min(1).max(1000).optional().default(1),
  // How the user receives the reward.
  fulfillmentType: z.enum(['manual', 'instant_code', 'affiliate_link']).optional().default('manual'),
  // For affiliate_link rewards — the URL delivered on redemption.
  affiliateUrl: z.string().trim().max(500).optional().nullable().default(null),
});

const catalogGameSchema = z.object({
  title:              z.string().trim().min(1).max(120),
  description:        z.string().trim().max(300).optional().default(''),
  points:             z.number().int().min(0).max(100000),
  route:              z.string().trim().max(120).optional().default(''),
  durationMinutes:    z.number().int().min(1).max(120).optional().default(5),
  commuteLengthLabel: z.string().trim().max(60).optional().default(''),
  difficulty:         z.enum(['easy','medium','hard']).optional().default('medium'),
  icon:               z.string().trim().max(10).optional().default('🎮'),
  active:             z.boolean().optional().default(true),
  sortOrder:          z.number().int().min(0).optional().default(0),
});

const catalogArticleSchema = z.object({
  title:           z.string().trim().min(1).max(200),
  body:            z.string().trim().min(1).max(100000),
  coverUrl:        z.string().trim().max(500).optional().default(''),
  readTimeMinutes: z.number().int().min(1).max(120).optional().default(3),
  points:          z.number().int().min(0).max(1000).optional().default(15),
  publishedAt:     z.string().optional().default(() => new Date().toISOString()),
  active:          z.boolean().optional().default(true),
  sortOrder:       z.number().int().min(0).optional().default(0),
});

const catalogSurveySchema = z.object({
  question:  z.string().trim().min(1).max(500),
  options:   z.array(z.string().trim().min(1).max(200)).min(2).max(10),
  points:    z.number().int().min(0).max(1000).optional().default(20),
  active:    z.boolean().optional().default(true),
  sortOrder: z.number().int().min(0).optional().default(0),
});

const catalogQuestSchema = z.object({
  title:       z.string().trim().min(1).max(120),
  description: z.string().trim().max(300).optional().default(''),
  points:      z.number().int().min(0).max(1000),
  // type maps to ACTIVITY_POINT_RULES keys — restricted set
  type:        z.enum([
    'game_completed','quest_completed','article_read','survey_submitted',
    'story_completed','ride_started','ride_completed','stamp_claimed',
    'station_quiz_completed','passport_viewed',
  ]),
  active:      z.boolean().optional().default(true),
  sortOrder:   z.number().int().min(0).optional().default(0),
});

const catalogVideoSchema = z.object({
  title:       z.string().trim().min(1).max(200),
  duration:    z.string().trim().max(20).optional().default(''),
  points:      z.number().int().min(0).max(1000).optional().default(20),
  description: z.string().trim().max(500).optional().default(''),
  active:      z.boolean().optional().default(true),
  sortOrder:   z.number().int().min(0).optional().default(0),
});

// Mapping of catalog type → zod schema
const CATALOG_SCHEMAS = {
  rewards:  catalogRewardSchema,
  games:    catalogGameSchema,
  articles: catalogArticleSchema,
  surveys:  catalogSurveySchema,
  quests:   catalogQuestSchema,
  videos:   catalogVideoSchema,
};

// Quest IDs reference user completion state — protect them from rename.
const QUEST_PROTECTED_IDS = new Set([
  'start_ride','play_game','read_article','station_quiz','check_passport',
]);

// ===========================================================================
// GENERIC CATALOG CRUD FACTORY
// Mounts list / get / create / update / soft-delete / reload routes for every
// catalog type.  All writes: Firestore → in-memory reload → audit log.
// ===========================================================================

function mountCatalogCrud(type) {
  const schema = CATALOG_SCHEMAS[type];
  const col    = () => firestore.collection(`catalog_${type}`);

  // ── GET /api/admin/catalog/:type  — list all (incl. inactive)
  app.get(`/api/admin/catalog/${type}`, requireAdmin, async (_req, res, next) => {
    try {
      const snap = await col().orderBy('sortOrder').get();
      const items = snap.docs.map(d => ({ id: d.id, ...d.data() }));
      res.json({ type, items, count: items.length });
    } catch (err) { next(err); }
  });

  // ── GET /api/admin/catalog/:type/:id
  app.get(`/api/admin/catalog/${type}/:id`, requireAdmin, async (req, res, next) => {
    try {
      const snap = await col().doc(req.params.id).get();
      if (!snap.exists) return res.status(404).json({ error: 'Not found' });
      res.json({ id: snap.id, ...snap.data() });
    } catch (err) { next(err); }
  });

  // ── POST /api/admin/catalog/:type  — create
  app.post(`/api/admin/catalog/${type}`, requireAdmin, validate(schema), async (req, res, next) => {
    try {
      const id  = req.body.id || req.body.title.toLowerCase().replace(/[^a-z0-9]+/g, '_').slice(0, 60);
      const ref = col().doc(id);
      const existing = await ref.get();
      if (existing.exists) return res.status(409).json({ error: `ID '${id}' already exists` });

      const data = { ...req.body, id: undefined, _updatedAt: new Date(), _updatedBy: req.admin.email };
      delete data.id;
      await ref.set(data);
      await reloadCatalogType(type);
      await appendAudit({ actor: req.admin.uid, actorEmail: req.admin.email, role: req.admin.role,
        action: `catalog.${type}.create`, after: { id, ...data }, ip: req.ip, ua: req.get('user-agent') });
      res.status(201).json({ id, ...data });
    } catch (err) { next(err); }
  });

  // ── PUT /api/admin/catalog/:type/:id  — full update
  app.put(`/api/admin/catalog/${type}/:id`, requireAdmin, validate(schema), async (req, res, next) => {
    try {
      const { id } = req.params;
      if (type === 'quests' && QUEST_PROTECTED_IDS.has(id) && req.body.type !== undefined) {
        // Allow edits but protect the 'type' field — user state references it
        delete req.body.type;
      }
      const ref  = col().doc(id);
      const snap = await ref.get();
      const before = snap.exists ? snap.data() : null;
      const data   = { ...req.body, id: undefined, _updatedAt: new Date(), _updatedBy: req.admin.email };
      delete data.id;
      await ref.set(data, { merge: false });
      await reloadCatalogType(type);
      await appendAudit({ actor: req.admin.uid, actorEmail: req.admin.email, role: req.admin.role,
        action: `catalog.${type}.update`, before, after: { id, ...data }, ip: req.ip, ua: req.get('user-agent') });
      res.json({ id, ...data });
    } catch (err) { next(err); }
  });

  // ── PATCH /api/admin/catalog/:type/:id  — partial update (e.g. toggle active)
  app.patch(`/api/admin/catalog/${type}/:id`, requireAdmin, async (req, res, next) => {
    try {
      const { id } = req.params;
      // Strip protected fields on quests
      if (type === 'quests' && QUEST_PROTECTED_IDS.has(id)) delete req.body.type;
      const ref  = col().doc(id);
      const snap = await ref.get();
      if (!snap.exists) return res.status(404).json({ error: 'Not found' });
      const before = snap.data();
      const patch  = { ...req.body, id: undefined, _updatedAt: new Date(), _updatedBy: req.admin.email };
      delete patch.id;
      await ref.update(patch);
      await reloadCatalogType(type);
      await appendAudit({ actor: req.admin.uid, actorEmail: req.admin.email, role: req.admin.role,
        action: `catalog.${type}.patch`, before, after: patch, ip: req.ip, ua: req.get('user-agent') });
      res.json({ id, ...before, ...patch });
    } catch (err) { next(err); }
  });

  // ── DELETE /api/admin/catalog/:type/:id
  //    ?hard=true → permanent delete   (default: soft disable)
  app.delete(`/api/admin/catalog/${type}/:id`, requireAdmin, async (req, res, next) => {
    try {
      const { id } = req.params;
      const hardDelete = req.query.hard === 'true';
      const ref  = col().doc(id);
      const snap = await ref.get();
      if (!snap.exists) return res.status(404).json({ error: 'Not found' });
      const before = snap.data();

      if (hardDelete) {
        await ref.delete();
      } else {
        await ref.update({ active: false, _updatedAt: new Date(), _updatedBy: req.admin.email });
      }
      await reloadCatalogType(type);
      await appendAudit({ actor: req.admin.uid, actorEmail: req.admin.email, role: req.admin.role,
        action: `catalog.${type}.${hardDelete ? 'delete' : 'disable'}`,
        before, ip: req.ip, ua: req.get('user-agent') });
      res.json({ success: true, id, action: hardDelete ? 'deleted' : 'disabled' });
    } catch (err) { next(err); }
  });
}

// Mount CRUD for every catalog type
for (const type of CATALOG_TYPES) mountCatalogCrud(type);

// ── POST /api/admin/catalog/reload  — manual cache flush (superadmin only)
app.post('/api/admin/catalog/reload', requireAdmin, async (req, res, next) => {
  try {
    if (req.admin.role !== 'superadmin') return res.status(403).json({ error: 'superadmin only' });
    const type = req.query.type;
    if (type) {
      if (!CATALOG_TYPES.includes(type)) return res.status(400).json({ error: `Unknown type: ${type}` });
      await reloadCatalogType(type);
      res.json({ reloaded: [type], counts: { [type]: catalog[type].length } });
    } else {
      await Promise.all(CATALOG_TYPES.map(t => reloadCatalogType(t)));
      const counts = Object.fromEntries(CATALOG_TYPES.map(t => [t, catalog[t].length]));
      res.json({ reloaded: CATALOG_TYPES, counts });
    }
  } catch (err) { next(err); }
});

// ── GET /api/admin/catalog  — overview of all catalog sizes
app.get('/api/admin/catalog', requireAdmin, (_req, res) => {
  const counts = Object.fromEntries(CATALOG_TYPES.map(t => [t, catalog[t].length]));
  res.json({ types: CATALOG_TYPES, counts });
});

// ===========================================================================
// ADMIN — REDEMPTION FULFILLMENT QUEUE (2a–2f)
// Lets an operator see who redeemed what, attach a voucher code / note, and
// mark each redemption fulfilled or cancelled. This is the surface the
// backend fulfillment logic plugs into.
// ===========================================================================

const REDEMPTION_STATUSES = new Set(['pending', 'fulfilled', 'cancelled']);

const redemptionUpdateSchema = z.object({
  status: z.enum(['pending', 'fulfilled', 'cancelled']).optional(),
  fulfillmentCode: z.string().trim().max(200).optional().nullable(),
  fulfillmentNote: z.string().trim().max(500).optional().nullable(),
});

// GET /api/admin/redemptions?status=pending&rewardId=&limit=
app.get('/api/admin/redemptions', requireAdmin, async (req, res, next) => {
  try {
    const { status, rewardId } = req.query;
    const limit = Math.max(1, Math.min(Number(req.query.limit || 200), 500));

    let q = firestore.collection('redemptions');
    if (status && REDEMPTION_STATUSES.has(status)) q = q.where('status', '==', status);
    if (rewardId) q = q.where('rewardId', '==', rewardId);
    q = q.orderBy('createdAt', 'desc').limit(limit);

    const snap = await q.get();
    const items = snap.docs.map(d => ({ id: d.id, ...d.data() }));

    // Lightweight status breakdown for the dashboard header
    const counts = { pending: 0, fulfilled: 0, cancelled: 0 };
    items.forEach(i => { if (counts[i.status] !== undefined) counts[i.status]++; });

    res.json({ items, count: items.length, counts });
  } catch (err) { next(err); }
});

// GET /api/admin/redemptions/:id
app.get('/api/admin/redemptions/:id', requireAdmin, async (req, res, next) => {
  try {
    const snap = await firestore.collection('redemptions').doc(req.params.id).get();
    if (!snap.exists) return res.status(404).json({ error: 'Redemption not found' });
    res.json({ id: snap.id, ...snap.data() });
  } catch (err) { next(err); }
});

// PATCH /api/admin/redemptions/:id — attach a code / note and/or change status
app.patch('/api/admin/redemptions/:id', requireAdmin, validate(redemptionUpdateSchema), async (req, res, next) => {
  try {
    const ref = firestore.collection('redemptions').doc(req.params.id);
    const snap = await ref.get();
    if (!snap.exists) return res.status(404).json({ error: 'Redemption not found' });
    const before = snap.data();

    const patch = { _updatedAt: new Date().toISOString() };
    if (req.body.fulfillmentCode !== undefined) patch.fulfillmentCode = req.body.fulfillmentCode;
    if (req.body.fulfillmentNote !== undefined) patch.fulfillmentNote = req.body.fulfillmentNote;
    if (req.body.status !== undefined) {
      patch.status = req.body.status;
      if (req.body.status === 'fulfilled') {
        patch.fulfilledAt = new Date().toISOString();
        patch.fulfilledBy = req.admin.email;
      }
    }

    await ref.update(patch);
    await appendAudit({
      actor: req.admin.uid, actorEmail: req.admin.email, role: req.admin.role,
      action: `redemption.${patch.status || 'update'}`, before, after: { id: req.params.id, ...patch },
      ip: req.ip, ua: req.get('user-agent'),
    });

    // Notify the user when their redemption becomes fulfilled (best-effort).
    if (patch.status === 'fulfilled' && before.status !== 'fulfilled') {
      notifyRedemptionFulfilled(before.userId, before.rewardTitle)
        .catch(e => logger.warn({ err: e }, 'Redemption fulfilled push failed'));
    }

    res.json({ id: req.params.id, ...before, ...patch });
  } catch (err) { next(err); }
});

// Best-effort FCM push to a user when a redemption is fulfilled.
async function notifyRedemptionFulfilled(userId, rewardTitle) {
  if (!userId) return;
  const userSnap = await firestore.collection('metrosafar_users').doc(userId).get();
  const token = userSnap.exists ? userSnap.data().fcmToken : null;
  if (!token) return;
  await admin.messaging().send({
    token,
    notification: {
      title: '🎁 Your reward is ready!',
      body: `${rewardTitle || 'Your reward'} has been fulfilled — tap to view your code.`,
    },
    data: { type: 'redemption_fulfilled', screen: 'my_redemptions' },
  });
}

// ---------------------------------------------------------------------------
// ADMIN — reward code pools (instant_code fulfillment)
// Upload a batch of voucher codes; redeem auto-assigns one per redemption.
// ---------------------------------------------------------------------------

const codeUploadSchema = z.object({
  codes: z.array(z.string().trim().min(1).max(200)).min(1).max(5000),
});

// POST /api/admin/catalog/rewards/:id/codes — bulk-add voucher codes
app.post('/api/admin/catalog/rewards/:id/codes', requireAdmin, validate(codeUploadSchema), async (req, res, next) => {
  try {
    const rewardRef = firestore.collection('catalog_rewards').doc(req.params.id);
    const rewardSnap = await rewardRef.get();
    if (!rewardSnap.exists) return res.status(404).json({ error: 'Reward not found' });

    // De-dup against the input; write in batches of 450 (Firestore limit 500).
    const unique = [...new Set(req.body.codes.map(c => c.trim()).filter(Boolean))];
    let written = 0;
    for (let i = 0; i < unique.length; i += 450) {
      const batch = firestore.batch();
      for (const code of unique.slice(i, i + 450)) {
        const ref = rewardRef.collection('codes').doc();
        batch.set(ref, {
          code, assigned: false, assignedTo: null, assignedAt: null,
          redemptionId: null, createdAt: new Date().toISOString(),
        });
        written++;
      }
      await batch.commit();
    }

    await appendAudit({
      actor: req.admin.uid, actorEmail: req.admin.email, role: req.admin.role,
      action: 'reward.codes.upload', after: { rewardId: req.params.id, count: written },
      ip: req.ip, ua: req.get('user-agent'),
    });
    res.status(201).json({ rewardId: req.params.id, added: written });
  } catch (err) { next(err); }
});

// GET /api/admin/catalog/rewards/:id/codes — availability summary (+ recent sample)
app.get('/api/admin/catalog/rewards/:id/codes', requireAdmin, async (req, res, next) => {
  try {
    const codesRef = firestore.collection('catalog_rewards').doc(req.params.id).collection('codes');
    const [availSnap, totalSnap] = await Promise.all([
      codesRef.where('assigned', '==', false).count().get().catch(() => null),
      codesRef.count().get().catch(() => null),
    ]);
    // Fallback if count() unavailable (emulator)
    let available = availSnap?.data().count;
    let total = totalSnap?.data().count;
    if (available === undefined || total === undefined) {
      const all = await codesRef.limit(5000).get();
      total = all.size;
      available = all.docs.filter(d => d.data().assigned === false).length;
    }
    res.json({ rewardId: req.params.id, total, available, assigned: total - available });
  } catch (err) { next(err); }
});

// ===========================================================================
// ADMIN ENDPOINTS — require Bearer ADMIN_API_KEY
// All city content management goes through here.
// ===========================================================================

/** GET /api/admin/cities — list ALL cities including unpublished */
app.get('/api/admin/cities', requireAdmin, (_req, res) => {
  res.json({ cities: Object.values(cityRegistry).map(({ stations: s, ...m }) => ({ ...m, stationCount: (s || []).length })) });
});

/** POST /api/admin/cities — create a new city */
app.post('/api/admin/cities', requireAdmin, async (req, res, next) => {
  try {
    const city = req.body;
    if (!city.id) return res.status(400).json({ error: 'city.id required' });
    if (cityRegistry[city.id]) return res.status(409).json({ error: 'City already exists' });

    cityRegistry[city.id] = { ...city, stations: [] };
    await firestore.collection('cities').doc(city.id).set({ ...city, _createdAt: new Date(), _updatedAt: new Date() });
    res.status(201).json({ success: true, city });
  } catch (error) { next(error); }
});

/** PUT /api/admin/cities/:cityId — update city metadata */
app.put('/api/admin/cities/:cityId', requireAdmin, async (req, res, next) => {
  try {
    const { cityId } = req.params;
    if (!cityRegistry[cityId]) return res.status(404).json({ error: 'City not found' });

    const existing = cityRegistry[cityId];
    const updated = { ...existing, ...req.body, id: cityId, stations: existing.stations };
    cityRegistry[cityId] = updated;

    const { stations: _s, ...meta } = updated;
    await firestore.collection('cities').doc(cityId).set({ ...meta, _updatedAt: new Date() }, { merge: true });
    res.json({ success: true, city: meta });
  } catch (error) { next(error); }
});

/** DELETE /api/admin/cities/:cityId — remove a city */
app.delete('/api/admin/cities/:cityId', requireAdmin, async (req, res, next) => {
  try {
    const { cityId } = req.params;
    if (!cityRegistry[cityId]) return res.status(404).json({ error: 'City not found' });
    delete cityRegistry[cityId];
    await firestore.collection('cities').doc(cityId).delete();
    res.json({ success: true });
  } catch (error) { next(error); }
});

/** POST /api/admin/cities/:cityId/publish — toggle live/beta/waitlist status */
app.post('/api/admin/cities/:cityId/publish', requireAdmin, async (req, res, next) => {
  try {
    const { cityId } = req.params;
    const { status } = req.body; // 'live' | 'beta' | 'waitlist'
    if (!cityRegistry[cityId]) return res.status(404).json({ error: 'City not found' });
    if (!['live', 'beta', 'waitlist'].includes(status)) return res.status(400).json({ error: 'status must be live | beta | waitlist' });

    cityRegistry[cityId].status = status;
    await firestore.collection('cities').doc(cityId).update({ status, _updatedAt: new Date() });
    res.json({ success: true, cityId, status });
  } catch (error) { next(error); }
});

/** GET /api/admin/cities/:cityId/stations — list stations */
app.get('/api/admin/cities/:cityId/stations', requireAdmin, (req, res) => {
  const bundle = cityRegistry[req.params.cityId];
  if (!bundle) return res.status(404).json({ error: 'City not found' });
  res.json({ stations: bundle.stations || [], count: (bundle.stations || []).length });
});

/** POST /api/admin/cities/:cityId/stations — bulk upload / replace stations */
app.post('/api/admin/cities/:cityId/stations', requireAdmin, async (req, res, next) => {
  try {
    const { cityId } = req.params;
    if (!cityRegistry[cityId]) return res.status(404).json({ error: 'City not found' });

    const incoming = req.body.stations;
    if (!Array.isArray(incoming)) return res.status(400).json({ error: 'body.stations must be an array' });

    // Validate minimal fields
    for (const s of incoming) {
      if (!s.id || !s.names || s.lat == null || s.lng == null) {
        return res.status(400).json({ error: `Station missing required fields (id, names, lat, lng): ${JSON.stringify(s)}` });
      }
      s.cityId = cityId; // enforce
    }

    const merge = req.query.merge === 'true'; // ?merge=true = upsert, default = replace
    if (merge) {
      const existingMap = Object.fromEntries((cityRegistry[cityId].stations || []).map(s => [s.id, s]));
      for (const s of incoming) existingMap[s.id] = s;
      cityRegistry[cityId].stations = Object.values(existingMap);
    } else {
      cityRegistry[cityId].stations = incoming;
    }

    // Persist to Firestore in batches of 500
    const cityRef = firestore.collection('cities').doc(cityId);
    const stationsToWrite = merge
      ? incoming
      : cityRegistry[cityId].stations;

    for (let i = 0; i < stationsToWrite.length; i += 400) {
      const chunk = stationsToWrite.slice(i, i + 400);
      const batch = firestore.batch();
      for (const s of chunk) batch.set(cityRef.collection('stations').doc(s.id), s);
      await batch.commit();
    }

    res.json({ success: true, count: cityRegistry[cityId].stations.length, mode: merge ? 'merge' : 'replace' });
  } catch (error) { next(error); }
});

/** PUT /api/admin/cities/:cityId/stations/:stationId — update one station */
app.put('/api/admin/cities/:cityId/stations/:stationId', requireAdmin, async (req, res, next) => {
  try {
    const { cityId, stationId } = req.params;
    if (!cityRegistry[cityId]) return res.status(404).json({ error: 'City not found' });

    const idx = (cityRegistry[cityId].stations || []).findIndex(s => s.id === stationId);
    const station = { ...req.body, id: stationId, cityId };

    if (idx >= 0) {
      cityRegistry[cityId].stations[idx] = station;
    } else {
      cityRegistry[cityId].stations.push(station);
    }

    await firestore.collection('cities').doc(cityId).collection('stations').doc(stationId).set(station);
    res.json({ success: true, station });
  } catch (error) { next(error); }
});

/** DELETE /api/admin/cities/:cityId/stations/:stationId — remove a station */
app.delete('/api/admin/cities/:cityId/stations/:stationId', requireAdmin, async (req, res, next) => {
  try {
    const { cityId, stationId } = req.params;
    if (!cityRegistry[cityId]) return res.status(404).json({ error: 'City not found' });

    cityRegistry[cityId].stations = (cityRegistry[cityId].stations || []).filter(s => s.id !== stationId);
    await firestore.collection('cities').doc(cityId).collection('stations').doc(stationId).delete();
    res.json({ success: true });
  } catch (error) { next(error); }
});

/** POST /api/admin/cities/:cityId/content/:type — upload content pack (stamps/trivia/phrases/themes/audio) */
app.post('/api/admin/cities/:cityId/content/:type', requireAdmin, async (req, res, next) => {
  try {
    const { cityId, type } = req.params;
    const validTypes = ['stamps', 'trivia', 'phrases', 'themes', 'audio', 'festival_windows'];
    if (!validTypes.includes(type)) {
      return res.status(400).json({ error: `type must be one of: ${validTypes.join(', ')}` });
    }
    if (!cityRegistry[cityId]) return res.status(404).json({ error: 'City not found' });

    const payload = req.body;
    await firestore.collection('cities').doc(cityId)
      .collection('content').doc(type)
      .set({ ...payload, _updatedAt: new Date() }, { merge: true });

    // Cache in memory on the registry
    if (!cityRegistry[cityId].content) cityRegistry[cityId].content = {};
    cityRegistry[cityId].content[type] = payload;

    res.json({ success: true, cityId, type, itemCount: Array.isArray(payload.items) ? payload.items.length : null });
  } catch (error) { next(error); }
});

/** GET /api/admin/cities/:cityId/content/:type — retrieve content pack */
app.get('/api/admin/cities/:cityId/content/:type', requireAdmin, async (req, res, next) => {
  try {
    const { cityId, type } = req.params;
    if (!cityRegistry[cityId]) return res.status(404).json({ error: 'City not found' });

    // Try in-memory cache first
    const cached = cityRegistry[cityId]?.content?.[type];
    if (cached) return res.json({ cityId, type, data: cached });

    // Fetch from Firestore
    const snap = await firestore.collection('cities').doc(cityId).collection('content').doc(type).get();
    if (!snap.exists) return res.status(404).json({ error: `Content type '${type}' not found for city '${cityId}'` });
    res.json({ cityId, type, data: snap.data() });
  } catch (error) { next(error); }
});

/** GET /api/admin/waitlist — view waitlist entries */
app.get('/api/admin/waitlist', requireAdmin, async (req, res, next) => {
  try {
    const cityId = req.query.cityId;
    let q = firestore.collection('city_waitlist').orderBy('createdAt', 'desc').limit(500);
    if (cityId) q = q.where('cityId', '==', cityId);
    const snap = await q.get();
    const entries = snap.docs.map(d => ({ id: d.id, ...d.data() }));
    res.json({ entries, count: entries.length });
  } catch (error) { next(error); }
});

// ---------------------------------------------------------------------------
// ADMIN — PATCH city (alias for PUT)
// ---------------------------------------------------------------------------
app.patch('/api/admin/cities/:cityId', requireAdmin, requireCityAccess, async (req, res, next) => {
  try {
    const { cityId } = req.params;
    if (!cityRegistry[cityId]) return res.status(404).json({ error: 'City not found' });
    const before = { ...cityRegistry[cityId] };
    const existing = cityRegistry[cityId];
    const updated = { ...existing, ...req.body, id: cityId, stations: existing.stations };
    cityRegistry[cityId] = updated;
    const { stations: _s, ...meta } = updated;
    await firestore.collection('cities').doc(cityId).set({ ...meta, _updatedAt: new Date() }, { merge: true });
    await appendAudit({ actor: req.admin.uid, actorEmail: req.admin.email, role: req.admin.role, action: 'cities.update', cityId, before, after: meta, ip: req.ip, ua: req.get('user-agent') });
    res.json({ success: true, city: meta });
  } catch (error) { next(error); }
});

// PUT GET for content (alias)
app.put('/api/admin/cities/:cityId/content/:type', requireAdmin, requireCityAccess, async (req, res, next) => {
  try {
    const { cityId, type } = req.params;
    if (!cityRegistry[cityId]) return res.status(404).json({ error: 'City not found' });
    const payload = req.body;
    await firestore.collection('cities').doc(cityId).collection('content').doc(type).set({ ...payload, _updatedAt: new Date() }, { merge: true });
    if (!cityRegistry[cityId].content) cityRegistry[cityId].content = {};
    cityRegistry[cityId].content[type] = payload;
    await appendAudit({ actor: req.admin.uid, actorEmail: req.admin.email, role: req.admin.role, action: `content.update`, cityId, after: { type }, ip: req.ip, ua: req.get('user-agent') });
    res.json({ success: true, cityId, type, data: payload, updatedAt: new Date().toISOString() });
  } catch (error) { next(error); }
});

// ---------------------------------------------------------------------------
// ADMIN — TELEMETRY
// ---------------------------------------------------------------------------

app.get('/api/admin/telemetry/summary', requireAdmin, async (req, res, next) => {
  try {
    const period = req.query.period || '24h';
    const hours = period === '1h' ? 1 : period === '7d' ? 168 : period === '30d' ? 720 : 24;
    const since = new Date(Date.now() - hours * 3_600_000);

    const [eventsSnap, usersSnap] = await Promise.allSettled([
      firestore.collection('telemetry_events').where('ts', '>=', since).limit(5000).get(),
      firestore.collection('metrosafar_users').limit(1000).get(),
    ]);

    const events = eventsSnap.status === 'fulfilled' ? eventsSnap.value.docs.map(d => d.data()) : [];
    const users = usersSnap.status === 'fulfilled' ? usersSnap.value.docs.map(d => d.data()) : [];

    // Event name counts
    const eventCounts = {};
    for (const e of events) {
      eventCounts[e.eventName] = (eventCounts[e.eventName] || 0) + 1;
    }
    const topEvents = Object.entries(eventCounts)
      .sort((a, b) => b[1] - a[1])
      .slice(0, 10)
      .map(([name, count]) => ({ name, count }));

    // City breakdown
    const cityMap = {};
    for (const u of users) {
      const cid = u.activeCityId || 'unknown';
      cityMap[cid] = (cityMap[cid] || 0) + 1;
    }
    const cityBreakdown = Object.entries(cityMap).map(([cityId, count]) => ({ cityId, users: count }));

    // Unique users in period
    const uniqueUids = new Set(events.map(e => e.userId).filter(Boolean));
    const dau = uniqueUids.size || Math.min(users.length, 50);

    res.json({
      dau,
      events24h: events.length,
      avgSessionMin: 4.2,
      topEvents,
      cityBreakdown,
    });
  } catch (error) { next(error); }
});

app.get('/api/admin/telemetry/events/recent', requireAdmin, async (_req, res, next) => {
  try {
    const since = new Date(Date.now() - 3_600_000);
    const snap = await firestore.collection('telemetry_events')
      .where('ts', '>=', since)
      .orderBy('ts', 'desc')
      .limit(100)
      .get();
    const events = snap.docs.map(d => ({ eventId: d.id, ...d.data() }));
    res.json({ events, count: events.length });
  } catch (error) { next(error); }
});

// ---------------------------------------------------------------------------
// ADMIN — TELEMETRY INGEST (called by mobile client outbox)
// ---------------------------------------------------------------------------

const telemetryBatchSchema = z.object({
  events: z.array(z.object({
    schemaVersion: z.string().optional(),
    eventName: z.string().min(1).max(80),
    eventId: z.string().optional(),
    ts: z.string().optional(),
    userId: z.string().optional(),
    cityId: z.string().optional(),
    props: z.record(z.unknown()).optional(),
  })).min(1).max(200),
});

app.post('/api/telemetry/batch', async (req, res, next) => {
  try {
    const result = telemetryBatchSchema.safeParse(req.body);
    if (!result.success) {
      return res.status(400).json({ error: 'Validation error', detail: result.error.flatten() });
    }
    const { events } = result.data;
    const batch = firestore.batch();
    for (const ev of events) {
      const ref = firestore.collection('telemetry_events').doc(ev.eventId || firestore.collection('_').doc().id);
      batch.set(ref, {
        ...ev,
        ts: ev.ts ? new Date(ev.ts) : new Date(),
        _ingestedAt: new Date(),
      });
    }
    await batch.commit();
    res.json({ accepted: events.length });
  } catch (error) { next(error); }
});

// ---------------------------------------------------------------------------
// ADMIN — USERS
// ---------------------------------------------------------------------------

app.get('/api/admin/users', requireAdmin, async (req, res, next) => {
  try {
    const q = String(req.query.q || '').trim().toLowerCase();
    if (!q) return res.status(400).json({ error: 'Query param q required' });

    let snap;
    if (q.includes('@')) {
      snap = await firestore.collection('metrosafar_users').where('email', '==', q).limit(20).get();
    } else if (q.length > 10) {
      snap = await firestore.collection('metrosafar_users').doc(q).get();
      snap = snap.exists ? { docs: [snap] } : { docs: [] };
    } else {
      snap = await firestore.collection('metrosafar_users')
        .where('name', '>=', q)
        .where('name', '<=', q + '')
        .limit(20)
        .get();
    }

    const users = snap.docs.map(d => buildDerivedProfile(d.data()));
    res.json({ users, count: users.length });
  } catch (error) { next(error); }
});

app.get('/api/admin/users/:uid', requireAdmin, async (req, res, next) => {
  try {
    const snap = await firestore.collection('metrosafar_users').doc(req.params.uid).get();
    if (!snap.exists) return res.status(404).json({ error: 'User not found' });
    res.json(buildDerivedProfile(snap.data()));
  } catch (error) { next(error); }
});

app.post('/api/admin/users/:uid/points', requireAdmin, async (req, res, next) => {
  try {
    const { uid } = req.params;
    const { delta, reason } = req.body;
    if (!Number.isInteger(delta) || delta === 0) return res.status(400).json({ error: 'delta must be non-zero integer' });
    if (!reason?.trim()) return res.status(400).json({ error: 'reason required' });

    const ref = firestore.collection('metrosafar_users').doc(uid);
    const snap = await ref.get();
    if (!snap.exists) return res.status(404).json({ error: 'User not found' });

    const before = snap.data();
    const next = buildDerivedProfile({ ...before, points: Math.max(0, (before.points || 0) + delta), lastUpdated: new Date().toISOString() });
    await ref.set(next, { merge: true });

    await appendAudit({
      actor: req.admin.uid, actorEmail: req.admin.email, role: req.admin.role,
      action: 'users.adjust_points', before: { points: before.points }, after: { points: next.points, reason }, ip: req.ip, ua: req.get('user-agent'),
    });

    res.json(next);
  } catch (error) { next(error); }
});

app.delete('/api/admin/users/:uid', requireAdmin, async (req, res, next) => {
  try {
    if (req.admin.role !== 'superadmin') return res.status(403).json({ error: 'superadmin only' });
    const { uid } = req.params;
    await firestore.collection('metrosafar_users').doc(uid).delete();
    try { await admin.auth().deleteUser(uid); } catch { /* ignore if not in Auth */ }
    await appendAudit({ actor: req.admin.uid, actorEmail: req.admin.email, role: req.admin.role, action: 'users.delete', after: { uid }, ip: req.ip, ua: req.get('user-agent') });
    res.json({ success: true });
  } catch (error) { next(error); }
});

// ---------------------------------------------------------------------------
// ADMIN — FEATURE FLAGS
// ---------------------------------------------------------------------------

app.get('/api/admin/flags', requireAdmin, async (_req, res, next) => {
  try {
    const snap = await firestore.collection('feature_flags').orderBy('_updatedAt', 'desc').get();
    const flags = snap.docs.map(d => ({ key: d.id, ...d.data(), updatedAt: d.data()._updatedAt?.toDate?.()?.toISOString() || new Date().toISOString() }));
    res.json({ flags });
  } catch (error) { next(error); }
});

app.put('/api/admin/flags/:key', requireAdmin, async (req, res, next) => {
  try {
    const { key } = req.params;
    const data = { ...req.body, key, _updatedAt: new Date() };
    await firestore.collection('feature_flags').doc(key).set(data, { merge: true });
    await appendAudit({ actor: req.admin.uid, actorEmail: req.admin.email, role: req.admin.role, action: 'flags.upsert', after: { key }, ip: req.ip, ua: req.get('user-agent') });
    res.json({ ...data, updatedAt: new Date().toISOString() });
  } catch (error) { next(error); }
});

app.delete('/api/admin/flags/:key', requireAdmin, async (req, res, next) => {
  try {
    await firestore.collection('feature_flags').doc(req.params.key).delete();
    res.json({ success: true });
  } catch (error) { next(error); }
});

// ---------------------------------------------------------------------------
// ADMIN — NOTIFICATIONS (FCM)
// ---------------------------------------------------------------------------

// Persist a notification to the in-app feed (best-effort, fire-and-forget).
async function recordNotificationFeed({ title, body, audience, data }) {
  try {
    await firestore.collection('app_notifications').add({
      title, body, audience: audience || 'all',
      data: data || {}, createdAt: new Date().toISOString(),
    });
  } catch (e) {
    logger.warn({ err: e }, 'Notification feed write failed');
  }
}

app.post('/api/admin/notifications/send', requireAdmin, async (req, res, next) => {
  try {
    const { title, body, topic, cityIds, userIds, data: extraData } = req.body;
    // Record to the in-app inbox feed regardless of delivery channel.
    recordNotificationFeed({
      title, body,
      audience: topic ? `topic:${topic}` : cityIds?.length ? `cities:${cityIds.join(',')}` : userIds?.length ? 'targeted' : 'all',
      data: extraData,
    });
    if (!title || !body) return res.status(400).json({ error: 'title and body required' });

    let message;
    if (topic) {
      message = { topic, notification: { title, body }, data: extraData || {} };
    } else if (cityIds?.length) {
      // Send to city topic (clients subscribe to city_<id>)
      const results = [];
      for (const cid of cityIds) {
        const r = await admin.messaging().send({
          topic: `city_${cid}`,
          notification: { title, body },
          data: extraData || {},
        });
        results.push(r);
      }
      await appendAudit({ actor: req.admin.uid, actorEmail: req.admin.email, role: req.admin.role, action: 'notifications.send', after: { title, cityIds }, ip: req.ip, ua: req.get('user-agent') });
      return res.json({ success: true, messageIds: results });
    } else if (userIds?.length) {
      // Look up FCM tokens for users
      const tokens = [];
      for (const uid of userIds.slice(0, 500)) {
        const snap = await firestore.collection('metrosafar_users').doc(uid).get();
        if (snap.exists && snap.data().fcmToken) tokens.push(snap.data().fcmToken);
      }
      if (tokens.length === 0) return res.status(400).json({ error: 'No FCM tokens found for given user IDs' });
      const r = await admin.messaging().sendEachForMulticast({ tokens, notification: { title, body }, data: extraData || {} });
      return res.json({ success: true, sent: r.successCount, failed: r.failureCount });
    } else {
      message = { topic: 'all_users', notification: { title, body }, data: extraData || {} };
    }

    const messageId = await admin.messaging().send(message);
    await appendAudit({ actor: req.admin.uid, actorEmail: req.admin.email, role: req.admin.role, action: 'notifications.send', after: { title, topic }, ip: req.ip, ua: req.get('user-agent') });
    res.json({ success: true, messageId });
  } catch (error) { next(error); }
});

// ---------------------------------------------------------------------------
// ADMIN — AUDIT LOG VIEWER
// ---------------------------------------------------------------------------

app.get('/api/admin/audit', requireAdmin, async (req, res, next) => {
  try {
    let q = firestore.collection('audit_log').orderBy('at', 'desc').limit(200);
    if (req.query.actor) q = q.where('actor', '==', req.query.actor);
    if (req.query.cityId) q = q.where('cityId', '==', req.query.cityId);
    const snap = await q.get();
    const entries = snap.docs.map(d => ({ id: d.id, ...d.data(), at: d.data().at?.toDate?.()?.toISOString() || d.data().at }));
    res.json({ entries, count: entries.length });
  } catch (error) { next(error); }
});

// ---------------------------------------------------------------------------
// ADMIN — RBAC (superadmin only — set custom claims on Firebase users)
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// ADMIN — SYSTEM HEALTH (live backend metrics)
// ---------------------------------------------------------------------------

app.get('/api/admin/health', requireAdmin, async (_req, res, next) => {
  try {
    // Latency percentiles from in-memory bucket
    const sorted = [...metrics.latencyBuckets].sort((a, b) => a - b);
    const pct = (p) => sorted.length ? sorted[Math.floor(sorted.length * p)] : 0;

    // Firestore roundtrip
    const fsStart = Date.now();
    let firestoreOk = true;
    try { await firestore.collection('metrosafar_users').limit(1).get(); }
    catch { firestoreOk = false; }
    const firestoreMs = Date.now() - fsStart;

    // User counts from Firestore
    let totalUsers = 0, activeToday = 0;
    try {
      const today = new Date(); today.setHours(0,0,0,0);
      const [allSnap, activeSnap] = await Promise.all([
        firestore.collection('metrosafar_users').count().get(),
        firestore.collection('metrosafar_users').where('lastUpdated', '>=', today.toISOString()).count().get(),
      ]);
      totalUsers = allSnap.data().count;
      activeToday = activeSnap.data().count;
    } catch { /* non-fatal */ }

    // Top slow routes (avg latency per route — approximated from recent data)
    const topRoutes = Object.entries(metrics.routeHits)
      .sort((a, b) => b[1] - a[1])
      .slice(0, 8)
      .map(([route, hits]) => ({ route, hits }));

    const uptimeSeconds = Math.floor((Date.now() - metrics.startedAt.getTime()) / 1000);

    res.json({
      status: firestoreOk ? 'healthy' : 'degraded',
      uptime: uptimeSeconds,
      startedAt: metrics.startedAt.toISOString(),
      firestore: { ok: firestoreOk, latencyMs: firestoreMs },
      requests: {
        ...metrics.requests,
        errorRate: metrics.requests.total > 0
          ? ((metrics.requests.error4xx + metrics.requests.error5xx) / metrics.requests.total * 100).toFixed(1) + '%'
          : '0%',
      },
      latency: {
        p50: pct(0.5),
        p90: pct(0.9),
        p95: pct(0.95),
        p99: pct(0.99),
        samples: sorted.length,
      },
      users: { total: totalUsers, activeToday },
      topRoutes,
      recentErrors: metrics.recentErrors.slice(0, 20),
      cities: Object.keys(cityRegistry).map(id => ({
        id,
        name: cityRegistry[id].name,
        status: cityRegistry[id].status,
        stationCount: (cityRegistry[id].stations || []).length,
      })),
    });
  } catch (error) { next(error); }
});

app.post('/api/admin/rbac/set-role', requireAdmin, async (req, res, next) => {
  try {
    if (req.admin.role !== 'superadmin') return res.status(403).json({ error: 'superadmin only' });
    const { uid, email, role, cities } = req.body;
    if ((!uid && !email) || !role) return res.status(400).json({ error: 'uid or email, and role, required' });
    if (!ADMIN_ROLES.has(role)) return res.status(400).json({ error: `role must be one of: ${[...ADMIN_ROLES].join(', ')}` });

    // Resolve email → uid server-side (the backend SA has Firebase Auth access).
    let targetUid = uid;
    if (!targetUid && email) {
      const userRecord = await admin.auth().getUserByEmail(email);
      targetUid = userRecord.uid;
    }

    await admin.auth().setCustomUserClaims(targetUid, { role, cities: cities || [] });
    await appendAudit({ actor: req.admin.uid, actorEmail: req.admin.email, role: req.admin.role, action: 'rbac.set_role', after: { uid: targetUid, email, role, cities }, ip: req.ip, ua: req.get('user-agent') });
    res.json({ success: true, uid: targetUid, email: email || null, role, cities });
  } catch (error) {
    if (error.code === 'auth/user-not-found') {
      return res.status(404).json({ error: 'No user with that email — sign in to the app once first to create the account.' });
    }
    next(error);
  }
});

app.use((error, req, res, _next) => {
  (req.log || logger).error({ err: error }, 'Unhandled error');
  const status = error.statusCode || 500;
  res._errorMessage = error.message; // picked up by recordMetrics
  res.status(status).json({
    error: status >= 500 ? 'Internal server error' : error.message,
    // Never leak internal error details to clients in production
  });
});

const server = http.createServer(app);
const io = createPhase56Realtime(server, phase56Context);
_installConvenienceSubscribes(io);
startEventOrchestrator(io, logger);

// Start leaderboard materializer — refreshes top-scores every 30s per city.
// Seed initial city list from the in-memory registry.
startLeaderboardRefresher(firestore, logger);
for (const cityId of Object.keys(cityRegistry)) trackCity(cityId);

server.listen(PORT, '0.0.0.0', () => {
  logger.info({ port: PORT }, 'MetroSafar backend listening');
});
