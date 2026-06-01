# MetroSafar — Frontend & Backend Launch Readiness (Deep Audit)

Date: 2026-05-19
Companion docs: `LAUNCH_READINESS_VISUAL_REVIEW.md`, `PRODUCTION_READINESS_CHECKLIST.md`

This pass goes one layer deeper than the screenshot / high-level reviews. It walks the actual Flutter code (`lib/`) and the Cloud Run backend (`backend/`) and lists issues those reviews did **not** cover.

---

## FRONTEND (`lib/`)

### 🛑 Blockers

1. **No global error boundary.** `lib/main.dart` has no `runZonedGuarded`, no `FlutterError.onError`, no `PlatformDispatcher.onError`. Unhandled exceptions die silently. Combined with Crashlytics being unwired, you have zero production crash visibility — you will not know the app is crashing for users.
2. **Auth tokens stored in `SharedPreferences`.** `lib/services/auth_service.dart:40,75` writes `mock_token_*` to plain prefs. Must move to `flutter_secure_storage` (Keychain / Keystore) before any real auth is added. Currently a P0 the moment auth becomes real.
3. **Google Maps API key not configured natively.** `google_maps_flutter` is in `pubspec.yaml` but no `AndroidManifest.xml` `<meta-data>` and no `Info.plist` `GMSApiKey` entry. Any map widget will fail at runtime with a cryptic native error.
4. **Riverpod override silently skipped if init throws.** `lib/main.dart:36-45` — if `AudioService.init()` throws, the audioHandler provider is never overridden; downstream reads will hit an uninitialized state for the whole app session with no surfaced error.

### ⚠️ Important

5. **Stream subscription leak in events.** `lib/features/events/presentation/events_screen.dart:100,123` — `_joinEvent` reassigns `_wsSub` without cancelling the prior subscription. Joining multiple events stacks listeners.
6. **TabController length race.** `lib/features/wallet/presentation/wallet_screen.dart:27-41` builds `_tabController` from `_categories.length` synchronously, then `_syncTabController()` recreates it if categories arrive late. If indices change between rebuilds you get an `IndexError`. Use `DefaultTabController` or await categories first.
7. **Onboarding flag is in-memory.** `lib/app/router.dart:17-35` reads a mutable global `_onboardingComplete`. Sign-out + sign-in keeps the flag true. Move to `SharedPreferences` and re-check on every route guard.
8. **`setState` after dispose risk.** `fetchWallet`, `fetchTransactions` and similar have no cancellation token. Navigating away during a slow call resolves the Future on a disposed widget.
9. **Rebuild storms in HomeScreen.** `lib/features/home/presentation/home_screen.dart:35-39` fires 5+ async fetches in `initState` via microtasks; no dedup. Orientation changes and tab returns re-trigger everything.
10. **`pubspec.yaml` declares no `assets:` block.** Any bundled image is loading from network only — slows cold start, eats data.
11. **20+ `print()` calls in production paths** (`auth_service.dart`, `location_service.dart`, `ticket_provider.dart`, …). Replace with `debugPrint` or a logger; release logs are user-visible via `adb logcat` and they're noisy.
12. **`cached_network_image` in pubspec but unused.** Images are not cached → scroll jank on lists. Either use it or remove the dep.
13. **No retry / offline UI.** When the backend returns 500 or is unreachable, screens show a generic "Could not load" with no retry button and no offline banner. UX dead-ends instantly.
14. **Legacy `ChangeNotifier` without dispose.** `lib/providers/user_provider.dart` accumulates listeners across screen rebuilds. Migrate to Riverpod `StateNotifier`.

### 📝 Polish

15. **Unnecessary `compute()` for small JSON.** `lib/services/ticket_service.dart` spawns isolates for sub-1MB payloads — isolate spawn (>50ms) costs more than the parse.
16. **No semantic labels** on bottom-nav icons / cards. Screen readers say "button, button, button".
17. **No request concurrency cap.** Home fires 5+ parallel calls. Slow networks compound this — add a small queue.
18. **Dart SDK constraint `^3.7.2`** isn't pinned to a major. Pin for reproducible CI builds.
19. **`audio_service` wired but no real content path** — dead weight in the APK until episodes are uploaded.
20. **No backend cache invalidation.** `backend_service.dart` caches by key indefinitely. Stale data persists until app restart.

---

## BACKEND (`backend/`, Express + Cloud Run, asia-south1)

### 🛑 Blockers

1. **Hardcoded WebSocket secret fallback.** `phase56.js:653,668` —
   ```js
   const secret = process.env.METROSAFAR_WS_SECRET || 'local-dev-ws-secret-change-me';
   ```
   If the env var is missing on Cloud Run, this string **becomes the production signing key**. Anyone reading the source can forge tokens. Remove the fallback and crash on boot if unset.
2. **No idempotency on any claim endpoint.** Streak claim (`server.js:437-470`), reward redeem (`server.js:299-337`), scratch cards, quests, daily spin, activity-events (`server.js:814-874`) — all are read-modify-write with `merge: true`, no Firestore transactions, no idempotency keys. Two concurrent requests can both pass the "already claimed?" check and both award. Daily 500-point cap is bypassable the same way.
3. **Zero server-side trip / geofence validation.** `phase56.js:217-273` (`startTrip`) and `319-403` (`endTrip`) accept whatever `startStationId` / `endStationId` the client sends. Heartbeats store lat/lng but never validate route plausibility. The entire rewards economy is client-trusted — a trivial Postman script farms points without leaving the house.
4. **"Auth" is an unverified header.** `server.js:160` — `req.clientId = normalizeClientId(req.header('X-Client-Id'))`. No signature, no JWT verification, no session. Sniff or guess a clientId and you are that user. This is the single biggest security hole.
5. **CORS wide open.** `server.js:156` uses `cors()` with default `origin: '*'`; Socket.io is the same. Any website on the internet can call the API as any user (combined with #4 above).
6. **No input validation framework.** No joi/zod/express-validator anywhere. Endpoints accept arbitrary JSON. Combined with the lack of idempotency, the attack surface is large.
7. **Audio URLs are `example.com` placeholders** (`phase56.js:24,43,475,1088`). All audio play attempts will 404 in production. Signed URL generation is a stub returning `token=dev_signed`.

### ⚠️ Important

8. **Socket.io subscriptions are unauthenticated by ownership.** `phase56.js:1322-1328` lets any connected socket join any `event:*` / `train:*` / `line:*` room. Any user can passively snoop event broadcasts (which include other users' answers/scores).
9. **WebSocket token lifetime + no revocation.** 15-minute tokens are fine, but there's no revoke list — a stolen token is good for its full lifetime.
10. **No rate limiting.** `express-rate-limit` is not installed. Streak claim, scratch, redeem are all spammable. With #2 above, this becomes free point printing.
11. **No Helmet / security headers.** No HSTS, no `X-Content-Type-Options`, no frame-options. Cloud Run terminates TLS but the app should still set HSTS for defense-in-depth.
12. **`console.log` / `console.error` everywhere** with no structured logger (pino/winston), no request IDs, no correlation. Debugging a prod incident will be painful and PII may end up in Cloud Logging unredacted.
13. **No `/healthz` or readiness endpoint** wired for Cloud Run probes. Cold-start failures will be invisible until users complain.
14. **`db.json` baked into the container.** Even read-only it means content changes (questions, quests, rewards) require a redeploy. Either move to Firestore collections or add an admin endpoint with proper auth.
15. **`EVENT_QUESTION_BANK`** in `phase56.js:56-81` has only 3 questions and is hardcoded. Live events will feel obviously canned within one session.
16. **Cron job fires every minute** for event status checks. Fine at small scale, but on Cloud Run with min-instances=0 you risk cold starts skipping ticks. Move scheduled work to Cloud Scheduler + a dedicated endpoint.

### 📝 Polish

17. **Zero backend tests.** No `*.test.js`, no Jest config. At least smoke tests for the claim endpoints would catch the idempotency bugs above.
18. **No OpenAPI / contract spec.** Frontend and backend can drift silently.
19. **Dependencies fresh** (Express 4.21.2, Socket.io 4.8.3, Firestore 7.11.2) — good. Add `npm audit` to CI.
20. **No feature-flag system actually wired** despite `METROSAFAR_FEATURE_FLAGS` env var existing — can't kill-switch a broken feature in prod without redeploy.
21. **`cors@2.8.5` is from 2015** — stable, but consider switching to a maintained alternative or pinning explicitly.

---

## Combined verdict

The earlier reviews flagged that the app **looks** unfinished. This pass shows the underlying systems are also unfinished:

- **Frontend**: missing crash visibility, insecure token storage, several leak/race paths that will manifest as random crashes once usage scales.
- **Backend**: the rewards economy can be farmed from a terminal, identity is asserted by an unsigned header, secrets have insecure fallbacks, and core endpoints have no idempotency.

If you launch as-is, expect:
1. A class of users discovering they can mint points trivially and the leaderboard becoming meaningless within days.
2. No crash data to diagnose the inevitable production issues.
3. App Store / Play rejections on visible bugs (already covered) before the security issues even get a chance to bite.

### Critical-path before submission

Frontend (≈3 days): error boundary + Crashlytics, secure token storage, Maps key config, fix tab controller + onboarding flag, kill `print()`s, add retry UI.

Backend (≈5 days): remove WS secret fallback, switch to Firestore transactions for all claims, add idempotency keys, server-side trip validation (even a basic "stations must be on the same line + time window plausible" check), real auth (JWT or Firebase Auth verifyIdToken), restrict CORS, add joi/zod validation on claim endpoints, add `express-rate-limit` + helmet, add `/healthz`.

Total additional engineering: **~2 weeks** on top of the visual + store-policy work already outstanding.
