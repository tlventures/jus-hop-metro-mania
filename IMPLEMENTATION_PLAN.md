# MetroSafar — Launch Implementation Plan

Date: 2026-05-19  
Covers: P0 (Blockers), P1 (Important), P2 (Polish)  
Companion: `LAUNCH_READINESS_FRONTEND_BACKEND.md`, `LAUNCH_READINESS_VISUAL_REVIEW.md`

---

## Priority definitions

| Level | Meaning | Target |
|---|---|---|
| **P0** | App will be rejected or security is actively exploitable | Fix before any external testing |
| **P1** | Feature is broken, crashes are likely, UX is confusing | Fix before store submission |
| **P2** | Polish, edge cases, performance | Fix before or shortly after v1.0 |

---

## P0 — Blockers (estimated ~6 days total)

### P0-1 · Android release signing  
**File:** `android/app/build.gradle.kts:40`  
**Problem:** Release builds use debug signing config. Play Store rejects them.  
**Fix:**
1. Generate a production upload keystore: `keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload`
2. Store it outside the repo (e.g., `~/.android/upload-keystore.jks`)
3. Create `android/key.properties` (git-ignored):
   ```
   storePassword=<password>
   keyPassword=<password>
   keyAlias=upload
   storeFile=<path>/upload-keystore.jks
   ```
4. In `build.gradle.kts`, add a proper `release` signing config that reads `key.properties`.
5. Add `android/key.properties` to `.gitignore`.

**Effort:** 1 hour

---

### P0-2 · Remove hardcoded WebSocket secret fallback  
**File:** `backend/phase56.js:653, 668`  
**Problem:** `|| 'local-dev-ws-secret-change-me'` means any deployment missing the env var uses a public secret.  
**Fix:**
```js
// Replace both lines with:
const secret = process.env.METROSAFAR_WS_SECRET;
if (!secret) throw new Error('METROSAFAR_WS_SECRET env var is required');
```
Set `METROSAFAR_WS_SECRET` in Cloud Run env vars (use Google Secret Manager, reference in Cloud Run service YAML).

**Effort:** 30 minutes

---

### P0-3 · Firestore transactions for all claim endpoints  
**Files:** `backend/server.js:437-470` (streak), `299-337` (rewards), `543-570` (scratch), `814-874` (activity-events); `backend/phase56.js` (quests, stories, surveys, spin)  
**Problem:** All reward/claim operations are read-modify-write with `merge:true`. Two concurrent requests both pass "already claimed?" → double awards. Daily 500-point cap is bypassable.  
**Fix pattern** for every claim endpoint:
```js
// Replace getUserState + saveUserState pattern with:
await firestore.runTransaction(async (txn) => {
  const ref = firestore.collection('metrosafar_users').doc(clientId);
  const doc = await txn.get(ref);
  const state = doc.exists ? buildDerivedProfile(doc.data()) : defaultUserState(clientId);

  // --- guard: already claimed? ---
  if (state.lastStreakClaimAt && /* 24h check */) {
    throw new AlreadyClaimedError('Already claimed');
  }

  // --- mutate state ---
  const next = { ...state, streakDay: state.streakDay + 1, lastStreakClaimAt: now };

  txn.set(ref, buildDerivedProfile({ ...next, lastUpdated: nowIso() }));
  return next;
});
```
Apply the same pattern to: streak, rewards, scratch cards, quests, stories, surveys, daily spin, activity-events.

**Effort:** 1 day

---

### P0-4 · Server-side trip validation  
**File:** `backend/phase56.js:217-273` (startTrip), `319-403` (endTrip)  
**Problem:** Client-supplied station IDs are accepted without any verification. Users can fake rides to earn points from their sofa.  
**Minimum viable fix (v1.0):**
1. In `startTrip`: verify `startStationId` exists in `stations.json`. If not → 400.
2. In `endTrip`: verify `endStationId` exists. Check `tripStartedAt` is within last 3 hours (prevents time-travelling claims). Require at least 1 heartbeat on record.
3. In `tripHeartbeat`: store lat/lng but also check it's plausibly near a Hyderabad metro station (bounding box check — simple, not GPS-precise, but blocks remote faking).

**Full fix (v1.1):** GPS-trace validation using a polyline corridor around each metro line.

**Effort:** 4 hours (minimal), 2 days (full)

---

### P0-5 · Input validation on all write endpoints  
**Files:** `backend/server.js`, `backend/phase56.js`  
**Problem:** No joi/zod. Clients can send unexpected payloads.  
**Fix:**
1. `npm install zod` (no extra deps, tree-shakeable)
2. Create `backend/validation.js` with schemas for each endpoint body:
   ```js
   const { z } = require('zod');
   const startTripSchema = z.object({
     startStationId: z.string().min(1).max(80),
     endStationId:   z.string().min(1).max(80),
   });
   // Add schemas for: endTrip, claimStreak, redeemReward, submitGame, etc.
   ```
3. Add a thin middleware helper:
   ```js
   function validate(schema) {
     return (req, res, next) => {
       const result = schema.safeParse(req.body);
       if (!result.success) return res.status(400).json({ error: result.error.flatten() });
       req.body = result.data;
       next();
     };
   }
   ```
4. Apply to every POST/PATCH route.

**Effort:** 3 hours

---

### P0-6 · Lock down CORS  
**Files:** `backend/server.js:156`, `backend/phase56.js` (Socket.io)  
**Problem:** `cors()` defaults to `origin: '*'`.  
**Fix:**
```js
const ALLOWED_ORIGINS = (process.env.ALLOWED_ORIGINS || '').split(',').filter(Boolean);
app.use(cors({
  origin: (origin, cb) => {
    if (!origin || ALLOWED_ORIGINS.includes(origin)) return cb(null, true);
    cb(new Error('Not allowed by CORS'));
  },
  credentials: true,
}));
// Socket.io:
cors: { origin: ALLOWED_ORIGINS, methods: ['GET', 'POST'] }
```
Set `ALLOWED_ORIGINS` in Cloud Run: your Flutter app's deep-link scheme + any web admin URL. For a pure mobile app with no web component, you can restrict to same-project origins only.

**Effort:** 30 minutes

---

### P0-7 · Global Flutter error boundary  
**File:** `lib/main.dart`  
**Problem:** Unhandled exceptions are invisible. No crash reporting.  
**Fix:**
```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    // When Crashlytics is wired: FirebaseCrashlytics.instance.recordFlutterFatalError(details);
    debugPrint('[FlutterError] ${details.summary}');
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('[PlatformError] $error\n$stack');
    // FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    return true;
  };

  await runZonedGuarded(() async {
    await initializeServices();
    await router_module.initializeRouter();
    // ... rest of main
    runApp(ProviderScope(child: const MetroSafarApp()));
  }, (error, stack) {
    debugPrint('[ZoneError] $error\n$stack');
    // FirebaseCrashlytics.instance.recordError(error, stack, fatal: false);
  });
}
```

**Effort:** 1 hour

---

### P0-8 · Move auth tokens to flutter_secure_storage  
**File:** `lib/services/auth_service.dart`  
**Problem:** `mock_token_*` written to `SharedPreferences`. Plain prefs are readable on rooted devices. `flutter_secure_storage` is already in `pubspec.yaml` — just not used.  
**Fix:** Replace every `prefs.setString(Constants.authTokenKey, ...)` and `prefs.getString(Constants.authTokenKey)` with `FlutterSecureStorage` read/write. Keep user profile JSON in `SharedPreferences` (not a secret); only the token moves.
```dart
final _secureStorage = const FlutterSecureStorage();
// write:
await _secureStorage.write(key: 'auth_token', value: token);
// read:
final token = await _secureStorage.read(key: 'auth_token');
// delete (logout):
await _secureStorage.delete(key: 'auth_token');
```

**Effort:** 1 hour

---

### P0-9 · Fix onboarding route guard (in-memory global)  
**File:** `lib/app/router.dart:17`  
**Problem:** `_onboardingComplete` is a file-level `bool`. Sign-out does not reset it → re-opened app skips onboarding. Also, if `initializeRouter()` is called once at launch, changes post-launch are invisible.  
**Fix:**
```dart
// Remove the global bool. Read SharedPreferences on every redirect evaluation:
redirect: (context, state) async {
  final prefs = await SharedPreferences.getInstance();
  final done = prefs.getBool('hasCompletedOnboarding') ?? false;
  if (!done && state.fullPath != '/onboarding') return '/onboarding';
  return null;
},
// In setOnboardingComplete():
Future<void> setOnboardingComplete() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool('hasCompletedOnboarding', true);
}
// On logout: prefs.remove('hasCompletedOnboarding')
```

**Effort:** 1 hour

---

### P0-10 · Fix visible debug tooltip overlay  
**Problem:** Every screen shows a floating "Home" or "Ride" dark pill above the bottom nav. This is Flutter's `NavigationDestination` default tooltip text appearing stuck.  
**Fix in `lib/app/router.dart` inside `_NavShell.build`:**
```dart
NavigationDestination(
  icon: Icon(Icons.home_outlined),
  selectedIcon: Icon(Icons.home),
  label: 'Home',
  tooltip: '',  // ← suppress the floating tooltip
),
// Apply tooltip: '' to all 5 NavigationDestination entries
```

**Effort:** 15 minutes

---

### P0-11 · Fix Silver tier label contradiction  
**Problem:** Home and Wallet show badge "Silver" but progress text says "345 points to Silver tier". With 155 points, `getTier()` in `server.js:30` returns `'Silver'` (< 300 threshold returns Silver, not Gold/Platinum). The tier name itself is confusing — the lowest tier is called Silver.  
**Options:**
- **Option A (rename tiers):** Change tiers to Bronze/Silver/Gold/Platinum at the 0/300/600 thresholds. Update `getTier()` in `server.js` + all Flutter tier display widgets.
- **Option B (fix progress copy):** If Silver is intentionally the base tier, change copy to "345 points to Gold tier" to show the *next* tier.  

Option B is the fastest fix. In the wallet/home widgets that display progress, pass `nextTierName` and `pointsToNextTier` from the API instead of hardcoding "Silver".

**Backend change (`server.js`):**
```js
function getNextTier(points) {
  if (points < 300) return { name: 'Gold', pointsNeeded: 300 - points };
  if (points < 600) return { name: 'Platinum', pointsNeeded: 600 - points };
  return { name: null, pointsNeeded: 0 };
}
// Add to buildDerivedProfile:
nextTier: getNextTier(points),
```
**Flutter change:** Update `WalletScreen` and `HomeScreen` to read `nextTier.name` and `nextTier.pointsNeeded` from the wallet response.

**Effort:** 2 hours

---

### P0-12 · Fix empty gray block in Wallet screen  
**File:** `lib/features/wallet/presentation/wallet_screen.dart`  
**Problem:** A large gray placeholder is visible below "Take Surveys". Likely an uninitialised widget or failed image container.  
**Fix:** Audit the widget tree in `WalletScreen` for:
- `Container()` or `SizedBox` with a height but no content
- `CachedNetworkImage` with no `placeholder` or `errorWidget` that collapses to gray
- Any video player (`VideoPlayerController`) initialised but not yet ready that renders gray

Replace all bare containers with conditional rendering or proper skeleton/shimmer.

**Effort:** 1-2 hours (after identifying the specific widget)

---

## P1 — Important (estimated ~5 days total)

### P1-1 · Rate limiting on claim endpoints  
**File:** `backend/server.js`, `backend/phase56.js`  
**Fix:**
```
npm install express-rate-limit
```
```js
const rateLimit = require('express-rate-limit');
const claimLimiter = rateLimit({ windowMs: 60_000, max: 10, keyGenerator: (req) => req.clientId });
const generalLimiter = rateLimit({ windowMs: 60_000, max: 60, keyGenerator: (req) => req.clientId });
app.use('/api/', generalLimiter);
app.use('/api/streak', claimLimiter);
app.use('/api/rewards/redeem', claimLimiter);
app.use('/api/scratch-cards', claimLimiter);
app.use('/api/quests', claimLimiter);
```

**Effort:** 1 hour

---

### P1-2 · Add Helmet security headers  
**File:** `backend/server.js`  
```
npm install helmet
```
```js
const helmet = require('helmet');
app.use(helmet());
// After cors() call, before routes
```

**Effort:** 30 minutes

---

### P1-3 · Structured backend logging + request IDs  
**File:** `backend/server.js`, `backend/phase56.js`  
**Fix:**
```
npm install pino pino-http
```
```js
const pino = require('pino');
const pinoHttp = require('pino-http');
const logger = pino({ level: process.env.LOG_LEVEL || 'info' });
app.use(pinoHttp({ logger }));
// Replace all console.log/console.error with req.log.info / req.log.error
```
Cloud Logging automatically indexes structured JSON; request IDs make incident tracing possible.

**Effort:** 3 hours

---

### P1-4 · Add /healthz readiness endpoint  
**File:** `backend/server.js`  
The existing `/health` endpoint exists but only returns static JSON. Add a proper readiness check:
```js
app.get('/healthz', async (_req, res) => {
  try {
    await firestore.collection('metrosafar_users').limit(1).get();
    res.json({ status: 'ready', firestore: 'ok' });
  } catch {
    res.status(503).json({ status: 'unavailable', firestore: 'error' });
  }
});
```
Set in Cloud Run service config: `livenessProbe.httpGet.path: /healthz`.

**Effort:** 30 minutes

---

### P1-5 · Fix stream subscription leak in EventsScreen  
**File:** `lib/features/events/presentation/events_screen.dart:100,123`  
**Fix:**
```dart
Future<void> _joinEvent(String eventId) async {
  _wsSub?.cancel();  // ← add this before reassigning
  _wsSub = realtimeService.eventStream(eventId).listen((_) { ... });
}
```

**Effort:** 15 minutes

---

### P1-6 · Fix TabController length race in WalletScreen  
**File:** `lib/features/wallet/presentation/wallet_screen.dart:27-41`  
**Fix:** Use `DefaultTabController` and derive length reactively, or await category data before initializing:
```dart
// Option: guard _syncTabController to only run if vsync is still alive
void _syncTabController(List<String> categories) {
  if (!mounted || categories.isEmpty || _categories == categories) return;
  setState(() {
    _tabController?.dispose();
    _categories = List.unmodifiable(categories);
    _tabController = TabController(length: _categories.length, vsync: this);
  });
}
```

**Effort:** 1 hour

---

### P1-7 · Cancel async calls on screen dispose  
**Files:** `lib/features/wallet/application/wallet_provider.dart`, home/quest/streak providers  
**Fix pattern:** Add a `CancelToken` (from Dio) or an `isMounted` guard:
```dart
// In each StateNotifier:
bool _disposed = false;

@override
void dispose() {
  _disposed = true;
  super.dispose();
}

Future<void> fetchWallet() async {
  // ...after await:
  if (_disposed) return;
  state = state.copyWith(wallet: data);
}
```

**Effort:** 2 hours

---

### P1-8 · Add offline banner + retry UI  
**Files:** `lib/services/connectivity_watcher.dart` (already exists), each feature screen  
**Fix:**
1. `ConnectivityWatcher` is already wired. Create a shared `OfflineBanner` widget:
   ```dart
   class OfflineBanner extends ConsumerWidget {
     @override
     Widget build(BuildContext context, WidgetRef ref) {
       final online = ref.watch(connectivityProvider);
       if (online) return const SizedBox.shrink();
       return Container(
         color: Colors.red.shade700,
         child: const Text('No internet connection', ...),
       );
     }
   }
   ```
2. Add `OfflineBanner` at top of each major screen's Sliver list.
3. In each error state widget, add a "Retry" `TextButton` that calls the fetch action.

**Effort:** 3 hours

---

### P1-9 · Remove all print() statements  
**Scope:** Run `grep -rn "print(" lib/ --include="*.dart"` and replace bare `print(` with `debugPrint(` (auto no-ops in release mode). Already uses `if (kDebugMode) print(...)` in `auth_service.dart` — consolidate to `debugPrint` everywhere.

**Effort:** 1 hour

---

### P1-10 · Fix content clipping behind bottom nav  
**File:** `lib/app/router.dart` (`_NavShell`), all Sliver-based screens  
**Problem:** List content scrolls behind the `NavigationBar`.  
**Fix:** Add `MediaQuery.of(context).padding.bottom` + nav bar height to the scroll view's bottom padding. Simplest: wrap `child` in `SafeArea(bottom: true)` inside `_NavShell`, or use `SliverPadding` at the bottom of each `CustomScrollView`:
```dart
SliverPadding(padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom + 80)),
```

**Effort:** 1 hour

---

### P1-11 · Wire cached_network_image  
**Problem:** `cached_network_image` is in `pubspec.yaml` but unused. All images load on every build.  
**Fix:** Search for `Image.network(` and `NetworkImage(` and replace with `CachedNetworkImage(...)`. Add error/placeholder builders:
```dart
CachedNetworkImage(
  imageUrl: url,
  placeholder: (context, url) => const ShimmerBox(),
  errorWidget: (context, url, error) => const Icon(Icons.broken_image),
)
```

**Effort:** 2 hours

---

### P1-12 · Google Maps API key native configuration  
**Problem:** `google_maps_flutter` in pubspec, no native key configured.  
**Fix:**
- **Android** `android/app/src/main/AndroidManifest.xml` inside `<application>`:
  ```xml
  <meta-data android:name="com.google.android.geo.API_KEY"
             android:value="${MAPS_API_KEY}"/>
  ```
  Add to `android/app/build.gradle.kts`:
  ```kotlin
  manifestPlaceholders["MAPS_API_KEY"] = System.getenv("MAPS_API_KEY") ?: ""
  ```
- **iOS** `ios/Runner/AppDelegate.swift`:
  ```swift
  GMSServices.provideAPIKey(ProcessInfo.processInfo.environment["MAPS_API_KEY"] ?? "")
  ```
- Store the actual key in CI environment / Xcode build settings, not in source.
- Restrict the key in GCP console to the app's bundle IDs and signing certificates.

**Effort:** 2 hours

---

### P1-13 · Add account deletion (required by Apple + Play)  
**Backend:** Add `DELETE /api/account` endpoint:
```js
app.delete('/api/account', async (req, res, next) => {
  try {
    await firestore.collection('metrosafar_users').doc(req.clientId).delete();
    res.json({ deleted: true });
  } catch (error) { next(error); }
});
```
**Frontend:** Add "Delete Account" option in `lib/features/profile/presentation/profile_screen.dart` with a confirmation dialog → call backend → clear local storage → navigate to `/onboarding`.

**Effort:** 3 hours

---

### P1-14 · Audio URLs: resolve or disable  
**File:** `backend/phase56.js:24,43`  
**Option A (launch without audio):** Add a feature flag `audio_stories_enabled: false` to the feature-flags endpoint. In Flutter `AudioStoriesScreen`, check the flag and show "Coming soon" if disabled.  
**Option B (launch with audio):** Upload real MP3 files to R2/GCS bucket, replace placeholder `example.com` URLs with real signed URLs, wire the signing function.  
**Recommendation:** Ship v1.0 with Option A (flag off), do Option B for v1.1.

**Effort:** 1 hour (Option A)

---

## P2 — Polish (estimated ~3 days)

### P2-1 · Add semantic labels to bottom nav and icon buttons  
Add `semanticLabel` to all `Icon` widgets inside `NavigationDestination` and action buttons. Required for screen reader (TalkBack / VoiceOver) support.

### P2-2 · Backend: add backend tests  
Scaffold Jest with at minimum:
- Claim endpoint idempotency test (call twice, expect second call to fail)
- Trip validation test (unknown stationId → 400)
- Daily cap test (award beyond 500 → capped)
`npm install --save-dev jest supertest`

### P2-3 · Add Crashlytics / Firebase  
Wire `firebase_crashlytics` properly. The `FlutterError.onError` and `runZonedGuarded` stubs from P0-7 are already set up to accept Crashlytics calls — add the actual `FirebaseCrashlytics.instance.record*` calls once Firebase is initialised.

### P2-4 · Cache invalidation in BackendService  
Add TTL to cache keys:
```dart
final _cacheExpiry = <String, DateTime>{};
static const _ttl = Duration(hours: 6);

Future<Map<String, dynamic>?> _getMap(String key) async {
  final expiry = _cacheExpiry[key];
  if (expiry != null && DateTime.now().isAfter(expiry)) {
    _cache.remove(key);
    _cacheExpiry.remove(key);
  }
  // ... existing read
}
// On write: _cacheExpiry[key] = DateTime.now().add(_ttl);
```

### P2-5 · Remove dead `lib/screens/` files  
Delete the 8 unreachable legacy screen files (home_screen.dart, profile_screen.dart, etc.) that predate the current feature-based structure. Run `flutter build apk` before and after to confirm binary shrinks.

### P2-6 · Feature flag kill-switch wired to features  
`METROSAFAR_FEATURE_FLAGS` env var exists but the flag values are not actually consulted by the trip, geofence, and audio features. Add a backend endpoint `GET /api/feature-flags` and read it at app launch to gate:
- `audio_stories_enabled`
- `geofencing_enabled`
- `live_events_enabled`

### P2-7 · OpenAPI / contract spec  
Add an `openapi.yaml` to `backend/`. Can be auto-generated from Zod schemas (P0-5) via `zod-to-openapi`. Prevents silent Flutter/backend drift.

### P2-8 · Replace emoji icons with brand iconography  
Replace 🔥📖🧠📍🎡🗺️🎬 list-item icons with SVG or `font_awesome_flutter` icons for consistent rendering across Android versions.

### P2-9 · Bottom nav active-tab color consistency  
Active tab currently renders with red fill; rest of app is purple. Change the `NavigationBarTheme.indicatorColor` in `lib/design_system/theme.dart` to match `AppColors.primary` (purple).

### P2-10 · Fix localization wiring  
`lib/main.dart` uses `GlobalMaterialLocalizations` but the app-generated `AppLocalizations` delegate is not in `localizationsDelegates`. All 6 `.arb` files are dead code.
```dart
localizationsDelegates: const [
  AppLocalizations.delegate,  // ← add this
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
],
```
Then replace hardcoded English strings screen by screen.

---

## Execution order

```
Week 1 — P0s
  Day 1: P0-2 (WS secret), P0-6 (CORS), P0-10 (tooltip), P0-7 (error boundary)
  Day 2: P0-1 (Android signing), P0-8 (secure storage), P0-9 (onboarding guard)
  Day 3: P0-3 (Firestore transactions — streak + rewards)
  Day 4: P0-3 continued (scratch, quests, spin, activity-events)
  Day 5: P0-4 (trip validation), P0-5 (input validation / zod)
  Day 6: P0-11 (tier label fix), P0-12 (wallet gray block)

Week 2 — P1s
  Day 7:  P1-1 (rate limiting), P1-2 (helmet), P1-4 (healthz), P1-9 (remove prints)
  Day 8:  P1-5 (stream leak), P1-6 (TabController), P1-7 (cancel on dispose)
  Day 9:  P1-8 (offline banner + retry UI), P1-10 (nav clipping)
  Day 10: P1-11 (cached images), P1-12 (Maps API key)
  Day 11: P1-13 (account deletion), P1-14 (audio flag-off)
  Day 12: P1-3 (structured logging), integration testing

Week 3 — P2s + release prep
  Day 13: P2-3 (Crashlytics), P2-5 (dead code), P2-9 (color fix), P2-8 (icons)
  Day 14: P2-2 (backend tests), P2-4 (cache TTL), P2-6 (feature flags)
  Day 15: P2-1 (a11y labels), P2-10 (localization wiring start)
  Day 16: Release build verification (clean APK + IPA), store listing assets
  Day 17: Buffer / fixes from test feedback
```

---

## Definition of "submittable"

- [ ] All P0s resolved and verified on a physical device
- [ ] Android release AAB signed and uploadable to Play Console (internal testing track)
- [ ] iOS IPA signed and uploadable to TestFlight
- [ ] No crash in the first 60 seconds of a fresh install
- [ ] Tier badge matches tier name and progress text
- [ ] Account deletion works end-to-end
- [ ] Streak and reward claims cannot be double-claimed (verified with parallel requests)
- [ ] All visible debug overlays removed
- [ ] Privacy policy + terms URLs live and reachable
- [ ] Play Data Safety form truthfully completable
