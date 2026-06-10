'use strict';

/**
 * rides.js — server-authoritative ride session (Phase 1).
 *
 * Replaces both metrosafar_trips (legacy Trip Mode) and
 * metrosafar_commute_sessions (legacy Commute Mode) with a single
 * metrosafar_rides collection.
 *
 * Lifecycle:  start (QR validated) → heartbeats → end
 * Eligibility rule: status==active && now < expiresAt && lastHeartbeatAt < 5 min ago
 */

const crypto = require('crypto');
const { z } = require('zod');
const { validateStationToken } = require('./lib/qr-tokens');
const { haversineMeters, nearestStation } = require('./lib/geo');

const RIDE_TTL_MS          = 2 * 60 * 60 * 1000;   // 2 h hard expiry
const HEARTBEAT_STALE_MS   = 5 * 60 * 1000;         // 5 min freshness window
const PROXIMITY_RADIUS_M   = 3_000;                  // heartbeat plausibility
const END_PROXIMITY_M      = 1_500;                  // end-station proximity
const MIN_PLAUSIBLE_BEATS  = 3;                      // minimum GPS beats to earn
const MIN_RIDE_DURATION_MS = 3 * 60 * 1000;         // cadence guard

function nowIso() { return new Date().toISOString(); }

// --------------------------------------------------------------------------
// Zod schemas
// --------------------------------------------------------------------------

const startRideSchema = z.object({
  qrToken: z.string().min(1).max(300),
  cityId:  z.string().trim().max(80).optional(),
});

const heartbeatSchema = z.object({
  lat:      z.number().min(-90).max(90),
  lng:      z.number().min(-180).max(180),
  speedKmh: z.number().min(0).max(120),
  accuracy: z.number().min(0).max(500).optional(),
  mockLocation: z.boolean().optional(),
});

const endRideSchema = z.object({
  endStationId: z.string().trim().max(120).optional(),
});

// --------------------------------------------------------------------------
// Station helpers (shared with phase56.js logic)
// --------------------------------------------------------------------------

function stationsForLine(stations, line) {
  const token = (line || '').replace(/line/i, '').trim().toLowerCase();
  return stations.filter((s) => {
    return (s.line || '').toLowerCase().split('&')
      .map((p) => p.replace(/line/i, '').trim())
      .includes(token);
  });
}

function sharedLine(a, b) {
  const aLines = (a.line || '').toLowerCase().split('&').map((p) => p.replace(/line/i, '').trim());
  const bLines = (b.line || '').toLowerCase().split('&').map((p) => p.replace(/line/i, '').trim());
  return aLines.find((l) => bLines.includes(l)) || null;
}

function findStation(stations, id) {
  if (!id) return null;
  const w = String(id).trim().toLowerCase();
  return stations.find((s) => String(s.id).toLowerCase() === w || String(s.name).toLowerCase() === w) || null;
}

// --------------------------------------------------------------------------
// Freshness helper — used by server.js to gate the 1.5× multiplier
// --------------------------------------------------------------------------

function isRideFresh(ride) {
  if (!ride || ride.status !== 'active') return false;
  if (ride.expiresAt && new Date(ride.expiresAt).getTime() <= Date.now()) return false;
  if (!ride.lastHeartbeatAt) return false;
  return Date.now() - new Date(ride.lastHeartbeatAt).getTime() < HEARTBEAT_STALE_MS;
}

// --------------------------------------------------------------------------
// Lazy expiry helper — called by getActiveRide and getMutiplier
// --------------------------------------------------------------------------

async function lazyExpireRide(ref, ride) {
  if (ride.status === 'active' && ride.expiresAt &&
      new Date(ride.expiresAt).getTime() <= Date.now()) {
    await ref.set({ status: 'expired', expiredAt: nowIso() }, { merge: true });
    return true;
  }
  return false;
}

// --------------------------------------------------------------------------
// Get the caller's active (possibly fresh) ride
// --------------------------------------------------------------------------

async function getActiveRide(firestore, clientId) {
  const snap = await firestore.collection('metrosafar_rides')
    .where('userId', '==', clientId)
    .where('status', '==', 'active')
    .orderBy('startedAt', 'desc')
    .limit(1)
    .get();
  if (snap.empty) return null;
  const ref = snap.docs[0].ref;
  const ride = { id: snap.docs[0].id, ...snap.docs[0].data() };
  if (await lazyExpireRide(ref, ride)) return null;
  return ride;
}

// --------------------------------------------------------------------------
// Multiplier for games/activity — replaces maybeGetCommuteMultiplier
// --------------------------------------------------------------------------

async function getRideMultiplier(firestore, clientId) {
  try {
    const ride = await getActiveRide(firestore, clientId);
    if (!ride) return { multiplier: 1, ride: null };
    return isRideFresh(ride)
      ? { multiplier: 1.5, ride }
      : { multiplier: 1, ride: null };
  } catch {
    return { multiplier: 1, ride: null };
  }
}

// --------------------------------------------------------------------------
// Route installer
// --------------------------------------------------------------------------

function installRideRoutes(app, context) {
  const { firestore, stations, logger, claimTransaction,
          incrementWeeklyStats, qualifyReferralForUser, checkRideCadenceAnomaly } = context;

  // zod validate middleware (same pattern as server.js)
  function validate(schema) {
    return (req, res, next) => {
      const result = schema.safeParse(req.body);
      if (!result.success) {
        return res.status(400).json({ error: 'Validation failed', issues: result.error.errors });
      }
      req.body = result.data;
      next();
    };
  }

  // -------------------------------------------------------------------------
  // POST /api/rides/start
  // -------------------------------------------------------------------------
  app.post('/api/rides/start', validate(startRideSchema), async (req, res, next) => {
    try {
      const { qrToken, cityId } = req.body;
      const clientId = req.clientId;

      // 1. Validate QR HMAC
      const qrResult = validateStationToken(qrToken);
      if (!qrResult.valid) {
        return res.status(400).json({ error: 'Invalid QR code', reason: qrResult.reason });
      }

      // 2. Bind QR to this user (atomic one-use-per-user per bucket)
      const [, bucketStr] = qrToken.split(':');
      const redemptionId = crypto
        .createHash('sha256')
        .update(`${qrResult.stationId}:${bucketStr}:${clientId}`)
        .digest('hex');
      const redemptionRef = firestore.collection('metrosafar_qr_redemptions').doc(redemptionId);
      try {
        await redemptionRef.create({
          stationId: qrResult.stationId,
          bucket: bucketStr,
          userId: clientId,
          redeemedAt: nowIso(),
        });
      } catch (err) {
        // Firestore create() throws on duplicate — return the existing ride if it's still active
        const existingRide = await getActiveRide(firestore, clientId);
        if (existingRide && existingRide.startStationId === qrResult.stationId) {
          return res.json({ rideId: existingRide.id, ride: existingRide, alreadyActive: true });
        }
        return res.status(409).json({ error: 'qr_already_used', message: 'You already scanned this code. Scan the station QR again for your next ride.' });
      }

      // 3. If user already has an active ride from a DIFFERENT station, void it
      const existingRide = await getActiveRide(firestore, clientId);
      if (existingRide) {
        await firestore.collection('metrosafar_rides').doc(existingRide.id)
          .set({ status: 'voided', voidedAt: nowIso(), voidReason: 'new_ride_started' }, { merge: true });
      }

      // 4. Create the ride — all timestamps are server-side
      const rideId = crypto.randomUUID();
      const startedAt = nowIso();
      const expiresAt = new Date(Date.now() + RIDE_TTL_MS).toISOString();
      const ride = {
        id: rideId,
        userId: clientId,
        cityId: cityId || null,
        status: 'active',
        startStationId: qrResult.stationId,
        endStationId: null,
        qr: {
          stationId: qrResult.stationId,
          bucket: bucketStr,
          codeHash: crypto.createHash('sha256').update(qrToken).digest('hex'),
        },
        startedAt,
        expiresAt,
        lastHeartbeatAt: null,
        heartbeats: [],
        pointsEarned: 0,
        co2SavedKg: 0,
        stamps: [],
      };

      await firestore.collection('metrosafar_rides').doc(rideId).set(ride);

      logger.info({ clientId, rideId, stationId: qrResult.stationId }, 'ride started');
      return res.status(201).json({ rideId, ride });
    } catch (err) {
      next(err);
    }
  });

  // -------------------------------------------------------------------------
  // POST /api/rides/:rideId/heartbeat
  // -------------------------------------------------------------------------
  app.post('/api/rides/:rideId/heartbeat', validate(heartbeatSchema), async (req, res, next) => {
    try {
      const { rideId } = req.params;
      const { lat, lng, speedKmh, accuracy, mockLocation } = req.body;
      const ref = firestore.collection('metrosafar_rides').doc(rideId);
      const snap = await ref.get();

      if (!snap.exists || snap.data().userId !== req.clientId) {
        return res.status(404).json({ error: 'Ride not found' });
      }

      const ride = snap.data();
      if (ride.status !== 'active') {
        return res.json({ status: ride.status, message: 'Ride is no longer active' });
      }

      // Lazy expire
      if (await lazyExpireRide(ref, ride)) {
        return res.json({ status: 'expired', message: 'Ride expired' });
      }

      // Plausibility: must be within 3 km of some station
      const nearest = nearestStation(lat, lng, stations);
      const implausible = !nearest || nearest.distanceM > PROXIMITY_RADIUS_M;

      const beat = {
        lat,
        lng,
        speedKmh,
        accuracy: accuracy || null,
        mockLocation: mockLocation || false,
        implausible,
        serverAt: nowIso(),
      };

      const heartbeats = [...(ride.heartbeats || []), beat].slice(-30);

      const update = { heartbeats, lastHeartbeatAt: implausible ? ride.lastHeartbeatAt || null : nowIso() };
      await ref.set(update, { merge: true });

      const expiresInMs = Math.max(0, new Date(ride.expiresAt).getTime() - Date.now());
      return res.json({
        status: 'active',
        implausible,
        nearestStation: nearest?.station?.name || null,
        expiresInSeconds: Math.floor(expiresInMs / 1000),
      });
    } catch (err) {
      next(err);
    }
  });

  // -------------------------------------------------------------------------
  // POST /api/rides/:rideId/end
  // -------------------------------------------------------------------------
  app.post('/api/rides/:rideId/end', validate(endRideSchema), async (req, res, next) => {
    try {
      const { rideId } = req.params;
      const ref = firestore.collection('metrosafar_rides').doc(rideId);
      const snap = await ref.get();

      if (!snap.exists || snap.data().userId !== req.clientId) {
        return res.status(404).json({ error: 'Ride not found' });
      }

      const ride = snap.data();

      // Idempotent: already completed
      if (ride.status === 'completed') {
        return res.json({ rideId, pointsAwarded: ride.pointsEarned || 0, co2SavedKg: ride.co2SavedKg || 0, stamps: ride.stamps || [], alreadyCompleted: true });
      }

      if (ride.status !== 'active') {
        return res.status(400).json({ error: `Cannot end a ride in status: ${ride.status}` });
      }

      // Server-side expiry check (ignore client timestamps entirely)
      const tooOld = ride.expiresAt && new Date(ride.expiresAt).getTime() <= Date.now();
      if (tooOld) {
        await ref.set({ status: 'expired', expiredAt: nowIso() }, { merge: true });
        return res.status(400).json({ error: 'Ride expired — too much time has passed', reason: 'expired' });
      }

      // Require minimum plausible heartbeats spanning MIN_RIDE_DURATION_MS
      const plausibleBeats = (ride.heartbeats || []).filter((b) => !b.implausible && !b.mockLocation);
      const hasEvidence = plausibleBeats.length >= MIN_PLAUSIBLE_BEATS;
      const firstBeat = plausibleBeats[0];
      const lastBeat = plausibleBeats[plausibleBeats.length - 1];
      const rideDurationMs = firstBeat && lastBeat
        ? new Date(lastBeat.serverAt).getTime() - new Date(firstBeat.serverAt).getTime()
        : 0;
      const longEnough = rideDurationMs >= MIN_RIDE_DURATION_MS;
      const earns = hasEvidence && longEnough;

      // Resolve end station: client hint → nearest to last good heartbeat
      let endStation = findStation(stations, req.body.endStationId);
      if (lastBeat) {
        const nearestToLastBeat = nearestStation(lastBeat.lat, lastBeat.lng, stations);
        if (nearestToLastBeat) {
          const claimed = endStation
            ? haversineMeters(lastBeat.lat, lastBeat.lng, endStation.latitude, endStation.longitude)
            : Infinity;
          // If client claim is > END_PROXIMITY_M from actual last beat, override
          if (claimed > END_PROXIMITY_M) {
            endStation = nearestToLastBeat.station;
          }
        }
      }
      if (!endStation) {
        endStation = findStation(stations, ride.startStationId);
      }

      // Compute hops along the line
      const startStation = findStation(stations, ride.startStationId);
      let hops = 1;
      if (startStation && endStation) {
        const line = sharedLine(startStation, endStation) || startStation.line;
        const lineStations = stationsForLine(stations, line);
        const si = lineStations.findIndex((s) => s.id === startStation.id);
        const ei = lineStations.findIndex((s) => s.id === endStation.id);
        if (si >= 0 && ei >= 0) hops = Math.max(1, Math.abs(ei - si));
      }

      const pointsAwarded = earns ? Math.min(80, 10 + hops * 4) : 0;
      const co2SavedKg    = Number((hops * 0.18).toFixed(2));
      const stamps        = endStation ? [endStation.id] : [];
      const completedAt   = nowIso(); // server time only

      await ref.set({
        status: 'completed',
        endStationId: endStation?.id || null,
        pointsEarned: pointsAwarded,
        co2SavedKg,
        stamps,
        completedAt,
      }, { merge: true });

      // Award via claimTransaction so it participates in the daily cap
      if (pointsAwarded > 0) {
        await claimTransaction(req.clientId, async (_txn, state) => {
          const today = new Date().toDateString();
          const isNewDay = !state.lastDailyEarnDate || new Date(state.lastDailyEarnDate).toDateString() !== today;
          const currentDailyEarned = isNewDay ? 0 : (state.dailyPointsEarned || 0);
          const capped = Math.min(pointsAwarded, Math.max(0, 500 - currentDailyEarned));
          const now = nowIso();
          const next = {
            ...state,
            points: state.points + capped,
            dailyPointsEarned: currentDailyEarned + capped,
            lastDailyEarnDate: now,
            lastRideCompletedAt: now, // used by streak to verify transit requirement
            ridesCompleted: (state.ridesCompleted || 0) + 1,
            tripSummary: {
              totalTrips: (state.tripSummary?.totalTrips || 0) + 1,
              totalKm: Number(((state.tripSummary?.totalKm || 0) + hops * 1.15).toFixed(2)),
              totalCo2Kg: Number(((state.tripSummary?.totalCo2Kg || 0) + co2SavedKg).toFixed(2)),
              mostVisitedStation: endStation?.name || state.tripSummary?.mostVisitedStation || null,
              lastUpdated: now,
            },
          };
          return { next, response: { pointsAwarded: capped } };
        });
      } else {
        // Still count the ride even with 0 points (no GPS evidence)
        const user = await context.getUserState(req.clientId);
        const now = nowIso();
        await context.saveUserState(req.clientId, {
          ...user,
          lastRideCompletedAt: now,
          ridesCompleted: (user.ridesCompleted || 0) + 1,
          tripSummary: {
            totalTrips: (user.tripSummary?.totalTrips || 0) + 1,
            totalKm: Number(((user.tripSummary?.totalKm || 0) + hops * 1.15).toFixed(2)),
            totalCo2Kg: Number(((user.tripSummary?.totalCo2Kg || 0) + co2SavedKg).toFixed(2)),
            mostVisitedStation: endStation?.name || user.tripSummary?.mostVisitedStation || null,
            lastUpdated: now,
          },
        });
      }

      // Write to activity_events so cadence detector actually works
      await firestore.collection('metrosafar_users').doc(req.clientId)
        .collection('activity_events')
        .add({ type: 'ride_completed', rideId, createdAt: nowIso() });

      // Post-completion hooks (fire-and-forget, don't fail the response)
      Promise.all([
        incrementWeeklyStats(req.clientId, { tripsCompleted: 1, pointsEarned: pointsAwarded, co2Kg: co2SavedKg }),
        qualifyReferralForUser(req.clientId, 'first_trip'),
        checkRideCadenceAnomaly(req.clientId),
      ]).catch((err) => logger.warn({ err, clientId: req.clientId }, 'ride end hooks failed'));

      logger.info({ clientId: req.clientId, rideId, pointsAwarded, earns }, 'ride completed');
      return res.json({
        rideId,
        pointsAwarded,
        co2SavedKg,
        stamps,
        endStationName: endStation?.name || null,
        reason: earns ? null : (hasEvidence ? 'insufficient_duration' : 'insufficient_evidence'),
        completedAt,
      });
    } catch (err) {
      next(err);
    }
  });

  // -------------------------------------------------------------------------
  // GET /api/rides/active
  // -------------------------------------------------------------------------
  app.get('/api/rides/active', async (req, res, next) => {
    try {
      const ride = await getActiveRide(firestore, req.clientId);
      return res.json({ ride: ride || null });
    } catch (err) {
      next(err);
    }
  });
}

module.exports = { installRideRoutes, getActiveRide, getRideMultiplier, isRideFresh };
