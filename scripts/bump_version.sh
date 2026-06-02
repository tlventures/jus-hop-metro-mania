#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# bump_version.sh
#
# Increments the patch (y) component of the Flutter version in pubspec.yaml.
# Format: major.minor.patch+buildNumber  →  e.g. 1.0.3+4
#
# Usage:
#   ./scripts/bump_version.sh            # patch bump:  1.0.0 → 1.0.1
#   ./scripts/bump_version.sh --minor    # minor bump:  1.0.x → 1.1.0
#   ./scripts/bump_version.sh --major    # major bump:  1.x.y → 2.0.0
#   ./scripts/bump_version.sh --dry-run  # print what would change, don't write
#
# The build number always increments by 1 regardless of which segment bumps.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

PUBSPEC="$(dirname "$0")/../pubspec.yaml"

# ── Parse arguments ──────────────────────────────────────────────────────────
BUMP="patch"
DRY_RUN=false
for arg in "$@"; do
  case "$arg" in
    --major)   BUMP="major" ;;
    --minor)   BUMP="minor" ;;
    --patch)   BUMP="patch" ;;
    --dry-run) DRY_RUN=true ;;
    *) echo "Unknown argument: $arg"; exit 1 ;;
  esac
done

# ── Read current version ─────────────────────────────────────────────────────
CURRENT=$(grep '^version:' "$PUBSPEC" | sed 's/version: *//')
# e.g. "1.0.0+1"
VERSION_NAME="${CURRENT%%+*}"   # "1.0.0"
BUILD_NUM="${CURRENT##*+}"      # "1"

IFS='.' read -r MAJOR MINOR PATCH <<< "$VERSION_NAME"

# ── Calculate new version ─────────────────────────────────────────────────────
case "$BUMP" in
  major) MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0 ;;
  minor) MINOR=$((MINOR + 1)); PATCH=0 ;;
  patch) PATCH=$((PATCH + 1)) ;;
esac

NEW_BUILD=$((BUILD_NUM + 1))
NEW_VERSION="${MAJOR}.${MINOR}.${PATCH}+${NEW_BUILD}"
NEW_VERSION_NAME="${MAJOR}.${MINOR}.${PATCH}"

echo "  current : $CURRENT"
echo "  new     : $NEW_VERSION  (bump: $BUMP)"

if [ "$DRY_RUN" = true ]; then
  echo "  [dry-run] pubspec.yaml NOT updated."
  exit 0
fi

# ── Write new version ─────────────────────────────────────────────────────────
if [[ "$OSTYPE" == "darwin"* ]]; then
  sed -i '' "s/^version: .*/version: $NEW_VERSION/" "$PUBSPEC"
else
  sed -i "s/^version: .*/version: $NEW_VERSION/" "$PUBSPEC"
fi

echo "  ✅ pubspec.yaml updated → version: $NEW_VERSION"
