# Codex insertion and Spotify follow-up — 27 October 2026

The first audit did not establish end-to-end compatibility in Codex. The user subsequently reported that insertion still failed and music continued playing.

## Findings and changes

Recent local history recorded an unverified Accessibility insertion for the app displayed as ChatGPT. The installed desktop app is identified as `com.openai.codex`. Far Flow previously attempted to set the selected text directly; an accepted write without observable editor-state change was reported as Insertion requested.

Codex and the listed Chromium/Electron editors now use the normal paste path directly instead of attempting an AX text mutation first. Before reading their focused element, Far Flow enables the accessibility tree through `AXManualAccessibility`, as described in [Electron's accessibility documentation](https://github.com/electron/electron/blob/main/docs/tutorial/accessibility.md). Focus, selection, secure-field, modifier-release, and clipboard ownership checks remain in place. No automatic second insertion is attempted after an accepted write.

The installed media bridge returned QuickTime Player's PID with `playing:false` while Spotify's own UI exposed Pause and advancing playback. The global Now Playing slot was therefore insufficient to detect Spotify playback. Added a Spotify-specific fallback using its accessible Player controls group. It presses only a button labeled with the requested action, without activating Spotify or requesting Apple Events Automation permission. The transport retains the chosen paused player for resume and yields if a different system player begins playing.

## Verification and installation

- Native Xcode unit suite: 61 tests, zero failures. Added coverage for Spotify playing while QuickTime owns a paused global media slot, previously paused Spotify, changed players, unavailable primary transport, and Codex/editor paste routing.
- Release build and signature verification passed. Installed at `/Applications/Far Flow.app` with previous installation retained by the installer.
- Live Spotify check in the installed app: started hands-free recording; Far Flow showed Listening and Spotify's control changed from Pause to Play. Canceled through Dictation → Cancel Dictation; Far Flow returned to Ready to use and Spotify's control changed back to Pause. The test recording was canceled without transcription or saved audio.
- Codex UI access is explicitly blocked by the computer-use tool. No alternative automation route was used to access Codex. The Codex-specific change needs a user dictation retry.
- Attempted a separate insertion-only check through Transforms in disposable external editors. The selected text could not be captured through this automation setup, so this is NOT a live paste pass. The disposable VS Code text was discarded. Browser test tabs were temporary; no messages or forms were submitted.

## Limits

The Spotify fallback depends on its accessible controls being exposed and on recognized English/Dutch/Spanish/French/German control labels. The primary Now Playing transport remains available for other players. This does not establish compatibility with every music player or every Codex editor state. The media bridge's command submission still reports transport acceptance rather than a confirmed playback transition; the live UI check above is the evidence for this Spotify session.
