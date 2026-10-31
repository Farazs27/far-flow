# Meeting verification — 31 October 2026

## Automated checks

The native suite passes **78 tests**. Twelve meeting tests cover:

- a simulated hour of two independent 16 kHz inputs, with exactly 120 full chunks per source, no repeated time ranges and bounded buffers;
- independent timestamp epochs, duplicate callback timestamps and clock resets;
- source offsets and final partial chunks;
- durable audio reopening and stable identity across repeated writes;
- queue backpressure without deleting existing pending audio;
- idempotent transcript checkpoints;
- meeting notes and summary round-trip through SQLite and portable JSON, independently of history retention;
- schema 1 migration with a pre-upgrade backup and preserved personal notes;
- long English/Dutch summary input batching without silently dropping the end;
- interrupted-session recovery, checkpoint failure and cancellation, preserving audio until persistence succeeds.

Results: `build/MeetingTests-clocks.xcresult`; log: `build/meeting-tests-clocks.log`.

The simulated hour tests the buffering/data path, not a real call, hardware capture, recognition accuracy or end-to-end performance.

## Native UI checks

An isolated review bundle and data directory were used. Checks covered the new Meetings navigation, source picker, original timestamped transcript, editable meeting notes, a real local Qwen summary, replacement confirmation, and recovery of a synthetic pending audio chunk. Recovery saved a checkpoint and removed the processed working file. Test fixtures contain synthetic text, not user meeting content.

## Local inference checks

`FarFlowBench meeting-summary` exercises English, Dutch and a long bilingual transcript whose final action occurs in the last input batch. It also cancels an in-progress summary. The process runs under `Benchmarks/offline.sb`, which denies outbound networking. Models are loaded from existing local files.

The summary prompt explicitly sets the output language, preserves deadline wording, distinguishes unresolved questions from assigned tasks, and forbids interpreting partial extracts as evidence that a meeting is unfinished. Long-input extraction carries explicit facts and references forward before the final summary. Generated summaries remain reviewable drafts; these checks cannot prove factual accuracy for arbitrary meetings.

Final offline results: `build/meeting-summary-accepted.json`. English took 6.4 seconds, Dutch 5.7 seconds, and the long bilingual case 46.5 seconds. In-progress cancellation passed. Peak process resident memory was approximately 905 MB; this is a benchmark-process measurement, not total app/GPU memory.

The final reduction receives the latest 1,800 characters of original transcript alongside bounded extracts. This corrected a contradiction in an earlier run where the closing task appeared in the overview but the action section claimed there were no tasks. English and Dutch fixtures retained the budget, unresolved venue and dated task; the long case retained the last-segment task and pilot decision. The long draft still added an unsupported open question about future steps. Summary quality remains a limitation of the local model: these are editable AI drafts, not verified minutes.

## Installed release

Release build and deep/strict signature verification passed (`build/meeting-release-final.log`). Version **0.3.0 (5)** is installed at `/Applications/Far Flow.app` and launches successfully. Existing data is migrated with a pre-upgrade backup.

The user authorized a short microphone plus synthetic QuickTime audio test. The first attempt was blocked by macOS because Far Flow's Screen & System Audio Recording permission was off. The app displayed the error, marked the meeting interrupted, and remained usable. The user subsequently approved the permission and the OS switch was observed enabled. The installed 0.4.0 workflow then passed a 39-second local microphone + QuickTime fixture check: both sources, four checkpointed segments, capture while the hub was closed, a complete transcript, automatic English summary, and the bottom transcript-ready prompt opening the saved session. Loudspeaker echo duplicated synthetic speech across the two inputs, as expected without headphones.

## Detection and distribution follow-up

The suite now passes 86 native tests (`build/distribution-tests-final.log`; the earlier 84-test result is `build/MeetingDetectionTests.xcresult`). Eight additional tests cover sustained-input debounce, suppression/rearm, busy-work deferral, helper attribution, English/Dutch speech-only language detection, memory defaults, and end reminders that never automatically stop on mute. Four Python installer tests cover pinned-file reuse/verification, corruption preserving the old model, read-only verification and path validation. `scripts/preflight.sh` and installed-model SHA-256 verification passed on the development Mac.

A stricter summary prompt was rejected after `build/meeting-summary-distribution.json` showed worse categorization and deadline wording. The final code retains the earlier accepted prompt and final-transcript-tail reduction. The successful capture's summary also misclassified the unresolved venue under Decisions. This remains a quality limitation, not a passed factual-accuracy gate.

Meeting detection timing and attribution are unit-tested and the native monitor compiles; live supported-call-app detection, a long real call and a second-Mac clean install still require acceptance. See [release gates](RELEASING.md).
