# Trust & Anti-Fraud Fix Plan — Implementation Guide

**Audience:** junior engineer. Every task lists the files to touch, the current behavior
(with line references), the exact change, how to verify it, and acceptance criteria.
Do the tasks in order — later tasks build on earlier ones.

**Scope:** fixes all findings from the June 2026 design-flaw audit
(verified against the codebase on 2026-06-10 — all findings except rewarded ads are still open).

---

## Ground rules

1. **One PR per task.** Keep each PR under ~400 lines of diff. Name branches
   `fix/<task-id>-short-name`, e.g. `fix/0.1-remove-ride-faucet`.
2. **Never trust client input for time, location, or points.** When in doubt, the
   server decides. This is the theme of the whole plan.
3. **Backend runs locally** with `node backend/server.js`. Required env vars for dev:
   `GOOGLE_APPLICATION_CREDENTIALS` (Firestore service account), `QR_HMAC_SECRET`
   (any `openssl rand -hex 32` value), optionally `ADMIN_API_KEY=devkey`.
4. **Testing endpoints with curl:** the auth middleware (`server.js:1170`) accepts
   `Authorization: Bearer $ADMIN_API_KEY` and sets `req.clientId = 'api-key'`, which
   behaves like a normal user account. Example:
   ```bash
   curl -s -X POST localhost:8080/api/games/sudoku/complete \
     -H "Authorization: Bearer devkey" -H "Content-Type: application/json" \
     -d '{"score": 500}' | jq
   ```
5. **Flutter checks:** run `flutter analyze` and `flutter test` before every PR.
6. **Do not delete the old trip endpoints until Phase 1.6.** Released app versions
   still call them; we deprecate behind a version check first.

---

## Task 0.0 — Add a minimal backend test harness (½ day)

There is currently **no test runner** in `backend/package.json`. Node 20's built-in
runner needs zero dependencies.

1. Create `backend/test/` and add to `package.json` scripts:
   ```json
   "test": "node --test test/"
   ```
2. First test file `backend/test/qr-tokens.test.js` covering
   `generateStationToken` / `validateStationToken` (pure functions, no Firestore):
   valid token round-trip, expired bucket rejected, tampered signature rejected,
   malformed string rejected.
3. As you complete each task below, add tests for any **pure** function you create
   (validators, point calculators, distance helpers). Don't attempt Firestore
   emulator tests yet — out of scope.

**Acceptance:** `npm test` passes in `backend/`.

---

# PHASE 0 — Quick wins (close the open faucets)

Estimated total: 3–4 days. No schema migrations, no breaking app changes except 0.1.

## Task 0.1 — Remove the `ride_completed` / `ride_started` point faucet (1 day)

**Findings fixed:** #6 (direct faucet), #7 (double award), half of the dead cadence detector.

**Current behavior:**
- `POST /api/activity-events` (`server.js:2041`) accepts `ride_started` (30 pts) and
  `ride_completed` (20 pts) from any authenticated caller, any time, no trip needed
  (`ACTIVITY_POINT_RULES`, `server.js:1991`).
- The Flutter app calls it *in addition to* `endTrip`, which already pays distance
  points (`phase56.js:414`) — every real trip pays twice
  (`lib/features/trip/application/trip_state_provider.dart:159`).
- The cadence detector (`server.js:991`) reads `metrosafar_users/{uid}/activity_events`,
  which **nothing ever writes** — it can never fire.

**Backend changes (`backend/server.js`, `backend/phase56.js`):**
1. Delete `ride_started` and `ride_completed` from `ACTIVITY_POINT_RULES`
   (server.js:1997–1998). The endpoint's existing "Unknown activity type" guard
   (server.js:2044) will now reject them with a 400 — that's the desired behavior
   for old app versions; they treat it as a failed bonus, the trip itself still works.
2. Move what those events did into `endTrip` (`phase56.js:343`), after the existing
   point award:
   - increment `ridesCompleted` on the user state (currently done in
     activity-events, server.js:2076),
   - call `incrementWeeklyStats(clientId, { tripsCompleted: 1, pointsEarned })`,
   - call `qualifyReferralForUser(clientId, 'first_trip')`,
   - call `checkRideCadenceAnomaly(clientId)`.
   `incrementWeeklyStats`, `qualifyReferralForUser`, and `checkRideCadenceAnomaly`
   live in server.js — export them through `phase56Context` (server.js:1209) the same
   way `getUserState`/`saveUserState` already are.
3. Make the cadence detector functional: in `endTrip`, write one doc per completion to
   `metrosafar_users/{uid}/activity_events`:
   ```js
   await context.firestore.collection('metrosafar_users').doc(clientId)
     .collection('activity_events')
     .add({ type: 'ride_completed', tripId, createdAt: nowIso() });
   ```
   Then **block** (not just flag): before awarding, run the same count query the
   detector uses; if a completion exists in the last 3 minutes, set
   `pointsAwarded = 0` and include `reason: 'cadence_limit'` in the response
   (still mark the trip completed — don't strand the user).

**Flutter changes:**
4. `trip_state_provider.dart:159` — delete the `logActivityEvent(type: 'ride_completed')`
   call and the surrounding points math; show the points from the `endTrip` response
   (`data['pointsAwarded']`) instead.
5. `trip_state_provider.dart:138` — delete `logActivityEvent(type: 'ride_started')`.
   Keep the `completeQuest('ride_started')` call — quests are a separate, capped system.

**Verify:**
```bash
# Must now return 400:
curl -s -X POST localhost:8080/api/activity-events \
  -H "Authorization: Bearer devkey" -H "Content-Type: application/json" \
  -d '{"type":"ride_completed"}' | jq
# Full trip flow still pays once: start → heartbeat → end, check pointsAwarded > 0
# Second end within 3 min of another completed trip → pointsAwarded: 0, reason cadence_limit
```
**Acceptance:** activity-events rejects ride types; a trip pays exactly once;
`metrosafar_flagged_trips` gets a doc when you complete two trips inside 3 minutes;
weekly stats and referral qualification still fire on trip end.

## Task 0.2 — Expire commute sessions on the server (½ day)

**Finding fixed:** #1 (permanent 1.5x multiplier).

**Current behavior:** `getActiveCommuteSession` (`server.js:769`) returns any session
with `status == 'active'`, forever. Nothing writes an expiry.

**Changes (`backend/server.js`):**
1. Add a constant near the function: `const COMMUTE_SESSION_TTL_MS = 2 * 60 * 60 * 1000;`
2. In `getActiveCommuteSession`, after fetching the doc, check staleness using the
   session's `updatedAt` (server-written on every signal, server.js:2728):
   ```js
   const updatedAt = new Date(doc.updatedAt || doc.startedAt || 0).getTime();
   if (Date.now() - updatedAt > COMMUTE_SESSION_TTL_MS) {
     await snap.docs[0].ref.set(
       { status: 'expired', expiredAt: new Date().toISOString() }, { merge: true });
     return null;
   }
   ```
   This is "lazy expiry" — no cron job needed; the session dies the next time anything
   asks about it.
3. In the create endpoint (server.js:2672), write an explicit
   `expiresAt: new Date(Date.now() + COMMUTE_SESSION_TTL_MS).toISOString()` into the
   payload so clients can display a countdown.

**Verify:** create a session, manually edit its `updatedAt` in the Firestore console to
3 hours ago, call `GET /api/trip/commute-session/active` → `session: null`, and the doc
status flips to `expired`. Games played after that get `commuteMultiplier: 1`.

**Acceptance:** no session older than 2h is ever returned as active or used for the
multiplier; doc is marked `expired` on first stale read.

## Task 0.3 — Games: gate on a real ride, cap, and decouple points from client score (1 day)

**Finding fixed:** #3 (unlimited repeatable game rewards) plus the newly found
daily-cap bypass.

**Current behavior (`server.js:1667–1741`):**
- Every completion (except daily spin) pays `clamp(score/2, 15, 50) × multiplier`,
  where `score` is whatever the client sends.
- Repeatable without limit (rate limiter only: 60/min).
- The award does **not** go through the 500/day cap — `claimTransaction` here adds
  points directly without touching `dailyPointsEarned` (compare with
  `/api/activity-events`, server.js:2047, which does it correctly).

**Changes (`backend/server.js`):**
1. **Decouple from score.** Replace the score-based formula with a fixed schedule:
   ```js
   const GAME_BASE_POINTS = { daily_spin: 20, trivia: 25, sudoku: 20, word_puzzle: 20, city_explorer: 20 };
   ```
   Keep recording the client `score` in `gameScores` for leaderboards — it just no
   longer buys points.
2. **Per-game daily completion cap.** Inside the `claimTransaction` callback, track
   rewarded plays per IST day on the user state (the streak code at server.js:1752
   shows the IST-day helpers `istDayString`):
   ```js
   const todayIst = istDayString(new Date());
   const plays = state.gameDailyPlays?.day === todayIst ? state.gameDailyPlays : { day: todayIst, counts: {} };
   const playedToday = plays.counts[gameId] || 0;
   const REWARDED_PLAYS_PER_DAY = 3;
   const earnsPoints = playedToday < REWARDED_PLAYS_PER_DAY;
   ```
   Always allow *playing* (return `pointsEarned: 0, reason: 'daily_game_cap'` past the
   cap) — never block fun, only points.
3. **Route through the 500/day cap.** Copy the `dailyPointsEarned` /
   `lastDailyEarnDate` logic from `/api/activity-events` (server.js:2048–2062) into
   the games transaction so games count against the same 500.
4. **Gate full rewards on transit.** Per the economy rule ("points only in transit"),
   when `commute.session` is null, multiply the base by 0 — i.e. games outside a ride
   pay nothing but still record scores and quest progress. If product wants a softer
   landing, pay a flat 5 points outside transit — make this a named constant either way.
5. Return the new fields in the response (`reason`, `playsRemainingToday`) so the
   Flutter games screens can explain why points were 0. Update
   `lib/features/play/` UIs to show those messages (search for usages of
   `completeGame` in `backend_service.dart`).

**Verify:**
```bash
# 4 plays in a row: first 3 pay (if a fresh session exists), 4th returns daily_game_cap
for i in 1 2 3 4; do curl -s -X POST localhost:8080/api/games/sudoku/complete \
  -H "Authorization: Bearer devkey" -H "Content-Type: application/json" \
  -d '{"score": 99999}' | jq '{pointsEarned, reason}'; done
# score 99999 vs score 1 must pay identically
```
**Acceptance:** game points are independent of submitted score; max 3 rewarded plays
per game per day; games points consume the 500/day budget; zero (or flat-5) points
without an active commute session.

## Task 0.4 — Fail closed on missing QR secret (1 hour)

**Finding fixed:** new finding — `qr-tokens.js:31` returns the fixed signature
`devmode00000000` when `QR_HMAC_SECRET` is unset, so anyone can forge station tokens
if the env var is ever dropped from a deploy.

**Change (`backend/lib/qr-tokens.js`):**
```js
if (!SECRET && process.env.NODE_ENV === 'production') {
  throw new Error('QR_HMAC_SECRET is required in production');
}
```
Module is loaded at server start, so a misconfigured deploy now crashes loudly instead
of silently accepting forged QRs. Keep the dev placeholder for local/test.
Add a test in `qr-tokens.test.js` (set/unset env, use `t.mock` or a child module load).

**Acceptance:** server refuses to boot in production without the secret; dev unchanged.

## Task 0.5 — Stop queuing 4xx as offline work; cap the outbox (½ day)

**Finding fixed:** #10.

**Current behavior:**
- `_sendJson` (`lib/services/backend_service.dart:815`) catches **every** error except
  401/429 and, when `queueOffline: true`, enqueues it as a pending mutation — including
  server-side 400 rejections ("invalid QR", "expired session"), which then show as
  "Saved offline" and retry forever.
- `Outbox` (`lib/services/sync/outbox.dart`) has **no retry cap and no age cap**;
  `flushOutbox` (`backend_service.dart:694`) re-queues all failures indefinitely.

**Changes:**
1. In `_sendJson`, introduce a typed error for HTTP failures:
   ```dart
   class BackendHttpException implements Exception {
     final int statusCode; final String body;
     const BackendHttpException(this.statusCode, this.body);
   }
   ```
   Throw it where the code currently throws the generic
   `Exception(response.body…)` (line 800). In the catch block, queue **only** genuine
   connectivity failures:
   ```dart
   final isNetworkError = error is SocketException ||
       error is TimeoutException || error is http.ClientException;
   if (queueOffline && isNetworkError) { …enqueue… }
   rethrow; // 4xx/5xx surface to the caller and the UI
   ```
   (Import `dart:io` / `dart:async` as needed.)
2. In `flushOutbox`, drop mutations permanently when the server answers with a 4xx
   (it has spoken — retrying won't change the answer), and re-queue only on network
   errors / 5xx with `retryCount + 1`.
3. Add caps when re-queuing: drop if `retryCount >= 5` or
   `DateTime.now().difference(mutation.createdAt) > const Duration(hours: 24)`.
4. Update callers that relied on the `{'queued': true}` sentinel for 4xx — e.g.
   `commute_provider.dart` (handled properly in Task 0.6) and
   `trip_state_provider.dart` `endTrip` — to catch `BackendHttpException` and show the
   server's error message instead of "Saved offline."

**Verify:** with the backend running, submit a commute session with a junk QR code →
the UI shows "Invalid QR code", `outboxCount()` stays 0. Kill the backend, end a trip →
it queues; restart backend, flush → it syncs. Add unit tests for the
queue/drop decision if a `_sendJson` seam allows it (or extract the decision into a
pure function `shouldQueueOffline(error)` and test that).

**Acceptance:** 4xx never enters the outbox; outbox entries die after 5 retries or 24h;
real network failures still queue and sync.

## Task 0.6 — Roll back UI state when activation fails (½ day)

**Finding fixed:** #9.

**Current behavior (`lib/core/commute/commute_provider.dart:59–112`):** `startManual` /
`acceptDetected` set `CommutePhase.active` *before* calling the backend; on failure
`_openBackendSession` only stores an error string — the UI stays "active" with no
session and no rewards. With Task 0.5 done, 4xx now throws instead of returning
`{'queued': true}`, so this is the moment to fix the state machine.

**Changes:**
1. Reorder: call the backend first, flip to `active` only on success:
   ```dart
   Future<void> startManual({...}) async {
     state = state.copyWith(phase: CommutePhase.verifying); // new enum value
     final ok = await _openBackendSession(...);             // returns bool now
     state = ok
         ? state.copyWith(phase: CommutePhase.active, confidenceScore: 1, startedAt: DateTime.now())
         : state.copyWith(phase: CommutePhase.detecting,
             error: state.error ?? 'Could not verify your ride. Please rescan the station QR.');
   }
   ```
2. `_openBackendSession` returns `false` when the call throws **or** when the response
   has no `session.id` / `confirmed != true` (the backend returns `confirmed`
   explicitly, server.js:2741).
3. Add `verifying` to `CommutePhase` (in `commute_session.dart`) and render it as a
   spinner state wherever the phase is switched on (grep for `CommutePhase.` in
   `lib/features/`).

**Verify:** in the app (or widget test), activate with an invalid code → UI returns to
detecting with the error banner; activate with a valid code → active with sessionId set.

**Acceptance:** the UI can never show "active" without a confirmed backend session ID.

## Task 0.7 — Make idempotency atomic and endpoint-bound (½ day)

**Finding fixed:** "Idempotency is non-atomic and not endpoint-bound."

**Current behavior (`backend/phase56.js:741–790`):** plain `get()` then conditional
replay — two concurrent duplicates both pass the `get` and both execute. The doc ID
hashes only `clientId:key`, so a key from one endpoint replays another endpoint's
cached response.

**Changes (`backend/phase56.js`):**
1. Bind to the endpoint: `const docId = hashId(\`${req.clientId}:${req.method}:${req.path}:${key}\`);`
2. Reserve atomically with `create()` (fails if the doc exists — that's the lock):
   ```js
   try {
     await ref.create({ status: 'in_flight', clientId: req.clientId, method: req.method,
       path: req.path, createdAt: nowIso(),
       expiresAt: new Date(Date.now() + 24 * 3600 * 1000).toISOString() });
   } catch (err) {
     const snap = await ref.get();
     const cached = snap.exists ? snap.data() : null;
     if (cached?.status === 'completed') {
       res.set('X-Idempotent-Replay', 'true');
       return res.status(cached.statusCode || 200).json(cached.body || {});
     }
     return res.status(409).json({ error: 'Request already in progress', retryable: true });
   }
   ```
3. The existing `res.json` wrapper then updates the doc to
   `{ status: 'completed', statusCode, body }` (keep the `< 500` condition; on a 5xx,
   *delete* the reservation so the client can retry).
4. The Flutter `_sendJson` already sends a fresh `Idempotency-Key` per logical request
   and reuses it on outbox retries (`backend_service.dart:779`, `outbox` stores
   headers) — no client change needed. Treat a 409 in `flushOutbox` like success
   (the original is processing).

**Verify:** fire two concurrent identical requests
(`curl ... & curl ... ; wait`) with the same `Idempotency-Key` header → one 200, one
409 or replayed response; never two executions (check points only moved once).

**Acceptance:** duplicate concurrent requests execute at most once; a key replays only
against the same method+path.

---

# PHASE 1 — One server-authoritative ride session (~1.5–2 weeks)

The structural fix. After this phase there is **one** ride concept
(`metrosafar_rides`), QR-activated, short-lived, mapped 1:1 to what the user sees.
Findings fixed: #1, #2, #4, #5, #8 (and #9 structurally).

## Task 1.1 — Schema + design doc (½ day, written before any code)

Create `docs/RIDE_SESSION_DESIGN.md` containing the doc shapes below, get it reviewed
before coding.

`metrosafar_rides/{rideId}`:
```
userId            string   (indexed with status)
cityId            string
status            'active' | 'completed' | 'expired' | 'voided'
startStationId    string   (from the validated QR — never client-claimed)
endStationId      string|null  (server-validated at end)
qr                { stationId, bucket, codeHash }
startedAt         server ISO timestamp (NEVER client-supplied)
expiresAt         startedAt + 2h
lastHeartbeatAt   server ISO timestamp
heartbeats        last 30 of { lat, lng, speedKmh, accuracy, serverAt }
pointsEarned, co2SavedKg, stamps   (written once, at end)
```

`metrosafar_qr_redemptions/{stationId_bucket_userId}` — existence = this user already
started a ride from this station QR in this rotation bucket. Doc ID is the natural key,
so `create()` gives atomic "first redemption wins."

**Eligibility rule (used everywhere):** a ride is *fresh* iff
`status == 'active' && now < expiresAt && now - lastHeartbeatAt < 5 min`.
Games multiplier, crowd reports, and end-of-ride awards all use this one helper.

## Task 1.2 — Backend: ride lifecycle endpoints (3 days)

New file `backend/rides.js` (mirroring how `phase56.js` is mounted via
`installPhase56Routes`, server.js:2787). Routes:

1. **`POST /api/rides/start`** — body `{ qrToken, cityId? }`, zod-validated.
   - `validateStationToken(qrToken)` (reuse `lib/qr-tokens.js`); 400 on invalid.
   - **Bind the QR to the user:** `create()` the `metrosafar_qr_redemptions` doc;
     if it already exists → 409 `qr_already_used` ("You already started a ride with
     this code — scan again at the station for your next ride"). This makes a
     screenshot worthless to its owner after one use, and lets you alert on codes
     redeemed by many distinct users (Task 2.7 dashboard query).
   - Reject if the user already has a fresh active ride (return it instead — idempotent).
   - Write the ride doc with **server** `startedAt`/`expiresAt`. Ignore any client
     timestamp fields entirely.
   - Tighten the rotation grace: in `qr-tokens.js`, accept the previous bucket only
     within 10 minutes of the boundary
     (`Date.now() % bucketMs < 10 * 60 * 1000`), not for the whole previous period.
2. **`POST /api/rides/:rideId/heartbeat`** — strict zod schema, **all required**:
   ```js
   z.object({ lat: z.number().min(-90).max(90), lng: z.number().min(-180).max(180),
              speedKmh: z.number().min(0).max(120), accuracy: z.number().min(0).max(500).optional() })
   ```
   - 404 if not the caller's ride; if expired (`now > expiresAt`), mark `expired`, return that status.
   - **Plausibility check:** compute distance to the nearest station in
     `backend/stations.json` (haversine — write `lib/geo.js` with
     `haversineMeters(lat1, lng1, lat2, lng2)` + unit tests; stations carry
     `latitude`/`longitude`). If > 3 km from every station on the network, store the
     heartbeat with `implausible: true` and don't update `lastHeartbeatAt`
     (the ride goes stale on fake coordinates but we keep the evidence).
   - Store `serverAt: nowIso()` on each heartbeat; ignore client timestamps.
3. **`POST /api/rides/:rideId/end`** — body `{ endStationId }`.
   - Server time only for the expiry check (the `body.detectedAt`/`body.endedAt`
     loopholes from `phase56.js:263`/`403` must not exist here).
   - Require ≥ 3 heartbeats with `implausible != true` spanning ≥ 3 minutes;
     otherwise complete with `pointsAwarded: 0, reason: 'insufficient_evidence'`.
   - **Proximity:** last good heartbeat must be within 1 km of the claimed
     `endStationId`'s coordinates; otherwise fall back to the nearest station to the
     last heartbeat as the effective end station (award honestly, don't punish a
     mis-tap).
   - Compute hops along the line (reuse `stationsForLine`/`sharedLine` logic from
     phase56.js:385–392), award `min(80, 10 + hops*4)` inside a `claimTransaction`,
     write the ledger event + weekly stats + referral + cadence check (all already
     wired by Task 0.1), and write `status: 'completed'` idempotently (an already
     completed ride returns its stored result — copy the guard at phase56.js:359).
4. **`GET /api/rides/active`** — returns the fresh active ride or null (apply the
   freshness rule, lazily expiring like Task 0.2).
5. Replace `maybeGetCommuteMultiplier` (server.js:780) internals to look up a fresh
   `metrosafar_rides` doc; keep its return shape `{ multiplier, session }` so the
   games/activity endpoints don't change.
6. Add a `firestore.indexes.json` entry for `metrosafar_rides (userId, status, updatedAt)`.

**Verify (curl):** full lifecycle; heartbeat with lat/lng omitted → 400; end with < 3
heartbeats → 0 points; end station 20 km from last heartbeat → falls back to nearest
station; second `start` with the same QR token → 409; ride untouched for 2h → expired.

## Task 1.3 — Flutter: one `RideSessionProvider` (3–4 days)

Replaces both `tripModeProvider` (`trip_state_provider.dart`) and `commuteProvider`
(`commute_provider.dart`). Finding #8 dies here: there is exactly one notion of
"on a ride," and it's whatever `GET /api/rides/active` says.

1. New `lib/core/ride/ride_session_provider.dart` with phases
   `idle → detecting → verifying → active → ending → summary`. Port the
   confirm-before-active pattern from Task 0.6.
2. `BackendService`: add `startRide({qrToken})`, `rideHeartbeat(rideId, {lat, lng, speedKmh, accuracy})`,
   `endRide(rideId, {endStationId})`, `getActiveRide()`. The heartbeat **must** send
   real GPS — use `Geolocator.getCurrentPosition` like `commute_detector.dart:65`
   already does; if location is unavailable, skip the beat (do not send zeros).
   `startRide`/`endRide` are **not** `queueOffline` (they're 4xx-prone, and Task 0.5
   already stopped queuing those); heartbeats are fire-and-forget.
3. Heartbeat timer: every 60 s while active (the existing 30 s timer at
   `trip_state_provider.dart:205` is fine too; 60 s halves battery/network cost and
   still satisfies the 5-minute freshness rule with margin).
4. UI: Trip Mode screen (`lib/features/trip/presentation/trip_mode_screen.dart`) and
   the commute card both read `rideSessionProvider`. The QR scan flow that currently
   feeds `RideVerification` into `submitCommuteSignal` now feeds `startRide`.
   The start/end station pickers go away as inputs to *earning* — end station is
   still selectable, but the server validates it against GPS.
5. Keep the auto-detector (`commute_detector.dart`) for the *nudge* only
   ("Looks like you're on the metro — scan the station QR to start earning"); it no
   longer opens backend sessions by itself (delete the `submitCommuteSignal` call at
   `commute_provider.dart:41`).
6. Games screens already show `commuteMultiplier` from responses — point their
   "Ride Mode required/active" indicators at `rideSessionProvider`.

**Verify:** manual run-through on a device/emulator: scan QR (use
`node -e "console.log(require('./backend/lib/qr-tokens').generateStationToken('1'))"`
to print a token for a test QR), ride activates, games show 1.5x, end ride shows
summary with server-computed points. Kill the app mid-ride, reopen → ride restored
from `GET /api/rides/active`.

## Task 1.4 — Deprecate the legacy trip/commute endpoints (1 day)

1. Mark `POST /api/trips/*` and `POST /api/trip/commute-session*` deprecated: add a
   response header `Deprecation: true` and a `logger.warn` counter so you can watch
   usage drop in logs.
2. **Neutralize their exploits now** (old app versions still call them):
   - `startTrip` (`phase56.js:263`): `createdAt: nowIso()` — drop `body.detectedAt`.
   - `endTrip` (`phase56.js:403`): `completedAt: nowIso()` — drop `body.endedAt`.
   - Heartbeat (`phase56.js:323`): if lat/lng are absent/zero, store the beat but tag
     `implausible: true`; `endTrip`'s `hasHeartbeats` check (phase56.js:379) counts only
     plausible beats. Old clients (which send no GPS) earn 0 points — acceptable
     during the deprecation window; the new app version is the fix.
   - Commute session create: already TTL'd by Task 0.2.
3. After the new app version reaches ~95% adoption (check Play console), remove the
   routes and delete `metrosafar_trips` / `metrosafar_commute_sessions` write paths.
   This step gets its own PR, weeks later — leave a `TODO(remove-after: vX.Y)` marker.

---

# PHASE 2 — Economy & trust cleanup (3–4 days)

## Task 2.1 — Streak claims require a ride that day (½ day)

`POST /api/streak/claim` (`server.js:1747`) pays `5 × streakDay` with no transit
requirement. Inside its `claimTransaction`, check the user had a completed ride today:
the user state now has a reliable signal — compare `istDayString` of the most recent
`activity_events` `ride_completed` doc (one indexed query), or simpler, stamp
`lastRideCompletedAt` onto user state in `endRide` (Task 1.2.3) and compare days.
If no ride today: still advance the streak (keep the habit loop) but `pointsEarned: 0`
with `reason: 'no_ride_today'`. Update the streak UI copy accordingly.

## Task 2.2 — Crowd reports: require a fresh ride + earned reliability (½ day)

`POST /api/intel/crowd-report` (`phase56.js:858`) accepts reports from anyone and
hardcodes `userReliabilityScore: 1`.
1. Require a fresh active ride (the Task 1.1 helper); 403 otherwise.
2. Reliability: count the user's completed rides (`ridesCompleted` from user state):
   `min(1, 0.3 + ridesCompleted * 0.05)`. Store it; the aggregation endpoint
   (phase56.js:902) weights by it instead of a plain average.
3. Rate-limit: one report per user per train per 5 minutes (a
   `metrosafar_crowd_reports` query on `clientId + trainId + createdAt`, or an
   in-memory/redis key like the rate limiters at server.js:381).

## Task 2.3 — Real games leaderboard (½ day)

`GET /api/games/leaderboard` (`server.js:1806`) returns five fabricated players and
`yourRank: Math.floor(Math.random() * 10) + 1`. Replace with real data — the pattern
already exists in `getTriviaRank` (server.js:790): top-N from
`metrosafar_weekly_leaderboards/{weekId}/users` ordered by `pointsEarned`, plus a
`count()` aggregation for the caller's rank. If the weekly collection is too sparse at
current user counts, show fewer rows honestly rather than padding with fakes.

## Task 2.4 — Quest reset: transactional, field-level (½ day)

Two racy full-state saves clobber concurrent point awards:
`/api/home` fire-and-forget (`server.js:1263`) and `/api/quests/today`
(`server.js:2027`). Replace both with a `claimTransaction` that re-checks
`needsReset` *inside* the transaction and writes **only**
`{ completedQuests: [], lastQuestResetAt }` (the `txn.set(..., { merge: true })` in
`claimTransaction` already merges, so passing a `next` containing just the full state
copy is the bug — build `next` from the freshly-read `state`, which `claimTransaction`
hands you, not from the pre-transaction read).

## Task 2.5 — UID-scoped caches, cleared on sign-out (½ day)

Finding #11. Cache keys in `backend_service.dart` (`cache_commute_session`,
`cache_friends`, …) are shared across accounts and survive sign-out.
1. In `_getMap`/`_sendJson`, prefix every cache key:
   `final scopedKey = '${FirebaseAuth.instance.currentUser?.uid ?? "anon"}_$cacheKey';`
   (BackendService already imports FirebaseAuth for tokens — check `_headers`).
2. In `AuthService.signOut` (`auth_service.dart:34`), before `_auth.signOut()`:
   remove all `SharedPreferences` keys starting with the current UID prefix **and**
   clear the outbox (`Outbox().replaceAll([])`) — queued mutations carry the old
   user's auth headers and must not replay under a new account.
3. Grep for other direct `SharedPreferences` reads of these keys
   (`grep -rn "cache_" lib/`) and scope them the same way.

## Task 2.6 — Retire the legacy watch-ad endpoint (¼ day)

SSV (`server.js:2218`) is the real award path. Put
`POST /api/rewards/watch-ad` (`server.js:2277`) behind
`if (process.env.LEGACY_WATCH_AD !== 'on') return res.status(410).json(...)`,
default off, after confirming SSV callbacks are arriving in production logs.
Remove the fallback call from the Flutter side if any remains
(grep `watch-ad` in `lib/`).

## Task 2.7 — Abuse dashboards (½ day, optional but cheap)

Two saved queries / tiny admin endpoints for the ops console (`backend/server.js`
admin section, after `requireAdmin`):
- QR codes redeemed by > 10 distinct users in one bucket (`metrosafar_qr_redemptions`
  group by `stationId_bucket`).
- Users hitting the 500/day cap > 3 days in a row.
These make every remaining soft limit observable instead of silent.

---

# PHASE 3 — Device attestation (App Check) (3–4 days, parallel track)

The fixes above stop the *easy* fraud (curl + screenshots). App Check raises scripted
abuse cost from "any HTTP client" to "rooted physical device." Roll out in
**log-only mode first** — enforcing immediately will lock out users on old app builds.

## Task 3.1 — Flutter integration (1 day)

1. Add `firebase_app_check` to `pubspec.yaml`. In `main.dart` after `Firebase.initializeApp`:
   ```dart
   await FirebaseAppCheck.instance.activate(
     androidProvider: kDebugMode ? AndroidProvider.debug : AndroidProvider.playIntegrity,
     appleProvider: kDebugMode ? AppleProvider.debug : AppleProvider.appAttest,
   );
   ```
2. In `BackendService._headers`, attach the token:
   ```dart
   final appCheckToken = await FirebaseAppCheck.instance.getToken();
   if (appCheckToken != null) headers['X-Firebase-AppCheck'] = appCheckToken;
   ```
   Never *block* the request client-side on a missing token — the server decides.
3. Register the debug tokens (printed in the run console) in Firebase console →
   App Check, so dev builds keep working. Enable Play Integrity / App Attest for the
   Android/iOS apps in the same console page.

## Task 3.2 — Backend verification middleware (1 day)

In `server.js`, after the auth middleware (line 1190):
```js
const APP_CHECK_MODE = process.env.APP_CHECK_MODE || 'off'; // off | log | enforce
app.use('/api', async (req, res, next) => {
  if (APP_CHECK_MODE === 'off' || isPublicApiRoute(req)) return next();
  const token = req.header('X-Firebase-AppCheck');
  try {
    if (!token) throw new Error('missing');
    await admin.appCheck().verifyToken(token);
    req.appCheckVerified = true;
  } catch (err) {
    req.appCheckVerified = false;
    logger.warn({ clientId: req.clientId, path: req.path, reason: err.message }, 'app-check failed');
    if (APP_CHECK_MODE === 'enforce') {
      return res.status(401).json({ error: 'App integrity check failed' });
    }
  }
  next();
});
```
Rollout: deploy with `APP_CHECK_MODE=log` → watch the failure rate for ~2 weeks as the
new app version rolls out → flip to `enforce` when failures are < 1% and clearly
bot-shaped. Keep `off` as the local-dev default (curl testing in this plan keeps working).

## Task 3.3 — Mock-location signal as advisory (½ day)

`commute_detector.dart:98` fail-open detection stays, but instead of gating locally,
send it: add `mockLocation: bool` to the ride heartbeat payload (Task 1.3.2) and store
it on the heartbeat server-side. Rides where most beats have `mockLocation: true` get
`pointsAwarded: 0, reason: 'integrity'` at end — combined with App Check this closes
the "API caller skips detection entirely" hole, because a caller without a valid
attestation can't reach the endpoint at all once enforcement is on.

---

## Suggested order & sizing recap

| Week | Tasks | Outcome |
|---|---|---|
| 1 | 0.0–0.7 | All open faucets closed, UI honest, idempotency safe |
| 2–3 | 1.1–1.3 | Unified server-authoritative ride session live |
| 3 | 1.4, 2.1–2.4 | Legacy endpoints neutralized, economy consistent |
| 4 | 2.5–2.7, 3.1–3.2 (log mode) | Caches scoped, dashboards, attestation logging |
| 5+ | 3.2 enforce, 1.4 removal | Enforcement after adoption metrics allow |

**Definition of done for the whole effort:** with only curl and a valid auth token (no
app), it is impossible to (a) earn ride points, (b) earn more than 3 rewarded game
plays/day at fixed point values, (c) keep a multiplier alive past 5 minutes without
plausible GPS heartbeats, or (d) replay any award request — and the app UI never
claims an earning state the server hasn't confirmed.
