# Using Far Flow

Far Flow is a native macOS app for English and Dutch dictation. It runs speech recognition and writing models locally after installation.

## First use

1. Open `/Applications/Far Flow.app`.
2. Grant Microphone and Accessibility from the setup screen. The global shortcut uses Accessibility and does not need a separate Input Monitoring grant. The same controls remain in Settings.
3. Wait for **Local models ready**. Model compilation/loading can take longer on the first launch.
4. Place the cursor in a text field in another app.
5. Hold **Fn (Globe)**, speak, then release to insert. **Double-tap Fn** to keep recording, then press Fn once to stop. Control–Option–Space is available as an alternative hold shortcut, and Control–Option–Return toggles hands-free. Escape cancels recording or processing before insertion starts.
6. If Far Flow cannot verify the destination, use its recovered text and Copy action.

The Start hands-free button inside the dashboard captures a dictation for review/copy. Use the global shortcut from another app for automatic insertion. In Scratchpad, the Dictate button appends the result to the current note.

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

## Data

- Audio stays in memory and is discarded after success or cancellation. It is not saved for later retry.
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

The red close button on the main dashboard fully quits Far Flow, including recording, global shortcuts, local speech/writing models, and its media helper. Command–Q and Quit Far Flow do the same. No Far Flow model host remains after the app exits. Minimize the dashboard if you want to keep using Fn and the floating bar in other apps. Reopening Far Flow loads speech again; the writing model stays lazy for standard Light cleanup.

The floating bar now rests as a 76 × 30 point availability indicator and expands to 224 × 38 during recording/processing. Listening shows only the waveform and stop control, with no live transcript or timer. Dragging preserves the bar's center position across its size changes and across launches. Your original, cleaned text and copy actions stay in the dashboard and bar context menu.
