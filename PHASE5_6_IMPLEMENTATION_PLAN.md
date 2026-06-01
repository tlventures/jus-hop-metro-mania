# Phase 5 + 6 — Detailed Implementation Plan

*Architect + Product Manager view. Frontend (Flutter) + Backend (Node/Express + Firestore).*

**Status:** Ready to estimate / sequence with team
**Owner:** Engineering + Product
**Last updated:** 2026-05-18
**Total effort:** ~6 engineering weeks (3 weeks Phase 5 + 3 weeks Phase 6) + 1-2 weeks foundational work

---

## Table of contents

1. [Architecture principles](#1-architecture-principles)
2. [Cross-cutting infrastructure (build first)](#2-cross-cutting-infrastructure-build-first)
3. [Phase 5.1 — Trip Detection & Trip Mode UI](#3-phase-51--trip-detection--trip-mode-ui)
4. [Phase 5.2 — Live Metro Intelligence](#4-phase-52--live-metro-intelligence)
5. [Phase 5.3 — Offline-First Tunnel Cache](#5-phase-53--offline-first-tunnel-cache)
6. [Phase 6.1 — Station Stamps](#6-phase-61--station-stamps)
7. [Phase 6.2 — Audio Stories](#7-phase-62--audio-stories)
8. [Phase 6.3 — Daily Live Events](#8-phase-63--daily-live-events)
9. [Sequencing & week-by-week](#9-sequencing--week-by-week)
10. [Team RACI](#10-team-raci)
11. [Open questions](#11-open-questions-to-resolve-before-sprint-1)

---

## 1. Architecture principles

These principles govern every decision in this plan:

1. **Server is source of truth.** Client state is a cache. Conflict resolution always defers to server. Enables cross-device continuity (audio resume, stamps, points).
2. **Offline-first by default.** Every read is cached. Every write is idempotent and queued. The tunnel never breaks the app.
3. **Real-time only where it earns its keep.** WebSockets for live events, disruptions, leaderboards. REST + polling for everything else. Polling is fine until it isn't.
4. **Feature-flagged everything.** No Phase 5/6 feature ships to 100% without a ramp. Default-off behind a flag at merge time.
5. **Layered detection / data sources.** Trip detection, ETA data, etc. abstract behind interfaces with multiple implementations stacked by priority. Today's bootstrap (timetable) becomes tomorrow's fallback (when partner feed lands).
6. **Battery is a feature.** Geofencing uses native iOS/Android primitives, not foreground GPS polling. High-accuracy mode is a 30-second burst, never persistent.
7. **Privacy as default-deny.** No location, no friend matching, no crowd reports without explicit opt-in. Anonymized aggregates only for public surfaces.

---

## 2. Cross-cutting infrastructure (build first)

These six are blockers — Phase 5/6 features cannot ship without them. Allocate ~1 week before Phase 5 sprint 1, parallelized across team.

### CC.1 — Real-time channel (WebSocket gateway)

- **Library:** `socket.io` server-side (battle-tested rooms + reconnect) + `socket_io_client` on Flutter
- **Auth:** Issue short-lived JWT (15 min) on WS handshake. JWT minted by an existing REST endpoint, signed with backend secret. Refresh on reconnect.
- **Rooms:**
  - `user:{userId}` — for personal pushes (trade requests, friend activity)
  - `event:{eventId}` — for live event broadcast
  - `train:{trainId}` — for chat (Phase 7)
  - `line:{lineId}` — for disruption broadcast
- **Heartbeat:** 30s ping/pong. Client treats no pong in 60s as disconnect.
- **Reconnect:** Exponential backoff (1s → 2s → 4s → … capped at 30s). Server holds room subscriptions briefly to allow seamless rejoin.
- **Scale:** Single Node process is fine to 5k concurrent. Cluster mode + Redis adapter when we exceed.

### CC.2 — Geofencing & background location

- **Plugin:** `flutter_background_geolocation` (commercial license, ~$300 one-time) — best-in-class for battery-aware background tracking. Fallback: `geofence_service` (free, less reliable on iOS).
- **iOS strategy:** Significant Location Change API for wake-ups; high-accuracy GPS only when within 500m of a known station polygon.
- **Android strategy:** Geofencing API (registered with `GeofencingClient`). Wake intents handled by `flutter_background_geolocation`'s native service.
- **Permission cascade (Phase 4 already drafted):**
  1. Onboarding asks for `whenInUse` with priming UI.
  2. After 3 successful Trip Mode sessions, prompt for `always` to enable auto-detection.
- **Pre-warm:** Station polygons loaded into native geofencing engine on app start + on every server-pushed catalog update.

### CC.3 — Push notifications (FCM)

- **Setup:** Firebase project; iOS APNS certs; Android sender ID.
- **Server SDK:** `firebase-admin` in Node.
- **Topics:**
  - `line_{lineId}` for disruptions
  - `event_{eventType}` for live event reminders
  - `user_{userId}` (single-device topic for personal pushes, or direct token send)
- **Quiet hours:** Respect existing `profile.notificationsEnabled` + new `quietHoursStart/End`. Server-side check before send.
- **Deep links:** Universal links (iOS) + App Links (Android). Format: `metrosafar://events/{id}`, `metrosafar://trip`, `metrosafar://stamps/collection/{id}`. Handled by `go_router` deep link routes.

### CC.4 — Feature flags

- **Choice:** GrowthBook self-hosted (free) or LaunchDarkly (paid, polished). Recommend GrowthBook for cost.
- **Flags reserved:** `phase5.trip_mode`, `phase5.live_etas`, `phase5.disruptions_ws`, `phase5.offline_cache`, `phase6.stamps`, `phase6.audio_stories`, `phase6.live_events`.
- **Default state:** off everywhere.
- **Ramp:** 1% (eng team) → 10% (Hyderabad beta cohort) → 50% → 100%.
- **Frontend:** Single `FeatureFlagsProvider` (Riverpod) wraps SDK; per-flag boolean providers for fine-grained widgets.

### CC.5 — Analytics pipeline

- **Today:** `lib/services/analytics_service.dart` only `debugPrint`s. **Action:** wire to Firebase Analytics + add Amplitude (free up to 10M events/mo).
- **Event catalog:** New file `docs/EVENTS.md` documenting every event name + property schema. Required reading for any new feature PR.
- **Required event categories for Phase 5/6:**
  - `trip_*` — `trip_started`, `trip_ended`, `trip_mode_opened`, `trip_detection_source`
  - `intel_*` — `eta_viewed`, `disruption_received`, `route_planned`
  - `cache_*` — `prefetch_completed`, `outbox_replay`, `offline_event_logged`
  - `stamp_*` — `stamp_claimed`, `collection_completed`, `trade_proposed`
  - `audio_*` — `episode_started`, `episode_completed`, `episode_position`
  - `event_*` — `event_joined`, `event_question_answered`, `event_finished`

### CC.6 — Idempotency & outbox (detailed in 5.3)

- Headers: every mutating request must include `Idempotency-Key: <uuid>`.
- Backend dedupes against `idempotency_keys/{key}` (24h TTL).
- Client persists pending mutations to SQLite; replays in order on reconnect.

---

## 3. Phase 5.1 — Trip Detection & Trip Mode UI

**Goal:** App auto-detects when user is commuting and reshapes UI to a focused, trip-length-aware experience.

### 3.1 Product spec

| User signal | App behavior |
|---|---|
| Approaches station (geofence) | Home shows "At Miyapur platform — Yellow Line train in 4 min · Tap to start trip" |
| Taps QR to enter | Trip Mode auto-activates; banner shows current trip; primary content (audio/trivia/article) sized to predicted duration |
| Train enters tunnel | Cached content plays seamlessly; "✓ Ready for tunnel" badge in corner |
| Exits at destination station | Trip ends; stamps + points awarded; return-trip suggestion shown |
| Denies location | Manual "I'm on the metro" button on home; ticket-scan signal still works |

### 3.2 Frontend architecture

```
lib/features/trip/
├── application/
│   ├── trip_state_provider.dart          # StateNotifier<TripState>
│   ├── trip_detection_service.dart       # Signal fusion engine
│   ├── geofence_listener.dart            # Wraps native geofencing
│   └── trip_inference.dart               # Predict end station + duration
├── domain/
│   ├── trip_state.dart                   # enum: idle | atPlatform | onTrip
│   ├── trip_session.dart                 # Active trip data
│   └── detection_signal.dart             # Source + confidence
├── data/
│   ├── station_geofence_repository.dart  # Polygons cached locally
│   └── trip_api.dart                     # Backend client
└── presentation/
    ├── trip_mode_shell.dart              # Replaces _NavShell when on trip
    ├── widgets/
    │   ├── trip_banner.dart              # Top sticky banner
    │   ├── trip_content_slot.dart        # Adaptive content (audio/trivia/article)
    │   ├── trip_ready_badge.dart         # "✓ Ready for tunnel"
    │   └── trip_end_summary.dart         # Bottom sheet on trip end
    └── manual_trip_start_dialog.dart     # Fallback for no-location users
```

**Signal fusion (priority cascade, fired by `TripDetectionService`):**

1. **Ticket activation event** (highest confidence) — when user scans QR, app fires `tripDetectionService.signalTicketScanned()`
2. **Geofence entry** at station polygon → state becomes `atPlatform`
3. **Geofence enter + sustained 30-80 km/h for 60s** → state becomes `onTrip`
4. **Activity recognition** (`activity_recognition_flutter`) reports `inVehicle` → corroborates signal 3
5. **Manual override** — user button → state becomes `onTrip` regardless

**Trip end detection:**
- Geofence exit + speed < 5 km/h for 60s at known station, OR
- Ticket tap-out event, OR
- 90-min auto-end timeout (safety), OR
- Manual "End trip" button

**Adaptive content slot logic:**

```dart
Widget _selectContent(int remainingMinutes) {
  if (remainingMinutes >= 20) return const AudioEpisodeCard();
  if (remainingMinutes >= 8)  return const TriviaRoundCard();
  if (remainingMinutes >= 3)  return const ScratchCardCard();
  return const StationStampPreviewCard();
}
```

**Battery strategy:**
- Background geofencing only (no continuous GPS).
- High-accuracy GPS enabled for 30s when geofence enter fires (to disambiguate direction).
- All ML/inference happens server-side; client only ships signals.

### 3.3 Backend architecture

```
backend/modules/trips/
├── routes.js
├── service.js
├── inference.js                # Predict end station from start + line + history
└── model.js                    # Firestore I/O
```

**Endpoints:**

| Method | Path | Purpose | Request | Response |
|---|---|---|---|---|
| POST | `/api/trips/start` | Open a new trip | `{startStationId, line, source, detectedAt}` | `{tripId, predictedEndStationId, predictedDurationSeconds}` |
| POST | `/api/trips/:tripId/heartbeat` | Update with GPS sample | `{lat, lng, speedKmh, timestamp}` | `{predictedEndStationId, remainingSeconds}` |
| POST | `/api/trips/:tripId/end` | Close trip | `{endStationId, endedAt}` | `{pointsAwarded, stampsEarned, co2SavedKg, returnTripSuggestion}` |
| GET | `/api/trips/active` | App resume | — | `{trip?}` |
| GET | `/api/trips/history?limit=N` | Diary | — | `{trips: []}` |

**Firestore schema:**

```
trips/{tripId}
  userId: string
  line: string
  direction: 'inbound' | 'outbound'
  startStation: { id, name, claimedAt }
  endStation:   { id, name, claimedAt } | null
  predictedEndStationId: string
  predictedEndAt: timestamp
  source: 'ticket_scan' | 'geofence' | 'manual'
  status: 'in_progress' | 'completed' | 'abandoned'
  heartbeats: [{lat, lng, speedKmh, ts}]  // capped at last 30
  pointsEarned: number
  stamps: string[]                         // station IDs claimed during trip
  co2SavedKg: number
  createdAt: timestamp
  completedAt: timestamp | null

users/{userId}/trip_summary  (denormalized)
  totalTrips: number
  totalKm: number
  totalCo2Kg: number
  mostVisitedStation: string
  lastUpdated: timestamp
```

**End-station inference (server-side):**
- Look up user's trip history; if same start station + same hour-of-day appears ≥3 times → predict same end.
- Else: use line direction + average commute length (5 stations).
- On heartbeat: refine using current position vs. remaining line distance.

**Validation rules:**
- Only one `in_progress` trip per user. New `start` auto-ends prior.
- `endStation` must be on same line as `startStation` (unless explicit transfer logged).
- Heartbeats older than trip start are rejected.

### 3.4 Task breakdown (≈7 dev-days)

| # | Task | Owner | Days |
|---|------|-------|------|
| 1 | Trip feature module skeleton + state notifier | Sr Flutter | 0.5 |
| 2 | Station geofence repository + load `stations.json` polygons | Sr Flutter | 0.5 |
| 3 | Signal fusion service (TripDetectionService) with unit tests | Sr Flutter | 2 |
| 4 | Native geofencing setup (iOS + Android) via `flutter_background_geolocation` | Sr Flutter | 1 |
| 5 | TripModeShell + adaptive content slot + banner | Mid Flutter | 1.5 |
| 6 | Backend `trips` module + endpoints + inference + tests | Backend | 1.5 |
| 7 | Permission priming UX (extends Phase 4) | Mid Flutter | 0.5 |
| 8 | E2E test with manual trigger + simulator location spoof | QA + Sr Flutter | 1 |

### 3.5 Edge cases & risks

| Case | Mitigation |
|---|---|
| App killed mid-trip | On resume, `GET /api/trips/active` rehydrates state |
| Transfer hub overlapping geofences (Ameerpet) | Use direction + recent history to disambiguate; allow manual line picker |
| User on parallel road by bus/auto | Require platform geofence dwell ≥30s before considering "onTrip" |
| iOS kills background process | Significant location change API wakes app; server-pushed silent push as backup |
| User denies location entirely | Manual mode (ticket-scan + button); still 70% of value preserved |
| GPS spoof for fake trips | Server cross-references trip with QR scan events; reject claims with no scan + impossible speed |

---

## 4. Phase 5.2 — Live Metro Intelligence

**Goal:** Real-time train arrivals, disruptions, crowding, smart routing. Utility = installs.

### 4.1 Product spec

- **Home — "Your Lines" card:** Next 3 trains at saved stations, refreshed every 30s when foreground.
- **Sticky disruption banner:** Pushed via WebSocket, shows severity-tinted banner with tap-to-detail.
- **Journey planner:** Standalone screen — pick from/to, get 3 route options with live timing.
- **Crowding heatmap:** During Trip Mode, see crowd estimate per coach. Tap to report your coach's current crowd.

### 4.2 Frontend architecture

```
lib/features/intelligence/
├── application/
│   ├── live_etas_provider.dart          # StreamProvider polling 30s
│   ├── disruption_provider.dart         # StreamProvider over WS
│   ├── crowding_provider.dart
│   ├── routing_provider.dart
│   └── intelligence_ws_client.dart      # Subscribe/unsubscribe per line
├── domain/
│   ├── train_arrival.dart
│   ├── disruption.dart
│   ├── crowd_level.dart
│   └── route_option.dart
├── data/
│   └── intelligence_api.dart
└── presentation/
    ├── live_etas_card.dart              # Home component
    ├── disruption_banner.dart           # Sticky top banner
    ├── journey_planner_screen.dart
    ├── crowding_report_sheet.dart       # Bottom sheet to submit
    └── crowding_heatmap.dart
```

**Real-time approach:**

| Data | Mechanism | Why |
|---|---|---|
| ETAs | REST polling every 30s when foreground | Simple, cacheable, "fresh enough" |
| Disruptions | WebSocket (room: `line:{lineId}`) | Push critical alerts immediately |
| Crowding | Push via WS when in `train:{trainId}` room | Mid-trip relevance |
| Routing | REST on demand | One-shot query |

### 4.3 Backend architecture

```
backend/modules/intelligence/
├── routes.js
├── service.js
├── sources/
│   ├── data_source.js                   # Interface
│   ├── static_timetable_source.js       # Bootstrap (today)
│   ├── crowdsourced_source.js           # User reports
│   └── partner_feed_source.js           # Future (when partnership lands)
├── cache.js                             # In-memory LRU, 30s TTL
└── crowding_model.js                    # Weighted avg with decay
```

**Endpoints:**

| Method | Path | Purpose |
|---|---|---|
| GET | `/api/intel/etas?stations=miyapur,hitech_city` | Next 3 trains per station per direction |
| GET | `/api/intel/disruptions?lines=yellow,blue` | Active disruptions |
| POST | `/api/intel/crowd-report` | Submit coach crowd level (rate-limited) |
| GET | `/api/intel/crowding/:trainId` | Aggregated crowd estimate per coach |
| GET | `/api/intel/route?from=X&to=Y` | Multi-leg route plan with live timing |
| WS | `event:disruption` | Push when disruption appears/clears |
| WS | `event:crowding_update` | Push to users in train room |

**Crowding model:**
- Each report: `{coachId, crowdLevel: 0..4, userReliabilityScore, ts}`
- Aggregate window: last 5 min.
- Weighted average; decay = `exp(-ageSeconds / 300)`.
- Display only when ≥3 reports OR partner feed available.

**Caching:**
- ETA queries hit Redis (or in-memory LRU) with 30s TTL keyed by `station:line:direction`.
- Disruption list cached in-memory, invalidated on WS publish.

**Data contracts:**

```json
// GET /api/intel/etas
{
  "asOf": "2026-05-18T07:48:00Z",
  "stations": [{
    "stationId": "miyapur",
    "stationName": "Miyapur",
    "arrivals": [
      {
        "trainId": "yellow_07",
        "line": "yellow",
        "direction": "northbound",
        "etaSeconds": 240,
        "crowdLevel": "moderate",
        "confidence": "high"
      }
    ]
  }]
}

// WS event:disruption
{
  "type": "disruption",
  "id": "disrupt_123",
  "severity": "warning",
  "lines": ["yellow"],
  "stations": ["ameerpet"],
  "title": "Delays on Yellow Line",
  "body": "Signal issue causing 5-7 min delays",
  "startedAt": "2026-05-18T07:42:00Z",
  "estimatedClearedAt": "2026-05-18T08:00:00Z"
}
```

### 4.4 Task breakdown (≈7 dev-days)

| # | Task | Owner | Days |
|---|------|-------|------|
| 1 | DataSource interface + StaticTimetableSource (compute schedule from `stations.json`) | Backend | 1 |
| 2 | ETA + disruption + crowd-report + route endpoints | Backend | 1.5 |
| 3 | WS event publishing (disruption + crowding) | Backend | 1 |
| 4 | Frontend: LiveEtasCard on home + 30s polling provider | Mid Flutter | 1 |
| 5 | Frontend: DisruptionBanner + WS client + reconnect logic | Mid Flutter | 1 |
| 6 | Frontend: Journey planner screen | Mid Flutter | 1 |
| 7 | Crowdsourcing UI in Trip Mode + user reliability scoring (backend) | Sr Flutter + Backend | 0.5 |

### 4.5 Edge cases

| Case | Mitigation |
|---|---|
| Partner feed down | Fall back to timetable source (warn confidence: low) |
| WS disconnected | Frontend polls disruption REST endpoint every 60s as backup |
| Single user spams crowd reports | Rate limit: 3 per coach per 10 min; reliability score capped |
| Stations with no upcoming trains (closing time) | Return empty array + "Service ended" message |

---

## 5. Phase 5.3 — Offline-First Tunnel Cache

**Goal:** App keeps working in tunnels. Every read is cached, every write is queued + replayed.

### 5.1 Product spec

- Audio episode plays through tunnel without buffering (pre-cached).
- Trivia answers submitted in tunnel show "Saved" optimistically; sync silently when reconnected.
- Stamp claims in tunnel queue + redeem on exit.
- "✓ Ready for tunnel" badge appears when sufficient content cached.

### 5.2 Frontend architecture

```
lib/services/sync/
├── prefetch_orchestrator.dart           # Central coordinator
├── outbox.dart                          # Persistent queue (SQLite)
├── outbox_client.dart                   # HTTP wrapper that routes through outbox
├── connectivity_watcher.dart            # Online/offline status
├── media_cache.dart                     # Wraps flutter_cache_manager for audio + images
└── background_sync_job.dart             # workmanager/BGTaskScheduler integration
```

**Prefetch policy:**

| Trigger | What's pre-fetched |
|---|---|
| App foreground + good network | Next audio episode + 5 trivia rounds + 2 articles |
| Trip Mode starts | Full predicted trip duration of content (aggressive) |
| Background daily | Today's episode + tomorrow's event metadata + stamp catalog |

**Outbox pattern:**
- All mutating API calls go through `OutboxClient.send(request)`.
- `OutboxClient` attempts network send first. On failure, persists request to local SQLite queue.
- Each request gets a client-generated UUID stored as `Idempotency-Key` header.
- `ConnectivityWatcher` detects reconnect → drains outbox in FIFO order.
- UI gets optimistic state immediately; outbox failures surface as toast after 3 retries.

**SQLite schema (using `sqflite`):**

```sql
CREATE TABLE outbox (
  id TEXT PRIMARY KEY,              -- idempotency key
  method TEXT NOT NULL,
  url TEXT NOT NULL,
  headers TEXT NOT NULL,            -- JSON
  body TEXT,                        -- JSON
  created_at INTEGER NOT NULL,
  retry_count INTEGER DEFAULT 0,
  last_error TEXT
);
```

### 5.3 Backend architecture

**Idempotency:**
- Middleware checks for `Idempotency-Key` header on POST/PATCH/DELETE.
- Looks up `idempotency_keys/{key}` in Firestore.
  - If found: return cached response.
  - If not: process request, then write `{key, statusCode, body, expiresAt: now+24h}`.
- A daily cron job purges expired keys.

**Batch replay endpoint:**

```
POST /api/sync/replay
Headers: Idempotency-Key: {batch_uuid}
Body: { operations: [{method, path, headers, body}] }
Response: { results: [{status, body}] }  // same order
```

Reduces N round-trips after long offline → 1 call.

### 5.4 Task breakdown (≈6 dev-days)

| # | Task | Owner | Days |
|---|------|-------|------|
| 1 | Outbox SQLite schema + OutboxClient + retry/backoff | Sr Flutter | 1.5 |
| 2 | Idempotency middleware (Node) + Firestore key store | Backend | 0.5 |
| 3 | Sync replay batch endpoint | Backend | 0.5 |
| 4 | PrefetchOrchestrator + ConnectivityWatcher | Sr Flutter | 1 |
| 5 | Media cache integration (audio + images) | Mid Flutter | 1 |
| 6 | Background sync job (workmanager + BGTaskScheduler) | Sr Flutter | 1 |
| 7 | "Ready for tunnel" UI indicator | Mid Flutter | 0.25 |
| 8 | E2E test: airplane mode → actions → reconnect → verify replay | QA | 0.25 |

### 5.5 Edge cases

| Case | Mitigation |
|---|---|
| Conflicting writes (offline edit, server changed) | Server returns 409; outbox surfaces conflict to user with merge UI |
| Outbox grows unbounded (user offline for days) | Cap at 1000 entries; drop oldest non-critical |
| Idempotency key collision (unlikely UUID v4) | Server logs + returns 400; client regenerates |
| Background job throttled by OS | Foreground prefetch on app open covers gap |

---

## 6. Phase 6.1 — Station Stamps

**Goal:** Pokémon-style collection mechanic. Auto-claim on station visit during trip, build collections, trade with friends.

### 6.1 Product spec

- Auto-stamp on geofence entry during active trip (no friction).
- Rarity tiers: Common (any station), Rare (transit hubs), Epic (heritage), Legendary (seasonal/limited).
- Collections unlock real rewards (free coffee voucher, AR souvenir, badge).
- Trading: propose stamp-for-stamp swaps with friends.
- Limited-time stamps (Diwali Charminar, etc.) — drives FOMO visits.

### 6.2 Frontend architecture

```
lib/features/stamps/
├── application/
│   ├── stamps_provider.dart             # User's collection
│   ├── collections_provider.dart        # Collection progress
│   ├── trades_provider.dart             # Inbox + outbox
│   └── stamp_claim_listener.dart        # Reacts to trip events
├── domain/
│   ├── stamp.dart
│   ├── collection.dart
│   └── trade.dart
├── data/
│   └── stamps_api.dart
└── presentation/
    ├── stamps_screen.dart               # Grid view; filter by rarity/collection
    ├── collection_detail_screen.dart    # Progress bar + reward preview
    ├── stamp_claim_overlay.dart         # Lottie reveal animation
    ├── trade_propose_screen.dart        # Select stamps to offer/request
    └── trade_inbox_screen.dart          # Pending trades
```

**Claim trigger:** `StampClaimListener` subscribes to `tripStateProvider`. On station enter event during `onTrip` state, fires `POST /api/stamps/claim` (idempotent — replays through outbox if offline).

**Reveal animation:** Full-screen Lottie when first-time claim of a rare/epic/legendary; subtle toast for repeats and commons.

### 6.3 Backend architecture

```
backend/modules/stamps/
├── routes.js
├── service.js
├── catalog.js                           # Loads stamps_catalog.json + seasonal overrides
├── claim_validator.js                   # Anti-abuse checks
└── trades_service.js
```

**Endpoints:**

| Method | Path | Purpose |
|---|---|---|
| POST | `/api/stamps/claim` | Claim a stamp (idempotent) |
| GET | `/api/stamps/mine` | User's collection |
| GET | `/api/stamps/catalog` | Master list (cached client-side, ETag) |
| GET | `/api/collections` | All collections + user progress |
| POST | `/api/trades/propose` | Offer trade |
| POST | `/api/trades/:id/accept` | Accept |
| POST | `/api/trades/:id/decline` | Decline |
| GET | `/api/trades/inbox` | Pending trades |

**Firestore schema:**

```
stamps_catalog/{stampId}
  name: string
  stationId: string
  rarity: 'common' | 'rare' | 'epic' | 'legendary'
  artUrl: string
  collectionIds: string[]
  seasonal: { startsAt?, endsAt? }       # null = always available
  pointsAwarded: number

collections/{collectionId}
  name: string
  requiredStampIds: string[]
  reward: { type: 'voucher' | 'badge' | 'points', value: ... }

users/{userId}/stamps/{stampId}
  count: number
  firstClaimedAt: timestamp
  lastClaimedAt: timestamp
  tripIds: string[]                      # provenance

users/{userId}/collections/{collectionId}
  progress: number                       # count of required stamps owned
  total: number
  completedAt: timestamp | null

trades/{tradeId}
  fromUserId: string
  toUserId: string
  offering: string[]                     # stamp IDs
  requesting: string[]
  status: 'pending' | 'accepted' | 'declined' | 'expired'
  createdAt: timestamp
  resolvedAt: timestamp | null
  version: number                        # optimistic lock
```

**Claim validation:**
1. User must have active trip (`trips/active`).
2. Station must be on the active trip's line.
3. Throttle: max 1 claim per station per user per day (deduped via `lastClaimedAt`).
4. Anti-spoof: reject if last claim was at a station > 50 km away in < 5 min.

**Trade execution (atomic):**
- Wrap in Firestore transaction.
- Re-check both users own offered stamps at execution time.
- Decrement from `from`, increment in `to`, and vice versa.
- Bump `version` field to prevent double-accept.

### 6.4 Task breakdown (≈7 dev-days)

| # | Task | Owner | Days |
|---|------|-------|------|
| 1 | Stamp catalog seed file + Firestore models + admin script | Backend | 1 |
| 2 | Claim endpoint + validation + anti-abuse | Backend | 1 |
| 3 | Collections logic + reward unlock service | Backend | 1 |
| 4 | Trade endpoints + transactional execution | Backend | 1.5 |
| 5 | Frontend stamps screen + collection detail | Mid Flutter | 1.5 |
| 6 | Stamp reveal animation + StampClaimListener wired to trip events | Sr Flutter | 1 |
| 7 | Trade propose + inbox screens | Mid Flutter | 1 |

### 6.5 Edge cases

| Case | Mitigation |
|---|---|
| User claims during non-trip (manual visit) | Allowed but earns 0 points (gated by `?bonus=true` query) |
| Two users trade simultaneously, both accept | Optimistic version lock → second accept gets 409 |
| Seasonal stamp expires mid-claim | Backend rejects if `seasonal.endsAt < now` |
| User gifts entire collection then leaves app | Allowed; trade is intentional transfer |
| GPS spoof teleport | Validator rejects sub-5-min cross-city claims |

---

## 7. Phase 6.2 — Audio Stories

**Goal:** Daily 10-15 min audio episodes synced to commute length, with cross-device resume + lock-screen controls.

### 7.1 Product spec

- "Metro Tales" — daily M-F serialized anthology (10-15 min episodes).
- Auto-plays on Trip Mode start.
- Lock screen + headphone controls.
- Per-second resume across devices.
- Streak: 5 episodes in a row unlocks bonus episode.
- Push notification at user's typical departure time (learned).

### 7.2 Frontend architecture

```
lib/features/audio/
├── application/
│   ├── audio_player_service.dart        # Wraps just_audio + audio_service
│   ├── episode_provider.dart            # Today's episode + backlog
│   ├── playback_position_sync.dart      # Debounced upload every 10s
│   └── audio_streak_provider.dart       # Consecutive episode tracking
├── domain/
│   ├── episode.dart
│   └── playback_position.dart
├── data/
│   └── episodes_api.dart
└── presentation/
    ├── now_playing_card.dart            # Sticky mini player (above bottom nav)
    ├── now_playing_screen.dart          # Full player with chapters + transcript
    ├── episodes_list_screen.dart        # Series backlog
    └── audio_streak_badge.dart
```

**Player stack:**
- `just_audio` for playback (better than `video_player` for audio).
- `audio_service` wraps it to enable background + lock-screen integration.
- Configured for system media controls: play/pause/skip/seek.

**Position sync:**
- Debounced upload every 10s while playing.
- Upload on: pause, end, app background.
- On episode open: fetch position before starting, seek to it.

**Trip Mode integration:**
- When `tripStateProvider` becomes `onTrip` and predicted duration ≥ episode length → auto-play today's episode (with user consent toggle).

### 7.3 Backend architecture

```
backend/modules/episodes/
├── routes.js
├── service.js
├── signed_urls.js                       # R2/S3 signed URL generation
└── streak_service.js
```

**Endpoints:**

| Method | Path | Purpose |
|---|---|---|
| GET | `/api/episodes/today` | Today's release |
| GET | `/api/episodes?series=metro_tales&limit=20` | Backlog |
| GET | `/api/episodes/:id` | Metadata + signed audio URL (1h expiry) |
| POST | `/api/episodes/:id/position` | Update position |
| GET | `/api/episodes/:id/position` | Cross-device resume |

**Firestore + media storage:**

```
episodes/{episodeId}
  series: string
  season: number
  episodeNumber: number
  title: string
  synopsis: string
  durationSeconds: number
  audioStorageKey: string                # e.g. r2://metrosafar-audio/ep_47.m4a
  artUrl: string
  transcript: string
  chapters: [{title, startSeconds}]
  releasedAt: timestamp                  # query gate
  isPremium: boolean

users/{userId}/episode_positions/{episodeId}
  positionSeconds: number
  durationSeconds: number
  completed: boolean
  updatedAt: timestamp

users/{userId}/audio_streak
  consecutiveDays: number
  lastListenedDate: string               # YYYY-MM-DD
```

**Storage:**
- Cloudflare R2 for audio (S3-compatible, no egress fees). $0.015/GB stored, free egress vs S3.
- Audio encoded to AAC 64 kbps (~30 MB for 10 min episode).
- Signed URL generation per request (1h expiry).

**CMS for content team (Phase 6 baseline — script-based; full CMS in Phase 7):**
- A simple Node script `scripts/upload-episode.js` that takes a `.m4a` file + JSON metadata and uploads to R2 + writes Firestore doc.
- Phase 7: replace with Strapi admin UI.

### 7.4 Task breakdown (≈6 dev-days)

| # | Task | Owner | Days |
|---|------|-------|------|
| 1 | Episode model + endpoints + signed URL generation | Backend | 1.5 |
| 2 | R2 bucket setup + upload script + 4 pilot episodes uploaded | Backend + Content | 0.5 |
| 3 | AudioPlayerService + background audio config (iOS + Android) | Sr Flutter | 1.5 |
| 4 | Position sync + cross-device resume | Sr Flutter | 1 |
| 5 | Now Playing card + screen + Trip Mode autoplay | Mid Flutter | 1 |
| 6 | Episode list screen + streak badge | Mid Flutter | 0.5 |

### 7.5 Edge cases

| Case | Mitigation |
|---|---|
| Lost network mid-playback | Continue from local cache; queue position sync |
| iOS background termination | `audio_service` keeps process alive |
| User skips episode | Still log as engagement; doesn't count toward streak |
| Signed URL expires mid-trip | Refresh on 403; player retries seamlessly |
| User opens on second device | Position fetched on episode load, seeks correctly |

---

## 8. Phase 6.3 — Daily Live Events

**Goal:** Scheduled, time-boxed events with all users joining simultaneously. Live leaderboard, real-time presence.

### 8.1 Product spec

- **Morning Brain Buzz** — 8 AM weekdays, 5 trivia questions, 60s total.
- **Power Hour** — 6 PM, 60-min rewards discount.
- **Friday Mega Spin** — once weekly, scheduled spin wheel with jackpot.
- Countdown card on home; push 5 min before; live participant count during.
- Top-N prize structure: top 10 → 200 pts + badge; top 100 → 100 pts; participation → 20 pts.

### 8.2 Frontend architecture

```
lib/features/events/
├── application/
│   ├── events_provider.dart             # Upcoming schedule
│   ├── active_event_provider.dart       # Currently live (subscribes to WS)
│   ├── event_session.dart               # User's answers + score
│   └── event_ws_client.dart
├── domain/
│   ├── event.dart
│   ├── event_question.dart
│   └── leaderboard_entry.dart
├── data/
│   └── events_api.dart
└── presentation/
    ├── event_countdown_card.dart        # Home component
    ├── event_lobby_screen.dart          # 5-min pre-event
    ├── event_play_screen.dart           # Live question UI
    ├── event_results_screen.dart        # Final leaderboard
    └── live_participant_counter.dart
```

**Lock-step play:**
- Server pushes question with `serverTimeMs` + `deadlineMs`.
- Client computes remaining time as `deadlineMs - serverTimeMs - clientOffset` (offset measured at WS handshake).
- All timing comes from server timestamps; client clock is never trusted.

### 8.3 Backend architecture

```
backend/modules/events/
├── routes.js
├── service.js
├── orchestrator.js                      # State machine, ticks events live
├── scheduler.js                         # node-cron jobs
├── question_bank.js                     # Pre-loaded into memory on event start
└── settlement.js                        # Calculate winners + award prizes
```

**Endpoints:**

| Method | Path | Purpose |
|---|---|---|
| GET | `/api/events/schedule` | Next 7 days of events |
| GET | `/api/events/:id` | Event details |
| POST | `/api/events/:id/join` | Register; returns WS room token |
| POST | `/api/events/:id/submit` | Submit answer (REST backup to WS) |
| GET | `/api/events/:id/leaderboard` | Snapshot |
| GET | `/api/events/:id/my-result` | User's final score |

**WebSocket protocol (room: `event:{eventId}`):**

| Direction | Message | Purpose |
|---|---|---|
| S → C | `question` | New question with options + deadline |
| S → C | `reveal` | Show correct answer after deadline |
| S → C | `leaderboard_update` | Throttled to once per 2s |
| S → C | `participant_count` | Live count |
| S → C | `event_end` | Final results |
| C → S | `submit_answer` | `{questionId, answer, clientTimeMs}` |

**Event state machine:**

```
scheduled
  ↓ 5 min before start
lobby_open    (users can join, countdown shown)
  ↓ at start time
live          (questions pushed every 12s; 8s answer + 4s reveal)
  ↓ after last question
ended         (final leaderboard shown for 60s)
  ↓
settled       (prizes distributed, results frozen)
```

**Orchestrator (single Node process for now — adequate to 10k concurrent per event):**
- `node-cron` job runs every minute checking upcoming events.
- 5 min before: transition `scheduled → lobby_open`, broadcast countdown.
- At start: load question bank into memory, transition `lobby_open → live`, start question loop.
- Question loop: push question → wait 8s → push reveal → wait 4s → next.
- At end: snapshot leaderboard → award prizes via service → transition `ended → settled`.

**Firestore schema:**

```
events/{eventId}
  type: 'trivia' | 'spin' | 'power_hour'
  title: string
  scheduledFor: timestamp
  durationSeconds: number
  status: 'scheduled' | 'lobby' | 'live' | 'ended' | 'settled'
  prizeStructure: { top10, top100, participation }
  participantCount: number               # incremented on join
  questionBankId: string

event_questions/{questionBankId}/questions/{questionId}
  prompt: string
  options: string[]
  correctIndex: number
  pointsBase: number
  pointsBonusPerSecondRemaining: number  # for speed bonus

events/{eventId}/participants/{userId}
  score: number
  answers: [{questionId, answer, correct, ms}]
  joinedAt: timestamp

event_results/{eventId}
  leaderboard: [{userId, name, score, rank}]
  settledAt: timestamp
```

**Push notification flow:**
- 24h before: FCM topic broadcast to subscribers of `event_brain_buzz` (opt-in only).
- 5 min before: targeted push to users who joined the last 3 events of this type (retention nudge).
- At event end: personal push to top 10 winners with prize.

### 8.4 Task breakdown (≈8 dev-days)

| # | Task | Owner | Days |
|---|------|-------|------|
| 1 | Event Firestore schema + question bank seed (~50 questions for pilot) | Backend + Content | 1 |
| 2 | Orchestrator state machine + question loop | Backend | 2 |
| 3 | Event REST endpoints (join, submit, schedule, leaderboard) | Backend | 1 |
| 4 | WS room with question push + leaderboard broadcast (throttled) | Backend | 1 |
| 5 | Settlement service (calculate winners, award prizes, persist) | Backend | 0.5 |
| 6 | Frontend: countdown card on home | Mid Flutter | 0.5 |
| 7 | Frontend: lobby + play + results screens | Mid Flutter | 1.5 |
| 8 | WS client + reconnect + leaderboard rendering | Sr Flutter | 1 |
| 9 | Push notification integration (FCM topic + targeted) | Backend | 0.5 |
| 10 | E2E test: pilot Brain Buzz with internal team | All | (in week 8) |

### 8.5 Edge cases

| Case | Mitigation |
|---|---|
| User joins mid-event | Spectator mode (sees questions but can't score), or join with reduced max |
| Network blip during question | REST `submit` as backup to WS; answer buffered locally with deadline check |
| Server clock drift | Use `serverTimeMs` not client clock for all timing decisions |
| Tie-breaking | Earliest correct answer wins (use `ms` field) |
| User answers after deadline (clock skew) | Reject; show "Time's up" UI |
| Orchestrator crash mid-event | State persisted to Firestore every 2s; restart resumes from last snapshot |
| Cheating via REST replay | Idempotency key on submit; one answer per question per user |

---

## 9. Sequencing & week-by-week

```
WEEK 1 — Foundation (cross-cutting)
├─ CC.1  WebSocket gateway        (Backend, 3d)
├─ CC.2  Geofencing native setup  (Sr Flutter, 2d)
├─ CC.3  FCM project + APNS       (Backend, 1d)
├─ CC.4  Feature flag SDK         (Both, 1d)
└─ CC.5  Analytics pipeline live  (Both, 1d)

WEEK 2 — Phase 5 starts
├─ 5.1   Trip module + signal fusion              (Sr Flutter, 3d)
├─ 5.2   DataSource interface + StaticTimetable   (Backend, 1d)
├─ 5.2   ETA + disruption endpoints               (Backend, 2d)
├─ 5.3   Outbox + idempotency middleware          (Both, 2d)
└─ 5.1   Trip endpoints + inference               (Backend, 1.5d)

WEEK 3 — Phase 5 completes
├─ 5.1   TripModeShell + adaptive content slot    (Mid Flutter, 1.5d)
├─ 5.2   LiveEtasCard + DisruptionBanner          (Mid Flutter, 2d)
├─ 5.2   Journey planner screen                    (Mid Flutter, 1d)
├─ 5.3   PrefetchOrchestrator + media cache       (Sr Flutter, 2d)
├─ 5.3   Background sync job                       (Sr Flutter, 1d)
└─ E2E   Trip Mode + offline polish + bug bash    (All, 2d)

WEEK 4 — Phase 5 GA (ramp 1% → 10% → 50%)
├─ Monitor metrics, fix issues
└─ Start Phase 6 prep:
    ├─ 6.1 Catalog seed + Firestore schema        (Backend, 1d)
    └─ 6.2 R2 bucket setup + 4 pilot episodes     (Backend + Content, 1d)

WEEK 5 — Phase 6 starts
├─ 6.1   Claim endpoint + collections + trades    (Backend, 2.5d)
├─ 6.1   Stamps screen + reveal animation         (Mid + Sr Flutter, 2.5d)
├─ 6.2   Episode endpoints + signed URLs          (Backend, 1.5d)
└─ 6.2   AudioPlayerService + background config   (Sr Flutter, 1.5d)

WEEK 6 — Phase 6 continues
├─ 6.1   Trade propose + inbox screens            (Mid Flutter, 1d)
├─ 6.2   Position sync + Now Playing UI           (Mid + Sr Flutter, 2d)
├─ 6.2   Trip Mode autoplay integration           (Sr Flutter, 0.5d)
├─ 6.3   Event schema + orchestrator              (Backend, 3d)
└─ 6.3   First Brain Buzz question bank (50 Qs)   (Content, ongoing)

WEEK 7 — Phase 6 events
├─ 6.3   WS event room + push broadcast           (Backend, 1d)
├─ 6.3   Settlement service                        (Backend, 0.5d)
├─ 6.3   Lobby + play + results screens           (Mid Flutter, 1.5d)
├─ 6.3   WS client + leaderboard rendering        (Sr Flutter, 1d)
├─ 6.3   FCM push integration                      (Backend, 0.5d)
└─ Pilot Brain Buzz with internal team             (All, 1d)

WEEK 8 — Phase 6 GA
├─ Ramp 1% → 100% over 5 days
├─ Daily monitoring; daily live events run
└─ Retro + Phase 7 planning
```

**Buffer:** 1 week recommended at end of Phase 6 for stabilization. So 8 weeks + 1 buffer = ~9 weeks total wall clock with the team described below.

---

## 10. Team RACI

| Role | Phase 5 ownership | Phase 6 ownership |
|---|---|---|
| **Senior Flutter eng** | Trip Mode shell, signal fusion, geofencing native setup, offline outbox | Audio player service, events WS client, stamp claim listener |
| **Mid Flutter eng** | Live ETA UI, journey planner, disruption banner, media cache integration | Stamps screen, trade UI, event lobby + play UI |
| **Backend eng** | Trip endpoints, intelligence module, WS gateway, idempotency middleware | Stamps service, episodes service, events orchestrator |
| **Designer** | Trip Mode flows, ETA card, journey planner, "Ready for tunnel" badge | Stamp reveal animation, event lobby + results, Now Playing |
| **Content lead / PM** | Identify metro authority data partnership | 4 audio episodes ready by Week 5; 50 trivia Qs by Week 6 |
| **QA** | E2E airplane mode flows, Trip Mode device matrix | Stamp claim race conditions, event live load test |

---

## 11. Open questions to resolve before sprint 1

1. **Metro authority data partnership** — Live ETAs depend on official feed. Without it, we ship "expected timetable" only. Who owns this conversation?
2. **`flutter_background_geolocation` license budget** — ~$300 one-time per app. Approved?
3. **Audio storage choice** — Cloudflare R2 ($0 egress, $0.015/GB) vs Firebase Storage (simpler, pricier). Recommend R2.
4. **Content production for Metro Tales** — Who's writing, who's recording, what's the studio cost? Need 4 episodes by Week 5.
5. **FCM project + APNS certs** — Are these set up? Apple Developer account active?
6. **Privacy review** — Trip detection + crowd reporting touches sensitive permissions. Legal sign-off required before GA.
7. **Beta cohort** — Who are the 100-500 Hyderabad users we ramp to first? Office colleagues? Existing high-engagement users?
8. **Monitoring & on-call** — Live events have hard SLA (event must run on time). Who's on call for event launches?

---

## Companion documents

- [PHASE5_PLUS_VISION.md](PHASE5_PLUS_VISION.md) — strategy + 6-month vision
- [PHASE4_PROGRESS.md] — onboarding + l10n + permissions (in flight)
- [PHASE3_COMPLETE_SUMMARY.md](PHASE3_COMPLETE_SUMMARY.md) — wallet + profile
