#!/bin/bash
# Read-only prerequisites check. Never installs tools or changes permissions.
set -euo pipefail
fail() { printf 'Required: %s\n' "$*" >&2; exit 1; }
[ "$(uname -s)" = Darwin ] || fail 'macOS 26 or newer.'
[ "$(uname -m)" = arm64 ] || fail 'An Apple Silicon Mac and a native arm64 terminal (not Rosetta). Intel is unsupported.'
FAR_FLOW_OS="$(sw_vers -productVersion)"
[ "${FAR_FLOW_OS%%.*}" -ge 26 ] || fail 'macOS 26 or newer. OS upgrades must be performed by the Mac owner.'
FAR_FLOW_RAM="$(sysctl -n hw.memsize)"
[ "$FAR_FLOW_RAM" -ge 8589934592 ] || fail 'At least 8 GB unified memory; 16 GB for the validated full workflow.'
if [ "$FAR_FLOW_RAM" -lt 17179869184 ]; then
  printf '8–15 GB profile: speech first; summaries manual by default. Full workflow needs validation on this Mac.\n'
else
  printf '16+ GB profile: standard Parakeet speech + Qwen 4B 4-bit summaries. No larger model needed.\n'
fi
command -v xcodebuild >/dev/null || fail 'Full Xcode 26, not Command Line Tools alone.'
FAR_FLOW_XCODE="$(xcodebuild -version 2>/dev/null)" || fail 'Select full Xcode and complete its first-launch setup.'
FAR_FLOW_XCODE_MAJOR="$(printf '%s\n' "$FAR_FLOW_XCODE" | awk '/^Xcode / {split($2,v,".");print v[1]}')"
[ "${FAR_FLOW_XCODE_MAJOR:-0}" -ge 26 ] || fail 'Full Xcode 26 or newer. This repository was validated with Xcode 26.6.'
command -v xcodegen >/dev/null || fail 'XcodeGen (brew install xcodegen), verified with 2.46.0.'
command -v python3 >/dev/null || fail 'Python 3 (brew install python), used for signing selection and pinned model installation.'
xcrun --find metal >/dev/null 2>&1 || fail 'Metal toolchain: xcodebuild -downloadComponent MetalToolchain'
FAR_FLOW_FREE_KB="$(df -Pk . | awk 'END {print $4}')"
[ "$FAR_FLOW_FREE_KB" -ge 20971520 ] || fail '20 GB free space for dependencies, build products and models, after installing Xcode.'
printf 'Ready: macOS %s, %s GB RAM.\n%s\n' "$FAR_FLOW_OS" "$((FAR_FLOW_RAM / 1073741824))" "$FAR_FLOW_XCODE"
xcodegen --version
