# MetroSafar — Production Gap Analysis
_Generated: 2026-05-18 · Compared against PHASE3_COMPLETE_SUMMARY.md + PHASE5_PLUS_VISION.md_

---

## Analyzer status
**0 issues** (down from 131 earlier this session). All deprecations, unused variables, and lint warnings resolved.

---

## What is genuinely complete

| Area | Status | Evidence |
|---|---|---|
| Design System (tokens, theme, Material 3 light/dark) | ✅ | `lib/design_system/` — tokens, theme, game_shell, app_scaffold |
| 5-tab bottom nav shell + GoRouter | ✅ | `lib/app/router.dart` — ShellRoute + first-run redirect |
| 5 games (Spin, Trivia, Sudoku, Word, City Explorer) | ✅ | `lib/features/play/games/` — all 5 screens |
| Streak + daily claim | ✅ | `streak_provider.dart` + home screen |
| Daily quests | ✅ | `quest_provider.dart` + home screen |
| Learn Hub (Articles / Surveys / Stories) | ✅ | Full Phase 3 content delivery |
| Wallet + rewards redemption | ✅ | `wallet_screen.dart`, `wallet_provider.dart` |
| Profile screen + language selector | ✅ | `profile_screen.dart`, `language_selector_screen.dart` |
| Onboarding flow (5 screens + first-run detection) | ✅ | `lib/features/onboarding/` — all 5 screens, router redirect |
| Privacy consent screen | ✅ | `privacy_consent_screen.dart` |
| Analytics service stub | ✅ | `analytics_service.dart` — consent-gated, ready to wire Firebase |
| Trip Mode UI + manual start/end | ✅ | `trip_mode_screen.dart` + backend `/api/trips/*` |
| Journey Planner (route + ETAs + disruptions) | ✅ | `journey_planner_screen.dart`, `intelligence_provider.dart` |
| Live ETAs card + disruption banner | ✅ | `live_etas_card.dart`, `disruption_banner.dart` |
| Offline outbox queue | ✅ | `lib/services/sync/outbox.dart` |
| Auto-flush on reconnect (ConnectivityWatcher) | ✅ | `connectivity_watcher.dart`, started in `main()` |
| WebSocket client (RealtimeService) | ✅ | `realtime_service.dart` — socket_io_client, typed streams |
| Stamps catalog + claim | ✅ | `stamps_screen.dart`, `stamps_provider.dart` |
| Audio Stories screen + player | ✅ | `audio_stories_screen.dart`, `audio_player_service.dart` |
| Events screen + live Q&A flow | ✅ | `events_screen.dart` — server-timing, answer UI, WS push |
| Backend event orchestrator (node-cron) | ✅ | `backend/phase56.js startEventOrchestrator()` |
| ARB translation files (6 languages) | ✅ | `lib/l10n/app_{en,hi,ta,te,kn,mr}.arb` |
| iOS location permission strings | ✅ | Info.plist has NSLocationWhenInUse + NSLocationAlwaysAndWhenInUse |
| RenderFlex overflow fixes | ✅ | Wrap quest chips, Expanded progress bars, LayoutBuilder wallet |

---

## Gaps — by severity

### 🔴 Critical (blocks usable app)

#### 1. Localization is ARB-only — strings are NOT wired into the UI
- **What's missing:** `flutter_localizations` SDK dep in `pubspec.yaml`, `localizationsDelegates` and `supportedLocales` in `MaterialApp`, and zero screens use `AppLocalizations.of(context)`.
- **Current effect:** The language selector UI appears to work but changes nothing. All 6 `.arb` files are unused.
- **Fix:** Add to `pubspec.yaml` under `flutter:`:
  ```yaml
  flutter:
    generate: true  # already present
  ```
  Add to `dependencies:`:
  ```yaml
  flutter_localizations:
    sdk: flutter
  ```
  Add to `MaterialApp.router` in `main.dart`:
  ```dart
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: ref.watch(localeProvider),
  ```
  Then replace all hardcoded strings in screens with `AppLocalizations.of(context)!.key`.

#### 2. Background audio is non-functional
- **What's missing:** `AudioService.init()` is NOT called in `main()`. The TODO comment in `audio_player_service.dart:201` confirms this.
- **Current effect:** Audio plays in foreground only. Lock-screen controls don't appear. App resuming from background loses playback position.
- **Android:** No `FOREGROUND_SERVICE` permission or `<service>` manifest entry for the audio handler.
- **iOS:** No `UIBackgroundModes: [audio]` in `Info.plist`.
- **Fix (3 steps):**
  1. Uncomment `AudioService.init()` block in `audio_player_service.dart` and call it from `main()`.
  2. Add to `android/app/src/main/AndroidManifest.xml`:
     ```xml
     <uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
     <service android:name="com.ryanheise.audioservice.AudioServiceBackground" android:taskAffinity="" android:exported="true"/>
     ```
  3. Add to `ios/Runner/Info.plist`:
     ```xml
     <key>UIBackgroundModes</key>
     <array><string>audio</string></array>
     ```

#### 3. Trip Mode trips on itself with 3 `Row` widgets and 0 `Expanded`/`Flexible`
- **What's missing:** `trip_mode_screen.dart` has 3 `Row`s with 0 expansion guards. On narrow phones (360 dp) these will overflow.
- **Fix:** Read the file and wrap any fixed-width sibling elements in `Expanded` or use `Wrap`.

---

### 🟠 High (feature gaps visible to users)

#### 4. Station stamp collections have no UI
- `BackendService.getCollections()` exists; backend endpoint exists; but there is no Flutter screen.
- **Fix:** Create `lib/features/stamps/presentation/collections_screen.dart` — a grid of collection progress cards, each showing N/M stamps earned and the reward to unlock.

#### 5. Event leaderboard has no UI
- `/api/events/:id/leaderboard` endpoint exists; no Flutter screen.
- Users who complete an event see no ranking.
- **Fix:** Add a `_LeaderboardSheet` bottom sheet shown after event settlement.

#### 6. Trip Mode shows same content regardless of remaining trip time
- PHASE5_PLUS_VISION.md spec: show audio episode if >20 min, trivia if 8–20 min, scratch card if <8 min.
- **What exists:** Static content layout regardless of `remainingMinutes`.
- **Fix:** Add `_contentForTrip(int remainingMinutes)` switch in `trip_mode_screen.dart`.

#### 7. Trip heartbeat not polling
- Backend `/api/trips/heartbeat` exists; Flutter never calls it during an active trip.
- Without it the server can't infer trip position or auto-end stale trips.
- **Fix:** Add a periodic timer in `trip_state_provider.dart` that calls `BackendService.sendTripHeartbeat()` every 30 s while `tripState.isActive`.

#### 8. Geofencing not native-registered
- `geofence_service: ^6.0.0+1` is in `pubspec.yaml` but no zone registration code exists.
- Without it, Trip Mode auto-detect and stamp auto-claim don't work.
- **Fix (minimum viable):** On app start, read `stations.json`, register geofences for each station with a 100 m radius. Wire the geofence enter callback to `StampsProvider.claimStamp()` and `TripStateProvider.startTripAtStation()`.

---

### 🟡 Medium (quality / polish)

#### 9. Analytics mock never fires real events
- `AnalyticsMock.log()` in `notification_service.dart` and `AnalyticsService.logEvent()` in `analytics_service.dart` are both stubs printing to `debugPrint`.
- Screens call neither consistently — article reads, game completions, and quest completions all fire against different stubs.
- **Fix:** Consolidate to one `AnalyticsService` (delete `AnalyticsMock`). Wire `firebase_analytics` once the Firebase project is configured.

#### 10. FCM is fully mocked
- `NotificationService` in `notification_service.dart` is a stub.
- No push token is registered on the backend → live event countdowns, disruption alerts, and episode drops never reach the device.
- **Fix:** Add `firebase_messaging` dep, run `flutterfire configure`, uncomment the TODO block in `NotificationService.init()`.

#### 11. Legacy `lib/screens/` folder is dead code
- `lib/screens/games/metro_trivia_screen.dart`, `sudoku_game.dart`, `word_puzzle_screen.dart`, `city_explorer_screen.dart` are old pre-refactor files that duplicate `lib/features/play/games/`.
- `lib/screens/home_screen.dart`, `profile_screen.dart`, `rewards_screen.dart`, `loyalty_program_screen.dart` etc. are also legacy.
- None are reachable from the router. They inflate the binary and confuse contributors.
- **Fix:** Delete `lib/screens/` directory. Confirm nothing imports from it first with `grep -r "lib/screens" lib/`.

#### 12. Onboarding language selection doesn't feed into MaterialApp locale
- `language_selector_screen.dart` calls `ref.read(localeProvider.notifier).setLocale()`, which updates `localeProvider`.
- `MaterialApp` doesn't consume `localeProvider` (see gap #1) so the locale switch has no effect at runtime.
- Blocked on fix #1.

#### 13. `DropdownButtonFormField.initialValue` doesn't actually control selected value on rebuild
- Both `journey_planner_screen.dart:150` and `trip_mode_screen.dart:211` now use `initialValue` (fixed this session).
- `initialValue` only sets the **initial** state — if the parent rebuilds with a new `value`, it won't update.
- Consider switching to a `StatefulWidget` that holds the current selection, or use `DropdownButton` directly with a controlled `value` field.

#### 14. No cache TTL — SharedPreferences can serve stale data indefinitely
- `BackendService._getMap` caches every successful GET with no expiry.
- A user who was offline for 2 days will see outdated articles/events.
- **Fix:** Store `{data, cachedAt}` pair; treat entries older than N minutes as stale and re-fetch in background.

#### 15. Outbox retry has no backoff
- `ConnectivityWatcher` calls `flushOutbox()` immediately on every reconnect.
- If the server is still down, all queued items fail silently and re-queue; the next reconnect triggers another flood.
- **Fix:** Add exponential backoff with jitter in `outbox.dart` (2 s, 4 s, 8 s… cap 60 s).

---

### ⚪ Low / Post-V1.0 (matches PHASE5_6_STATUS "Low" list)

| Item | Notes |
|---|---|
| QR deep-link stamp scanning | Needs iOS Universal Links + Android App Links config |
| TripDetectionService signal fusion | Ticket scan + geofence + accelerometer heuristic |
| Power Hour event type | Orchestrator currently skips non-trivia events |
| ONDC Beckn live feed | Requires buyer app registration |
| A/B testing (GrowthBook) | Needed before any ramp of Trip Mode or live events |
| Subscription billing (Razorpay) | Phase 8 — Pass+ monetization |
| Social layer (friends, route-mates) | Phase 7 |
| Content CMS (Strapi/Sanity) | Needed once daily episode cadence begins |
| Year-in-review / Metro Diary | Phase 8 |
| Real audio assets | 3 pilot episodes needed; currently placeholder URLs |

---

## Priority order to unblock internal beta

1. **Wire l10n into MaterialApp** — critical for all non-English markets (10 hours)
2. **Background audio native setup** — 3 native config changes, then uncomment AudioService.init() (4 hours)
3. **Fix trip_mode_screen overflow** — read + fix 3 Row widgets (1 hour)
4. **Trip heartbeat polling** — 20-line change in trip_state_provider (1 hour)
5. **Collections screen** — new screen, ~150 lines (3 hours)
6. **Event leaderboard bottom sheet** — ~100 lines (2 hours)
7. **Trip adaptive content slot** — switch block in trip_mode_screen (2 hours)
8. **Geofencing zone registration** — register from stations.json on startup (3 hours)
9. **FCM wiring** — `flutterfire configure` + uncomment TODO (2 hours + GCloud setup)
10. **Delete dead `lib/screens/` folder** — cleanup (30 min)

**Estimated total to beta-ready: ~28 hours of focused work**

---

## What PHASE3_COMPLETE_SUMMARY.md claims vs reality

Everything Phase 3 claims is present and correct. Phase 3 is 100% implemented.

## What PHASE5_PLUS_VISION.md expects vs reality

| Vision feature | Reality |
|---|---|
| Trip Mode foundation | ✅ UI done; ❌ auto-detect, ❌ adaptive content |
| Live Metro Intelligence | ✅ Journey planner + ETAs; 🔶 real-time push partial |
| Offline-first cache | ✅ outbox + read cache; 🔶 no TTL, no backoff |
| Station Stamps | ✅ UI + backend; ❌ geofence auto-claim, ❌ collections UI, ❌ QR deep-link |
| Audio Stories | ✅ player UI; 🔶 background playback broken, no real assets |
| Daily Live Events | ✅ orchestrator + real-time Q&A; 🔶 no leaderboard UI |
| Social layer (Phase 7) | ❌ not started |
| Metro Pass+ subscription (Phase 8) | ❌ not started |
| Year-in-Review (Phase 8) | ❌ not started |
| Pan-India localization | ✅ ARB files; ❌ not wired into UI |
| Analytics pipeline | 🔶 stub only |
| FCM push | 🔶 stub only |
| A/B testing (GrowthBook) | ❌ not started |
