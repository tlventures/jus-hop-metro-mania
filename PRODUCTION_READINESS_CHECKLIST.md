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

## Still required before Play Store release

- [ ] Replace debug release signing with a real upload keystore
- [ ] Move Google Maps API keys out of source and lock them down by app/package restrictions
- [ ] Replace the remaining mocked auth flow with a real authenticated backend workflow
- [ ] Add and declare real app assets, or remove unused asset references/constants
- [ ] Verify release build and Play Console requirements on a machine with enough free disk space
- [ ] Review the included compliance audit and complete the final Play policy submission materials

## Validation status

- `flutter analyze` previously reported lint and safety issues
- `flutter test` could not complete because the machine was out of disk space
