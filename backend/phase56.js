const crypto = require('crypto');
const cron = require('node-cron');
const { Server } = require('socket.io');
const { createAdapter } = require('@socket.io/redis-adapter');
const { getPubClient, getSubClient } = require('./lib/redis');

const FEATURE_FLAG_DEFAULTS = {
  'phase5.trip_mode': false,
  'phase5.live_etas': false,
  'phase5.disruptions_ws': false,
  'phase5.offline_cache': false,
  'phase6.stamps': false,
  'phase6.audio_stories': false,
  'phase6.live_events': false,
};

const EPISODE_METADATA = [
  {
    id: 'metro_tales_001',
    series: 'metro_tales',
    season: 1,
    episodeNumber: 1,
    title: 'The Last Train From Miyapur',
    synopsis: 'A short commuter mystery designed for a 12-minute ride.',
    durationSeconds: 720,
    audioPath: 'audio/metro_tales_001.m4a',
    artPath: 'audio/metro_tales_001.jpg',
    transcript: 'A short commuter mystery set between Miyapur and Ameerpet.',
    chapters: [
      { title: 'Platform', startSeconds: 0 },
      { title: 'Tunnel', startSeconds: 210 },
      { title: 'Arrival', startSeconds: 540 },
    ],
    releasedAt: '2026-05-18T00:00:00.000Z',
    isPremium: false,
  },
  {
    id: 'metro_tales_002',
    series: 'metro_tales',
    season: 1,
    episodeNumber: 2,
    title: 'Ameerpet Interchange',
    synopsis: 'A warm story about missed connections and second chances.',
    durationSeconds: 840,
    audioPath: 'audio/metro_tales_002.m4a',
    artPath: 'audio/metro_tales_002.jpg',
    transcript: 'A warm story about missed connections and second chances.',
    chapters: [
      { title: 'Rush Hour', startSeconds: 0 },
      { title: 'The Platform Number', startSeconds: 300 },
      { title: 'Homeward', startSeconds: 650 },
    ],
    releasedAt: '2026-05-19T00:00:00.000Z',
    isPremium: false,
  },
];

const EVENT_QUESTION_BANK = [
  {
    id: 'q_1',
    prompt: 'Which station is a major interchange between Red and Blue lines?',
    options: ['Miyapur', 'Ameerpet', 'Raidurg', 'Uppal'],
    correctIndex: 1,
    pointsBase: 20,
    pointsBonusPerSecondRemaining: 2,
  },
  {
    id: 'q_2',
    prompt: 'What is the best app behavior in a tunnel?',
    options: ['Stop working', 'Use cached content', 'Force GPS', 'Clear wallet'],
    correctIndex: 1,
    pointsBase: 20,
    pointsBonusPerSecondRemaining: 2,
  },
  {
    id: 'q_3',
    prompt: 'Which action should require explicit user consent?',
    options: ['Viewing points', 'Background location', 'Reading articles', 'Opening profile'],
    correctIndex: 1,
    pointsBase: 20,
    pointsBonusPerSecondRemaining: 2,
  },
];

function nowIso() {
  return new Date().toISOString();
}

function cleanId(value, fallback = '') {
  return String(value || fallback)
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9_-]/g, '_')
    .replace(/_+/g, '_')
    .slice(0, 120);
}

function hashId(value) {
  return crypto.createHash('sha256').update(String(value)).digest('hex');
}

function dayKey(date = new Date()) {
  return date.toISOString().slice(0, 10);
}

function parseFeatureFlags() {
  const flags = { ...FEATURE_FLAG_DEFAULTS };
  if (!process.env.METROSAFAR_FEATURE_FLAGS) return flags;

  try {
    const overrides = JSON.parse(process.env.METROSAFAR_FEATURE_FLAGS);
    for (const [key, value] of Object.entries(overrides)) {
      if (Object.prototype.hasOwnProperty.call(flags, key)) {
        flags[key] = Boolean(value);
      }
    }
  } catch (error) {
    // context.logger may not be available here; fall back to stderr
    process.stderr.write(`[phase56] Ignoring invalid METROSAFAR_FEATURE_FLAGS JSON: ${error.message}\n`);
  }

  return flags;
}

function createFeatureFlagPayload() {
  return {
    flags: parseFeatureFlags(),
    source: process.env.METROSAFAR_FEATURE_FLAGS ? 'env' : 'defaults',
    updatedAt: nowIso(),
  };
}

function assetBaseUrl() {
  return String(process.env.METROSAFAR_ASSET_BASE_URL || '')
    .trim()
    .replace(/\/+$/, '');
}

function assetUrl(path) {
  const base = assetBaseUrl();
  if (!base) return null;
  return `${base}/${String(path).replace(/^\/+/, '')}`;
}

function buildEpisodeCatalog() {
  return EPISODE_METADATA.map(({ audioPath, artPath, ...episode }) => ({
    ...episode,
    audioUrl: assetUrl(audioPath),
    artUrl: assetUrl(artPath),
  }));
}

function stationSlug(station) {
  return cleanId(station.id || station.name);
}

function findStation(stations, value) {
  if (!value) return null;
  const wanted = String(value).trim().toLowerCase();
  return stations.find((station) => {
    return String(station.id).toLowerCase() === wanted ||
      String(station.name).toLowerCase() === wanted ||
      cleanId(station.name) === cleanId(wanted);
  }) || null;
}

function splitLines(line) {
  return String(line || '')
    .split('&')
    .map((part) => part.replace(/line/i, '').trim().toLowerCase())
    .filter(Boolean);
}

function lineToken(line) {
  const lines = splitLines(line);
  return lines[0] || cleanId(line || 'metro');
}

function stationsForLine(stations, line) {
  const token = lineToken(line);
  return stations.filter((station) => splitLines(station.line).includes(token));
}

function sharedLine(a, b) {
  const aLines = splitLines(a.line);
  const bLines = splitLines(b.line);
  return aLines.find((line) => bLines.includes(line)) || null;
}

function inferTrip(stations, startStation, requestedLine, history = []) {
  const line = requestedLine || startStation.line;
  const lineStations = stationsForLine(stations, line);
  const startIndex = Math.max(0, lineStations.findIndex((station) => station.id === startStation.id));
  const historical = history.find((trip) => {
    return trip.startStation?.id === startStation.id && trip.endStation?.id;
  });

  const fallbackIndex = Math.min(lineStations.length - 1, startIndex + 5);
  const predictedStation = historical
    ? findStation(stations, historical.endStation.id) || lineStations[fallbackIndex] || startStation
    : lineStations[fallbackIndex] || startStation;

  const hops = Math.max(1, Math.abs(
    lineStations.findIndex((station) => station.id === predictedStation.id) - startIndex,
  ));

  return {
    line: startStation.line,
    direction: predictedStation.id === startStation.id || fallbackIndex >= startIndex ? 'outbound' : 'inbound',
    predictedEndStationId: predictedStation.id,
    predictedDurationSeconds: Math.max(300, hops * 150),
  };
}

async function getTripHistory(firestore, clientId, limit = 8) {
  const snapshot = await firestore.collection('metrosafar_trips')
    .where('userId', '==', clientId)
    .limit(limit)
    .get();

  return snapshot.docs
    .map((doc) => ({ id: doc.id, ...doc.data() }))
    .sort((a, b) => String(b.createdAt || '').localeCompare(String(a.createdAt || '')));
}

async function getActiveTrip(context, clientId) {
  const user = await context.getUserState(clientId);
  if (!user.activeTripId) return null;

  const snapshot = await context.firestore
    .collection('metrosafar_trips')
    .doc(user.activeTripId)
    .get();

  if (!snapshot.exists) return null;
  const trip = { id: snapshot.id, ...snapshot.data() };
  return trip.status === 'in_progress' ? trip : null;
}

async function startTrip(context, clientId, body = {}) {
  // Validate that the requested station exists in our catalog.
  const requestedId = body.startStationId || body.stationId;
  const startStation = requestedId ? findStation(context.stations, requestedId) : null;

  if (!startStation) {
    const error = new Error(requestedId ? `Station '${requestedId}' not found` : 'startStationId is required');
    error.statusCode = 400;
    throw error;
  }

  const user = await context.getUserState(clientId);
  if (user.activeTripId) {
    await context.firestore.collection('metrosafar_trips').doc(user.activeTripId).set({
      status: 'abandoned',
      completedAt: nowIso(),
      abandonReason: 'new_trip_started',
    }, { merge: true });
  }

  const history = await getTripHistory(context.firestore, clientId);
  const inference = inferTrip(context.stations, startStation, body.line, history);
  const tripId = crypto.randomUUID();
  const createdAt = body.detectedAt || nowIso();
  const trip = {
    id: tripId,
    userId: clientId,
    line: body.line || inference.line,
    direction: inference.direction,
    startStation: {
      id: startStation.id,
      name: startStation.name,
      claimedAt: createdAt,
    },
    endStation: null,
    predictedEndStationId: inference.predictedEndStationId,
    predictedEndAt: new Date(Date.now() + inference.predictedDurationSeconds * 1000).toISOString(),
    predictedDurationSeconds: inference.predictedDurationSeconds,
    source: body.source || 'manual',
    status: 'in_progress',
    heartbeats: [],
    pointsEarned: 0,
    stamps: [],
    co2SavedKg: 0,
    createdAt,
    completedAt: null,
  };

  await context.firestore.collection('metrosafar_trips').doc(tripId).set(trip);
  await context.saveUserState(clientId, { ...user, activeTripId: tripId });

  return {
    tripId,
    trip,
    predictedEndStationId: inference.predictedEndStationId,
    predictedDurationSeconds: inference.predictedDurationSeconds,
  };
}

async function updateTripHeartbeat(context, clientId, tripId, body = {}) {
  const ref = context.firestore.collection('metrosafar_trips').doc(tripId);
  const snapshot = await ref.get();
  if (!snapshot.exists) {
    const error = new Error('Trip not found');
    error.statusCode = 404;
    throw error;
  }

  const trip = snapshot.data();
  if (trip.userId !== clientId) {
    const error = new Error('Trip not found');
    error.statusCode = 404;
    throw error;
  }

  if (trip.status !== 'in_progress') {
    return {
      predictedEndStationId: trip.predictedEndStationId,
      remainingSeconds: 0,
      status: trip.status,
    };
  }

  const heartbeat = {
    lat: Number(body.lat || 0),
    lng: Number(body.lng || 0),
    speedKmh: Number(body.speedKmh || 0),
    timestamp: body.timestamp || nowIso(),
  };
  const heartbeats = [...(trip.heartbeats || []), heartbeat].slice(-30);
  const remainingSeconds = Math.max(
    0,
    Math.floor((new Date(trip.predictedEndAt).getTime() - Date.now()) / 1000),
  );

  await ref.set({ heartbeats, lastHeartbeatAt: nowIso() }, { merge: true });
  return {
    predictedEndStationId: trip.predictedEndStationId,
    remainingSeconds,
    status: trip.status,
  };
}

async function endTrip(context, clientId, tripId, body = {}) {
  const ref = context.firestore.collection('metrosafar_trips').doc(tripId);
  const snapshot = await ref.get();
  if (!snapshot.exists) {
    const error = new Error('Trip not found');
    error.statusCode = 404;
    throw error;
  }

  const trip = snapshot.data();
  if (trip.userId !== clientId) {
    const error = new Error('Trip not found');
    error.statusCode = 404;
    throw error;
  }

  if (trip.status === 'completed') {
    return {
      pointsAwarded: trip.pointsEarned || 0,
      stampsEarned: trip.stamps || [],
      co2SavedKg: trip.co2SavedKg || 0,
      returnTripSuggestion: trip.returnTripSuggestion || null,
      trip: { id: tripId, ...trip },
    };
  }

  // Validate: trip must have been started within the last 3 hours.
  const tripAge = Date.now() - new Date(trip.createdAt || 0).getTime();
  if (tripAge > 3 * 60 * 60 * 1000) {
    await ref.set({ status: 'expired', completedAt: nowIso() }, { merge: true });
    const error = new Error('Trip expired — too much time has passed since it was started');
    error.statusCode = 400;
    throw error;
  }

  // Validate: require at least one heartbeat to earn points.
  const hasHeartbeats = Array.isArray(trip.heartbeats) && trip.heartbeats.length > 0;

  const endStation = findStation(context.stations, body.endStationId) ||
    findStation(context.stations, trip.predictedEndStationId) ||
    findStation(context.stations, trip.startStation?.id);
  const startStation = findStation(context.stations, trip.startStation?.id);
  const lineStations = startStation && endStation
    ? stationsForLine(context.stations, sharedLine(startStation, endStation) || startStation.line)
    : [];
  const startIndex = lineStations.findIndex((station) => station.id === startStation?.id);
  const endIndex = lineStations.findIndex((station) => station.id === endStation?.id);
  const hops = startIndex >= 0 && endIndex >= 0 ? Math.max(1, Math.abs(endIndex - startIndex)) : 3;
  // No heartbeats → source=manual without any real GPS evidence → award 0 points.
  const pointsAwarded = hasHeartbeats ? Math.min(80, 10 + hops * 4) : 0;
  const co2SavedKg = Number((hops * 0.18).toFixed(2));
  const stampsEarned = endStation ? [endStation.id] : [];
  const returnTripSuggestion = startStation && endStation
    ? {
        startStationId: endStation.id,
        endStationId: startStation.id,
        label: `${endStation.name} to ${startStation.name}`,
      }
    : null;

  const completedAt = body.endedAt || nowIso();
  await ref.set({
    endStation: endStation ? { id: endStation.id, name: endStation.name, claimedAt: completedAt } : null,
    status: 'completed',
    pointsEarned: pointsAwarded,
    stamps: stampsEarned,
    co2SavedKg,
    returnTripSuggestion,
    completedAt,
  }, { merge: true });

  const user = await context.getUserState(clientId);
  await context.saveUserState(clientId, {
    ...user,
    activeTripId: null,
    points: Number(user.points || 0) + pointsAwarded,
    tripSummary: {
      totalTrips: Number(user.tripSummary?.totalTrips || 0) + 1,
      totalKm: Number((Number(user.tripSummary?.totalKm || 0) + hops * 1.15).toFixed(2)),
      totalCo2Kg: Number((Number(user.tripSummary?.totalCo2Kg || 0) + co2SavedKg).toFixed(2)),
      mostVisitedStation: endStation?.name || user.tripSummary?.mostVisitedStation || null,
      lastUpdated: nowIso(),
    },
  });

  return {
    pointsAwarded,
    stampsEarned,
    co2SavedKg,
    returnTripSuggestion,
    trip: {
      id: tripId,
      ...trip,
      status: 'completed',
      completedAt,
    },
  };
}

function buildArrivalsForStation(station) {
  const now = new Date();
  const serviceStart = new Date(now);
  serviceStart.setHours(5, 30, 0, 0);
  const elapsed = Math.max(0, Math.floor((now.getTime() - serviceStart.getTime()) / 1000));
  const headway = 6 * 60;
  const firstEta = (headway - (elapsed % headway)) % headway || headway;
  const line = lineToken(station.line);

  return [0, 1, 2].map((index) => {
    const etaSeconds = firstEta + index * headway;
    return {
      trainId: `${line}_${Math.floor((elapsed + etaSeconds) / headway)}`,
      line,
      direction: index % 2 === 0 ? 'outbound' : 'inbound',
      etaSeconds,
      crowdLevel: index === 0 ? 'moderate' : 'light',
      confidence: 'timetable',
    };
  });
}

function routeBetweenStations(stations, fromStation, toStation) {
  const directLine = sharedLine(fromStation, toStation);
  if (directLine) {
    const lineStations = stationsForLine(stations, directLine);
    const fromIndex = lineStations.findIndex((station) => station.id === fromStation.id);
    const toIndex = lineStations.findIndex((station) => station.id === toStation.id);
    const stops = Math.max(1, Math.abs(toIndex - fromIndex));
    return [{
      id: `${fromStation.id}_${toStation.id}_direct`,
      summary: `${fromStation.name} to ${toStation.name}`,
      line: directLine,
      transfers: [],
      durationSeconds: stops * 150,
      fareEstimate: Math.min(60, 10 + stops * 3),
      confidence: 'timetable',
    }];
  }

  const transfer = stations.find((station) => {
    return splitLines(station.line).some((line) => splitLines(fromStation.line).includes(line)) &&
      splitLines(station.line).some((line) => splitLines(toStation.line).includes(line));
  }) || stations.find((station) => station.name === 'Ameerpet') || stations[0];

  return [{
    id: `${fromStation.id}_${toStation.id}_transfer`,
    summary: `${fromStation.name} to ${toStation.name} via ${transfer.name}`,
    line: `${fromStation.line} + ${toStation.line}`,
    transfers: [{ stationId: transfer.id, stationName: transfer.name }],
    durationSeconds: 1800,
    fareEstimate: 50,
    confidence: 'timetable',
  }];
}

function buildStampCatalog(stations) {
  return stations.slice(0, 36).map((station, index) => {
    const rarity = station.line.includes('&')
      ? 'rare'
      : index % 13 === 0
        ? 'epic'
        : 'common';
    return {
      id: `stamp_${stationSlug(station)}`,
      name: `${station.name} Stamp`,
      stationId: station.id,
      stationName: station.name,
      line: station.line,
      rarity,
      artUrl: assetUrl(`stamps/${stationSlug(station)}.png`),
      collectionIds: [`line_${lineToken(station.line)}`, 'hyderabad_starter'],
      seasonal: null,
      pointsAwarded: rarity === 'epic' ? 25 : rarity === 'rare' ? 15 : 5,
    };
  });
}

function buildCollections(stations, catalog) {
  const lineCollections = [...new Set(stations.flatMap((station) => splitLines(station.line)))]
    .map((line) => {
      const requiredStampIds = catalog
        .filter((stamp) => splitLines(stamp.line).includes(line))
        .map((stamp) => stamp.id);
      return {
        id: `line_${line}`,
        name: `${line[0].toUpperCase()}${line.slice(1)} Line Collector`,
        requiredStampIds,
        reward: { type: 'points', value: 150 },
      };
    });

  return [
    {
      id: 'hyderabad_starter',
      name: 'Hyderabad Starter Set',
      requiredStampIds: catalog.slice(0, 5).map((stamp) => stamp.id),
      reward: { type: 'badge', value: 'starter_explorer' },
    },
    ...lineCollections,
  ];
}

async function getUserStampMap(context, clientId) {
  const snapshot = await context.firestore
    .collection('metrosafar_users')
    .doc(clientId)
    .collection('stamps')
    .get();

  const stamps = {};
  for (const doc of snapshot.docs) {
    stamps[doc.id] = doc.data();
  }
  return stamps;
}

async function claimStamp(context, clientId, body = {}) {
  const catalog = buildStampCatalog(context.stations);
  const station = findStation(context.stations, body.stationId);
  const stamp = station
    ? catalog.find((item) => item.stationId === station.id)
    : catalog.find((item) => item.id === body.stampId);

  if (!stamp) {
    const error = new Error('Stamp not found');
    error.statusCode = 404;
    throw error;
  }

  const activeTrip = await getActiveTrip(context, clientId);
  const bonusEligible = Boolean(activeTrip && activeTrip.status === 'in_progress');
  const pointsAwarded = bonusEligible ? Number(stamp.pointsAwarded || 0) : 0;
  const ref = context.firestore
    .collection('metrosafar_users')
    .doc(clientId)
    .collection('stamps')
    .doc(stamp.id);
  const snapshot = await ref.get();
  const existing = snapshot.exists ? snapshot.data() : null;
  const lastClaimDate = existing?.lastClaimDate;
  const today = dayKey();

  if (lastClaimDate === today) {
    return {
      stamp,
      firstClaim: false,
      duplicateToday: true,
      pointsAwarded: 0,
      bonusEligible,
    };
  }

  await ref.set({
    count: Number(existing?.count || 0) + 1,
    firstClaimedAt: existing?.firstClaimedAt || nowIso(),
    lastClaimedAt: nowIso(),
    lastClaimDate: today,
    tripIds: [...new Set([...(existing?.tripIds || []), activeTrip?.id].filter(Boolean))],
  }, { merge: true });

  if (pointsAwarded > 0) {
    const user = await context.getUserState(clientId);
    await context.saveUserState(clientId, {
      ...user,
      points: Number(user.points || 0) + pointsAwarded,
    });
  }

  return {
    stamp,
    firstClaim: !existing,
    duplicateToday: false,
    pointsAwarded,
    bonusEligible,
  };
}

async function buildCollectionProgress(context, clientId) {
  const catalog = buildStampCatalog(context.stations);
  const collections = buildCollections(context.stations, catalog);
  const owned = await getUserStampMap(context, clientId);

  return collections.map((collection) => {
    const ownedCount = collection.requiredStampIds
      .filter((stampId) => Number(owned[stampId]?.count || 0) > 0)
      .length;
    return {
      ...collection,
      progress: ownedCount,
      total: collection.requiredStampIds.length,
      completedAt: ownedCount >= collection.requiredStampIds.length ? nowIso() : null,
    };
  });
}

function nextDateAt(hour, minute, offsetDays = 0) {
  const date = new Date();
  date.setDate(date.getDate() + offsetDays);
  date.setHours(hour, minute, 0, 0);
  if (offsetDays === 0 && date.getTime() < Date.now()) {
    date.setDate(date.getDate() + 1);
  }
  return date;
}

function eventStatus(scheduledFor, durationSeconds) {
  const start = new Date(scheduledFor).getTime();
  const now = Date.now();
  if (now < start - 5 * 60 * 1000) return 'scheduled';
  if (now < start) return 'lobby';
  if (now < start + durationSeconds * 1000) return 'live';
  if (now < start + (durationSeconds + 60) * 1000) return 'ended';
  return 'settled';
}

function buildEventSchedule() {
  const events = [];
  for (let dayOffset = 0; dayOffset < 7; dayOffset += 1) {
    const brainBuzz = nextDateAt(8, 0, dayOffset);
    const powerHour = nextDateAt(18, 0, dayOffset);
    events.push({
      id: `brain_buzz_${brainBuzz.toISOString().slice(0, 10)}`,
      type: 'trivia',
      title: 'Morning Brain Buzz',
      scheduledFor: brainBuzz.toISOString(),
      durationSeconds: 60,
      status: eventStatus(brainBuzz, 60),
      prizeStructure: { top10: 200, top100: 100, participation: 20 },
      participantCount: 0,
      questionBankId: 'brain_buzz_pilot',
    });
    events.push({
      id: `power_hour_${powerHour.toISOString().slice(0, 10)}`,
      type: 'power_hour',
      title: 'Power Hour',
      scheduledFor: powerHour.toISOString(),
      durationSeconds: 3600,
      status: eventStatus(powerHour, 3600),
      prizeStructure: { participation: 20 },
      participantCount: 0,
      questionBankId: null,
    });
  }
  return events;
}

const WS_SECRET = process.env.METROSAFAR_WS_SECRET;
if (!WS_SECRET) {
  // Crash fast in production; allow local dev with a warning.
  if (process.env.NODE_ENV === 'production') {
    throw new Error('METROSAFAR_WS_SECRET env var is required in production');
  }
  // eslint-disable-next-line no-console
  console.warn('[WARNING] METROSAFAR_WS_SECRET is not set — using insecure local default');
}
const _wsSecret = WS_SECRET || 'local-dev-only-not-for-production';

function signRealtimeToken(clientId) {
  const header = Buffer.from(JSON.stringify({ alg: 'HS256', typ: 'JWT' })).toString('base64url');
  const payload = Buffer.from(JSON.stringify({
    sub: clientId,
    exp: Math.floor(Date.now() / 1000) + 15 * 60,
    iat: Math.floor(Date.now() / 1000),
  })).toString('base64url');
  const signature = crypto
    .createHmac('sha256', _wsSecret)
    .update(`${header}.${payload}`)
    .digest('base64url');
  return `${header}.${payload}.${signature}`;
}

function verifyRealtimeToken(token) {
  const secret = _wsSecret;
  const [header, payload, signature] = String(token || '').split('.');
  if (!header || !payload || !signature) return null;
  const expected = crypto
    .createHmac('sha256', secret)
    .update(`${header}.${payload}`)
    .digest('base64url');
  if (!crypto.timingSafeEqual(Buffer.from(signature), Buffer.from(expected))) return null;

  const decoded = JSON.parse(Buffer.from(payload, 'base64url').toString('utf8'));
  if (!decoded.exp || decoded.exp < Math.floor(Date.now() / 1000)) return null;
  return decoded;
}

function installPhase56Middleware(app, context) {
  app.get('/api/feature-flags', (_req, res) => {
    res.json(createFeatureFlagPayload());
  });

  app.get('/api/realtime/token', (req, res) => {
    res.json({
      token: signRealtimeToken(req.clientId),
      expiresInSeconds: 900,
    });
  });

  app.use(async (req, res, next) => {
    if (!['POST', 'PATCH', 'DELETE'].includes(req.method)) {
      next();
      return;
    }

    const key = req.header('Idempotency-Key');
    if (!key) {
      next();
      return;
    }

    const docId = hashId(`${req.clientId}:${key}`);
    const ref = context.firestore.collection('metrosafar_idempotency_keys').doc(docId);

    try {
      const snapshot = await ref.get();
      if (snapshot.exists) {
        const cached = snapshot.data();
        if (!cached.expiresAt || new Date(cached.expiresAt).getTime() > Date.now()) {
          res.set('X-Idempotent-Replay', 'true');
          res.status(cached.statusCode || 200).json(cached.body || {});
          return;
        }
      }

      const originalJson = res.json.bind(res);
      res.json = (body) => {
        if (res.statusCode < 500) {
          ref.set({
            key,
            clientId: req.clientId,
            method: req.method,
            path: req.path,
            statusCode: res.statusCode,
            body,
            createdAt: nowIso(),
            expiresAt: new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString(),
          }).catch((error) => {
            if (context.logger) context.logger.error({ err: error }, 'Failed to store idempotency response');
          });
        }
        return originalJson(body);
      };

      next();
    } catch (error) {
      next(error);
    }
  });
}

function installPhase56Routes(app, context) {
  app.post('/api/trips/start', async (req, res, next) => {
    try {
      res.json(await startTrip(context, req.clientId, req.body));
    } catch (error) {
      next(error);
    }
  });

  app.post('/api/trips/:tripId/heartbeat', async (req, res, next) => {
    try {
      res.json(await updateTripHeartbeat(context, req.clientId, req.params.tripId, req.body));
    } catch (error) {
      next(error);
    }
  });

  app.post('/api/trips/:tripId/end', async (req, res, next) => {
    try {
      res.json(await endTrip(context, req.clientId, req.params.tripId, req.body));
    } catch (error) {
      next(error);
    }
  });

  app.get('/api/trips/active', async (req, res, next) => {
    try {
      res.json({ trip: await getActiveTrip(context, req.clientId) });
    } catch (error) {
      next(error);
    }
  });

  app.get('/api/trips/history', async (req, res, next) => {
    try {
      const limit = Math.min(50, Number(req.query.limit || 20));
      res.json({ trips: await getTripHistory(context.firestore, req.clientId, limit) });
    } catch (error) {
      next(error);
    }
  });

  app.get('/api/intel/etas', (req, res) => {
    const requested = String(req.query.stations || '')
      .split(',')
      .map((item) => item.trim())
      .filter(Boolean);
    const selected = requested.length
      ? requested.map((item) => findStation(context.stations, item)).filter(Boolean)
      : context.stations.slice(0, 2);

    res.json({
      asOf: nowIso(),
      stations: selected.map((station) => ({
        stationId: station.id,
        stationName: station.name,
        arrivals: buildArrivalsForStation(station),
      })),
    });
  });

  app.get('/api/intel/disruptions', (_req, res) => {
    res.json({ asOf: nowIso(), disruptions: [] });
  });

  app.post('/api/intel/crowd-report', async (req, res, next) => {
    try {
      const trainId = cleanId(req.body.trainId, 'unknown_train');
      const coachId = cleanId(req.body.coachId, 'coach_1');
      const crowdLevel = Math.max(0, Math.min(4, Number(req.body.crowdLevel || 0)));
      await context.firestore.collection('metrosafar_crowd_reports').add({
        clientId: req.clientId,
        trainId,
        coachId,
        crowdLevel,
        userReliabilityScore: 1,
        createdAt: nowIso(),
      });
      if (context.io) {
        context.io.to(`train:${trainId}`).emit('crowding_update', {
          trainId,
          coachId,
          crowdLevel,
          asOf: nowIso(),
        });
      }
      res.json({ accepted: true, trainId, coachId, crowdLevel });
    } catch (error) {
      next(error);
    }
  });

  app.get('/api/intel/crowding/:trainId', async (req, res, next) => {
    try {
      const trainId = cleanId(req.params.trainId);
      const since = Date.now() - 5 * 60 * 1000;
      const snapshot = await context.firestore.collection('metrosafar_crowd_reports')
        .where('trainId', '==', trainId)
        .limit(100)
        .get();
      const byCoach = {};
      snapshot.docs
        .map((doc) => doc.data())
        .filter((report) => new Date(report.createdAt).getTime() >= since)
        .forEach((report) => {
          byCoach[report.coachId] ||= [];
          byCoach[report.coachId].push(report);
        });

      const coaches = Object.entries(byCoach).map(([coachId, reports]) => {
        const average = reports.reduce((sum, report) => sum + Number(report.crowdLevel || 0), 0) /
          Math.max(1, reports.length);
        return {
          coachId,
          reportCount: reports.length,
          crowdLevel: Number(average.toFixed(1)),
          confidence: reports.length >= 3 ? 'high' : 'low',
        };
      });

      res.json({ trainId, asOf: nowIso(), coaches });
    } catch (error) {
      next(error);
    }
  });

  app.get('/api/intel/route', (req, res) => {
    const from = findStation(context.stations, req.query.from);
    const to = findStation(context.stations, req.query.to);
    if (!from || !to) {
      res.status(400).json({ error: 'Both from and to stations are required' });
      return;
    }
    res.json({
      asOf: nowIso(),
      from: { id: from.id, name: from.name },
      to: { id: to.id, name: to.name },
      options: routeBetweenStations(context.stations, from, to),
    });
  });

  app.get('/api/stamps/catalog', (_req, res) => {
    res.json({
      stamps: buildStampCatalog(context.stations),
      collections: buildCollections(context.stations, buildStampCatalog(context.stations)),
      etag: hashId(JSON.stringify(context.stations)).slice(0, 16),
    });
  });

  app.get('/api/stamps/mine', async (req, res, next) => {
    try {
      const catalog = buildStampCatalog(context.stations);
      const owned = await getUserStampMap(context, req.clientId);
      res.json({
        stamps: catalog.map((stamp) => ({
          ...stamp,
          ownedCount: Number(owned[stamp.id]?.count || 0),
          firstClaimedAt: owned[stamp.id]?.firstClaimedAt || null,
          lastClaimedAt: owned[stamp.id]?.lastClaimedAt || null,
        })),
      });
    } catch (error) {
      next(error);
    }
  });

  app.post('/api/stamps/claim', async (req, res, next) => {
    try {
      res.json(await claimStamp(context, req.clientId, req.body));
    } catch (error) {
      next(error);
    }
  });

  app.get('/api/collections', async (req, res, next) => {
    try {
      res.json({ collections: await buildCollectionProgress(context, req.clientId) });
    } catch (error) {
      next(error);
    }
  });

  app.post('/api/trades/propose', async (req, res, next) => {
    try {
      const tradeId = crypto.randomUUID();
      const toUserId = cleanId(req.body.toUserId);
      if (!toUserId) {
        res.status(400).json({ error: 'toUserId is required' });
        return;
      }
      const trade = {
        id: tradeId,
        fromUserId: req.clientId,
        toUserId,
        offering: Array.isArray(req.body.offering) ? req.body.offering.map(cleanId) : [],
        requesting: Array.isArray(req.body.requesting) ? req.body.requesting.map(cleanId) : [],
        status: 'pending',
        createdAt: nowIso(),
        resolvedAt: null,
        version: 1,
      };
      await context.firestore.collection('metrosafar_trades').doc(tradeId).set(trade);
      res.json({ trade });
    } catch (error) {
      next(error);
    }
  });

  app.get('/api/trades/inbox', async (req, res, next) => {
    try {
      const incoming = await context.firestore.collection('metrosafar_trades')
        .where('toUserId', '==', req.clientId)
        .limit(50)
        .get();
      const outgoing = await context.firestore.collection('metrosafar_trades')
        .where('fromUserId', '==', req.clientId)
        .limit(50)
        .get();
      res.json({
        incoming: incoming.docs.map((doc) => ({ id: doc.id, ...doc.data() })),
        outgoing: outgoing.docs.map((doc) => ({ id: doc.id, ...doc.data() })),
      });
    } catch (error) {
      next(error);
    }
  });

  app.post('/api/trades/:id/decline', async (req, res, next) => {
    try {
      const ref = context.firestore.collection('metrosafar_trades').doc(req.params.id);
      const snapshot = await ref.get();
      if (!snapshot.exists || snapshot.data().toUserId !== req.clientId) {
        res.status(404).json({ error: 'Trade not found' });
        return;
      }
      await ref.set({ status: 'declined', resolvedAt: nowIso() }, { merge: true });
      res.json({ accepted: false, tradeId: req.params.id });
    } catch (error) {
      next(error);
    }
  });

  app.post('/api/trades/:id/accept', async (req, res, next) => {
    try {
      const tradeRef = context.firestore.collection('metrosafar_trades').doc(req.params.id);
      await context.firestore.runTransaction(async (transaction) => {
        const tradeSnapshot = await transaction.get(tradeRef);
        if (!tradeSnapshot.exists) {
          const error = new Error('Trade not found');
          error.statusCode = 404;
          throw error;
        }
        const trade = tradeSnapshot.data();
        if (trade.toUserId !== req.clientId || trade.status !== 'pending') {
          const error = new Error('Trade is not available');
          error.statusCode = 409;
          throw error;
        }

        const fromUserRef = context.firestore.collection('metrosafar_users').doc(trade.fromUserId);
        const toUserRef = context.firestore.collection('metrosafar_users').doc(trade.toUserId);

        const transfers = [
          ...(trade.offering || []).map((stampId) => ({
            stampId,
            fromRef: fromUserRef.collection('stamps').doc(stampId),
            toRef: toUserRef.collection('stamps').doc(stampId),
          })),
          ...(trade.requesting || []).map((stampId) => ({
            stampId,
            fromRef: toUserRef.collection('stamps').doc(stampId),
            toRef: fromUserRef.collection('stamps').doc(stampId),
          })),
        ];

        const snapshots = [];
        for (const transfer of transfers) {
          snapshots.push({
            transfer,
            fromSnapshot: await transaction.get(transfer.fromRef),
            toSnapshot: await transaction.get(transfer.toRef),
          });
        }

        for (const item of snapshots) {
          const ownedCount = Number(item.fromSnapshot.data()?.count || 0);
          if (ownedCount < 1) {
            const error = new Error(`Stamp ${item.transfer.stampId} is no longer available`);
            error.statusCode = 409;
            throw error;
          }
        }

        const decrement = (ref, currentCount) => {
          transaction.set(ref, {
            count: Math.max(0, currentCount - 1),
            lastClaimedAt: nowIso(),
          }, { merge: true });
        };
        const increment = (ref, snapshot) => {
          const current = snapshot.exists ? snapshot.data() : {};
          transaction.set(ref, {
            count: Number(current.count || 0) + 1,
            firstClaimedAt: current.firstClaimedAt || nowIso(),
            lastClaimedAt: nowIso(),
          }, { merge: true });
        };

        snapshots.forEach((item) => {
          decrement(item.transfer.fromRef, Number(item.fromSnapshot.data()?.count || 0));
          increment(item.transfer.toRef, item.toSnapshot);
        });

        transaction.set(tradeRef, {
          status: 'accepted',
          resolvedAt: nowIso(),
          version: Number(trade.version || 1) + 1,
        }, { merge: true });
      });
      res.json({ accepted: true, tradeId: req.params.id });
    } catch (error) {
      next(error);
    }
  });

  // ---------------------------------------------------------------------------
  // Audio episodes — feature-flagged off until real audio files are uploaded
  // ---------------------------------------------------------------------------

  function audioEnabled() {
    return parseFeatureFlags()['phase6.audio_stories'] === true && Boolean(assetBaseUrl());
  }

  function unavailableAudio(res) {
    res.status(503).json({
      error: 'Audio stories are not yet available. Check back soon!',
    });
  }

  app.get('/api/episodes/today', (_req, res) => {
    if (!audioEnabled()) {
      unavailableAudio(res);
      return;
    }
    res.json({ episode: buildEpisodeCatalog()[0] });
  });

  app.get('/api/episodes', (_req, res) => {
    if (!audioEnabled()) {
      unavailableAudio(res);
      return;
    }
    res.json({ episodes: buildEpisodeCatalog() });
  });

  app.get('/api/episodes/:id', (req, res) => {
    if (!audioEnabled()) {
      unavailableAudio(res);
      return;
    }
    const episode = buildEpisodeCatalog().find((item) => item.id === req.params.id);
    if (!episode) {
      res.status(404).json({ error: 'Episode not found' });
      return;
    }
    res.json({
      episode: {
        ...episode,
        signedAudioUrl: episode.audioUrl,
        signedUrlExpiresInSeconds: 3600,
      },
    });
  });

  app.get('/api/episodes/:id/position', async (req, res, next) => {
    try {
      const ref = context.firestore
        .collection('metrosafar_users')
        .doc(req.clientId)
        .collection('episode_positions')
        .doc(req.params.id);
      const snapshot = await ref.get();
      res.json({
        position: snapshot.exists
          ? snapshot.data()
          : { episodeId: req.params.id, positionSeconds: 0, completed: false },
      });
    } catch (error) {
      next(error);
    }
  });

  app.post('/api/episodes/:id/position', async (req, res, next) => {
    try {
      const episode = buildEpisodeCatalog().find((item) => item.id === req.params.id);
      if (!episode) {
        res.status(404).json({ error: 'Episode not found' });
        return;
      }
      const positionSeconds = Math.max(0, Math.min(
        episode.durationSeconds,
        Number(req.body.positionSeconds || 0),
      ));
      const completed = Boolean(req.body.completed) || positionSeconds >= episode.durationSeconds * 0.9;
      const position = {
        episodeId: episode.id,
        positionSeconds,
        durationSeconds: episode.durationSeconds,
        completed,
        updatedAt: nowIso(),
      };
      await context.firestore
        .collection('metrosafar_users')
        .doc(req.clientId)
        .collection('episode_positions')
        .doc(episode.id)
        .set(position, { merge: true });
      res.json({ position });
    } catch (error) {
      next(error);
    }
  });

  app.get('/api/events/schedule', (_req, res) => {
    res.json({ events: buildEventSchedule() });
  });

  app.get('/api/events/:id', (req, res) => {
    const event = buildEventSchedule().find((item) => item.id === req.params.id);
    if (!event) {
      res.status(404).json({ error: 'Event not found' });
      return;
    }
    res.json({
      event,
      questions: event.type === 'trivia' ? EVENT_QUESTION_BANK.map(({ correctIndex, ...safe }) => safe) : [],
      serverTimeMs: Date.now(),
    });
  });

  app.post('/api/events/:id/join', async (req, res, next) => {
    try {
      const event = buildEventSchedule().find((item) => item.id === req.params.id);
      if (!event) {
        res.status(404).json({ error: 'Event not found' });
        return;
      }
      await context.firestore
        .collection('metrosafar_events')
        .doc(event.id)
        .collection('participants')
        .doc(req.clientId)
        .set({
          userId: req.clientId,
          score: 0,
          answers: [],
          joinedAt: nowIso(),
        }, { merge: true });
      res.json({
        event,
        room: `event:${event.id}`,
        roomToken: signRealtimeToken(req.clientId),
      });
    } catch (error) {
      next(error);
    }
  });

  app.post('/api/events/:id/submit', async (req, res, next) => {
    try {
      const question = EVENT_QUESTION_BANK.find((item) => item.id === req.body.questionId);
      if (!question) {
        res.status(404).json({ error: 'Question not found' });
        return;
      }

      const answer = Number(req.body.answer);
      const correct = answer === question.correctIndex;
      const points = correct ? question.pointsBase : 0;
      const participantRef = context.firestore
        .collection('metrosafar_events')
        .doc(req.params.id)
        .collection('participants')
        .doc(req.clientId);
      const snapshot = await participantRef.get();
      const current = snapshot.exists ? snapshot.data() : { score: 0, answers: [] };
      const alreadyAnswered = (current.answers || []).some((item) => item.questionId === question.id);
      const nextScore = alreadyAnswered ? Number(current.score || 0) : Number(current.score || 0) + points;
      const answers = alreadyAnswered
        ? current.answers
        : [
            ...(current.answers || []),
            {
              questionId: question.id,
              answer,
              correct,
              ms: Number(req.body.clientTimeMs || 0),
              submittedAt: nowIso(),
            },
          ];

      await participantRef.set({
        userId: req.clientId,
        score: nextScore,
        answers,
        joinedAt: current.joinedAt || nowIso(),
        updatedAt: nowIso(),
      }, { merge: true });

      if (context.io) {
        context.io.to(`event:${req.params.id}`).emit('leaderboard_update', {
          eventId: req.params.id,
          userId: req.clientId,
          score: nextScore,
        });
      }

      res.json({ correct, pointsAwarded: alreadyAnswered ? 0 : points, score: nextScore });
    } catch (error) {
      next(error);
    }
  });

  app.get('/api/events/:id/leaderboard', async (req, res, next) => {
    try {
      const snapshot = await context.firestore
        .collection('metrosafar_events')
        .doc(req.params.id)
        .collection('participants')
        .limit(100)
        .get();
      const leaderboard = snapshot.docs
        .map((doc) => ({ userId: doc.id, name: doc.id.slice(-8), score: Number(doc.data().score || 0) }))
        .sort((a, b) => b.score - a.score)
        .map((entry, index) => ({ ...entry, rank: index + 1 }));
      res.json({ eventId: req.params.id, leaderboard });
    } catch (error) {
      next(error);
    }
  });

  app.get('/api/events/:id/my-result', async (req, res, next) => {
    try {
      const ref = context.firestore
        .collection('metrosafar_events')
        .doc(req.params.id)
        .collection('participants')
        .doc(req.clientId);
      const snapshot = await ref.get();
      res.json({
        eventId: req.params.id,
        result: snapshot.exists ? snapshot.data() : null,
      });
    } catch (error) {
      next(error);
    }
  });

  app.post('/api/sync/replay', async (req, res) => {
    const operations = Array.isArray(req.body.operations) ? req.body.operations : [];
    res.json({
      replayedAt: nowIso(),
      results: operations.map((operation, index) => ({
        index,
        status: 202,
        body: {
          accepted: true,
          method: operation.method,
          path: operation.path,
          message: 'Operation accepted by replay queue. Individual online replay remains authoritative.',
        },
      })),
    });
  });
}

function createPhase56Realtime(server, context) {
  const allowedOrigins = (process.env.ALLOWED_ORIGINS || '')
    .split(',')
    .map((origin) => origin.trim())
    .filter(Boolean);
  const resolveOrigin = (origin, cb) => {
    if (!origin || allowedOrigins.includes(origin)) {
      cb(null, true);
      return;
    }
    if (process.env.NODE_ENV !== 'production' && allowedOrigins.length === 0) {
      cb(null, true);
      return;
    }
    const error = new Error('Not allowed by CORS');
    error.statusCode = 403;
    cb(error);
  };

  const io = new Server(server, {
    cors: {
      origin: resolveOrigin,
      methods: ['GET', 'POST'],
    },
    pingInterval: 30000,
    pingTimeout: 60000,
  });

  // Attach Redis adapter so io.to(room).emit() fans out across all instances.
  // Falls back to in-process adapter when Redis is not configured (dev/single-instance).
  const pubClient = getPubClient();
  const subClient = getSubClient();
  if (pubClient && subClient) {
    io.adapter(createAdapter(pubClient, subClient));
    console.info('[socket.io] Redis adapter attached — multi-instance fan-out enabled');
  } else {
    console.info('[socket.io] No Redis configured — using in-process adapter (single instance only)');
  }

  io.use((socket, next) => {
    const decoded = verifyRealtimeToken(socket.handshake.auth?.token);
    if (!decoded?.sub) {
      next(new Error('Unauthorized'));
      return;
    }
    socket.clientId = decoded.sub;
    next();
  });

  io.on('connection', (socket) => {
    socket.join(`user:${socket.clientId}`);

    socket.on('subscribe', (room) => {
      const value = String(room || '');
      if (/^(event|train|line):[a-zA-Z0-9_-]+$/.test(value)) {
        socket.join(value);
      }
    });

    socket.on('unsubscribe', (room) => {
      const value = String(room || '');
      if (/^(event|train|line):[a-zA-Z0-9_-]+$/.test(value)) {
        socket.leave(value);
      }
    });

    socket.on('submit_answer', (payload = {}) => {
      socket.to(`event:${payload.eventId}`).emit('participant_answered', {
        eventId: payload.eventId,
        userId: socket.clientId,
      });
    });
  });

  context.io = io;
  return io;
}

// ---------------------------------------------------------------------------
// Event Orchestrator — state machine driven by node-cron
// States: scheduled → lobby_open → live → question_push (loop) → ended → settled
// ---------------------------------------------------------------------------

const QUESTION_DURATION_SECONDS = 20;
const INTER_QUESTION_PAUSE_SECONDS = 5;

// Tracks in-memory state per event id so we never double-schedule.
const _orchestratorState = new Map();

function _pushQuestion(io, eventId, question, index, total) {
  const serverTimeMs = Date.now();
  const deadlineMs = serverTimeMs + QUESTION_DURATION_SECONDS * 1000;
  io.to(`event:${eventId}`).emit('event:question', {
    eventId,
    questionIndex: index,
    totalQuestions: total,
    id: question.id,
    prompt: question.prompt,
    options: question.options,
    pointsBase: question.pointsBase,
    pointsBonusPerSecondRemaining: question.pointsBonusPerSecondRemaining,
    serverTimeMs,
    deadlineMs,
  });
  console.log(`[Orchestrator] ${eventId} pushed question ${index + 1}/${total}`);
}

function _scheduleQuestions(io, eventId, questions, onDone) {
  let index = 0;

  function next() {
    if (index >= questions.length) {
      onDone();
      return;
    }
    _pushQuestion(io, eventId, questions[index], index, questions.length);
    index += 1;
    // After question window + inter-question pause, push next.
    setTimeout(next, (QUESTION_DURATION_SECONDS + INTER_QUESTION_PAUSE_SECONDS) * 1000);
  }

  next();
}

function _transitionEvent(io, eventId, newStatus) {
  const serverTimeMs = Date.now();
  io.to(`event:${eventId}`).emit('event:status', { eventId, status: newStatus, serverTimeMs });
  if (io._logger) io._logger.info({ eventId, status: newStatus }, '[Orchestrator] status transition');
  _orchestratorState.set(eventId, newStatus);
}

function startEventOrchestrator(io, logger) {
  if (logger) io._logger = logger;
  // Runs every minute to check whether any event needs state transition.
  cron.schedule('* * * * *', () => {
    const events = buildEventSchedule();
    for (const event of events) {
      if (event.type !== 'trivia') continue; // Power Hour has no question loop.

      const state = _orchestratorState.get(event.id) || 'idle';
      const computedStatus = event.status;

      // Open lobby 5 min before start.
      if (state === 'idle' && computedStatus === 'lobby') {
        _transitionEvent(io, event.id, 'lobby_open');
      }

      // Go live at start time.
      if ((state === 'idle' || state === 'lobby_open') && computedStatus === 'live') {
        _transitionEvent(io, event.id, 'live');
        _orchestratorState.set(event.id, 'running');

        const questions = EVENT_QUESTION_BANK;
        _scheduleQuestions(io, event.id, questions, () => {
          _transitionEvent(io, event.id, 'ended');
          // Settle 60 s after ending.
          setTimeout(() => {
            _transitionEvent(io, event.id, 'settled');
            _orchestratorState.delete(event.id); // allow re-trigger tomorrow
          }, 60_000);
        });
      }
    }
  });

  if (logger) logger.info('[Orchestrator] cron scheduler started');
}

// Also expose subscribe:event / subscribe:line convenience events on the socket
function _installConvenienceSubscribes(io) {
  io.on('connection', (socket) => {
    socket.on('subscribe:event', (payload = {}) => {
      const eventId = String(payload.eventId || '');
      if (eventId) socket.join(`event:${eventId}`);
    });
    socket.on('unsubscribe:event', (payload = {}) => {
      const eventId = String(payload.eventId || '');
      if (eventId) socket.leave(`event:${eventId}`);
    });
    socket.on('subscribe:line', (payload = {}) => {
      const lineId = String(payload.lineId || '');
      if (lineId) socket.join(`line:${lineId}`);
    });
  });
}

module.exports = {
  installPhase56Middleware,
  installPhase56Routes,
  createPhase56Realtime,
  startEventOrchestrator,
  _installConvenienceSubscribes,
};
