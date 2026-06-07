# MetroSafar Backend — Modularization & Scalability Guide

The backend currently lives in a single `server.js` (~4,000 lines, ~109 routes).
It works, but the single-file shape makes it hard to test in isolation, risky to
change, and slow to onboard. This document proposes an **incremental** refactor
(no big-bang rewrite) toward a modular, testable, horizontally-scalable service,
plus the scalability changes that matter as traffic grows.

---

## 1. Target module layout

Keep `server.js` as a thin **composition root** only. Everything else moves into
focused modules under `src/`:

```
backend/
  server.js                # bootstrap: config, middleware, mount routers, listen
  src/
    config/
      env.js               # all process.env reads, validated once with zod
      app-config.js        # APP_CONFIG (force-update floor, store URL)
    middleware/
      auth.js              # Firebase token verification → req.firebaseUser/clientId
      rate-limit.js        # buildLimiter + the per-group limiters
      validate.js          # zod validate(schema) helper
      metrics.js           # request timing/counters (see §4)
      error-handler.js     # central error → JSON + logging
    routes/
      home.js              # /api/home, /api/profile
      games.js             # /api/games/*  (+ trivia score, leaderboard)
      rewards.js           # /api/rewards/*  (watch-ad, redeem, SSV)
      trips.js             # /api/trips/*, /api/trip/commute-session/*
      stamps.js            # /api/stamps/*
      social.js            # /api/social/*, /api/referral/*
      content.js           # /api/catalog/*, /api/articles, /api/surveys, /api/stories
      intel.js             # /api/intel/* (etas, route, disruptions, crowd)
      account.js           # /api/account, /api/me/*, consent, parental
      admin.js             # admin-only routes (guarded by role middleware)
    domain/                # PURE business logic — no Express, no req/res
      scoring.js           # point rules, daily-cap math
      anti-cheat.js        # (already extracted) score plausibility
      streak.js            # streak day-boundary logic
      quests.js            # quest building/reset
      rewards.js           # redemption eligibility, monthly cap
    data/                  # persistence adapters — the ONLY place that touches Firestore
      users.js             # getUserState/saveUserState, claimTransaction
      catalog.js           # live catalog load + onSnapshot subscriptions
      cities.js            # city registry load
      leaderboard.js       # (already a lib) materializer + reads
    lib/                   # cross-cutting infra (already exists)
      redis.js  qr-tokens.js  admob-ssv.js
  test/                    # node:test, mirrors src/ (pure modules first)
```

**Routers** receive their dependencies (firestore, logger, services) via a small
factory so they can be unit-tested with fakes:

```js
// src/routes/games.js
module.exports = function gamesRouter({ users, scoring, antiCheat, leaderboard }) {
  const router = require('express').Router();
  router.post('/trivia/score', validate(triviaScoreSchema), async (req, res, next) => {
    try {
      const verdict = antiCheat.validateTriviaScore(req.body);
      const rank = await leaderboard.recordTriviaScore(req.clientId, { ...req.body, score: verdict.score });
      res.json(rank);
    } catch (e) { next(e); }
  });
  return router;
};
```

```js
// server.js (composition root)
app.use('/api/games', gamesRouter({ users, scoring, antiCheat, leaderboard }));
```

### The key rule: separate the three layers
- **routes/** — HTTP only (parse, validate, status codes). No business rules.
- **domain/** — pure functions, fully unit-testable, no I/O. This is where the
  money lives (scoring, caps, anti-cheat) and where tests pay off most.
- **data/** — the only modules that import `firestore`. Swappable for a fake in
  tests; lets you add caching/batching in one place.

---

## 2. Incremental migration path (no freeze, no rewrite)

Do it route-group by route-group; each step is independently shippable:

1. **Extract pure domain first** (lowest risk, highest test ROI): `scoring.js`,
   `streak.js`, `quests.js`, `rewards.js`. `anti-cheat.js` is already done. Add
   `node:test` for each. `server.js` just `require`s them.
2. **Introduce `data/users.js`** wrapping the existing `getUserState` /
   `saveUserState` / `claimTransaction`. Point `server.js` at it. No behavior change.
3. **Carve one router at a time** (start with `games.js`, the highest-traffic +
   now security-sensitive group), mount it, delete the inline routes. Repeat for
   rewards, trips, etc.
4. **Move middleware** (auth, rate-limit, validate, error-handler) into
   `src/middleware/`. `server.js` becomes ~150 lines of wiring.
5. **Mirror tests** under `test/` as each module lands.

Each PR stays small and is guarded by the new CI (`npm test`).

---

## 3. Scalability — already done & next

- **Leaderboard materializer (done):** now elected per tick via a Redis `SET NX
  PX` leader lock (`lib/leaderboard.js`). Only one Cloud Run instance scans &
  materializes per cycle regardless of instance count — removes duplicated
  500-doc scans and write contention. Falls back to local execution when Redis
  is absent (single-instance/dev).
- **Read path:** leaderboard reads already serve a materialized doc + Redis
  rank cache (60s TTL). Keep this; add CDN cache headers on the GET so Cloud
  Run/Cloudflare can absorb live-event spikes.
- **Next — move the materializer out of the request process entirely:** for true
  isolation, replace the in-process `setInterval` with **Cloud Scheduler →
  Pub/Sub → a dedicated Cloud Function** (or a `--min-instances=1` worker
  service). The leader lock is a good interim; a scheduled function gives
  exactly-once execution and decouples background work from request capacity.
- **Firestore hot spots:** the per-user score doc and daily-cap counter are
  written on every game completion. Use transactions (already used via
  `claimTransaction`) and consider sharded counters if a single city's live
  event drives >1 write/sec to one doc.

---

## 4. Metrics — move off per-instance memory

Today `metrics` is an in-process object: it resets on redeploy and each Cloud
Run instance only sees its own slice, so the admin dashboard is partial and
non-deterministic under autoscaling. Two options, in order of preference:

1. **Cloud Monitoring custom metrics** (recommended for production): emit
   counters/latencies via `@google-cloud/monitoring` (or structured log-based
   metrics — Cloud Run already ships Pino logs to Cloud Logging, so a
   log-based metric needs zero new code, just a metric definition). This gives
   correct cross-instance aggregation, dashboards, and alerting for free.
2. **Aggregate in Redis** (cheap interim): replace the in-memory counters with
   `INCR`/`INCRBYFLOAT` on Redis keys (e.g. `metrics:req:total`,
   `metrics:route:<k>`), and have `/admin/metrics` read them. One shared view
   across instances; survives individual instance restarts.

Either way, keep the in-memory version as a local-dev fallback when Redis/
Monitoring isn't configured.

---

## 5. Testing strategy

- **Pure domain modules** → `node:test`, no infra. (anti-cheat, qr-tokens done.)
- **Data + routes** → run against the **Firestore emulator** in CI
  (`gcloud emulators firestore start`) with a tiny supertest harness. Prioritize
  the money paths: earning pipeline daily-cap, idempotency-key dedup, SSV
  transaction dedup, auth middleware (valid/expired/missing token).
- Wire `npm test` (done) into the CI workflow (done) so every PR is gated.
