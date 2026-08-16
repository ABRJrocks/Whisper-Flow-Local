# FlowLocal

Local-first voice dictation, rewriting, and voice commands for macOS.
Hold a key, speak, release — clean text appears at your cursor, in almost any app.
Everything — audio, transcription, AI cleanup, history — stays on your Mac.

## Features

- **Push-to-talk anywhere** — hold `Fn` (or `Ctrl+Opt`), speak, release.
- **Hands-free** — double-tap `Fn` to lock recording; tap again, Esc, or silence timeout to stop.
- **Command Mode** — select text, hold `Ctrl+Opt+Cmd`, say "make this shorter / fix grammar /
  turn into bullets / translate to Urdu" — the selection is transformed in place.
- **Three local ASR engines**, routed by language:
  - Apple on-device speech (default, streaming live preview, OS-managed models)
  - NVIDIA Parakeet TDT v3 via FluidAudio CoreML (25 European languages, ~1 GB)
  - Whisper large-v3-turbo via WhisperKit (~100 languages incl. **Urdu**, ~632 MB)
- **Local AI cleanup** — optional MLX Qwen model removes fillers, fixes self-corrections
  ("Tuesday, actually Wednesday" → "Wednesday"), applies per-app writing styles. Guardrails
  guarantee numbers, emails, URLs and protected terms survive; otherwise output is rejected.
- **Deterministic pipeline first** — dictionary replacements, snippets with placeholders,
  backtrack correction, spoken punctuation; the LLM only runs when it's actually needed.
- **App-aware styles** — messaging apps get casual joins (no final period on short texts),
  email/documents stay formal, terminals/coding preserve identifiers.
- **Animated floating flow bar** — live waveform, partial transcript, processing stages,
  cancel/stop controls; non-activating (never steals focus).
- **Spoken commands** — end a dictation with "press enter" or "send it" to submit after paste.
- **Cleanup intensity** — Light / Standard / Heavy AI-rewrite levels (Intelligence settings).
- **Insights** — words dictated, WPM, streak, top apps, daily activity chart. All computed
  locally from your own history; nothing new is collected.
- **History** — searchable, per-day grouping, raw vs final, copy/delete, retention windows.
- **Scratchpad** — local notes with autosave, versions, pinning; dictate straight into it.
- **Failure-safe** — any insertion doubt leaves your text on the clipboard. Secure/password
  fields are never read and never auto-pasted into.
- **Private** — zero telemetry, zero accounts, zero network after model install. See PRIVACY.md.

## Build & run

```bash
cd FlowLocal
./Scripts/make-app.sh          # swift build -c release + bundle + codesign
open build/FlowLocal.app
```

First run: grant **Accessibility** (System Settings → Privacy & Security) and **Microphone**,
then relaunch. Onboarding walks through both plus model setup.

## Testing

`swift test` for units; `TESTING.md` for the full manual matrix; headless engine checks:

```bash
.build/debug/FlowLocal --transcribe sample.wav --engine parakeet
.build/debug/FlowLocal --transcribe urdu.wav --engine whisper --locale ur_PK
```

## Docs

- `ARCHITECTURE.md` — component graph and key decisions
- `PRIVACY.md` — data handling guarantees
- `THIRD_PARTY_NOTICES.md` — licenses and model attribution (Parakeet is CC BY 4.0)
