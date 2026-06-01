# Phase 5/6 Implementation Status

_Last updated: 2026-05-18_

---

## Legend
- ✅ Done — fully wired and testable
- 🔶 Partial — scaffolded, needs real external integration
- ❌ Not started
- 🟡 Backend-only / no UI yet

---

## Infrastructure

| Item | Status | Notes |
|------|--------|-------|
| Outbox offline queue | ✅ | `lib/services/sync/outbox.dart` — SharedPreferences-backed, 1000-cap, dedup by idempotency key |
| Auto-flush on connectivity change | ✅ | `lib/services/connectivity_watcher.dart` — ConnectivityWatcher singleton, started in `main()` |
| Idempotency-Key on all mutations | ✅ | `BackendService._sendJson` generates `req_<ts>_<rand>` and attaches header |
| Socket.io WebSocket gateway | ✅ | `backend/phase56.js` — rooms: `user:`, `event:`, `line:` |
| RealtimeService (Flutter client) | ✅ | `lib/services/realtime_service.dart` — socket_io_client, auto-reconnect, typed streams |
| Feature flags (env-driven) | ✅ | `backend/phase56.js` FEATURE_FLAG_DEFAULTS — all phase5/6 flags default to `false` |
| FCM push notifications | 🔶 | `lib/services/notification_service.dart` — full mock with TODOs. Needs `firebase_messaging` + GCloud project |
| Analytics (Firebase + Amplitude) | 🔶 | `lib/services/notification_service.dart#AnalyticsMock` — stub with TODOs |
| ONDC Beckn integration | 🔶 | `lib/services/notification_service.dart#OndcStub` — stub. Needs Beckn buyer app registration |
| Cloudflare R2 signed URLs (audio) | 🔶 | `lib/services/notification_service.dart#AudioStorageMock` — stub. Needs R2 bucket + backend endpoint |

---

## Phase 5.1 — Trip Mode

| Item | Status | Notes |
|------|--------|-------|
| TripModeScreen UI | ✅ | `lib/features/trip/presentation/trip_mode_screen.dart` |
| Manual trip start/end | ✅ | Calls `BackendService.startTrip` / `endTrip`, queues offline |
| Backend trip endpoints | ✅ | `backend/phase56.js` — `/api/trips/start`, `/end`, `/active`, `/history` |
| Trip inference (predict end station) | ✅ | `inferTrip()` in backend using historical trips + line position |
| Trip heartbeat | 🟡 | Backend endpoint exists; Flutter side not yet polling |
| Geofencing (auto-detect station entry) | 🔶 | `geofence_service` dep added. **TODO:** native setup — iOS `Info.plist` background modes, Android manifest permissions, zone registration from station catalog |
| Signal fusion (ticket scan + GPS + speed) | ❌ | Architecture in PHASE5_6_IMPLEMENTATION_PLAN.md. Needs TripDetectionService |
| Trip Mode adaptive content slot | ❌ | Spec: show audio/game/quiz based on `remainingMinutes` |
| CO₂ savings card | ✅ | Backend computes `co2SavedKg` per trip and exposes on profile |

---

## Phase 5.2 — Live Metro Intelligence

| Item | Status | Notes |
|------|--------|-------|
| JourneyPlannerScreen | ✅ | `lib/features/intelligence/presentation/journey_planner_screen.dart` |
| intelligence_provider (route, ETAs, disruptions) | ✅ | `lib/features/intelligence/application/intelligence_provider.dart` |
| LiveEtasCard widget | ✅ | `lib/features/intelligence/presentation/live_etas_card.dart` |
| DisruptionBanner widget | ✅ | `lib/features/intelligence/presentation/disruption_banner.dart` |
| Backend ETA / disruption / route endpoints | ✅ | `backend/phase56.js` — `/api/intel/etas`, `/disruptions`, `/route` |
| Real-time disruption push (WS) | 🔶 | RealtimeService wires `disruption:update` stream. **TODO:** backend to emit on data change |
| Crowd report submit | ✅ | `BackendService.submitCrowdReport` — queues offline |
| ONDC live feed | 🔶 | Stub in `notification_service.dart`. Needs Beckn registration |
| Per-line WS room subscription | ✅ | `RealtimeService.subscribeToLine()` + backend `subscribe:line` handler |

---

## Phase 5.3 — Offline Cache

| Item | Status | Notes |
|------|--------|-------|
| Outbox queue (mutations) | ✅ | All `queueOffline: true` calls enqueue when offline |
| Read-through cache (GET) | ✅ | `BackendService._getMap` caches every successful GET to SharedPreferences |
| Auto-flush on reconnect | ✅ | `ConnectivityWatcher` triggers `BackendService.flushOutbox()` |
| Cache invalidation strategy | 🔶 | Current: each write overwrites the matching cacheKey. No TTL yet. |
| Retry with backoff | 🔶 | Flush retries but no exponential backoff — retries on next connectivity event |

---

## Phase 6.1 — Stamps

| Item | Status | Notes |
|------|--------|-------|
| StampsScreen UI | ✅ | `lib/features/stamps/presentation/stamps_screen.dart` |
| stamps_provider | ✅ | `lib/features/stamps/application/stamps_provider.dart` |
| Backend stamp endpoints | ✅ | `backend/phase56.js` — `/api/stamps/catalog`, `/mine`, `/claim` |
| Stamp claim (offline-safe) | ✅ | `BackendService.claimStamp` has `queueOffline: true` |
| Collections page | 🟡 | `BackendService.getCollections` exists. No dedicated UI screen yet |
| QR-based station stamp scan | ❌ | Spec: scan station QR → deep link → auto-claim stamp |
| Per-station QR code (beta acquisition) | ❌ | Spec: `/stamp/:stationId` deep link + install attribution |

---

## Phase 6.2 — Audio Stories

| Item | Status | Notes |
|------|--------|-------|
| AudioStoriesScreen with real player | ✅ | `lib/features/audio/presentation/audio_stories_screen.dart` — just_audio + now-playing bar |
| AudioPlayerService | ✅ | `lib/services/audio_player_service.dart` — play, pause, seek, stop |
| MetroAudioHandler (audio_service) | ✅ | Lock-screen controls bridge; wired to just_audio |
| Cross-device resume (position sync) | ✅ | `getEpisodePosition` on play start; `updateEpisodePosition` every 10 s + on stop |
| Offline position queue | ✅ | `updateEpisodePosition` uses `queueOffline: true` |
| episodes_provider | ✅ | `lib/features/audio/application/episodes_provider.dart` |
| Backend episode endpoints | ✅ | `backend/phase56.js` — `/api/episodes`, `/today`, `/:id`, `/:id/position` |
| Background playback (fully native) | 🔶 | `audio_service` dep added + handler created. **TODO:** call `AudioService.init()` in `main()` with `AndroidNotificationConfig`. Requires Android service manifest entry + iOS background modes |
| Real audio files (R2) | 🔶 | Backend returns `example.com` URLs. `AudioStorageMock.getSignedUrl` stub in place. **TODO:** upload pilot `.m4a` files to R2 bucket + update db.json |
| Pilot episode content | 🔶 | 2 placeholder episodes in backend DEFAULT_EPISODES. Needs real recordings |

---

## Phase 6.3 — Live Events

| Item | Status | Notes |
|------|--------|-------|
| EventsScreen with real UI | ✅ | `lib/features/events/presentation/events_screen.dart` — status chips, join, live question flow |
| Answer selection UI | ✅ | Tap-to-select options with correct/wrong highlight post-answer |
| Server-timing lock-step | ✅ | Countdown derived from `serverTimeMs + deadlineMs` — never client clock |
| WS question push (event:question) | ✅ | `RealtimeService.eventQuestions()` stream; `_EventCardState._onQuestionPushed` |
| WS status push (event:status) | ✅ | `RealtimeService.eventStatusChanges()` stream |
| events_provider (schedule) | ✅ | `lib/features/events/application/events_provider.dart` |
| Event orchestrator state machine | ✅ | `backend/phase56.js` `startEventOrchestrator()` — node-cron, lobby_open → live → question loop → ended → settled |
| Backend event endpoints | ✅ | `backend/phase56.js` — `/schedule`, `/:id`, `/join`, `/submit`, `/leaderboard` |
| Leaderboard screen | 🔶 | Endpoint exists (`/api/events/:id/leaderboard`). No dedicated Flutter screen |
| My result screen | 🔶 | Endpoint `/api/events/:id/my-result` exists. No Flutter UI |
| Power Hour (non-trivia events) | 🔶 | Orchestrator skips non-trivia events. Power Hour needs custom logic |

---

## What to do next (priority order)

### High — needed before internal beta

1. **Background audio native wiring**: `AudioService.init()` in `main()`, Android `AndroidManifest.xml` service entry, iOS `Info.plist` background modes (`audio`).
2. **Geofencing native setup**: Register station zones from `stations.json`; iOS always-on location permission; Android foreground service.
3. **Real audio assets**: Record / commission 3 pilot episodes (8–14 min each); upload to R2; update `audioUrl` in `db.json`.
4. **FCM production wiring**: `firebase_messaging` package, `flutterfire configure`, upload token to backend, handle foreground + background messages.
5. **Deep-link QR stamp scanning**: iOS Universal Links + Android App Links for `/stamp/:stationId`; auto-claim on install.

### Medium — V1.0 quality

6. **TripDetectionService** signal fusion (ticket scan + geofence + speed heuristic).
7. **Trip Mode adaptive content slot** — switch card by `remainingMinutes`.
8. **Leaderboard screen** for events post-settlement.
9. **Collections UI** for stamps.
10. **Analytics wiring** — swap `AnalyticsMock` for `firebase_analytics` once consent flow is approved by legal.

### Low — post-V1.0

11. ONDC live feed (Beckn buyer app registration required).
12. Cache TTL strategy (currently no expiry on SharedPreferences cache).
13. Exponential backoff in outbox flush.
14. Power Hour event type (non-trivia orchestration).
15. A/B testing framework (GrowthBook SDK).

---

## Key file map

```
lib/
  main.dart                         — app entry, ConnectivityWatcher start
  app/router.dart                   — GoRouter, all routes
  config/api_config.dart            — base URL config

  services/
    backend_service.dart            — all API calls, offline queue
    connectivity_watcher.dart       — auto-flush outbox on reconnect
    realtime_service.dart           — socket_io_client WS client
    audio_player_service.dart       — just_audio + audio_service bridge
    notification_service.dart       — FCM mock + Analytics mock + ONDC stub
    sync/outbox.dart                — offline mutation queue

  features/
    home/                           — home screen, streak, wallet
    play/                           — games hub
    learn/                          — articles, surveys
    wallet/                         — points, rewards
    profile/                        — settings, legal, support
    onboarding/                     — onboarding flow
    trip/                           — TripModeScreen
    intelligence/                   — journey planner, ETAs, disruptions
    stamps/                         — stamp catalog + claim
    audio/                          — Metro Tales audio player
    events/                         — Live Events + real-time Q&A

backend/
  server.js                         — Express app + orchestrator wiring
  phase56.js                        — all Phase 5/6 routes + WS + orchestrator
  db.json                           — static content (articles, games, rewards…)
  stations.json                     — Hyderabad Metro station catalog
```
