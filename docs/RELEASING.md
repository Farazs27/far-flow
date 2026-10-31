# Distribution and release gates

The application uses the normal Release configuration, not a demo profile. A version bump alone does not establish production readiness.

## Current evidence

- Native unit suite: 86 passing tests, including bounded one-hour dual-source buffering, interruption recovery, persistence failures, detection debounce/rearm, helper attribution and English/Dutch selection.
- A 39-second installed-app capture test recorded microphone and selected QuickTime audio, stayed active with the hub closed, saved four source-tagged chunks, and generated a summary. The bottom transcript-ready prompt opened the saved meeting. Loudspeaker playback appeared in both sources as expected; use headphones for calls.
- Offline English, Dutch and long bilingual summaries and cancellation were exercised with outbound network denied. Summaries can still misclassify or invent details and must be reviewed against the transcript.
- Checked-in model hashes verify against the installed files. README documents source and model installation.

## Remaining acceptance gates

Do not advertise the app as production-validated for all Macs until these pass:

1. A 60-minute real call with both sides, bounded memory/storage, no duplicate chunks, sleep/device changes and quit/relaunch recovery. The accelerated hour-long buffer test is not a substitute.
2. Meeting suggestions in actual supported call apps and browsers, including decline, mute, reconnection and call-end behavior. Microphone activity is a heuristic, not a meeting API. Shared WebKit attribution is deliberately not guessed.
3. A clean installation on a second supported Mac following README verbatim, with fresh permissions and short English/Dutch dictation and meeting tests. Record RAM and macOS version. The 8 GB profile is not validated for full meeting summarization.
4. Summary-quality review on representative English/Dutch meetings. Preserve the AI-draft label even after release; never imply authoritative minutes.
5. For a binary download: Developer ID signing, Apple notarization, stapling and Gatekeeper assessment, then launch the downloaded artifact on another Mac with default security settings.

This workstation has an Apple Development identity, not a Developer ID Application identity. Source installation can be shared with authorized users; a notarized downloadable installer is not available. Do not distribute the development-signed bundle as though notarized.

## Maintainer workflow

1. Start from a reviewed commit. Run `./scripts/preflight.sh`, `./scripts/test.sh` and `./scripts/build.sh`. Complete the manual gates above and record evidence without private meeting content.
2. The owner obtains a **Developer ID Application** certificate through their Apple Developer account and installs it with its private key in Keychain. Never send signing credentials to recipients.
3. Configure an existing `notarytool` Keychain profile using Apple's authentication flow. The owner handles sign-in and secrets; do not put credentials in scripts, logs or GitHub.
4. Set `FAR_FLOW_SIGN_IDENTITY` to that identity and `FAR_FLOW_NOTARY_PROFILE` to the profile name. Run `./scripts/package_release.sh`.
5. The script signs a staged app and frameworks with hardened runtime and secure timestamps, submits it to Apple, staples the accepted ticket, validates it and assesses Gatekeeper. It stops on failure and publishes nothing. Preserve the submission ID and inspect Apple's log on rejection; do not bypass checks.
6. Test `build/Release/Far-Flow-<version>-arm64.zip` on another Mac. Publish its ZIP and checksum only after acceptance, attached to a GitHub release tied to the verified commit. Keep logs, models, personal data and credentials out of Git.

References: [Apple notarization](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution) and [Developer ID](https://developer.apple.com/developer-id/).
