# Dictation insertion audit — 27 October 2026

## Evidence

Reviewed recording lifecycle, hotkey handling, destination capture, Accessibility replacement, synthetic paste, clipboard restoration, audio import and recovery UI. Local outcome metadata was inspected without exporting transcript contents. A requested insertion is not proof of delivery or failure; verification must inspect the destination.

## Changes

- Wait up to one second for physical shortcut modifiers to release, checking destination focus during the wait. If modifiers remain held, preserve the result for copying instead of sending a modified paste shortcut.
- Never follow an accepted Accessibility replacement with a second paste simply because the editor's value has not updated yet. Also avoid another write if a failed Accessibility request nevertheless changed the field.
- Confirm the exact replacement at the captured UTF-16 selection. Merely finding the dictated words somewhere in a changed field could falsely report success.
- Serialize delayed clipboard restorations. Previously, a second dictation could snapshot the first dictation and later restore it instead of the original clipboard. Preserve newer user copies and multiple clipboard formats.
- Do not resolve an explicitly requested, exited destination process to an unrelated frontmost app.
- Clear previous transcription state before importing audio. An import failure previously could present an old transcript as the new result.
- Show the last insertion outcome in the menu and recording-bar tooltip, alongside the existing Copy Last Dictation action.

## Verification

Native Xcode Debug unit suite: 56 tests passed, zero failures. Six new tests cover exact replacement, emoji/UTF-16 selection offsets, repeated text and false-positive verification, physical modifiers, overlapping clipboard leases, user clipboard changes, rich clipboard content, and empty clipboard restoration. Tests use isolated named pasteboards, leaving the user's general clipboard untouched.

These tests do not reproduce physical Fn timing or prove insertion in every external editor. The duplicate-write guard and exited-process resolution were reviewed in code; they are not exercised by the new clipboard/verification tests. Speech recognition accuracy was not benchmarked in this audit. No new microphone recording was made.

Release build and signature verification passed. Installed to `/Applications/Far Flow.app`; the installer preserved the previous bundle under `build/PreviousReleases/`. Confirmed that the installed executable matches the verified build. Relaunched successfully: speech ready, Microphone granted, Accessibility granted, and Global shortcut active. Existing history remains visible.

## Remaining improvements

1. Add a controlled external-editor integration harness for native text fields, browser contenteditable fields, Electron editors, and terminals. Exercise cursor movement, app switching, selected-text replacement, held modifiers, and delayed pasteboard reads. Distinguish accepted-but-unverified insertion from confirmed failure.
2. Make recovery visible on the floating bar, with a concise outcome and Copy action. The current bar still collapses after processing; menu/tooltip feedback is an incremental improvement.
3. Retry transient Accessibility reads only while verifying the same destination. A missing focused element currently produces Ready to copy; silently redirecting to another app would be inappropriate.
4. Add optional local diagnostic events containing timings, app bundle ID, destination role, and failure category, without transcript or clipboard contents. Existing history cannot distinguish all causes of intermittent delivery.
5. Expand the real English/Dutch microphone benchmark corpus. Existing written acceptance cases do not establish speech accuracy.

Historical note: the later 31 October lifecycle update supersedes this behavior. Closing the dashboard now keeps Far Flow running; Command–Q quits. See APP-AUDIT-2026-10-31.md.
