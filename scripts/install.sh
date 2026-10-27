#!/bin/bash
set -euo pipefail
FAR_FLOW_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FAR_FLOW_APP="$FAR_FLOW_ROOT/build/DerivedData/Build/Products/Release/Far Flow.app"
FAR_FLOW_DEST="${FAR_FLOW_INSTALL_DIR:-/Applications}/Far Flow.app"
if [ ! -d "$FAR_FLOW_APP" ]; then printf 'Run scripts/build.sh first.\n' >&2; exit 1; fi
if pgrep -x 'Far Flow' >/dev/null; then printf 'Quit Far Flow before installing a replacement.\n' >&2; exit 1; fi
codesign --verify --deep --strict "$FAR_FLOW_APP"
# Stage into an empty bundle. ditto directly over an older .app merges obsolete
# icon/resources into it, even when the current build no longer contains them.
mkdir -p "$(dirname "$FAR_FLOW_DEST")"
FAR_FLOW_STAGE="$(mktemp -d "$(dirname "$FAR_FLOW_DEST")/.FarFlow-install.XXXXXX")"
trap 'rm -rf "$FAR_FLOW_STAGE"' EXIT
ditto "$FAR_FLOW_APP" "$FAR_FLOW_STAGE/Far Flow.app"
codesign --verify --deep --strict "$FAR_FLOW_STAGE/Far Flow.app"
FAR_FLOW_PREVIOUS=''
if [ -d "$FAR_FLOW_DEST" ]; then
  FAR_FLOW_EXISTING_ID="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$FAR_FLOW_DEST/Contents/Info.plist")"
  if [ "$FAR_FLOW_EXISTING_ID" != 'com.faraz.farflow' ]; then printf 'Destination belongs to another app; refusing to replace it.\n' >&2; exit 1; fi
  mkdir -p "$FAR_FLOW_ROOT/build/PreviousReleases"
  FAR_FLOW_PREVIOUS="$FAR_FLOW_ROOT/build/PreviousReleases/Far Flow-$(date +%Y%m%d-%H%M%S).app"
  mv "$FAR_FLOW_DEST" "$FAR_FLOW_PREVIOUS"
fi
if ! mv "$FAR_FLOW_STAGE/Far Flow.app" "$FAR_FLOW_DEST"; then
  if [ -n "$FAR_FLOW_PREVIOUS" ]; then mv "$FAR_FLOW_PREVIOUS" "$FAR_FLOW_DEST"; fi
  exit 1
fi
codesign --verify --deep --strict "$FAR_FLOW_DEST"
FAR_FLOW_LSREGISTER='/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister'
if [ -x "$FAR_FLOW_LSREGISTER" ]; then
  "$FAR_FLOW_LSREGISTER" -f "$FAR_FLOW_DEST" >/dev/null 2>&1 || true
fi
printf 'Installed: %s\n' "$FAR_FLOW_DEST"
