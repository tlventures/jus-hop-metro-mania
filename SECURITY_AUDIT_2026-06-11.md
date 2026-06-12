# Security Audit — MetroSafar (2026-06-11)

22 findings across bot gaming, ad farming, design flaws, and user flow problems.

## Summary

| Severity | Count |
|----------|-------|
| Critical | 6 |
| High | 7 |
| Medium | 5 |
| Low | 4 |

---

## Bot Gaming & Point Farming

### #1 — CRITICAL: Legacy `/api/trips/start` + `/api/trips/:id/end` — no QR, no daily cap

The phase56 trip system is still fully live. `startTrip` only requires a valid `stationId` (public from `/api/v2/cities/:id/stations`) — no HMAC token. `endTrip` writes points directly via `saveUserState`, bypassing `claimTransaction`, so the 500/day cap is never checked. One GPS heartbeat near any station → up to 80 pts, uncapped, indefinitely repeatable.

**File:** `backend/phase56.js` — `startTrip()`, `endTrip()`

---

### #2 — CRITICAL: `POST /api/activity-events` with `type: game_completed` bypasses per-game daily cap

The `/api/games/:id/complete` endpoint enforces 3 plays/game/day via `gameDailyPlays`. The `/api/activity-events` endpoint accepts `game_completed` type and awards 20 pts (or up to 50 with `metadata.points`) per call with no `gameDailyPlays` check — only the 500/day cap. A bot can POST this endpoint 25 times to hit the cap purely from fake game events.

**File:** `backend/server.js` — `POST /api/activity-events`, `ACTIVITY_POINT_RULES`

---

### #3 — CRITICAL: Streak points bypass the 500/day cap and grow unbounded

`/api/streak/claim` writes `points + (5 × streakDay)` directly without touching `dailyPointsEarned`. No cap is checked, and no streak ceiling exists. By day 100 a user earns 500 pts/claim purely from streak, entirely outside the daily cap. Combined with 500 pts from other activities = 1000+ pts/day.

**File:** `backend/server.js` — `POST /api/streak/claim`

---

### #4 — HIGH: `metadata.points` injection in activity-events

The `activityEventSchema` allows `metadata.points` up to 1000 and the server picks `Math.min(metadata.points, rule.max)`. Since `game_completed` max = 50 (base = 20), a caller can inflate each call by 2.5×. `stamp_claimed` max = 15 vs base = 10; `quest_completed` max = 30 vs base = 20.

**File:** `backend/server.js` line 336, line 2158

---

### #5 — HIGH: No per-entityId deduplication for `stamp_claimed`, `station_quiz_completed`, `passport_viewed` via activity-events

Dedicated endpoints (`/api/articles`, `/api/surveys`, `/api/stories`) track IDs in user state and deduplicate. The generic `/api/activity-events` endpoint writes no per-entityId state for these types — the same `entityId` can earn points repeatedly every request, bounded only by the 500/day cap. A bot can hit 500 pts/day calling `{type:"stamp_claimed", entityId:"station_1", metadata:{points:15}}` ~33 times.

**File:** `backend/server.js` — `POST /api/activity-events` (no set tracking for stamp/quiz/passport types)

---

### #6 — HIGH: Sybil / account farming — no device fingerprint or phone uniqueness check

Firebase Auth has no deduplication by device or phone-number family. Creating 10 fake accounts (e.g. via VoIP SIMs) + one referral code: referrer earns 10 × 150 = 1,500 pts/month; each fake account gets 100 pts on first activity. The first-activity trigger for referral qualification is just completing any activity event — achievable in seconds.

**File:** `backend/server.js` — `qualifyReferralForUser()`, `applyReferralToken()`

---

### #7 — HIGH: GPS spoofing bypasses ride evidence gate on rooted devices

`SafeDevice.isMockLocation` only detects Android mock-location via the system API. Root + Xposed/Magisk modules inject false GPS coordinates at a lower level — both the client check and server haversine (3 km from any station, not the specific station) pass. Rooted device + coords near any metro station = valid heartbeats = points.

**File:** `lib/core/ride/ride_session_provider.dart` line 218; `backend/rides.js` haversine proximity check

---

### #8 — MEDIUM: QR code screenshot shared across unlimited users in same 24h bucket

Idempotency is per user per bucket (one ride per user per QR per 24h). A single station QR screenshot shared to 500 users via WhatsApp gives each user one valid ride start. With 25 nearby stations each with a 24h window, a coordinated group gets daily point farming without commuting.

**File:** `backend/rides.js` — `metrosafar_qr_redemptions` doc key is `${stationId}:${bucket}:${clientId}`

---

### #9 — MEDIUM: Cadence anomaly detection is advisory-only — no automated action

`checkRideCadenceAnomaly` writes to `metrosafar_flagged_trips` for manual review. No automatic rate limit, throttle, or account flag is applied. A bot accumulates flags with no operational consequence until an admin manually reviews.

**File:** `backend/server.js` — `checkRideCadenceAnomaly()`

---

## Ad Farming

### #10 — CRITICAL: AdMob SSV points bypass the 500/day overall cap

The SSV handler (`/api/rewards/admob-ssv`) tracks ad watches in `adWatchesToday` and awards points via `claimTransaction`, but it never reads or writes `dailyPointsEarned`. The 5 ads/day limit is separate from the 500 pt cap, so 5 × 15 pts + 1 quest bonus (15 pts) = 90 pts stack on top of the daily cap → 590+ pts/day maximum.

**File:** `backend/server.js` — `GET /api/rewards/admob-ssv` (lines ~2326–2345)

---

### #11 — HIGH: SSV `reward_amount` has no server-side maximum

`const amount = Number(reward_amount) || AD_REWARD_POINTS` — no `Math.min(amount, AD_REWARD_POINTS)`. If the AdMob console is misconfigured (e.g. reward_amount=500) or a future SDK bug sends a large value, the server awards it verbatim. This also bypasses the 500/day cap (tracked separately). The ECDSA signature only prevents spoofing at the HTTP layer — it doesn't restrict the reward_amount field value.

**File:** `backend/server.js` line ~2326

---

### #12 — MEDIUM: `LEGACY_WATCH_AD` kill switch lacks any secondary protection

If `LEGACY_WATCH_AD=on` is accidentally set in production (e.g. during an SSV debug session that was never reverted), the client-side endpoint is live with only the `redeemLimiter` (12 req/min) as protection. No QR, no GPS, no cryptographic verification — call it 5 times and earn 5 × 30 pts (ad + quest bonus) per day, completely client-driven.

**File:** `backend/server.js` — `POST /api/rewards/watch-ad` (line ~2363)

---

## Design Flaws

### #13 — CRITICAL: Legacy trip system and new rides system are both fully operational simultaneously

Phase56 `/api/trips/*` endpoints and the new `/api/rides/*` system coexist with no versioning gate or sunset flag. Old-client trips award points through a different, less-guarded path (no QR, no haversine proximity, no `claimTransaction` for daily cap). There is no mechanism to shut off the legacy path without breaking old app versions.

**File:** `backend/phase56.js` — all `/api/trips/*` routes still mounted

---

### #14 — MEDIUM: Event trivia uses 3 static hardcoded questions — competition is meaningless

`EVENT_QUESTION_BANK` in `phase56.js` has exactly 3 questions repeated across every event. Any user who played once knows all answers. The top-10/top-100 prize structure creates an illusion of competition while the "correct" answers are permanently memorized after one session.

**File:** `backend/phase56.js` lines ~58–83

---

### #15 — LOW: 500/day cap uses UTC date; game/streak caps use IST — timezone inconsistency

`dailyPointsEarned` resets at UTC midnight (5:30 AM IST). `gameDailyPlays` and streak reset at IST midnight. No double-earn is possible, but the cap mismatch causes user-visible confusion ("my daily limit didn't reset but my game plays did") and audit divergence between systems.

**File:** `backend/server.js` — activity-events uses `new Date().toDateString()` (UTC); games/streak use `istDayString()` (IST)

---

### #16 — MEDIUM: Game leaderboard score is client-supplied with no server-side floor or validation

`newScore = Math.max(current.score, Number(req.body.score) || 0)` — a client can submit `score: 99999999` to permanently own the trivia leaderboard. While points are unaffected, leaderboard manipulation undermines competitive features and could drive legitimate users away.

**File:** `backend/server.js` — `POST /api/games/:gameId/complete` line ~1741

---

### #17 — LOW: No server-side minimum game duration — games completable in 0 ms

`timeSpent` is accepted from the client and stored, but never validated against a floor. A bot calling `/api/games/trivia/complete` with `timeSpent: 0` gets the same points as a genuine player. Even a 15-second minimum would distinguish robots from humans for trivia and word_puzzle.

**File:** `backend/server.js` — `POST /api/games/:gameId/complete`

---

### #18 — MEDIUM: Minor / age-gate status is client-side only — no server enforcement

The `is_minor` flag is stored in `SharedPreferences` and used to disable AdMob ads client-side. The server never checks this status. Reinstalling the app, clearing data, or using a modified client resets the flag to non-minor. DPDPA requires server-side enforcement of age-appropriate data handling.

**File:** `lib/core/compliance/minor_status.dart`; no corresponding server-side gate

---

## User Flow Flaws

### #19 — HIGH: Offline QR scan silently rolls back — users at the station can't start a ride

If the user scans a valid station QR while offline, `startWithQr` immediately rolls back to `idle` with "No network — please scan when you have signal." Underground stations and crowded platforms frequently have no signal. The QR is time-limited; by the time the user has signal, the bucket may have rotated. No option to retry, no queue, no explanation that the QR was valid.

**File:** `lib/core/ride/ride_session_provider.dart` lines ~127–134

---

### #20 — HIGH: Two parallel ride providers send duplicate heartbeats

Both `TripModeNotifier` (`tripModeProvider`) and `RideSessionNotifier` (`rideSessionProvider`) fire 60-second heartbeat timers independently. If a user has an active legacy trip and an active new ride simultaneously, both send GPS heartbeats to their respective endpoints. Double GPS polling drains battery and creates duplicate Firestore writes. No exclusivity guard exists.

**File:** `lib/features/trip/application/trip_state_provider.dart` line ~203; `lib/core/ride/ride_session_provider.dart` line ~214

---

### #21 — LOW: `rideRestoreProvider` race condition — restore skipped if city loads late

`rideRestoreProvider` watches `activeCityProvider` and fires a microtask to call `restore()` only when the city is non-null. On cold start, Firestore may return the active city after the provider initializes — the watch fires with city = null → restore never called. The user sees no active ride UI despite having one in progress.

**File:** `lib/core/ride/ride_session_provider.dart` lines ~270–275

---

### #22 — LOW: Ride summary state is not persisted — app crash during summary loses points display

After `endRide` succeeds, state moves to `RidePhase.summary` with `pointsEarned` and `co2SavedKg`. This is in-memory only. A crash or backgrounding during the summary screen loses the data. On next launch, `restore()` finds no active ride and returns to idle — the user never sees their reward summary. Points are safely on the server, but the UX tells them nothing happened.

**File:** `lib/core/ride/ride_session_provider.dart` — `RidePhase.summary` state, no SharedPreferences persistence

---

## Priority Fix Order

1. **#1** — Route legacy `endTrip` through `claimTransaction` + add deprecation flag to block new legacy trip starts
2. **#13** — Add a server-side kill switch (`LEGACY_TRIPS_ENABLED=off`) to gate `/api/trips/*`
3. **#2** — Add `gameDailyPlays` check inside activity-events for `game_completed` type
4. **#3** — Route streak points through `claimTransaction` / check `dailyPointsEarned`; add `STREAK_CAP` (e.g. day 30 = 150 pts max)
5. **#10** — Include ad reward in `dailyPointsEarned` (or subtract from remaining cap)
6. **#11** — Clamp SSV `reward_amount`: `const amount = Math.min(Number(reward_amount) || AD_REWARD_POINTS, AD_REWARD_POINTS)`
7. **#4** — Remove `metadata.points` from activity-events schema (or set max = base for all types)
8. **#5** — Add per-entityId dedup (a `Set` in user state) for stamp/quiz/passport in activity-events
9. **#16** — Cap submitted game score at a reasonable max per game type server-side
10. **#17** — Add minimum `timeSpent` per game (e.g. 15s for trivia, 60s for sudoku)
11. **#19** — Cache the validated QR token locally for 5 min and retry on reconnect
12. **#20** — Add exclusivity guard: if `rideSessionProvider` has an active ride, stop `tripModeProvider` heartbeat timer
