#!/usr/bin/env bash
#
# Reproducible Play Store release build for MetroSafar.
#
# Every environment-specific value is injected via --dart-define so a build can
# never silently ship the wrong backend or AdMob units. Required env vars (fail
# fast if any are missing):
#
#   METROSAFAR_API_BASE_URL        App backend base URL (home, rewards, etc.)
#   METROSAFAR_ONDC_BASE_URL       ONDC/Beckn backend base URL (ticket booking)
#   ADMOB_APP_ID                   Real AdMob application id (passed to Gradle)
#   ADMOB_ANDROID_BANNER_UNIT_ID   Real banner ad unit id
#   ADMOB_ANDROID_REWARDED_UNIT_ID Real rewarded ad unit id
#   METROSAFAR_MAPS_API_KEY        Google Maps key (optional; only if maps on)
#
# Signing comes from android/key.properties (never committed). The release
# Gradle config fails the build if that file is absent.
#
# Usage:  scripts/build_release.sh           # builds an .aab (Play upload)
#         OUTPUT=apk scripts/build_release.sh # builds a universal .apk

set -euo pipefail

require() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    echo "ERROR: required env var $name is not set." >&2
    exit 1
  fi
}

require METROSAFAR_API_BASE_URL
require METROSAFAR_ONDC_BASE_URL
require ADMOB_APP_ID
require ADMOB_ANDROID_BANNER_UNIT_ID
require ADMOB_ANDROID_REWARDED_UNIT_ID

MAPS_KEY="${METROSAFAR_MAPS_API_KEY:-}"

DEFINES=(
  --dart-define=METROSAFAR_API_BASE_URL="$METROSAFAR_API_BASE_URL"
  --dart-define=METROSAFAR_ONDC_BASE_URL="$METROSAFAR_ONDC_BASE_URL"
  --dart-define=ADMOB_ANDROID_BANNER_UNIT_ID="$ADMOB_ANDROID_BANNER_UNIT_ID"
  --dart-define=ADMOB_ANDROID_REWARDED_UNIT_ID="$ADMOB_ANDROID_REWARDED_UNIT_ID"
  --dart-define=METROSAFAR_MAPS_API_KEY="$MAPS_KEY"
)

# ADMOB_APP_ID is consumed by Gradle (manifest placeholder), not dart-define.
GRADLE_PROPS=(-PADMOB_APP_ID="$ADMOB_APP_ID")

echo "==> flutter pub get"
flutter pub get

echo "==> Building ${OUTPUT:-appbundle} (release)"
if [[ "${OUTPUT:-appbundle}" == "apk" ]]; then
  flutter build apk --release "${DEFINES[@]}" "${GRADLE_PROPS[@]}"
else
  flutter build appbundle --release "${DEFINES[@]}" "${GRADLE_PROPS[@]}"
fi

echo "==> Done."
