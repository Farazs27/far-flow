# Using Far Flow

Far Flow is a native macOS app for English and Dutch dictation. It runs speech recognition and writing models locally after installation.

## First use

1. Open `/Applications/Far Flow.app`.
2. Grant Microphone and Accessibility from the setup screen. The global shortcut uses Accessibility and does not need a separate Input Monitoring grant. The same controls remain in Settings.
3. Wait for **Local models ready**. Model compilation/loading can take longer on the first launch.
4. Place the cursor in a text field in another app.
5. Hold **Fn (Globe)**, speak, then release to insert. **Double-tap Fn** to keep recording, then press Fn once to stop. Control–Option–Space is available as an alternative hold shortcut, and Control–Option–Return toggles hands-free. Escape cancels recording or processing before insertion starts.
6. If Far Flow cannot verify the destination, use its recovered text and Copy action.

The Start hands-free button inside the dashboard captures a dictation for review/copy. Use the global shortcut from another app for automatic insertion. In Notes, the Dictate button and global shortcut append speech to the note selected when recording starts.

The recording bar rests at 76 × 30 points and expands to 224 × 38 while busy. Drag its waveform/status area to the top, bottom, left or right; the position is saved across launches. Settings has **Always show the recording bar** and **Reset bar position** controls. It remains a nonactivating panel so moving it does not deliberately bring the dashboard forward.

**Pause media while dictating** is enabled by default in Settings. Far Flow pauses the current macOS Now Playing player and resumes it when recording stops or is canceled. It leaves an already paused player paused and avoids starting a different player if the active player changes during dictation. This covers players that integrate with macOS media controls; unrelated sounds and players without that integration may continue. The media transport uses a version-dependent local macOS API; speech recognition is independent of it.

## English and Dutch

Auto supports English, Dutch and mixed speech. English/Dutch selections provide a recognition hint and scope language-specific dictionary entries. Parakeet's hint filters scripts rather than forcing a translation. Recognition preserves the spoken language.

Use Dictionary for names and recurring mistakes. Far Flow includes a `farflow` → `Far Flow` entry. Dictionary changes happen after recognition and cannot recover words that were never recognized. Snippets match an entire dictated trigger and insert its saved expansion without AI rewriting.

## Cleanup and transforms

None returns recognized wording with dictionary spellings. **Light is the fast default**: punctuation comes from speech recognition, and deterministic local rules handle fillers, dictionary spellings and explicit adjacent numeric corrections. It does not run the writing model for standard style. Medium and custom writing styles use the local AI model and take longer. Original recognition remains available in history if retention allows it.

Deeper AI cleanup uses the local Qwen model. A protected-span check rejects certain changes to numbers, identifiers, addresses, dictionary terms and negation, but it cannot prove that every sentence preserves meaning. Review important text before sending it.

Normal dictation stays in the background. The cursor position at the moment you stop recording determines the destination; if focus changes afterward during processing, Far Flow preserves the text for copying instead of sending it to a different field. You can always open the dashboard to review history or copy the last dictation from the menu bar or recording bar.

For a selected-text transform, select text in another app and choose **Transform Selection** from the Far Flow menu bar. Review the result before replacing the selection. Far Flow checks that the selection still matches. Undo replacement is available when insertion was verified and the caret/text are unchanged; otherwise use the destination app's Undo or copy the original.

## Notes

Open **Notes** in the sidebar or menu bar. **Command–N** creates and selects a new note, including after the dashboard has closed. Rename the title, type, or use Dictate; changes save automatically. The last selected note survives navigation and relaunch. Search matches titles and content; the list shows recently edited notes first.

Dictation appends to the note selected at recording start, even if you switch notes or close the dashboard. Each recording is limited to five minutes; continue with another dictation to add more. If the target note is deleted during processing, the transcript is shown for recovery. Notes remain when history retention is Off.

Use **Save as note** in a history row or the transcript preview, or **Save Last Dictation as Note** in the menu bar, to keep text independently of history. A note’s actions menu can copy it, export plain text, or delete it after confirmation. A failed save shows a persistent warning with Retry save and Export data; export a copy before quitting if storage remains unavailable.

Notes are plain-text personal drafts. For calls, use the separate **Meetings** workspace: choose the meeting app, start recording, stop to finish transcription, then explicitly generate a local summary. Read [Local meetings](MEETINGS.md) for permissions, recovery and limitations. Audio sources are labeled; individual speakers are not identified.

## Data

- Dictation audio stays in memory and is discarded after success or cancellation. Meeting audio uses temporary local chunks until each transcript checkpoint saves; interrupted meetings can finish saved audio later.
- History retention is Off, 24 hours, 30 days or Keep. The choice applies to both raw and cleaned text.
- Local data and models live in `~/Library/Application Support/FarFlow/`.
- Data is protected by the macOS account and any existing FileVault configuration. Far Flow does not add separate database encryption.
- Settings can export a portable JSON backup. Import first saves the current data to a `Before Import … .json` file in the data folder.
- Installed models can be verified, imported or moved to Trash from Models.

No login, API key or inference subscription is required. Downloads happen through the explicit model installation action. Core inference uses local model and tokenizer files, without a cloud fallback.

## Troubleshooting

**Shortcut does nothing:** enable Accessibility; quit/reopen if macOS requests it. Confirm that Settings shows Global shortcut active. Fn is the default; avoid assigning Fn to Far Flow and Wispr simultaneously.

**Fn also changes the keyboard language:** set System Settings → Keyboard → **Press 🌐 key to** → **Do Nothing**. Hold Fn for dictation or double-tap it for hands-free recording.

**Speech appears in Far Flow but not in another app:** grant Accessibility, keep the original cursor position, and check the destination. Some editors do not expose enough accessibility information to verify insertion; Copy remains available. Secure fields are blocked. Terminal dictation never presses Return automatically.

**Microphone unavailable:** select System default or another connected input. A device change during capture stops the session and attempts to recover captured speech.

**Writing model cannot load:** recognition can still be used with local AI disabled in Settings. Install/verify the writing model before using transforms.

**Models missing or corrupt:** use Models → Verify files or install/import the exact pinned model folder. Inference does not automatically fetch missing files.

**Text is wrong:** inspect the original, choose lighter cleanup, add a dictionary alias, or select the language hint. Personal-voice accuracy and app compatibility should be checked during the pilot.

## Closing Far Flow

The red close button and Command–W close the dashboard while Far Flow keeps running. Fn, the menu bar and the floating bar remain available, including during an active recording. Reopen the dashboard from the Far Flow menu bar, the bar’s context menu or the Dock. Command–Q and Quit Far Flow fully stop recording, shortcuts, local speech/writing models and the media helper. Finish dictation before quitting: unfinished audio is canceled, not saved. No Far Flow model host remains after the app exits. Launching after a full quit loads speech again; the writing model stays lazy for standard Light cleanup.

The floating bar now rests as a 76 × 30 point availability indicator and expands to 224 × 38 during recording/processing. Listening shows only the waveform and stop control, with no live transcript or timer. Dragging preserves the bar's center position across its size changes and across launches. Your original, cleaned text and copy actions stay in the dashboard and bar context menu.
