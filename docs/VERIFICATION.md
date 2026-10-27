# Verification

Recorded 27 October 2026. Environment: Apple M4, 16 GB RAM, macOS 26.6.2, Xcode 26.6, arm64. These results describe this development environment and are not universal latency or accuracy promises.

## Native build and tests

- Native Release build and deep code-signature verification passed.
- The unit suite passed **44 tests, zero failures**, covering bilingual text handling, protected spans, retention/persistence, checksums, short audio, cancellation-related rules, Fn gestures, media ownership and recording-bar geometry.
- The UI-test target is included. XCTest could not enable UI automation on the development Mac, so the UI suite is not reported as passed.
- Native live checks exercised hold/release, double-tap hands-free, insertion into ChatGPT, media pause/resume and bar dragging.
- Closing the main window was exercised: the app/model-host PID and its owned media-helper PID exited.
- README images are actual native light/dark captures using an isolated sample profile. The separate floating panel has geometry/state tests and live interaction evidence, but no separate publication screenshot.

Logs and `.xcresult` bundles remain local and are not committed. Build/test commands are in [BUILDING.md](BUILDING.md).

## Offline component benchmarks

The corpus contains 18 locally synthesized macOS Daniel/Xander clips. Outbound networking was denied with `Benchmarks/offline.sb` during the offline runs. Results are committed under `Benchmarks/Results/`.

| Path | Median | p95 | Scope |
| --- | --- | --- | --- |
| Parakeet speech | 41 ms | 53 ms | 18 prerecorded clips; model already loaded |
| Whisper large-v3 turbo | 490 ms | 542 ms | Same 18 clips; model already loaded |
| Parakeet repeated speech | 42 ms | 51 ms | 200 file transcriptions, no transcription failures |
| Standard Light cleanup | 0.086 ms | — | Eight rule-based examples; no writing-model load |

Mean per-clip raw word error rate: Parakeet English 6.5%, Dutch 11.4%, mixed 16.7%; Whisper English 12.8%, Dutch 7.3%, mixed 55.6%. Formatting contributes to raw WER. Whisper performed better on the Dutch-only synthetic fixtures; Parakeet was selected for speed and mixed-language behavior.

This small synthetic set does not establish personal-voice accuracy. Speech timings exclude capture, model loading, focus handling, insertion and destination-app response. The initial measured Parakeet load was 12.9 seconds; compilation and warm caches vary. The 200-run stress test covers file inference, not 200 full microphone/hotkey sessions. Process RSS omits some Core ML service/GPU allocations.

## Reproduce the speech run

From the repository root, with speech model files installed:

```sh
python3 scripts/generate_fixtures.py
xcodebuild -project FarFlow.xcodeproj -scheme FarFlowBench \
  -configuration Release -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath build/DerivedData \
  -clonedSourcePackagesDirPath build/SourcePackages build
sandbox-exec -f Benchmarks/offline.sb \
  build/DerivedData/Build/Products/Release/FarFlowBench \
  speech Benchmarks/corpus.json build/parakeet-local.json
```

Install the Daniel and Xander system voices if `say` cannot find them. Corpus paths are relative to the repository root. Use `stress` in place of `speech` for 200 repeated runs. For rule cleanup, the benchmark accepts `cleanup-fast build/cleanup-local.json`; deeper model cleanup uses `cleanup`.

The Whisper comparison requires an explicit `FarFlowBench prepare-whisper` download before an offline run. It is optional and not needed to run Far Flow. `sandbox-exec` is a development verification tool whose availability may change on macOS.

## Remaining acceptance work

- Reviewed personal English/Dutch voice corpus, including accents, room noise and mixed speech.
- Broader insertion compatibility across native editors, browsers and terminals.
- Longer daily-use pilot, route-change/reboot and low-memory testing.
- Full accessibility audit and a separate live capture of the nonactivating panel.
- Signed/notarized distribution and testing outside the development machine.
