#!/bin/bash
set -euo pipefail
FAR_FLOW_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$FAR_FLOW_ROOT"
xcodegen generate
xcodebuild -project FarFlow.xcodeproj -scheme FarFlow -configuration Release \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData \
  -clonedSourcePackagesDirPath build/SourcePackages -jobs 4 \
  ONLY_ACTIVE_ARCH=YES ARCHS=arm64 build
FAR_FLOW_IDENTITY="${FAR_FLOW_SIGN_IDENTITY:-}"
if [ -z "$FAR_FLOW_IDENTITY" ]; then
  FAR_FLOW_IDENTITY="$(security find-identity -v -p codesigning | python3 -c 'import sys,re;s=sys.stdin.read();m=re.search(r"\) ([A-F0-9]{40}) \"(?:Apple Development|Developer ID Application|Mac Developer):",s);print(m.group(1) if m else "-")')"
fi
FAR_FLOW_APP="$FAR_FLOW_ROOT/build/DerivedData/Build/Products/Release/Far Flow.app"
if [ "$FAR_FLOW_IDENTITY" != '-' ]; then
  for FAR_FLOW_FRAMEWORK in "$FAR_FLOW_APP"/Contents/Frameworks/*.framework; do
    codesign --force --sign "$FAR_FLOW_IDENTITY" --options runtime --timestamp=none "$FAR_FLOW_FRAMEWORK"
  done
  codesign --force --sign "$FAR_FLOW_IDENTITY" --options runtime --timestamp=none --entitlements FarFlow/FarFlow.entitlements "$FAR_FLOW_APP"
fi
codesign --verify --deep --strict "$FAR_FLOW_APP"
printf 'Built and verified: %s\n' "$FAR_FLOW_APP"
