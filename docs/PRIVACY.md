# Privacy and data lifecycle

Far Flow is designed for local dictation after explicit model installation. No account, inference API key, cloud transcription or Far Flow telemetry endpoint is required.

| Data | Location and lifetime |
| --- | --- |
| Microphone audio | In memory during capture and processing; discarded after completion or cancellation |
| Original and cleaned transcripts | Local SQLite data when retention is enabled |
| Dictionary, snippets, styles, scratchpad and preferences | Local application-support data |
| Model weights and tokenizers | Local `Models/` folder; persist on disk after quitting |
| JSON export | A file at the destination you explicitly choose |
| Pre-import backup | Saved in the local data folder before an import replaces user data |

The normal data root is `~/Library/Application Support/FarFlow/`. Transcript retention can be Off, 24 hours, 30 days or Keep, and applies to raw and cleaned text. Existing macOS account protections and FileVault configuration protect the files; Far Flow does not add separate SQLite encryption. Clearing data inside Far Flow is not a guarantee that OS backups or snapshots have been erased.

## Network boundary

Swift package resolution and explicit model downloads require network access. Model downloads go to the pinned Hugging Face repositories in the bundled manifest. Runtime inference loads local models and tokenizers without a cloud fallback. Offline component verification used an outbound-network-denied sandbox; see [verification](VERIFICATION.md).

The source-check GitHub workflow runs against source files only. Public screenshots contain isolated sample text. Local dictations, exported data, audio, model weights, credentials and signing files are excluded from the repository.

## Permissions and insertion

Microphone permission is used to capture speech. Accessibility permission supports the global shortcut and cross-app text insertion. The current implementation does not need a separate Input Monitoring grant. Setup actions open the corresponding macOS controls; Far Flow cannot grant these permissions itself.

Text inserted into another app becomes subject to that app's behavior, including any sync or network services it uses. Paste fallback temporarily uses the system clipboard and attempts to restore it without overwriting newer clipboard content. Secure fields and changed destinations are rejected where detected.

## Quitting

Closing the main dashboard or quitting ends Far Flow's running model host and owned media helper. Disk model files remain installed for the next launch. Minimize keeps dictation available. Open at login is a user-controlled preference.
