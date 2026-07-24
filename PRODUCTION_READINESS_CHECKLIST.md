# Production Readiness Checklist

## Fixed in this pass

- [x] Prevent startup crash when the splash logo asset is missing
- [x] Register previously missing named routes to avoid runtime navigation failures
- [x] Wire `GamesProvider` into the app so trivia can resolve its provider
- [x] Replace random booking fare calculation with deterministic station-based fare logic
- [x] Load persisted tickets into the home screen provider on startup
- [x] Replace Android package/application id with `com.tlventures.metrosafar`
- [x] Add backend-driven privacy policy, terms, support, and disclosure screens
- [x] Add widget and integration test coverage for booking, permissions, navigation, and persistence

## Fixed since the deep audit (verified 2026-07-24)

- [x] Real Firebase Auth — `lib/services/auth_service.dart` uses `FirebaseAuth`
      (`signInWithEmailAndPassword`, `getIdToken()`); tokens are held in the
      platform Keychain/Keystore by the SDK, not `SharedPreferences`. The old
      `mock_token_*` flow is gone.
- [x] Release signing wired — `android/app/build.gradle.kts` reads a gitignored
      `android/key.properties`; `.gitignore` excludes `key.properties`, `*.jks`,
      `*.keystore`. Only the real keystore + `key.properties` remain to be
      created (see `RELEASE_SETUP.md`).
- [x] Maps API key moved out of source — Android manifest declares
      `com.google.android.geo.API_KEY` injected from a `manifestPlaceholder`
      (sourced from `key.properties` / `MAPS_API_KEY`), empty by default.
- [x] Backend claim idempotency — Firestore transactions + idempotency records
      in place (`backend/server.js:563`, `2232`, `2258`).

## Still required before Play Store release

- [ ] Create the real upload keystore and `android/key.properties` (steps in
      `RELEASE_SETUP.md`) — release builds are debug-signed until then.
- [ ] Provide a real, package-restricted Google Maps key before shipping any map
      screen (`google_maps_flutter` is a dependency but no `GoogleMap` widget is
      rendered yet, so it is not a runtime crash today). iOS `AppDelegate` wiring
      still pending — see `RELEASE_SETUP.md`.
- [ ] Add and declare real app assets, or remove unused asset references/constants
- [ ] Review the included compliance audit and complete the final Play policy
      submission materials

## Validation status

- `flutter build apk --release` succeeds (verified 2026-07-24; 80 MB APK,
  debug-signed) and installs on a physical device (Samsung SM-F415F, Android 12).
- `flutter analyze` previously reported lint and safety issues — re-run before submission.
