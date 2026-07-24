# Release Setup — Signing & API Keys

The release build reads all secrets from `android/key.properties`, which is
**gitignored** (see `.gitignore`). Nothing sensitive lives in source. Copy the
template and fill it in:

```bash
cp android/key.properties.example android/key.properties
```

## 1. Release keystore (hard blocker for Play Store upload)

Until `android/key.properties` exists, `flutter build apk --release` falls back
to the **debug** signing key. Debug-signed artifacts install fine on a test
device but **cannot be uploaded to Play**.

Generate an upload keystore once:

```bash
keytool -genkey -v -keystore ~/upload-keystore.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

Then set `storeFile`, `storePassword`, `keyAlias`, `keyPassword` in
`android/key.properties`. `android/app/build.gradle.kts` picks these up
automatically for `buildTypes.release`.

Keep the `.jks` file and passwords backed up somewhere safe — losing the upload
key means you can no longer publish updates to the same Play listing.

## 2. Google Maps API key

`google_maps_flutter` is a dependency. No `GoogleMap` widget renders one yet,
but the moment a map screen ships it will crash at runtime without a native key.
The Android manifest already declares `com.google.android.geo.API_KEY`, injected
from a `manifestPlaceholder`.

Supply the key by any one of:

- `mapsApiKey=...` in `android/key.properties` (recommended — one secrets file), or
- `flutter build apk --release -PMAPS_API_KEY=...`, or
- `MAPS_API_KEY=... flutter build apk --release`

Restrict the key in Google Cloud Console to the app's package name
(`com.tlventures.metrosafar`) and SHA-1 of the signing cert.

### iOS (when an iOS map ships)

iOS is not yet wired. Add to `ios/Runner/AppDelegate.swift`:

```swift
import GoogleMaps
// inside didFinishLaunchingWithOptions, before super:
GMSServices.provideAPIKey("<IOS_MAPS_KEY>")
```

Run `pod install` in `ios/` first so the `GoogleMaps` pod is present, otherwise
the `import` will not compile. This step was intentionally left out of this
change so it can be verified against a real iOS build.
