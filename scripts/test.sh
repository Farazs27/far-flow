#!/bin/bash
set -euo pipefail
FAR_FLOW_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$FAR_FLOW_ROOT"
xcodegen generate
xcodebuild -project FarFlow.xcodeproj -scheme FarFlow -configuration Debug \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData \
  -clonedSourcePackagesDirPath build/SourcePackages -jobs 4 \
  -only-testing:FarFlowTests ONLY_ACTIVE_ARCH=YES ARCHS=arm64 ENABLE_HARDENED_RUNTIME=NO test
