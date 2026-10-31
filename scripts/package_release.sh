#!/bin/bash
# Maintainer-only distribution. Fails closed without Developer ID and notarization.
set -euo pipefail
FAR_FLOW_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$FAR_FLOW_ROOT"
: "${FAR_FLOW_SIGN_IDENTITY:?Set FAR_FLOW_SIGN_IDENTITY to your Developer ID Application identity}"
: "${FAR_FLOW_NOTARY_PROFILE:?Set FAR_FLOW_NOTARY_PROFILE to an existing notarytool Keychain profile}"
FAR_FLOW_APP="$FAR_FLOW_ROOT/build/DerivedData/Build/Products/Release/Far Flow.app"
[ -d "$FAR_FLOW_APP" ] || { printf 'Run scripts/build.sh first.\n' >&2; exit 1; }
FAR_FLOW_VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$FAR_FLOW_APP/Contents/Info.plist")"
mkdir -p build/Release
FAR_FLOW_STAGE="$(mktemp -d "$FAR_FLOW_ROOT/build/Release/package.XXXXXX")"
trap 'rm -rf "$FAR_FLOW_STAGE"' EXIT
ditto "$FAR_FLOW_APP" "$FAR_FLOW_STAGE/Far Flow.app"
FAR_FLOW_APP="$FAR_FLOW_STAGE/Far Flow.app"
for FAR_FLOW_FRAMEWORK in "$FAR_FLOW_APP"/Contents/Frameworks/*.framework; do
  codesign --force --sign "$FAR_FLOW_SIGN_IDENTITY" --options runtime --timestamp "$FAR_FLOW_FRAMEWORK"
done
codesign --force --sign "$FAR_FLOW_SIGN_IDENTITY" --options runtime --timestamp --entitlements FarFlow/FarFlow.entitlements "$FAR_FLOW_APP"
codesign -dv "$FAR_FLOW_APP" 2>&1 | grep -q '^Authority=Developer ID Application:' || { printf 'A Developer ID Application signature is required.\n' >&2; exit 1; }
codesign --verify --deep --strict "$FAR_FLOW_APP"
ditto -c -k --keepParent "$FAR_FLOW_APP" "$FAR_FLOW_STAGE/submission.zip"
xcrun notarytool submit "$FAR_FLOW_STAGE/submission.zip" --keychain-profile "$FAR_FLOW_NOTARY_PROFILE" --wait
xcrun stapler staple "$FAR_FLOW_APP"
xcrun stapler validate "$FAR_FLOW_APP"
spctl --assess --type execute --verbose=2 "$FAR_FLOW_APP"
FAR_FLOW_ZIP="$FAR_FLOW_ROOT/build/Release/Far-Flow-$FAR_FLOW_VERSION-arm64.zip"
ditto -c -k --keepParent "$FAR_FLOW_APP" "$FAR_FLOW_ZIP"
shasum -a 256 "$FAR_FLOW_ZIP" > "$FAR_FLOW_ZIP.sha256"
printf 'Notarized package ready for a second-Mac acceptance check: %s\n' "$FAR_FLOW_ZIP"
