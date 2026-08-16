# FlowLocal Privacy

FlowLocal is local-first by construction.

## What stays on this Mac (everything)

- Microphone audio — captured in memory, discarded after transcription (audio retention is not implemented; nothing is written unless a future opt-in adds it)
- Transcripts and history — SQLite at `~/Library/Application Support/FlowLocal/Database/`
- Dictionary, snippets, styles, notes — same local database
- App context (frontmost app, focused-field text near the cursor) — used in-process, never persisted beyond history rows you can delete
- All ASR and LLM inference — Core ML / MLX on-device

## Network access

The core app makes **zero** network calls. The only networking code paths are
model installers, which run only when you click Install:

- Apple speech assets — downloaded by macOS itself
- Parakeet / Whisper / Qwen models — from huggingface.co over HTTPS

After models are installed, everything works with Wi-Fi off.

## Secure fields

Password-style fields (AX secure role, or password/PIN/OTP-style labels) are
never read, never included in prompts, and never auto-pasted into. Dictation
aimed at a secure field is copied to the clipboard instead, with a warning.

## Data controls (Settings → Privacy)

- Disable history entirely, or set retention to 24 hours / 7 days / 30 days
- Clear all history with one click
- Disable context awareness
- Storage usage readout

## Telemetry

None. No analytics, crash reporting, accounts, or remote configuration.
