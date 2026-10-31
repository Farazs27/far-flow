# Local meetings

## Meeting suggestions

Far Flow checks macOS audio-process metadata roughly every six seconds. When a supported running app has used the microphone for at least six seconds, a nonactivating bottom-right prompt asks **Record this meeting?** Choose **Record meeting** or **Not now**. Detection never starts capture itself and reads no audio, screen content, calendar, browser history or meeting titles. Turn it off in **Settings → Meetings**.

Supported families are Zoom, Teams, Webex, FaceTime, Chrome, Edge, Arc, Brave, Firefox and Safari when macOS exposes an attributable microphone process. Shared WebKit helpers cannot safely be assigned to Safari and are not guessed. Browser voice chat or dictation may trigger a suggestion; muted/listen-only calls can be missed. A declined or expired prompt stays suppressed until the app has stopped using the microphone for 90 seconds. Manual recording remains available.

When a call ends but its app stays open, choose **Stop recording**. Microphone inactivity never automatically ends capture: you may just be muted. After 90 seconds without previously observed source input, one **Meeting finished?** reminder offers **Stop & transcribe** or **Keep recording**. Unknown source activity does not trigger this reminder. Quitting the selected source app stops capture and finishes transcription. Closing Far Flow's hub keeps capture running; Command–Q flushes working audio for later recovery and fully quits.

After transcription, a bottom notification opens the saved meeting. On Macs with at least 16 GB, the installed writing model summarizes automatically by default; below 16 GB it starts manually by default and is released after a meeting summary. Either preference can be changed in Settings. **Meeting language** defaults to Auto English/Dutch independently of dictation settings. Summary language is detected from spoken text, excluding the UI's English source labels. English and Nederlands overrides are available.

Open **Meetings**, choose the meeting app and select **Start recording**. The selected microphone comes from Settings. Both inputs are captured with macOS ScreenCaptureKit; no video output is attached or saved. Selecting a browser captures all audio from that browser. Choose All Mac audio only when you want all system audio, including notifications.

The first recording may require Microphone and **Screen & System Audio Recording** permission in System Settings. Far Flow cannot grant these permissions itself. Let participants know before recording and use headphones to keep remote audio from being recorded again through the microphone.

## During and after recording

The microphone and meeting-app meters show incoming audio. Speech appears in timestamped chunks, roughly every 30 seconds plus local processing time. Microphone and Meeting app are source labels, not individual speaker identities.

Close the window to keep recording. The floating bar and menu bar continue to show meeting status and have a Stop control. Choose **Stop recording** to stop both inputs and finish queued transcription. **Pause transcription** leaves remaining chunks available for later. Dictation, transforms and model replacement are unavailable while meeting work uses their engines. Meetings do not pause call audio or Spotify.

After recording, use the three tabs:

- **Transcript** keeps the original recognized words, timestamps and audio-source labels. Recognition can be wrong, especially with overlapping voices or echo.
- **Notes** is a freely editable personal note saved with the meeting.
- **Summary** uses the installed Qwen model automatically when enabled, or through **Generate summary**. It produces an editable draft with overview, decisions, action items and open questions in the detected or selected language. Empty sections may be omitted. Bracketed references point to transcript segments. Check the draft against the transcript; local generation does not guarantee factual accuracy. Regeneration asks before replacing edited text and keeps the previous text on failure or cancellation.

Use the meeting actions menu to copy the transcript, export a plain-text meeting document or delete the meeting. History retention does not delete meetings. Search matches titles, notes, summaries and transcript text. No calendar connection, cloud service, account, speaker-identification model or new dependency is used.

## Recovery and local data

Meeting audio is temporarily written to `~/Library/Application Support/FarFlow/MeetingAudio/<meeting-id>/`. Each file contains at most 30 seconds of 16 kHz mono audio for one source. These are private local working files, not a permanent playback archive.

A chunk is deleted only after its transcript checkpoint is successfully saved to SQLite. Chunk IDs are stable across write retries; replaying a checkpoint after a crash cannot duplicate that segment. A recording interrupted by a crash, quit or capture error is labeled accordingly on relaunch. Select **Finish saved audio** to process what remains. The unflushed tail of a crash (up to 30 seconds per source) cannot be recovered. Normal quit flushes partial chunks before shutting down; a disk failure can still prevent that save.

Each meeting holds at most 40 pending audio chunks, about 77 MB of sample data. If transcription cannot keep up, recording stops with a visible issue instead of allowing memory or disk usage to grow indefinitely. Completed transcript and queued audio remain available. Stop, permission failures and device errors preserve prior checkpoints. Sleep stops capture; macOS may delay pending transcription until wake.

The app's JSON backup includes meeting metadata, completed transcripts, notes and summaries. It does **not** include pending audio. Finish pending audio before exporting a complete meeting backup. Restore is blocked while meeting work or pending audio exists, avoiding accidental loss or merging with a restored transcript. Deleting a meeting explicitly removes its pending audio as well.

The upgrade writes a `Before Meetings Upgrade … .json` backup before moving the local document from schema 1 to schema 2. Old notes and settings are retained. Older Far Flow versions refuse the newer schema rather than overwriting meeting records they cannot understand. For a downgrade, restore the pre-upgrade backup with the old version; it will not contain meetings created afterward.

## Implementation boundaries

- `Meetings.swift`: meeting data, source-tagged transcript segments, bounded chunk buffering, local audio queue and summary input batching.
- `MeetingCapture.swift`: ScreenCaptureKit stream, selected-app filtering, continuous audio conversion and serial audio callbacks. Capture state stays off the UI thread.
- `MeetingController.swift`: start/stop, one-at-a-time transcription, checkpoint-before-delete recovery, cancellation and summaries. It reuses the existing speech and writing actors and saves through AppModel's SQLite document.
- `MeetingsView.swift`: recording controls, meters, searchable library and transcript/notes/summary tabs.

Long summaries use bounded input batches and pairwise reduction. Each reduction pass decreases the number of extracts, so context and memory do not grow with meeting duration. Every batch is considered; the transcript is never silently truncated to a model's input limit. This can still omit details in a generated summary, so the full transcript remains available.

Current limits: no speaker diarization, echo cancellation, calendar integration, audio playback/archive or cross-device sync. Chunk boundaries can split speech. Headphones and the exact meeting application should be checked in daily use. A synthetic hour-long buffering test is not a live 60-minute call acceptance test.
