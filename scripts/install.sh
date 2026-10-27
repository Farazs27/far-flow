#!/bin/bash
set -euo pipefail
FAR_FLOW_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FAR_FLOW_APP="$FAR_FLOW_ROOT/build/DerivedData/Build/Products/Release/Far Flow.app"
FAR_FLOW_DEST="${FAR_FLOW_INSTALL_DIR:-/Applications}/Far Flow.app"
if [ ! -d "$FAR_FLOW_APP" ]; then printf 'Run scripts/build.sh first.\n' >&2; exit 1; fi
if pgrep -x 'Far Flow' >/dev/null; then printf 'Quit Far Flow before installing a replacement.\n' >&2; exit 1; fi
codesign --verify --deep --strict "$FAR_FLOW_APP"
if [ -d "$FAR_FLOW_DEST" ]; then
  FAR_FLOW_EXISTING_ID="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$FAR_FLOW_DEST/Contents/Info.plist")"
  if [ "$FAR_FLOW_EXISTING_ID" != 'com.faraz.farflow' ]; then printf 'Destination belongs to another app; refusing to replace it.\n' >&2; exit 1; fi
  mkdir -p "$FAR_FLOW_ROOT/build/PreviousReleases"
  ditto "$FAR_FLOW_DEST" "$FAR_FLOW_ROOT/build/PreviousReleases/Far Flow-$(date +%Y%m%d-%H%M%S).app"
fi
ditto "$FAR_FLOW_APP" "$FAR_FLOW_DEST"
codesign --verify --deep --strict "$FAR_FLOW_DEST"
FAR_FLOW_LSREGISTER='/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister'
if [ -x "$FAR_FLOW_LSREGISTER" ]; then
  "$FAR_FLOW_LSREGISTER" -f "$FAR_FLOW_DEST" >/dev/null 2>&1 || true
fi
printf 'Installed: %s\n' "$FAR_FLOW_DEST"
