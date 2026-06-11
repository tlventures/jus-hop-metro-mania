# Security Fix Implementation Plan — MetroSafar

**For:** junior engineer
**Source audit:** `SECURITY_AUDIT_2026-06-11.md` (22 findings)
**Goal:** fix the maximum number of findings with the minimum number of new code paths, leaving a working app — not a differently-broken one.

---

## 0. Read this first — the core idea

Half of the critical findings exist for **one reason**: points get awarded in several different places, and not every place goes through the same guard. The legacy trip path, the streak path, the AdMob path, and the activity-events path each award points their own way, so the daily cap (and other rules) leak.

**The whole strategy is: build one award chokepoint and route everything through it.**

We add a single pure helper, `awardCapped(state, requested, now)`, that:
- knows the 500/day cap,
- reads and writes the *same* ledger fields (`dailyPointsEarned`, `lastDailyEarnDate`),
- returns exactly how many points were actually granted.

Once every earning endpoint calls it, findings **#2, #3, #4, #10, #11** collapse into "use the helper," and we stop the next person from re-introducing the same bug.

Do the phases **in order**. Each phase is independently shippable and testable. Do not start a phase until the previous one's verification steps pass.

> ⚠️ **One product decision is required before Phase 1 ships** — see the callout in Phase 1.3. Get sign-off; do not guess.

---

## Phase 0 — Setup & safety net (30 min)

1. Branch off the current work:
   ```bash
   git checkout -b fix/security-hardening-phase1
   ```
2. Confirm the backend boots locally and the test suite (if any) is green **before** touching anything:
   ```bash
   cd backend && npm install && npm test 2>/dev/null || echo "no tests — rely on manual verification"
   node -e "require('./server.js')" 2>&1 | head   # smoke: does it parse/require cleanly?
   ```
3. Keep a scratch terminal open running the server so you can curl endpoints after each change.

---

## Phase 1 — The award chokepoint (backend) — fixes #2, #3, #4, #10, #11 + the SSV crash bug

All edits in `backend/server.js`.

### 1.1 — Add the helper

Put this **immediately after** the `DAILY_POINT_CAP = 500` declaration (currently ~line 2101) so the constant is in scope:

```js
// Single source of truth for awarding points under the daily cap.
// Every earning path MUST go through this so the cap can never leak again.
// Pure function: takes the current user state + requested points, returns
// how many were actually awarded and the state fields to merge.
function awardCapped(state, requested, now = new Date()) {
  const isNewDay = !state.lastDailyEarnDate ||
    new Date(state.lastDailyEarnDate).toDateString() !== now.toDateString();
  const currentDailyEarned = isNewDay ? 0 : (state.dailyPointsEarned || 0);
  const remaining = Math.max(0, DAILY_POINT_CAP - currentDailyEarned);
  const awarded = Math.min(Math.max(0, Math.round(requested || 0)), remaining);
  return {
    awarded,
    capReached: remaining === 0,
    dailyEarned: currentDailyEarned + awarded,
    fields: {
      points: (state.points || 0) + awarded,
      dailyPointsEarned: currentDailyEarned + awarded,
      lastDailyEarnDate: awarded > 0 ? now.toISOString() : state.lastDailyEarnDate,
    },
  };
}
```

> Note: this uses `toDateString()` (server/UTC day) to match the **existing** games + activity-events cap logic. Do **not** switch it to IST here — that is finding #15, handled separately in Phase 3. Changing it now would silently shift everyone's reset time.

### 1.2 — Fix the AdMob SSV handler — #10, #11, and the `completeDailyQuestOnce` crash

In `GET /api/rewards/admob-ssv` (~line 2304):

**a) Clamp the reward (#11).** Replace:
```js
const amount = Number(reward_amount) || AD_REWARD_POINTS;
```
with:
```js
// Never trust the reward_amount field beyond our configured value, even though
// the ECDSA signature is valid — a misconfigured AdMob unit could send anything.
const amount = Math.min(Number(reward_amount) || AD_REWARD_POINTS, AD_REWARD_POINTS);
```

**b) Route through the cap (#10) and remove the undefined-function crash.** Replace the whole `claimTransaction(...)` callback body with:
```js
await claimTransaction(user_id, async (txn, state) => {
  const today = new Date().toDateString();
  const isNewDay = state.adWatchDate !== today;
  const watchesToday = isNewDay ? 0 : (state.adWatchesToday || 0);
  if (watchesToday >= AD_REWARD_DAILY_LIMIT) {
    return { next: null, response: { capped: true } };
  }

  // Ad points now count against the same 500/day ledger as everything else.
  const award = awardCapped(state, amount, new Date());

  // Daily "watch_video" quest bonus, once per day, also capped.
  const completed = new Set(state.completedQuests || []);
  let questBonus = 0;
  if (!completed.has('watch_video')) {
    const q = awardCapped({ ...state, ...award.fields }, QUEST_POINTS['watch_video'] || 15, new Date());
    questBonus = q.awarded;
    completed.add('watch_video');
    // fold the quest award into the final fields
    award.fields = q.fields;
  }

  const next = {
    ...state,
    ...award.fields,
    adWatchesToday: watchesToday + 1,
    adWatchDate: today,
    completedQuests: [...completed],
  };
  return { next, response: { pointsAwarded: award.awarded + questBonus } };
});
```
This deletes the call to the non-existent `completeDailyQuestOnce` (which would throw `ReferenceError` on every genuine Google callback) and replaces it with the same inline quest logic the legacy `watch-ad` endpoint already uses.

> Keep the `adWatchesToday` / `AD_REWARD_DAILY_LIMIT` 5-ads/day limit. That counts *ads*, not points — it's a separate, legitimate guard.

### 1.3 — Route the streak through the cap — #3

In `POST /api/streak/claim` (~line 1806), the points line is currently:
```js
const pointsEarned = hadRideToday ? 5 * newDay : 0;
const next = {
  ...state,
  points: state.points + pointsEarned,
  ...
};
```
Replace with:
```js
const STREAK_DAILY_BONUS_CAP = 100;   // a single streak claim can't dwarf real activity
const requested = hadRideToday ? Math.min(5 * newDay, STREAK_DAILY_BONUS_CAP) : 0;
const award = awardCapped(state, requested, now);
const pointsEarned = award.awarded;
const next = {
  ...state,
  ...award.fields,
  streakDay: newDay,
  longestStreak: newLongest,
  lastStreakClaimAt: now.toISOString(),
};
```
And add `dailyCapped: award.capReached` to the response object so the client can show the right message.

> 🚦 **PRODUCT DECISION REQUIRED.** Today, streak points bypass the daily cap (that's the bug). After this fix, streak bonus **counts toward** the 500/day cap, and a single claim is capped at `STREAK_DAILY_BONUS_CAP` (100). Both are deliberate but **user-visible** changes. Confirm the cap value and the "counts toward daily limit" behavior with the product owner before shipping. Do not invent a different number.

### 1.4 — Lock down `/api/activity-events` — #2, #4, #5

This endpoint has **zero call sites in the current Flutter app** (verified — games use `/api/games/:id/complete`). It's only reachable by old clients and attackers, so we tighten it hard.

**a) Remove the `game_completed` faucet (#2).** In `ACTIVITY_POINT_RULES` (~line 2091), delete the `game_completed` line entirely — game completion has its own properly-capped endpoint. (This mirrors how `ride_completed` was already removed.) The endpoint already 400s on unknown types, so old clients sending `game_completed` will simply get "Unknown activity type," which is correct.

**b) Kill the `metadata.points` override (#4).** In `activityEventSchema` (~line 333), change:
```js
metadata: z.object({ points: z.number().int().min(0).max(1000).optional() }).optional(),
```
to:
```js
metadata: z.object({}).passthrough().optional(),   // points are server-decided only
```
Then in the handler (~line 2158), replace:
```js
const requested = metadata?.points ? Math.min(Number(metadata.points), rule.max) : rule.base;
```
with:
```js
const requested = rule.base;   // never let the client choose the amount
```

**c) Add per-entityId dedup for repeatable types (#5).** The repeatable, entity-scoped types (`stamp_claimed`, `station_quiz_completed`, `passport_viewed`) currently re-award the same `entityId` forever. Add a once-per-entity guard inside the `claimTransaction` callback, before computing points:
```js
const DEDUP_TYPES = new Set(['stamp_claimed', 'station_quiz_completed', 'passport_viewed']);
const claimedKey = entityId ? `${type}:${entityId}` : null;
const claimedSet = new Set(state.claimedActivityKeys || []);
if (DEDUP_TYPES.has(type) && claimedKey && claimedSet.has(claimedKey)) {
  return { next: null, response: { pointsAwarded: 0, reason: 'already_claimed', totalPoints: state.points } };
}
```
Then route the award through the helper and persist the key:
```js
const award = awardCapped(state, rule.base, new Date());
if (claimedKey && DEDUP_TYPES.has(type)) claimedSet.add(claimedKey);
const next = {
  ...state,
  ...award.fields,
  claimedActivityKeys: [...claimedSet].slice(-500),   // bounded
  walletTransactions: transactions,
};
```
Also apply the commute multiplier the same way it was applied before — multiply **before** calling `awardCapped`: `awardCapped(state, Math.round(rule.base * commute.multiplier), now)`.

> Keep `defaultUserState` in sync: add `claimedActivityKeys: []` next to the other array fields (~line 487-491) so existing-user merges don't choke.

### Phase 1 verification

```bash
# #11 reward clamp — send an inflated reward_amount with a (test) valid signature:
#   expect pointsAwarded <= AD_REWARD_POINTS (15), never the inflated value.
# #10 SSV cap — set a user's dailyPointsEarned to 500 in Firestore, then fire SSV:
#   expect pointsAwarded: 0 (cap reached), not 90.
# SSV crash — confirm a genuine SSV callback returns 200 OK, not 500.
# #3 streak — with dailyPointsEarned already 500, claim streak: expect pointsEarned 0.
# #2 — POST /api/activity-events {"type":"game_completed"} → 400 Unknown activity type.
# #4 — POST /api/activity-events {"type":"stamp_claimed","metadata":{"points":15}} → awards base (10), not 15.
# #5 — POST the same {"type":"stamp_claimed","entityId":"s1"} twice → first awards, second reason: already_claimed.
```
Manually verify each in the scratch terminal. Commit Phase 1 only when all pass.

---

## Phase 2 — Legacy trip neutralisation (backend) — fixes #1, #13

The legacy `/api/trips/*` system is the single biggest hole: no QR required and `endTrip` writes points **outside** `claimTransaction`, so the cap never applies. We fix it in two safe steps.

### 2.1 — Route legacy `endTrip` through the cap (#1)

In `backend/phase56.js`, `endTrip()` (~line 354) currently does a non-transactional read-modify-write:
```js
const user = await context.getUserState(clientId);
await context.saveUserState(clientId, { ...user, points: Number(user.points||0) + pointsAwarded, ... });
```
This is both **uncapped** and **race-prone** (two concurrent ends can both read the old balance). Replace the award with `context.claimTransaction` (already provided in the phase56 context) so it shares the same atomic ledger as everything else:

```js
const result = await context.claimTransaction(clientId, async (txn, state) => {
  const isNewDay = !state.lastDailyEarnDate ||
    new Date(state.lastDailyEarnDate).toDateString() !== new Date().toDateString();
  const currentDailyEarned = isNewDay ? 0 : (state.dailyPointsEarned || 0);
  const granted = Math.min(Math.max(0, pointsAwarded), Math.max(0, 500 - currentDailyEarned));
  const next = {
    ...state,
    activeTripId: null,
    points: (state.points || 0) + granted,
    dailyPointsEarned: currentDailyEarned + granted,
    lastDailyEarnDate: granted > 0 ? new Date().toISOString() : state.lastDailyEarnDate,
    tripSummary: { /* keep the existing tripSummary block, unchanged */ },
  };
  return { next, response: { granted } };
});
const grantedPoints = result.granted;
```
Use `grantedPoints` (not `pointsAwarded`) in the response payload so the client sees what was actually awarded.

> The cleanest long-term move is to make `awardCapped` importable and reuse it here. For Phase 2, inlining the same 500-cap math (as above) is acceptable and avoids a cross-file refactor mid-stream. If you prefer DRY, export `awardCapped` from `server.js` and pass it into `phase56Context` — but only do that if Phase 1 is already merged and green.

### 2.2 — Add the legacy kill switch (#13)

Old clients can't send QR tokens, so we can't *require* QR without breaking them. Instead add an env-gated shutoff, defaulting to **on** (don't break anyone today), that ops can flip once new-client adoption is high enough — exactly the pattern `LEGACY_WATCH_AD` already uses.

In `installPhase56Routes` (`phase56.js` ~line 819), at the top of the `/api/trips/start` handler:
```js
if (process.env.LEGACY_TRIPS !== 'on') {
  return res.status(410).json({
    error: 'Please update the app to start a ride.',
    code: 'legacy_trips_retired',
  });
}
```
Apply the same guard to `/api/trips/:tripId/heartbeat`. **Do not** gate `/api/trips/:tripId/end` — a user mid-trip when the flag flips must still be able to finish and get capped points.

For local/staging keep `LEGACY_TRIPS=on`. Production rollout (flipping it off) is a **release decision** tied to forced-upgrade — flag it to the team, don't flip it yourself.

### Phase 2 verification

```bash
# With LEGACY_TRIPS unset (default off):
#   POST /api/trips/start → 410 legacy_trips_retired.
# With LEGACY_TRIPS=on, start a trip, one GPS heartbeat, end it:
#   set dailyPointsEarned=500 first → end awards 0 (capped), not 80.
#   confirm two rapid concurrent /end calls don't double-credit (transaction guard).
```

---

## Phase 3 — Validation & integrity hardening (backend) — #16, #17, #15, #9, #14, #8

These are independent, low-risk, and can be done in any order. Each is small.

### 3.1 — Game score sanity floor/ceiling (#16)
In `POST /api/games/:gameId/complete`, the score is client-supplied and used for the leaderboard. Add a per-game ceiling so `score: 99999999` can't own the board. Define realistic maxes:
```js
const GAME_SCORE_MAX = { daily_spin: 1000, trivia: 5000, sudoku: 5000, word_puzzle: 5000, city_explorer: 5000 };
const submitted = Math.min(Math.max(0, Number(req.body.score) || 0), GAME_SCORE_MAX[req.params.gameId] || 5000);
const newScore = Math.max(current.score, submitted);
```
(Tune the maxes with whoever owns game design — these are placeholders.)

### 3.2 — Minimum game duration (#17)
Reject implausibly fast completions. Near the top of the same handler:
```js
const MIN_GAME_SECONDS = { trivia: 10, sudoku: 30, word_puzzle: 20, city_explorer: 15, daily_spin: 0 };
const min = MIN_GAME_SECONDS[req.params.gameId] ?? 0;
if (min > 0 && (Number(req.body.timeSpent) || 0) < min) {
  return res.status(400).json({ error: 'Game completed too quickly', reason: 'too_fast' });
}
```
> `timeSpent` is still client-supplied, so this only raises the bar — it isn't proof. Real proof needs Play Integrity (out of scope here). Document that.

### 3.3 — Daily-cap timezone consistency (#15)
The 500/day ledger uses UTC `toDateString()`; game-play and streak caps use `istDayString()`. Pick **one** — IST is correct for an India-only app. This is a coordinated change: switch the cap ledger to IST by replacing every `new Date().toDateString()` / `new Date(state.lastDailyEarnDate).toDateString()` comparison in the earning paths with `istDayString(...)` equality. **Do this as its own commit** and re-run all Phase 1 verifications, because it shifts when everyone's daily counters reset. If you'd rather not risk it now, leave a `// TODO(#15)` and ship the rest — it's Low severity.

### 3.4 — Cadence auto-throttle (#9)
`checkRideCadenceAnomaly` only logs to `metrosafar_flagged_trips`. Add a soft consequence: if a user trips the anomaly **N times within a window**, return a cool-down on the next ride-end award instead of points.
- Track `rideAnomalyCount` + `rideAnomalyWindowStart` on the user doc.
- If count ≥ 3 within 30 min, the next `endRide` awards 0 with `reason: 'cooldown'` and surfaces a friendly "slow down" message. Reset the window after 30 min.
Keep it conservative — false positives must not punish real commuters. Pair with the team on thresholds.

### 3.5 — Event question bank (#14)
`EVENT_QUESTION_BANK` (`phase56.js` ~line 58) has 3 static questions. Minimum viable fix: expand to a larger pool (≥30) and **randomly sample per event** so answers can't be memorised in one sitting. Better: load questions from the city content packs already in Firestore (`catalog`/content-pack loader) rather than hardcoding. Scope the larger version with product; the random-sample-from-a-bigger-pool version is the safe interim.

### 3.6 — QR sharing window (#8) — *needs a product/ops call, plan only*
A 24h QR bucket means one screenshot works for everyone all day. Two levers, both server-side:
1. Shorten `QR_TOKEN_ROTATION_HOURS` to minutes (the validator already supports a previous-bucket grace), so a shared screenshot dies fast.
2. At `/api/rides/start`, require the **starting GPS fix** to be within the proximity radius of the *scanned* station (not just any station). The rides system already collects GPS at heartbeat — extend it to the start call.
Don't implement blind — rotation cadence affects how QR posters/displays are generated at stations. Write the proposal, get ops sign-off, then build.

---

## Phase 4 — Flutter / UX — #19, #20, #21, #22, #18

### 4.1 — Stop duplicate heartbeats (#20)
`TripModeNotifier` and `RideSessionNotifier` each run their own 60s GPS timer. Guarantee only one is ever active:
- In `RideSessionNotifier.startWithQr` / `restore`, when a new ride becomes active, ensure the legacy `tripModeProvider` heartbeat timer is stopped.
- Simplest robust approach: have whichever notifier starts a session call a shared "active ride lock" (a small provider holding the current owner). A timer only fires GPS if it owns the lock.
- Given Phase 2 retires legacy trip *starts*, the realistic remaining case is "old in-flight trip + app updated." Stopping the legacy timer when a new ride starts covers it.

### 4.2 — Offline QR scan retry (#19)
In `ride_session_provider.dart` `startWithQr` (~line 127), a scan with no network rolls straight back to `idle`. Instead:
- Keep the scanned token + timestamp in memory, set phase to a new `RidePhase.awaitingNetwork` (or reuse `verifying` with a "reconnecting…" message).
- Listen for connectivity; on reconnect within the token's validity window, auto-retry `startRide` once.
- If the token's bucket has expired by reconnect, show "QR expired, please rescan" — don't silently fail.
Do **not** queue QR starts in the generic outbox: QR validity is time-bound and the outbox is for idempotent mutations, not time-sensitive verification. A dedicated single-retry is correct.

### 4.3 — Restore race on cold start (#21)
`rideRestoreProvider` calls `restore()` only when `activeCityProvider` is already non-null, so a late city load means restore never runs. Fix by reacting to the city *becoming* available rather than sampling once:
- Use `ref.listen(activeCityProvider, ...)` (or a `ref.watch` inside a provider that re-runs) so that when the city transitions null → set, `restore()` fires exactly once (guard with a `bool _restored` so it can't double-fire).

### 4.4 — Persist ride summary (#22)
After `endRide`, the summary (`pointsEarned`, `co2SavedKg`, `stamps`) is in-memory only; a crash loses it.
- Write the summary to UID-scoped `SharedPreferences` (reuse the existing `uid_`-prefix convention) right when `RidePhase.summary` is set.
- On launch, if `restore()` finds no active ride but a *recent* (< 24h) unshown summary exists, show it once, then clear it.
- Points are already safe server-side; this only fixes the missing reward screen.

### 4.5 — Server-side age-gate enforcement (#18)
The `is_minor` flag lives only in `SharedPreferences`, so a reinstall clears it. Move the source of truth to the server:
- On signup / DOB capture, compute minor status server-side from DOB and store it on the user doc (`isMinor: true|false`, plus DOB or just the derived flag for DPDPA minimisation).
- Gate ad-reward endpoints (`/api/rewards/admob-ssv` award, `/api/rewards/watch-ad`) and any ad-serving config so minors never receive ad rewards regardless of client.
- The client keeps its local flag for UX, but the server stops trusting it.
> This is a compliance change — loop in whoever owns the DPDPA work before shipping.

---

## What we are *not* fully fixing here (be honest about it)

| Finding | Why it's only partially addressed |
|---|---|
| #6 Sybil / fake-account referral farming | Needs device attestation (Play Integrity / App Check) + phone-verified accounts + per-device referral caps — infra work. **Interim:** require a phone-verified account before a referral *qualifies*, and cap qualified referrals per device/IP. Plan it; don't fake it. |
| #7 GPS spoofing on rooted devices | Client mock-location detection is advisory only. Real defense = Play Integrity + server-side teleport/speed sanity between heartbeats. Phase 3.4's heuristics help; full fix is its own project. |
| #8 QR screenshot sharing | Needs a rotation-cadence + station-poster decision (3.6). Server work is ready; rollout is an ops call. |

These three are flagged so nobody assumes they're closed.

---

## Suggested commit / PR sequence

1. `fix: award chokepoint + SSV cap/clamp/crash + activity-events lockdown` (Phase 1)
2. `fix: route legacy trip-end through daily cap + kill switch` (Phase 2)
3. `fix: game score/duration validation` (Phase 3.1–3.2)
4. `fix(flutter): single heartbeat, offline QR retry, restore race, summary persistence` (Phase 4.1–4.4)
5. Separate, sign-off-gated PRs for: streak product decision (1.3), timezone unification (3.3), age-gate server enforcement (4.5), and the infra items (#6/#7/#8).

Ship 1–2 first; they close every Critical that's a pure code change. Don't batch the product/compliance-gated items in with the mechanical fixes — that's how reviews stall and "working app" becomes "mystery regression."
