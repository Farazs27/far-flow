# Building Far Flow

## Requirements

- Apple Silicon Mac running macOS 26 or later.
- Full Xcode 26 with command-line tools selected. The verified environment used Xcode 26.6 and an M4 Mac with 16 GB RAM.
- XcodeGen available on PATH; Python 3 for optional provisioning and fixtures.
- Network access to resolve Swift packages and explicitly download model files.
- Several GB of disk space for models, plus Xcode build products and package caches.

Install the Metal toolchain if Xcode reports that it is missing:

```sh
xcodebuild -downloadComponent MetalToolchain
```

## Build and run

From the repository root:

```sh
./scripts/build.sh
```

The script regenerates `FarFlow.xcodeproj` from `project.yml`, resolves packages, builds the arm64 Release app and verifies its signature. Build output is `build/DerivedData/Build/Products/Release/Far Flow.app`.

You can also open `FarFlow.xcodeproj` in Xcode, select **FarFlow → My Mac**, and run. Change project configuration in `project.yml` before regenerating it.

The script selects an existing Apple Development, Developer ID Application or Mac Developer identity when available. Set `FAR_FLOW_SIGN_IDENTITY` to choose your own identity explicitly. Without one, the project uses ad hoc signing; no signing certificate or team credentials are shipped in this repository. The result is a local development build, not a notarized distribution.

## Install locally

Quit the running app, then:

```sh
./scripts/install.sh
```

The destination is `/Applications/Far Flow.app`. Set `FAR_FLOW_INSTALL_DIR` for another writable parent folder. The installer verifies signatures, refuses to replace another bundle ID and preserves the previous installation under `build/PreviousReleases/`.

Models and data live outside the application bundle and survive app replacement. Keep the signing identity stable to reduce permission resets. Grant Microphone and Accessibility in the app's setup screen; a separate Input Monitoring grant is not required.

## Models

Use **Models → Download model**, or import an existing folder matching the pinned manifest. The app verifies SHA-256 hashes before installing files.

| Model | Purpose | Approximate files | Terms |
| --- | --- | --- | --- |
| Parakeet TDT 0.6B v3, Core ML int8-v2 | Speech, including English/Dutch | 632 MB | CC BY 4.0 |
| Qwen3-4B-Instruct-2507, MLX 4-bit | Deeper cleanup and transforms | 2.28 GB | Apache 2.0 |

Exact revisions and file hashes are in `FarFlow/Resources/ModelManifest.json`. Model weights are not included in Git.

For a development machine, `python3 scripts/provision_models.py` downloads the pinned files to your local application-support directory and refreshes the bundled manifest. This is an explicit network operation. The app itself never downloads missing files during transcription.

## Tests

```sh
xcodebuild -project FarFlow.xcodeproj -scheme FarFlow \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath build/DerivedData \
  -clonedSourcePackagesDirPath build/SourcePackages \
  -only-testing:FarFlowTests ENABLE_HARDENED_RUNTIME=NO test
```

The UI target requires macOS XCTest automation access and a live desktop session. It is not part of the claimed unit-test pass. GitHub's source-check workflow checks metadata and script syntax; it does not replace a native Xcode build.

## Recovery

Quit Far Flow before replacing its bundle. Restore a prior `.app` from `build/PreviousReleases/` if needed. Export a JSON data backup in Settings before deliberate data migrations. Do not commit exports, databases, audio recordings, model weights, signing files or local logs.
