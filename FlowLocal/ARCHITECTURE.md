# FlowLocal Architecture

SPM executable → bundled into `FlowLocal.app` by `Scripts/make-app.sh`.
Swift 6, SwiftUI + AppKit, macOS 26+.

```
main.swift (AppDelegate, menu bar, hotkey wiring, --transcribe CLI mode)
   │
   ├── HotkeyService          NSEvent global monitors; chords: Fn / Ctrl+Opt (dictation),
   │                          Ctrl+Opt+Cmd (Command Mode), double-tap → hands-free, Esc cancel
   │
   ├── DictationController    THE state machine: idle → recording → processing → idle
   │      ├── AudioRecorder        AVAudioEngine input tap → PCM buffers + RMS level
   │      ├── ASRRouter            picks engine by language / preference / installed state
   │      │      ├── AppleSpeechEngine   macOS 26 SpeechAnalyzer (streaming partials)
   │      │      ├── ParakeetEngine      FluidAudio CoreML, Parakeet TDT v3, 25 EU languages
   │      │      └── WhisperEngine       WhisperKit large-v3-turbo, ~100 languages incl. Urdu
   │      ├── ProcessingPipeline   cleanup → spoken punctuation → dictionary → backtrack
   │      │                        → snippets → RefinementDecider → LLM refine → guardrails
   │      │      └── LLMManager / MLXRefiner   MLX Qwen, fast-polish + Command Mode JSON
   │      ├── PasteService         clipboard transaction + AX focus/secure-field checks
   │      └── HistoryStore         GRDB transcripts table
   │
   ├── FlowPanelController    floating non-activating pill: waveform, states, partials
   ├── AppWindows             Settings / History / Scratchpad / Onboarding windows (SwiftUI)
   ├── AppDatabase (GRDB)     transcripts, dictionary, snippets, styles, notes(+versions)
   └── AdaptivePerformanceController   thermal/low-power downshift; HardwareProfiler tiers
```

## Key decisions

- **SPM executable, no .xcodeproj** — scriptable builds, no Xcode project churn. The spec's
  repo layout is otherwise followed in spirit (Core/Features split folded into Sources dirs).
- **Apple SpeechTranscriber as default engine** — zero-setup, high quality, OS-managed
  models; Parakeet/Whisper are opt-in installs through Model Center.
- **Engines are batch-first** — Parakeet/Whisper accumulate 16 kHz Float32 and decode on
  release (3.8 MB/min ceiling); Apple engine streams partials for the live preview.
- **LLM is optional** — RefinementDecider skips it for short clean utterances; guardrails
  (protected tokens, length ratio, wrapper stripping) reject bad outputs and fall back to
  rule-processed text. Command Mode requires strict JSON and whitelisted actions only.
- **One dictation at a time** — concurrent sessions rejected (spec §8.3).
- **Failure = clipboard** — any insertion doubt leaves the final text on the clipboard.

## Testing

- `swift test` — 32+ unit tests (pipeline, guardrails, cleanup, engine gating)
- `FlowLocal --transcribe file.wav --engine apple|parakeet|whisper [--locale ur_PK]` —
  headless end-to-end engine checks without permissions
- `TESTING.md` — manual matrix for hotkeys, insertion, secure fields, hands-free
