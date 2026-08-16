# FlowLocal
## Complete Local-First macOS Voice Dictation, Rewriting, and Command System

**Research and implementation specification**  
**Research date:** July 22, 2026  
**Target platform:** Apple Silicon Mac, macOS 15 or newer  
**Primary target devices:** MacBook Air M4 and MacBook Air M5  
**Distribution:** Private personal use, direct local build, not Mac App Store  
**Working product name:** FlowLocal  
**Recommended bundle identifier:** `com.local.flowlocal`

---

## 0. Implementation Requirements

This is a production-quality native macOS application, not a prototype, mockup, web wrapper, or partial demo.

The product must provide a feature-equivalent local-first alternative to Wispr Flow for personal use. It must not copy Wispr's proprietary source code, private APIs, trademarks, branding, iconography, or visual assets. Reproduce useful behavior and workflows using original implementation and original interface design.

Follow these rules throughout development:

1. Build the application in native Swift 6 using SwiftUI and AppKit.
2. Support Apple Silicon only for the first release.
3. Target macOS 15 or newer.
4. Keep all transcription, text refinement, settings, history, and context processing on the device.
5. Do not add cloud APIs, paid services, accounts, subscriptions, telemetry, analytics SDKs, crash-reporting SDKs, remote configuration, or hidden network calls.
6. Model downloads from Hugging Face or GitHub Releases are permitted only when the user explicitly initiates or approves the download.
7. After models are downloaded, the complete core workflow must work without an internet connection.
8. Every feature must fail safely. Never lose dictated text because an app refused paste, a model failed, or the focused field changed.
9. Do not hardcode one model for every Mac. Implement adaptive model selection based on unified memory, measured speed, thermal state, power mode, user preference, and language.
10. Use actors and structured concurrency for model state, audio state, database access, and clipboard operations.
11. Do not block the main thread with model loading, inference, disk access, Accessibility calls, or audio conversion.
12. Create unit tests, integration tests, UI tests, benchmark tools, and a reproducible manual test checklist as specified below.
13. Pin every dependency and model to a tested version or immutable revision before declaring the build complete.
14. Maintain a `THIRD_PARTY_NOTICES.md` file and comply with every code and model license.
15. Do not claim completion until every acceptance criterion in this document is demonstrated.

---

# 1. Executive Summary

FlowLocal is a native macOS menu bar application that lets the user hold a global shortcut, speak naturally, release the shortcut, and have clean text appear at the current cursor in almost any Mac application.

It should feel instantaneous and dependable while remaining completely local. It must support:

- Push-to-talk dictation anywhere
- Hands-free dictation
- Live waveform and optional streaming preview
- Automatic punctuation and capitalization
- Filler removal and self-correction handling
- App-aware and cursor-aware formatting
- Personal vocabulary, substitutions, and snippets
- Per-context writing styles
- Voice-driven rewriting and commands
- Selection transformation
- Dictation and transformation history
- Paste last and copy last
- Local scratchpad and note history
- Automatic selection of lighter or heavier local models
- English, Pakistani English, Urdu, Arabic, Hindi, and other supported languages through an engine-routing layer
- Fully offline operation after model installation

The correct engineering approach is not to force one model to perform all tasks. Use a layered pipeline:

1. **Low-latency audio capture and VAD** for immediate response.
2. **Fast ASR engine** for English and supported European languages.
3. **Higher-quality multilingual ASR engine** when the machine has enough memory.
4. **Whisper fallback** for Urdu and languages missing from the preferred ASR engine's published language list.
5. **Deterministic text processing** for operations that do not need an LLM.
6. **Small local LLM** for fast cleanup.
7. **Larger local LLM** for voice commands, rewrites, and high-quality polish on higher-memory Macs.
8. **Reliable context capture and text injection** through macOS Accessibility and clipboard APIs.

This architecture allows a 16 GB MacBook Air to remain responsive while a 24 GB or 32 GB Mac can use heavier models for higher accuracy.

---

# 2. Product and Legal Boundary

## 2.1 What this project is

This is an original, local-first macOS voice productivity application inspired by publicly documented behavior found in commercial dictation products.

## 2.2 What this project is not

Do not:

- Use the name Wispr, Wispr Flow, Flow by Wispr, or a confusingly similar brand in the shipping app.
- Copy their logo, colors, marketing text, animations, screenshots, sounds, icons, or exact interface.
- Reverse engineer binaries, decrypt traffic, scrape private endpoints, bypass subscriptions, or use confidential material.
- represent the application as affiliated with Wispr.

## 2.3 Code-license policy

- New code should use an MIT license unless the owner wants the repository private with all rights reserved.
- MIT-licensed repositories may be studied and adapted with attribution.
- GPL code must not be copied into this project unless the entire resulting project will be distributed under GPL-compatible terms.
- TypeWhisper is useful as a behavioral reference but is GPLv3. Do not copy its code into a non-GPL codebase.
- NVIDIA Parakeet TDT v3 model weights are CC BY 4.0 and require attribution.
- Qwen3-ASR and Qwen3.5 model weights are Apache 2.0 at the researched revisions.
- OpenAI Whisper is MIT.
- Preserve all required notices in `THIRD_PARTY_NOTICES.md` and an in-app Licenses screen.

---

# 3. Research: What Wispr Flow Currently Does

The following section records publicly documented product behavior as of July 22, 2026. The objective is behavioral coverage, not source-code imitation.

## 3.1 System-wide voice dictation

Wispr Flow provides voice dictation into text fields across desktop applications. On Mac, the documented default push-to-talk shortcut is the Apple `Fn` key. The user holds it while speaking and releases it to submit. A cross-keyboard fallback such as `Ctrl+Opt` is recommended when a true Apple Fn key is unavailable.

FlowLocal must support:

- Hold-to-record
- Release-to-transcribe
- A configurable minimum press duration to avoid accidental recordings
- Multiple shortcuts per action
- Built-in keyboard and external keyboard compatibility
- Mouse-button shortcuts where macOS exposes them
- An always-available fallback shortcut

## 3.2 Hands-free mode

The commercial reference supports starting dictation without holding a key, including double-tapping the dictation shortcut or using a separate hands-free binding.

FlowLocal must support:

- Double-tap the push-to-talk shortcut to lock recording
- A dedicated hands-free shortcut
- Click Stop in the floating bar
- Press Escape to cancel
- Optional silence timeout
- Long sessions with chunking so memory does not grow without bound

## 3.3 Floating Flow Bar behavior

The reference product has a compact floating bar that shows listening state, waveform, cancel, and stop controls. It can remain above other windows and can be hidden.

FlowLocal should have an original floating interface with:

- Non-activating `NSPanel`
- No focus theft from the user's current application
- Placement at bottom center by default
- Optional edge snapping
- Drag support
- All Spaces support
- Full-screen auxiliary behavior
- Idle, listening, processing, success, warning, and error states
- Live audio level visualization
- Optional partial transcript preview
- Accessibility labels and reduced-motion support

## 3.4 Smart formatting

Public documentation describes formatting behavior such as:

- Context-aware capitalization
- Correct spacing before and after inserted text
- Filler-word removal
- False-start removal
- Self-correction handling based on phrases such as “actually” and “scratch that”
- Different punctuation behavior in messaging applications
- Preservation of meaning while cleaning speech

FlowLocal must implement a three-stage text pipeline:

1. ASR normalization
2. Deterministic rules
3. Optional local LLM refinement

The local LLM must never freely rewrite factual content. It should clean speech conservatively and preserve names, numbers, code, URLs, commands, quotations, and domain terms.

## 3.5 Context awareness

The reference product uses the active application and nearby text to improve spelling, capitalization, punctuation, and style. Its documentation states that Accessibility permission is needed on Mac.

FlowLocal should locally collect only the minimum context necessary:

- Frontmost application name and bundle identifier
- Focused element role and subrole
- Selected text
- Cursor position, when exposed
- Limited text before the cursor
- Limited text after the cursor
- Placeholder or field title only when useful
- Browser hostname only when it can be obtained locally without screen scraping

Default limits:

- Up to 1,000 Unicode scalar characters before the cursor
- Up to 400 characters after the cursor
- Up to 12,000 characters of explicitly selected text for Command Mode
- No screenshots in the default product
- No full-window scraping
- No unrelated fields

Password and secure fields must never be read. Custom web password fields can be difficult to detect, so also use heuristics based on AX role, subrole, HTML-like metadata when exposed, field labels, and app blocklists.

## 3.6 Styles

The reference product provides app-category style personalization, including categories resembling:

- Personal messages
- Work messages
- Email
- Other

FlowLocal should support the same useful concept with original names and design. Each style profile can define:

- Formality
- Concision
- Emoji allowance
- Contraction preference
- Greeting behavior
- Sign-off behavior
- Bullet formatting
- Sentence length preference
- Custom instructions
- Writing examples

The user should be able to map bundle identifiers and websites to style profiles.

## 3.7 Dictionary and replacements

The reference product supports vocabulary entries, automatic learning from corrections, imports, and replacement behavior.

FlowLocal must support:

- Preferred spelling
- Spoken alias to written form
- Case-sensitive or case-insensitive matching
- Whole-word matching
- Literal phrase replacement
- Optional phonetic hints
- Per-language entries
- Personal priority flag
- Import and export as JSON and CSV
- Immediate activation without app restart
- Optional learning from post-paste corrections

Automatic learning must be opt-in and local. It should compare the recently inserted text with the field contents after a configurable delay, then propose a correction rather than silently learning every edit.

## 3.8 Snippets

The reference product supports spoken triggers that expand into longer saved text. Its desktop documentation describes triggers up to 60 characters and expansions up to 4,000 characters.

FlowLocal should support at least those limits and add:

- Exact trigger
- Natural-language trigger aliases
- Case-insensitive matching
- Optional confirmation for sensitive snippets
- Placeholders such as date, time, clipboard, and cursor marker
- Import and export
- Category folders
- App-specific availability

Example:

- Trigger: `my meeting link`
- Expansion: `https://calendly.com/example/30min`

Sensitive snippets such as addresses, account details, or identity numbers must be marked sensitive and never shown in history previews.

## 3.9 Command Mode

The reference product supports selecting text and speaking an instruction to transform it. It also permits inline text generation when nothing is selected.

FlowLocal Command Mode must support:

- Rewrite selected text
- Shorten
- Expand
- Make professional
- Make friendly
- Fix grammar
- Turn into bullets
- Translate
- Summarize
- Change tone
- Generate new text at the cursor
- Execute safe text-editing actions such as press Enter, delete last word, or insert a line break
- Propose settings changes, but require visual confirmation before applying them

Do not implement unrestricted computer-control commands in v1. Command Mode is a text transformation system, not a general autonomous agent.

## 3.10 History and recovery

The reference product retains transcript history and allows recovery, retry, copy, and AI-edit undo or redo.

FlowLocal must store:

- Raw transcript
- Rule-processed text
- Final polished text
- Active application
- Language
- Model and engine
- Timing metrics
- Whether insertion succeeded
- Original selected text for transformations
- Transformation instruction
- Error details

The user must be able to:

- Copy raw or final text
- Paste final text again
- Re-run cleanup with another profile
- Undo the local AI polish in history
- Retry a failed ASR job if audio retention was enabled
- Delete one item
- Clear a date range
- Auto-delete after a chosen retention period
- Disable history entirely

Audio retention must be off by default.

## 3.11 Scratchpad

The reference product includes a notes workspace with search, tabs, version history, formatting, and attachments.

FlowLocal should include a local Scratchpad after core dictation is stable. It should support:

- Fast global shortcut
- New note or resume last note
- Multi-tab editing
- Markdown or attributed-string editing
- Autosave
- Search
- Pinning
- Version history
- Dictation directly into notes
- Local image attachments
- Export as Markdown, plain text, or PDF only if later requested

This is a secondary feature. It must not delay delivery of reliable system-wide dictation.

## 3.12 Coding context

The reference product offers IDE-specific enhancements such as variable recognition and file tagging in selected editors.

FlowLocal v1 should provide safe coding assistance through:

- Dictionary boosting from open project symbols when permission is granted
- Recognition of `camelCase`, `PascalCase`, `snake_case`, kebab-case, file extensions, paths, and common programming tokens
- App profile for Cursor, Visual Studio Code, Xcode, Terminal, iTerm2, and Warp
- Terminal-specific paste behavior
- Optional workspace file index in Cursor or Visual Studio Code, never enabled automatically

Do not modify project files or run terminal commands merely because they were spoken during dictation.

## 3.13 Privacy difference

Wispr's current public data-controls page states that its transcription always occurs in the cloud, even though it offers privacy controls and zero-retention arrangements. FlowLocal's central differentiator is that audio, context, transcript cleanup, history, and notes remain on the Mac.

---

# 4. Inferred Architecture of the Commercial Reference

Wispr has not published its complete proprietary architecture. The following is an inference from public product behavior and documentation, not a claim about its private source code.

A likely request pipeline is:

1. Global shortcut listener starts microphone capture.
2. A floating overlay displays listening state.
3. Audio is streamed or submitted to cloud ASR.
4. The app identifies the frontmost application and focused text field.
5. Nearby text and user personalization are attached to the request when enabled.
6. ASR output is processed by rules and one or more language models.
7. The desktop client temporarily places the result on the clipboard.
8. The client simulates paste into the focused application.
9. On successful paste, the original clipboard is restored.
10. On failed paste, the dictated text remains on the clipboard for manual recovery.
11. Transcript and editing metadata may be stored locally or synchronized according to privacy settings.

FlowLocal should recreate this interaction pattern locally, replacing cloud inference with Core ML and MLX engines.

---

# 5. Goals, Non-Goals, and Release Scope

## 5.1 Primary goals

1. Dictation should work in nearly every common editable Mac text field.
2. Core functionality should work offline.
3. No recurring cost or API key should be required.
4. English accuracy should be excellent for a Pakistani English speaker.
5. Urdu should be supported through the Whisper engine.
6. M4 and M5 MacBook Air models should receive different model recommendations when their memory and benchmarks differ.
7. The application should automatically downshift under heat, low power, or memory pressure.
8. Dictated text must always be recoverable.
9. The interaction should feel immediate even when final polishing takes longer.
10. The codebase should be maintainable and modular enough to swap models later.

## 5.2 Non-goals for v1

- iPhone, iPad, Windows, or Android clients
- Cross-device sync
- Cloud backups
- Team administration
- Enterprise policy management
- General autonomous computer control
- Meeting transcription and speaker diarization
- Screen capture as context
- Browser extensions
- App Store submission
- Exact reproduction of Wispr branding or interface

## 5.3 Definition of “100% working”

For this project, “100% working” means every accepted feature in the release scope passes its defined test matrix and failure-recovery requirements. It does not mean copying undisclosed proprietary internals or guaranteeing compatibility with every third-party application in existence.

---

# 6. Target Hardware and Adaptive Performance Profiles

## 6.1 Supported machines

Initial support:

- Apple Silicon M1 or newer
- macOS 15 or newer
- 8 GB unified memory minimum for basic mode
- 16 GB or more strongly recommended

Primary optimization targets:

- MacBook Air M4
- MacBook Air M5

Apple lists the M5 MacBook Air with a 10-core CPU, 8-core or 10-core GPU, 16-core Neural Engine, 153 GB/s memory bandwidth, and unified-memory configurations of 16 GB, 24 GB, or 32 GB. Do not infer memory from chip generation alone. Read actual physical memory at runtime.

## 6.2 Runtime hardware detection

Create a `HardwareProfiler` that records:

```swift
struct HardwareProfile: Codable, Sendable {
    let machineIdentifier: String
    let chipFamily: String
    let physicalMemoryBytes: UInt64
    let osVersion: OperatingSystemVersion
    let isLowPowerModeEnabled: Bool
    let thermalState: ProcessInfo.ThermalState
    let batteryPowered: Bool
    let batteryPercent: Double?
    let availableDiskBytes: Int64
}
```

Use:

- `ProcessInfo.processInfo.physicalMemory`
- `ProcessInfo.processInfo.thermalState`
- `ProcessInfo.thermalStateDidChangeNotification`
- `ProcessInfo.processInfo.isLowPowerModeEnabled`
- IOKit or supported system APIs for battery status
- `URLResourceValues.volumeAvailableCapacityForImportantUsage`
- `sysctl` for machine and CPU identifiers where appropriate

## 6.3 Recommended profiles

These are initial recommendations. The first-run benchmark can override them.

| Profile | Typical hardware | Streaming or preview ASR | Final ASR | Fast cleanup LLM | Command LLM |
|---|---|---|---|---|---|
| Minimal | 8 GB Apple Silicon | Parakeet or lightweight Whisper | Parakeet TDT v3 or Whisper small | Rules first, Qwen3.5 0.8B optional | Qwen3.5 0.8B |
| Balanced | 16 GB M4 or M5 | Parakeet streaming preview | Parakeet TDT v3 for supported languages, Qwen3-ASR 0.6B optional, Whisper for Urdu | Qwen3.5 0.8B or 2B | Qwen3.5 2B |
| Quality | 24 GB M4 or M5 | Parakeet streaming preview | Qwen3-ASR 1.7B or selected benchmark winner, Whisper large-v3-turbo for Urdu | Qwen3.5 2B | Qwen3.5 4B |
| Maximum | 32 GB or more | High-quality streaming engine | Qwen3-ASR 1.7B plus optional verification, Whisper large-v3 for unsupported languages | Qwen3.5 4B | Qwen3.5 9B 4-bit if benchmarks remain acceptable |

## 6.4 Dynamic downshift rules

Immediately downshift one tier when:

- Thermal state becomes `.serious`
- Low Power Mode is enabled and the user selected automatic power management
- Available memory falls below a safe threshold
- Model inference exceeds the configured latency budget for three consecutive jobs

Downshift to the minimum safe engine when:

- Thermal state becomes `.critical`
- The operating system issues memory-pressure warnings
- A model load fails due to memory

Restore a heavier tier only after:

- Thermal state is `.nominal` or `.fair` for five minutes
- There is no active dictation
- No model job is queued
- The user has not locked a manual profile

Never switch models in the middle of an active transcription unless the active engine fails. If failure occurs, retain the audio buffer and retry with the fallback engine.

## 6.5 First-run personalized benchmark

Do not select models only from synthetic benchmark claims. Build an onboarding benchmark using the actual user and Mac.

Collect a local sample set containing:

- 30 seconds of normal Pakistani English
- Names such as Abdul Rafay, Dev Entities, ZCA, Claude, Supabase, PostgreSQL, SwiftUI, Xcode
- A sentence with numbers and currency
- A sentence with self-correction
- A code-oriented sentence with identifiers
- Optional Urdu sample
- Optional Arabic or Hindi sample

For each installed candidate engine, measure:

- Word error rate against the displayed reference sentence
- Name and technical-term accuracy
- First partial latency
- Finalization latency
- Peak memory
- Average power impact where obtainable
- Thermal change during repeated runs

Default weighted score:

```text
score =
    0.55 * normalizedAccuracyScore
  + 0.25 * normalizedLatencyScore
  + 0.10 * normalizedMemoryScore
  + 0.10 * normalizedEnergyScore
```

The user can choose Automatic, Fastest, Balanced, Highest Accuracy, or Manual after seeing results.

---

# 7. Model Research and Selected Stack

## 7.1 ASR engine abstraction

Define a common protocol:

```swift
protocol ASREngine: Actor {
    var id: String { get }
    var displayName: String { get }
    var capabilities: ASRCapabilities { get }

    func prepare(configuration: ASRConfiguration) async throws
    func startStreaming(context: ASRContext) async throws
    func acceptAudio(_ buffer: AudioChunk) async throws -> ASRPartial?
    func finishStreaming() async throws -> ASRResult
    func transcribeFile(_ url: URL, context: ASRContext) async throws -> ASRResult
    func cancel() async
    func unload() async
}
```

Every engine must return a common result:

```swift
struct ASRResult: Codable, Sendable {
    let text: String
    let detectedLanguage: String?
    let segments: [ASRSegment]
    let words: [ASRWord]
    let confidence: Double?
    let durationSeconds: Double
    let inferenceSeconds: Double
    let modelID: String
}
```

## 7.2 FluidAudio and NVIDIA Parakeet TDT v3

**Role:** Default low-latency English and European-language engine.

Why:

- Native Swift SDK
- Fully local inference
- Core ML and Apple Neural Engine focus
- Low latency on Apple hardware
- NVIDIA Parakeet TDT v3 includes punctuation, capitalization, timestamps, and 25 European languages
- 600 million parameters

Limitations:

- Published language support does not include Urdu, Arabic, or Hindi.
- Vocabulary boosting and postprocessing remain important for names and technical words.
- Model attribution is required under CC BY 4.0.

Implementation:

- Add FluidAudio using Swift Package Manager.
- Research snapshot package line: `from: "0.12.4"`.
- Pin the exact tested tag and model revision after integration testing.
- Use the streaming-capable FluidAudio path if stable at the pinned version.
- If final TDT decoding is more accurate than streaming output, use streaming for preview and run a final decode on release.

## 7.3 Qwen3-ASR 0.6B and 1.7B

**Role:** Higher-quality multilingual engine on sufficiently capable Macs.

The official model card states that Qwen3-ASR supports 30 languages and 22 Chinese dialects, offers both streaming and offline inference, and provides 0.6B and 1.7B models. The 1.7B model is the quality tier. The published language list includes Arabic, Hindi, Persian, and many others, but it does not list Urdu.

Recommended Apple Silicon integration options:

1. `ontypehq/mlx-swift-asr`
   - Qwen3-ASR 0.6B and 1.7B support
   - Actor-based API
   - Built-in resampling
   - Metal warmup
   - MIT license
2. `soniqo/speech-swift`
   - Broader Apple Silicon speech toolkit
   - MLX and Core ML

Start with `mlx-swift-asr` because it is narrower and easier to isolate behind the ASR protocol. Keep the adapter replaceable.

Initial routing:

- 16 GB: allow Qwen3-ASR 0.6B as an optional quality engine after benchmark.
- 24 GB and 32 GB: install and benchmark Qwen3-ASR 1.7B.
- Use Qwen for Arabic, Hindi, Persian, and other supported languages if it beats Whisper on the user's samples.
- Do not route Urdu to Qwen by default because Urdu is absent from its published language list.

## 7.4 Whisper and WhisperKit

**Role:** Universal multilingual fallback, especially Urdu.

OpenAI Whisper is a general-purpose multilingual speech-recognition system. Its official tokenizer includes Urdu (`ur`). WhisperKit provides on-device Apple Silicon deployment with streaming, word timestamps, and voice activity detection.

Recommended model choices:

| Device profile | Whisper model |
|---|---|
| 8 GB | small or small multilingual |
| 16 GB | large-v3-turbo if stable and benchmarked, otherwise medium |
| 24 GB | large-v3-turbo |
| 32 GB | large-v3 or large-v3-turbo according to accuracy and heat |

Use an explicit language hint for Urdu when the user selects Urdu or when language detection is uncertain. Hindi and Urdu can be acoustically similar, and automatic detection may choose the wrong script.

WhisperKit repository history and packaging have changed. Pin a tested stable package revision rather than blindly tracking `main`.

## 7.5 Voxtral Mini 4B Realtime

**Role:** Experimental optional engine only.

Mistral's Voxtral Mini 4B Realtime offers streaming transcription with configurable delay, but its published deployment path is centered on vLLM rather than a mature native Swift stack. A 4B audio model is also comparatively heavy for a fanless MacBook Air.

Do not make Voxtral a release blocker or default. Add it later only if a stable MLX or Core ML implementation proves competitive on the target Macs.

## 7.6 Local text-refinement LLM

Use MLX Swift LM for embedded local text models.

Recommended family:

- Qwen3.5 0.8B
- Qwen3.5 2B
- Qwen3.5 4B
- Qwen3.5 9B, only on high-memory Macs if measured latency is acceptable

Reasons:

- Apache 2.0 model license
- Small and medium sizes
- Strong instruction following
- Current MLX Swift LM support
- Structured output and tool-call support in recent MLX Swift LM releases

Research snapshot:

```swift
.package(
    url: "https://github.com/ml-explore/mlx-swift-lm",
    .upToNextMajor(from: "3.31.3")
)
```

Pin the exact tested release. Do not automatically upgrade model runtime libraries in a working build.

## 7.7 Two local LLM roles

### Fast Refiner

Always warm when memory permits.

Responsibilities:

- Filler removal
- False-start cleanup
- Conservative self-correction resolution
- Spacing and capitalization
- App-style application
- Light grammar repair

Target models:

- 16 GB: Qwen3.5 0.8B or 2B
- 24 GB: Qwen3.5 2B
- 32 GB: Qwen3.5 4B

### Command Model

Loaded lazily or kept warm only on high-memory machines.

Responsibilities:

- Selection rewrites
- Summaries
- Translations
- Structured voice commands
- Settings-change proposals
- More complex style transformations

Target models:

- 16 GB: Qwen3.5 2B
- 24 GB: Qwen3.5 4B
- 32 GB: Qwen3.5 9B 4-bit if benchmarked, otherwise 4B

## 7.8 Model download and inventory manager

Create a `ModelManager` actor with:

- Registry of approved models
- Download URL and source repository
- Immutable revision or SHA
- Expected files
- Expected byte size
- SHA-256 verification
- License and attribution metadata
- Minimum RAM
- Recommended RAM
- Supported languages
- Engine adapter
- Install, pause, resume, cancel, verify, repair, and delete operations
- Disk-space preflight
- Partial-download cleanup
- User-imported local model folder support
- No automatic download on launch

Store models under:

```text
~/Library/Application Support/FlowLocal/Models/
```

Use one subfolder per provider, model, quantization, and revision.

Example registry model:

```swift
struct ModelManifest: Codable, Hashable, Sendable {
    let id: String
    let family: String
    let task: ModelTask
    let sourceURL: URL
    let revision: String
    let files: [ModelFile]
    let license: String
    let attribution: String?
    let minimumMemoryGB: Int
    let recommendedMemoryGB: Int
    let languages: [String]
    let experimental: Bool
}
```

---

# 8. Native macOS Architecture

## 8.1 Technology choices

- Swift 6
- SwiftUI for settings, history, onboarding, and Scratchpad
- AppKit for menu bar, non-activating panels, event taps, window behavior, and paste integration
- AVFoundation and `AVAudioEngine` for microphone capture
- Core Audio utilities for device selection and format conversion
- Core Graphics `CGEventTap` for press and release detection
- macOS Accessibility API through `AXUIElement`
- MLX Swift and MLX Swift LM for local LLM inference
- Core ML through FluidAudio for Parakeet
- WhisperKit for Whisper
- SQLite through GRDB for durable local storage
- OSLog for local diagnostic logging
- CryptoKit for SHA-256 verification
- ServiceManagement `SMAppService` for launch at login

## 8.2 High-level component graph

```text
┌─────────────────────────────────────────────────────────────────┐
│                         FlowLocal App                            │
├─────────────────────────────────────────────────────────────────┤
│ Menu Bar │ Settings │ History │ Scratchpad │ Floating Panel     │
├─────────────────────────────────────────────────────────────────┤
│                     DictationCoordinator                        │
├───────────────┬────────────────┬────────────────┬───────────────┤
│ HotkeyService │ ContextService │ AudioPipeline  │ PasteService  │
├───────────────┴────────────────┴────────────────┴───────────────┤
│                       ProcessingPipeline                        │
│  ASR Router -> Rules -> Dictionary -> Snippets -> Local LLM    │
├───────────────────────┬─────────────────────────────────────────┤
│ ModelManager          │ AdaptivePerformanceController           │
├───────────────────────┼─────────────────────────────────────────┤
│ SQLite Store          │ Local Files and Model Cache             │
└───────────────────────┴─────────────────────────────────────────┘
```

## 8.3 State machine

Use one authoritative state machine. Do not scatter booleans through views.

```swift
enum DictationState: Equatable, Sendable {
    case idle
    case arming(sessionID: UUID)
    case recording(SessionSnapshot)
    case finalizing(SessionSnapshot)
    case transcribing(SessionSnapshot, progress: Double?)
    case refining(SessionSnapshot, rawText: String)
    case inserting(SessionSnapshot, finalText: String)
    case succeeded(SessionResult)
    case recoverableFailure(SessionFailure)
    case cancelled
}
```

Valid transitions:

```text
idle -> arming -> recording -> finalizing -> transcribing
transcribing -> refining -> inserting -> succeeded -> idle
transcribing -> inserting -> succeeded -> idle
any active state -> cancelled -> idle
any processing state -> recoverableFailure
recoverableFailure -> retry | copy | paste | discard -> idle
```

Reject concurrent dictations in v1. If the user presses the shortcut while a previous job is processing, either:

- Queue one new recording only if the audio pipeline can safely isolate sessions, or
- Show a brief “Finishing previous dictation” warning.

Prefer correctness over allowing uncontrolled concurrency.

## 8.4 Repository structure

```text
FlowLocal/
├── FlowLocal.xcodeproj
├── App/
│   ├── FlowLocalApp.swift
│   ├── AppDelegate.swift
│   ├── AppEnvironment.swift
│   └── AppCommands.swift
├── Core/
│   ├── Dictation/
│   │   ├── DictationCoordinator.swift
│   │   ├── DictationState.swift
│   │   ├── DictationSession.swift
│   │   └── SessionRecovery.swift
│   ├── Audio/
│   │   ├── AudioCaptureService.swift
│   │   ├── AudioDeviceManager.swift
│   │   ├── AudioResampler.swift
│   │   ├── VoiceActivityDetector.swift
│   │   └── AudioRingBuffer.swift
│   ├── Hotkeys/
│   │   ├── GlobalHotkeyService.swift
│   │   ├── EventTapManager.swift
│   │   ├── ShortcutRecorder.swift
│   │   └── ShortcutValidator.swift
│   ├── Accessibility/
│   │   ├── PermissionService.swift
│   │   ├── FocusedElementReader.swift
│   │   ├── ContextSnapshot.swift
│   │   ├── SecureFieldDetector.swift
│   │   └── AXHelpers.swift
│   ├── Insertion/
│   │   ├── TextInjectionService.swift
│   │   ├── ClipboardSnapshot.swift
│   │   ├── PasteVerification.swift
│   │   └── AppPasteStrategy.swift
│   ├── Processing/
│   │   ├── ProcessingPipeline.swift
│   │   ├── TextNormalizer.swift
│   │   ├── BacktrackProcessor.swift
│   │   ├── ContextFormatter.swift
│   │   ├── DictionaryProcessor.swift
│   │   ├── SnippetProcessor.swift
│   │   ├── RefinementDecider.swift
│   │   └── ResultValidator.swift
│   ├── Models/
│   │   ├── ModelManager.swift
│   │   ├── ModelRegistry.swift
│   │   ├── ModelDownloader.swift
│   │   ├── HardwareProfiler.swift
│   │   ├── BenchmarkRunner.swift
│   │   └── AdaptivePerformanceController.swift
│   ├── ASR/
│   │   ├── ASREngine.swift
│   │   ├── ASRRouter.swift
│   │   ├── FluidAudioASREngine.swift
│   │   ├── QwenASREngine.swift
│   │   └── WhisperASREngine.swift
│   ├── LLM/
│   │   ├── LocalLLMEngine.swift
│   │   ├── MLXLLMEngine.swift
│   │   ├── PromptBuilder.swift
│   │   ├── StructuredOutputParser.swift
│   │   └── LLMGuardrails.swift
│   └── Storage/
│       ├── AppDatabase.swift
│       ├── Migrations.swift
│       ├── Repositories/
│       └── RetentionService.swift
├── Features/
│   ├── Onboarding/
│   ├── MenuBar/
│   ├── FloatingPanel/
│   ├── Settings/
│   ├── History/
│   ├── Dictionary/
│   ├── Snippets/
│   ├── Styles/
│   ├── CommandMode/
│   ├── Scratchpad/
│   ├── ModelCenter/
│   └── Diagnostics/
├── Shared/
│   ├── DesignSystem/
│   ├── Extensions/
│   ├── Utilities/
│   └── Logging/
├── Resources/
│   ├── Assets.xcassets
│   ├── Localizable.xcstrings
│   ├── DefaultProfiles.json
│   └── ModelRegistry.json
├── Tests/
│   ├── UnitTests/
│   ├── IntegrationTests/
│   ├── UITests/
│   ├── PerformanceTests/
│   └── Fixtures/
├── Scripts/
│   ├── build-local.sh
│   ├── package-dmg.sh
│   ├── verify-models.sh
│   └── run-benchmarks.sh
├── README.md
├── ARCHITECTURE.md
├── PRIVACY.md
├── THIRD_PARTY_NOTICES.md
└── TESTING.md
```

---

# 9. Detailed End-to-End Dictation Flow

## 9.1 Shortcut press

1. Global event tap detects shortcut down.
2. Reject autorepeat.
3. Record press timestamp.
4. Create a new session UUID.
5. Capture a lightweight context snapshot immediately:
   - Frontmost app
   - Focused element identity
   - Secure-field risk
6. Display listening panel within 50 ms.
7. Start microphone capture within 100 ms.
8. Play optional subtle start sound.

## 9.2 During recording

1. Capture mono PCM.
2. Maintain the original device sample rate internally only as needed.
3. Resample to 16 kHz mono Float32 for ASR.
4. Feed VAD.
5. Feed streaming ASR if active.
6. Update audio level at 30 to 60 Hz, but throttle UI rendering.
7. Update partial transcript no more than 4 to 8 times per second.
8. Write long-session audio to a temporary chunked file instead of retaining unlimited RAM.
9. If the input device disconnects, attempt one automatic switch to the default input and notify the user.

## 9.3 Shortcut release

1. Stop accepting new audio.
2. Flush resampler and streaming decoder.
3. Capture final cursor and field context again.
4. Determine whether focus changed:
   - If the same editable field remains focused, target it.
   - If another editable field is now focused and the user changed focus during dictation, target the current field but include a visible recovery option.
   - If no editable field is focused, copy final text and show recovery notification.
5. Select ASR route based on language, profile, benchmark, heat, and installed models.
6. Run final ASR if streaming output is not authoritative.
7. Run deterministic text processing.
8. Decide whether local LLM refinement is necessary.
9. Validate final text.
10. Insert and verify.
11. Persist history according to retention settings.
12. Delete temporary audio unless audio retention is enabled.

## 9.4 Empty or accidental recording

If duration is shorter than the configurable threshold, default 250 ms, or VAD finds no speech:

- Cancel without invoking a model.
- Do not modify clipboard.
- Do not create a history row unless diagnostics are enabled.
- Play an optional soft cancel sound.

---

# 10. Global Hotkeys

## 10.1 Default bindings

Recommended defaults:

| Action | Default |
|---|---|
| Push to talk | `Fn` on built-in Apple keyboard |
| Cross-keyboard push to talk | `Ctrl+Opt` |
| Hands-free | `Fn+Space` or `Ctrl+Opt+Space` |
| Command Mode | `Fn+Ctrl` or `Ctrl+Opt+Cmd` |
| Cancel | `Esc` while active |
| Paste last | `Ctrl+Cmd+V` |
| Copy last | `Ctrl+Cmd+C` |
| Open Scratchpad | `Opt+S` |

Do not register conflicting defaults simultaneously without explicit user confirmation.

## 10.2 Implementation

Use a `CGEventTap` for:

- Modifier-only shortcuts
- Press and release state
- Fn handling
- Mouse buttons
- Double-tap detection

A convenience shortcut package can be used for ordinary key combinations, but it must not replace the event-tap path for modifier-only hold behavior.

## 10.3 Shortcut safety

- Never swallow normal keystrokes except the configured shortcut while it is actively being interpreted.
- Restore event-tap state after wake from sleep.
- Detect when macOS disables the event tap due to timeout and re-enable it.
- Validate reserved shortcuts.
- Detect duplicate bindings.
- Permit up to four bindings per action.
- Exclude left and right click.
- Provide a test field in Settings.

## 10.4 Secure Keyboard Entry

Some applications or focused password fields enable Secure Keyboard Entry, which can block global shortcuts.

FlowLocal must:

- Detect shortcut failure patterns where possible.
- Keep a fallback modifier or mouse shortcut available.
- Show a local notification explaining that another application may have Secure Keyboard Entry enabled.
- Never attempt to bypass macOS security controls.

---

# 11. Audio Capture and VAD

## 11.1 Capture

Use `AVAudioEngine.inputNode` and install a tap on the input node.

Requirements:

- User-selectable input device
- Follow-system-default option
- AirPods support
- USB microphone support
- Automatic handling of format changes
- Echo-safe operation with no system-audio capture in v1
- Ring buffer with bounded memory
- Monotonic timestamps

## 11.2 Audio format

Canonical ASR format:

```text
16,000 Hz
Mono
Float32 normalized to [-1, 1]
```

Keep audio conversion in an actor or dedicated real-time-safe processing path. Do not allocate excessively in the audio callback.

## 11.3 VAD

VAD responsibilities:

- Detect no-speech recordings
- Trim excessive leading and trailing silence
- Support hands-free silence termination
- Break long recordings into stable chunks
- Avoid cutting pauses within sentences

Suggested defaults:

- Start speech threshold: tune from user microphone noise floor
- End silence for hands-free: 1.2 seconds, configurable
- Keep 250 ms pre-roll
- Keep 300 ms post-roll
- Maximum in-memory audio: 60 seconds before spilling to a temp file

Use FluidAudio VAD if stable in the pinned release, otherwise use a small local VAD with a permissive license.

## 11.4 Long sessions

Support at least 20 minutes per session to match the reference behavior. Architect for longer sessions by chunking.

At 19 minutes:

- Show a one-minute warning if the configured limit remains 20 minutes.

At the limit:

- Finalize safely.
- Preserve all audio chunks until transcription succeeds or the user discards them.
- Permit immediate start of a new session.

The user can later raise the local limit because there is no cloud request limit, but thermal and memory safeguards still apply.

---

# 12. Context Awareness and Secure Data Handling

## 12.1 Accessibility permission

On first use, call `AXIsProcessTrustedWithOptions` with a user-facing prompt. Explain why Accessibility is required:

- Detect focused text field
- Read limited text around the cursor
- Insert dictated text
- Transform selected text

Do not ask for Screen Recording permission in v1.

## 12.2 Focused element capture

Use:

- `AXUIElementCreateSystemWide()`
- `kAXFocusedUIElementAttribute`
- `kAXRoleAttribute`
- `kAXSubroleAttribute`
- `kAXValueAttribute`
- `kAXSelectedTextAttribute`
- `kAXSelectedTextRangeAttribute`
- `kAXTitleAttribute`
- `kAXDescriptionAttribute`
- `kAXPlaceholderValueAttribute`, where available

All Accessibility calls must have timeouts and error handling. Some applications expose incomplete or expensive AX trees.

## 12.3 Context snapshot

```swift
struct ContextSnapshot: Codable, Sendable {
    let timestamp: Date
    let appName: String
    let bundleIdentifier: String?
    let processIdentifier: pid_t
    let elementRole: String?
    let elementSubrole: String?
    let fieldTitle: String?
    let placeholder: String?
    let selectedText: String?
    let textBeforeCursor: String?
    let textAfterCursor: String?
    let cursorLocation: Int?
    let isEditable: Bool
    let isSecure: Bool
    let browserHost: String?
    let contextConfidence: Double
}
```

## 12.4 Secure-field detector

Treat the field as secure when any of these apply:

- AX secure text role or subrole
- Known password-manager secure surface
- Label or placeholder strongly indicates password, passcode, PIN, CVV, OTP, recovery phrase, private key, or secret
- Browser field metadata exposes password behavior
- User-defined blocked application

Secure behavior:

- Do not read existing contents.
- Do not include app-context text in an LLM prompt.
- Do not store a transcript preview in history by default.
- By default, do not auto-paste into a field suspected to contain a password, private key, banking credential, or recovery phrase.
- Offer Copy instead with a clear warning.

## 12.5 App categories

Create default mapping rules:

- Personal messaging: Messages, WhatsApp, Telegram, Signal, Discord personal chats
- Work messaging: Slack, Microsoft Teams, Discord workspaces
- Email: Mail, Gmail, Outlook, Spark
- Documents: Notes, TextEdit, Pages, Word, Notion, Google Docs
- Coding: Xcode, Cursor, Visual Studio Code
- Terminal: Terminal, iTerm2, Warp
- AI chat: ChatGPT, Claude, local model chats
- Other

Allow per-app and per-host overrides.

---

# 13. Text Processing Pipeline

## 13.1 Pipeline order

```text
Raw ASR
  -> Unicode normalization
  -> ASR artifact cleanup
  -> Explicit spoken punctuation handling
  -> Dictionary alias replacement
  -> Snippet detection and expansion
  -> Deterministic backtrack processing
  -> Context-aware spacing and capitalization
  -> LLM-needed decision
  -> Local LLM polish if required
  -> Output validation
  -> App-specific final adjustment
  -> Insert
```

## 13.2 Unicode and whitespace normalization

- Normalize to NFC.
- Replace unusual ASR whitespace with ordinary spaces where language-appropriate.
- Preserve newlines intentionally produced by commands.
- Never collapse whitespace inside code blocks or detected literal dictation.
- Preserve non-Latin scripts.

## 13.3 Spoken punctuation

Support explicit commands only when enabled:

- comma
- period or full stop
- question mark
- exclamation mark
- colon
- semicolon
- new line
- new paragraph
- open quote and close quote
- open parenthesis and close parenthesis

Avoid replacing the ordinary word “period” when context indicates a time period or historical period. Use phrase-level rules and confidence.

## 13.4 Deterministic backtrack processor

Handle common patterns before calling an LLM:

```text
"Send it on Tuesday, actually Wednesday"
-> "Send it on Wednesday"

"The price is five hundred, scratch that, six hundred dollars"
-> "The price is six hundred dollars"

"Contact Umar, no, Umer Anjum"
-> "Contact Umer Anjum"
```

Do not apply aggressive deletion inside quotations, code, URLs, or when the correction relationship is uncertain.

## 13.5 Context-aware joining

Given text before and after cursor, determine:

- Leading space needed
- Trailing space needed
- Initial capitalization
- Whether terminal punctuation is appropriate
- Whether the insertion is mid-sentence
- Whether a selected range is being replaced

Examples:

```text
Before: "Please send"
Dictation: "the updated proposal"
Result inserted: " the updated proposal"

Before: "The build failed. "
Dictation: "I am checking the logs"
Result inserted: "I am checking the logs."
```

Messaging profiles may omit a final period for a short single sentence. Do not remove punctuation from formal email or documents.

## 13.6 Decide whether LLM refinement is needed

Skip the LLM when all of these are true:

- ASR output is short and grammatical
- No filler, false start, or self-correction marker is detected
- No style transformation is requested
- No ambiguous punctuation issue exists
- No Command Mode instruction exists

Use the LLM when one or more are true:

- Multiple fillers or repeated phrases
- A self-correction is detected but deterministic rules are uncertain
- Long unstructured utterance
- User style requests cleanup
- Selected text transformation
- Translation or summarization
- Complex coding-language formatting

This rule saves time, battery, heat, and memory.

## 13.7 Output guardrails

After LLM output:

- Reject empty output when input contained speech.
- Reject output more than 2.5 times longer than input unless the instruction requested expansion.
- Compare all numbers, dates, currency values, emails, URLs, and code identifiers between input and output.
- If protected tokens disappear or change unexpectedly, fall back to rule-processed text.
- Strip model preambles, quotation wrappers, markdown fences, and explanations unless requested.
- Preserve the original if JSON parsing fails.

---

# 14. Local LLM Prompts

## 14.1 Fast dictation polish system prompt

```text
You are the local dictation cleanup engine inside a macOS voice typing app.

Your task is to turn a raw speech transcript into the exact text the user intended to type.

Rules:
1. Preserve meaning, facts, names, numbers, dates, currency, URLs, email addresses, code, and technical terms.
2. Remove filler words only when they do not add meaning.
3. Resolve false starts and self-corrections by keeping the user's final intended version.
4. Fix punctuation, capitalization, spacing, and obvious grammar.
5. Apply the supplied writing style conservatively.
6. Use surrounding text only to join the insertion naturally.
7. Do not answer the user's content.
8. Do not add explanations, labels, quotation marks, or markdown fences.
9. Do not invent information.
10. Return only the final insertion text.
```

User payload:

```json
{
  "rawTranscript": "...",
  "language": "en",
  "appCategory": "work_message",
  "style": {
    "formality": 0.45,
    "concision": 0.75,
    "emojiAllowed": false,
    "customInstructions": "Keep Slack messages direct and human."
  },
  "textBeforeCursor": "...",
  "textAfterCursor": "...",
  "protectedTerms": ["Dev Entities", "ZCA", "$1,200", "Supabase"]
}
```

Generation settings:

- Temperature: 0.0 to 0.15
- Top-p: 0.8 or lower
- Repetition penalty: mild
- Maximum output tokens: derived from input, not a fixed huge value

## 14.2 Command Mode system prompt

```text
You are a local text-editing command engine.

Interpret the spoken instruction and return strict JSON only.
Never perform network actions, run shell commands, change files, send messages, or control applications.
You may transform selected text, generate text for insertion, propose a supported app-setting change, or return no action.
Preserve facts unless the user explicitly asks to change them.

Schema:
{
  "action": "replace" | "insert" | "settings_proposal" | "keystroke" | "none",
  "text": "string or empty",
  "settingsPatch": {},
  "keystroke": "enter" | "tab" | "backspace" | "none",
  "reason": "brief internal explanation"
}
```

User payload:

```json
{
  "instruction": "Make this shorter and more professional",
  "selectedText": "...",
  "textBeforeCursor": "...",
  "textAfterCursor": "...",
  "appCategory": "email",
  "language": "en",
  "supportedSettingsSchema": {}
}
```

The parser must reject unknown keys and unsupported actions.

## 14.3 Translation prompt

```text
Translate the supplied text into the requested target language.
Preserve proper names, numbers, URLs, email addresses, code identifiers, formatting, and line breaks.
Return only the translation.
Do not explain.
```

## 14.4 Coding dictation prompt

```text
Format the spoken content for a software-development context.
Preserve exact protected symbols and identifiers.
Convert spoken casing instructions only when explicit, such as "camel case user profile service".
Do not invent code that was not dictated.
Do not execute or suggest shell commands.
Return only the intended text.
```

---

# 15. Dictionary, Vocabulary Boosting, and Correction Learning

## 15.1 Entry types

```swift
enum DictionaryEntryType: String, Codable {
    case vocabulary
    case replacement
    case spokenAlias
    case protectedTerm
    case codingSymbol
}
```

Schema:

```swift
struct DictionaryEntry: Codable, Identifiable, Sendable {
    let id: UUID
    var language: String?
    var spokenForm: String?
    var writtenForm: String
    var type: DictionaryEntryType
    var caseSensitive: Bool
    var wholeWordOnly: Bool
    var priority: Int
    var appBundleIDs: [String]
    var isSensitive: Bool
    var source: EntrySource
    var createdAt: Date
    var updatedAt: Date
}
```

## 15.2 Processing

- Apply exact protected terms before fuzzy replacements.
- Use longest-match-first phrase replacement.
- Avoid replacing substrings inside larger words.
- Keep per-language indexes.
- Permit app-scoped entries.
- Escape regex safely.
- Add tests for punctuation boundaries and Unicode scripts.

## 15.3 Model vocabulary boosting

Where an ASR engine supports vocabulary boosting, pass a bounded list of high-priority terms relevant to:

- Active app
- Current project
- Current language
- Recently used dictionary terms

Never pass thousands of entries blindly if the model's biasing mechanism degrades decoding.

## 15.4 Auto-learn workflow

When enabled:

1. Save the exact inserted text and field identity hash.
2. Wait 3 to 10 seconds.
3. Re-read only the relevant text range if the field is still safely accessible.
4. Detect a minimal edit pair.
5. Filter common ordinary corrections.
6. Add a proposed dictionary entry to an Inbox.
7. Let the user accept, edit, or reject it.

Never monitor every keystroke globally.

---

# 16. Snippets

## 16.1 Matching rules

A snippet triggers only when:

- The complete normalized dictation matches a trigger, or
- A distinct phrase begins with an explicit expansion command such as “insert snippet”.

Do not replace a trigger buried accidentally inside a longer ordinary sentence unless the snippet has `allowInlineExpansion` enabled.

## 16.2 Placeholders

Supported local placeholders:

```text
{{date}}
{{time}}
{{datetime}}
{{clipboard}}
{{cursor}}
{{newline}}
```

Sensitive placeholder values must not be sent to any model. Expansion occurs after ASR and after LLM cleanup.

## 16.3 Safety

- Confirm before inserting a sensitive snippet into an unrecognized application.
- Keep sensitive expansion text out of notification previews and search indexes.
- Encrypt sensitive snippet values at rest using Keychain-backed keys if implemented.

---

# 17. Command Mode and Text Transformations

## 17.1 Activation

1. User selects text.
2. User holds Command Mode shortcut.
3. FlowLocal captures selected text and limited surrounding context.
4. User speaks an instruction.
5. Local ASR transcribes the instruction.
6. Command LLM returns strict structured output.
7. FlowLocal validates it.
8. Selected text is replaced, or a preview is shown depending on user settings.

## 17.2 Limits

- Default selected-text limit: 12,000 characters.
- Warn above limit and offer to process a smaller selection.
- Never silently truncate selected text.
- Maximum transform duration target: 10 seconds on a 16 GB Mac and 6 seconds on 24 GB or higher for typical 500-word selections.

## 17.3 Preview policy

Immediate replacement is acceptable for low-risk text edits:

- Fix grammar
- Shorten
- Make professional
- Turn into bullets

Show confirmation for:

- Translation of long text
- Settings changes
- Sensitive fields
- Text containing credentials or financial information
- Any output failing protected-token validation

## 17.4 Undo

Before replacement:

- Store original selected text in the session result.
- Use the target application's native undo stack where possible.
- Also provide a FlowLocal recovery action for a limited time.

---

# 18. Reliable Text Insertion

## 18.1 Strategy order

1. Attempt direct AX selected-text replacement when the target supports it reliably.
2. Otherwise use clipboard-based paste.
3. Use app-specific paste shortcut when needed, especially terminals.
4. If insertion cannot be verified, leave final text on the clipboard and notify the user.

## 18.2 Clipboard transaction

Implement a `ClipboardTransaction` actor.

Steps:

1. Snapshot all current pasteboard items and their declared types where possible.
2. Write final plain text to the general pasteboard.
3. Synthesize the correct paste shortcut.
4. Wait an app-specific delay, initially 50 to 250 ms.
5. Verify insertion through AX text change when possible.
6. On success, restore the prior clipboard snapshot only if the pasteboard change count still indicates FlowLocal owns the temporary value.
7. On failure, keep dictated text on clipboard.
8. Never overwrite clipboard changes made by the user during the paste transaction.

## 18.3 App-specific strategies

Create a registry:

```swift
struct AppPasteStrategy: Codable, Sendable {
    let bundleIdentifier: String
    let method: PasteMethod
    let shortcut: KeyChord
    let prePasteDelayMs: Int
    let postPasteDelayMs: Int
    let verifyWithAccessibility: Bool
    let restoreClipboard: Bool
}
```

Examples:

- Standard apps: `Cmd+V`
- Some terminal configurations: `Cmd+V`, with bracketed-paste awareness
- Remote desktop: copy only by default
- Secure or banking apps: copy only by default

## 18.4 Duplicate-paste protection

Assign every insertion a UUID. Keep a short-lived record of:

- Target process
- Target element fingerprint
- Pasteboard change count
- Text hash
- Paste timestamp

Suppress an accidental second injection for the same transaction.

---

# 19. User Interface and Experience Specification

## 19.1 Original visual direction

Do not replicate Wispr's exact visual identity. Create an original restrained macOS design:

- Native materials
- Compact neutral panels
- High contrast
- System accent color by default
- Optional teal accent as a user choice
- SF Symbols where appropriate
- No oversized marketing interface
- No account or upgrade surfaces

## 19.2 Menu bar

Menu items:

- Start Dictation
- Start Hands-Free
- Command Mode
- Paste Last
- Copy Last
- Open Scratchpad
- History
- Dictionary
- Snippets
- Model Center
- Microphone
- Language
- Settings
- Diagnostics
- Quit

Display current model state and download progress without opening the main window.

## 19.3 Floating panel states

### Idle, optional

- Small microphone indicator
- Hidden by default unless user enables persistent panel

### Listening

- Live waveform
- Duration
- Cancel and Stop
- Optional partial transcript
- Current language indicator

### Processing

- Stage label: Transcribing, Cleaning, or Inserting
- Compact progress indicator
- Cancel where technically safe

### Success

- Brief check indicator, under 600 ms
- No unnecessary notification if paste succeeded

### Recoverable failure

- Short error message
- Copy
- Paste Again
- Retry
- Open History

## 19.4 Settings sections

### General

- Launch at login
- Menu bar only or Dock icon
- Show floating panel
- Start and stop sounds
- Notification settings
- Default language
- Automatic language detection
- Microphone

### Shortcuts

- Push to talk
- Hands-free
- Command Mode
- Paste last
- Copy last
- Scratchpad
- Cancel
- Shortcut conflict testing

### Intelligence

- Automatic model selection
- Speed vs quality preference
- Fast cleanup toggle
- Cleanup strength
- Self-correction handling
- App-aware styles
- Model Center

### Privacy

- Context awareness
- History retention
- Audio retention
- Sensitive-field policy
- Blocked apps
- Clear data
- Network activity status

### Personalization

- Dictionary
- Snippets
- Styles
- Writing samples
- App mappings

### Advanced

- Streaming preview
- Force ASR engine
- Force LLM
- VAD settings
- Paste delays
- Diagnostic logs
- Re-run benchmarks

## 19.5 Onboarding

1. Welcome and local-first explanation
2. Microphone permission
3. Accessibility permission
4. Input Monitoring permission if required for the selected global-hotkey approach
5. Choose built-in or cross-keyboard shortcut
6. Detect hardware and memory
7. Recommend model profile
8. Display exact model download sizes and licenses
9. Download essential model
10. Test dictation in an in-app field
11. Optional personalized benchmark
12. Optional dictionary starter terms
13. Finish

The app must remain usable with a minimal model even if the user skips heavy downloads.

---

# 20. Data Storage

## 20.1 Locations

```text
~/Library/Application Support/FlowLocal/
├── Database/flowlocal.sqlite
├── Models/
├── Notes/
├── Attachments/
├── TemporaryAudio/
├── Exports/
└── Logs/
```

Do not store user content in `UserDefaults` beyond lightweight preferences.

## 20.2 Database tables

### `transcripts`

- id
- created_at
- session_type
- language
- app_name
- bundle_id
- raw_text
- rule_processed_text
- final_text
- selected_text_before
- command_instruction
- asr_engine
- asr_model
- llm_model
- audio_duration_ms
- asr_latency_ms
- refinement_latency_ms
- insertion_latency_ms
- insertion_status
- error_code
- audio_file_path nullable
- is_sensitive

### `dictionary_entries`

Fields from the dictionary schema.

### `snippets`

- id
- trigger
- aliases_json
- expansion
- category
- app_scope_json
- is_sensitive
- allow_inline
- created_at
- updated_at

### `styles`

- id
- name
- category
- formality
- concision
- emoji_policy
- contraction_policy
- punctuation_policy
- custom_instructions
- examples_json

### `app_rules`

- id
- bundle_id
- host_pattern
- style_id
- context_enabled
- paste_strategy
- secure_policy
- language_override

### `model_inventory`

- model_id
- revision
- installed_path
- verified_hash
- installed_at
- last_used_at
- benchmark_json
- status

### `notes`

- id
- title
- current_content
- format
- pinned
- created_at
- updated_at

### `note_versions`

- id
- note_id
- content
- source_type
- created_at

### `settings`

Use typed settings migration rather than an unbounded key-value dump wherever practical.

## 20.3 Encryption and sensitive data

- SQLite can remain unencrypted for ordinary transcripts in the first private-use build if the Mac uses FileVault.
- Sensitive snippets and secrets should use Keychain or encryption with a Keychain-stored key.
- Clearly state that local data is protected by the user's macOS account and FileVault.
- Never log full transcript or context content in production logs.

## 20.4 Retention

Options:

- Keep until manually deleted
- Delete after 24 hours
- Delete after 7 days
- Delete after 30 days
- Never store transcripts

Run retention cleanup on launch and once daily while running.

---

# 21. Privacy and Network Guarantees

## 21.1 Core guarantee

After models are installed, dictation, refinement, context, history, and notes must work with Wi-Fi disabled.

## 21.2 Network architecture

Use no networking SDK in the core target except the model-downloader module. Isolate model download code in a separate package or target so it can be audited.

Model downloads must:

- Start only after user action
- Show source domain
- Show model, size, license, and purpose
- Support cancellation
- Verify files
- Stop all network access after completion

## 21.3 Privacy dashboard

Show:

- Last network request made by FlowLocal
- Installed models and source
- Local storage usage
- Transcript count
- Audio files retained
- Context awareness status
- Blocked apps
- Button to export privacy report

## 21.4 Offline test

A release cannot pass unless:

1. All required models are installed.
2. The Mac is disconnected from the internet.
3. The app is relaunched.
4. Dictation, cleanup, Command Mode, history, dictionary, snippets, and Scratchpad all work.

---

# 22. Performance Targets

These are acceptance targets, not marketing claims.

| Metric | Target |
|---|---|
| Floating panel response after shortcut | Under 50 ms perceived, under 100 ms measured |
| Audio capture start | Under 100 ms |
| First partial transcript | Under 500 ms where streaming engine supports it |
| Final ASR after a 10-second English utterance | Under 1.5 seconds on Balanced profile, benchmark-dependent |
| Rule-only finalization | Under 50 ms |
| Fast LLM cleanup | Under 1.5 seconds on the selected balanced model for a normal sentence |
| Paste after final text | Under 200 ms in standard apps |
| Idle CPU | Near 0 percent |
| Idle memory without loaded heavy models | Under 150 MB target |
| Crash-free local test sessions | 500 consecutive dictations |
| Text recovery after insertion failure | 100 percent in test matrix |

Thermal performance matters on MacBook Air because it is fanless. Include a 30-minute repeated-dictation soak test and report latency drift.

---

# 23. Error Handling and Recovery

## 23.1 Failure classes

- Permission denied
- No microphone
- Input device disconnected
- Empty audio
- ASR model missing
- ASR model load failure
- ASR inference failure
- LLM model failure
- Invalid LLM output
- No editable field
- Focus changed
- Clipboard unavailable
- Paste blocked
- AX API timeout
- Low disk space
- Memory pressure
- Thermal critical

## 23.2 Recovery rules

- Always retain raw audio in a temporary file until ASR completes.
- Always retain raw transcript until insertion completes.
- If LLM fails, insert deterministic rule-processed text.
- If preferred ASR fails, retry once with fallback engine.
- If insertion fails, leave final text on clipboard.
- If clipboard restore is unsafe because the user changed it, do not overwrite the user's new clipboard.
- If the focused field changes, show a copy/paste recovery action.
- If a model is missing, offer Model Center and preserve audio for retry.
- If disk is low, stop optional audio retention before recording.

## 23.3 Diagnostics bundle

Generate a user-approved local ZIP containing:

- App version
- macOS version
- Hardware profile
- Installed model manifest
- Permission statuses
- Redacted logs
- Performance timings
- No transcript text, audio, nearby context, snippet content, or dictionary content unless separately opted in

---

# 24. Application Compatibility Test Matrix

Test at minimum:

## Apple apps

- TextEdit
- Notes
- Mail
- Messages
- Safari address bar
- Safari text fields
- Pages
- Numbers text cells
- Keynote notes
- Xcode editor
- Terminal

## Browsers and web apps

- Chrome
- Gmail
- Google Docs
- Notion
- ChatGPT
- Claude
- Reddit editor
- LinkedIn composer

## Communication

- Slack
- Microsoft Teams
- Discord
- WhatsApp Desktop or web
- Telegram

## Development

- Cursor
- Visual Studio Code
- Xcode
- Terminal
- iTerm2
- Warp

## Productivity

- Microsoft Word
- Outlook
- Obsidian
- Linear

For each target, test:

- Empty field
- Cursor at start
- Cursor in middle
- Cursor at end
- Selected-text replacement
- Multiline text
- Rich text
- Rapid consecutive dictations
- Switching fields during dictation
- Switching applications during dictation
- Copy/paste recovery
- Undo
- External keyboard

---

# 25. Language and Accuracy Test Matrix

## 25.1 English

Include:

- Pakistani English accent
- Fast speech
- Quiet speech
- Whispered speech
- Background fan or traffic noise
- AirPods microphone
- Internal microphone
- Technical vocabulary
- Names
- Currency
- Dates
- Email addresses
- URLs
- Self-corrections

## 25.2 Urdu

Test Whisper with explicit `ur` language mode:

- Standard Urdu
- Urdu with English technical words
- Urdu names
- Roman Urdu as a separate mode, since spoken Urdu to Latin script is a transliteration task rather than ordinary Urdu ASR

For Roman Urdu, first transcribe Urdu script accurately, then optionally run a local transliteration transform. Keep this feature separate and user-selectable.

## 25.3 Arabic, Hindi, and Persian

Benchmark Qwen3-ASR against Whisper per language. Select the winner locally.

## 25.4 Code switching

Test:

- English with Urdu words
- Urdu with English product names
- English with Arabic names
- English technical speech containing code identifiers

Do not promise perfect code-switch accuracy. Provide engine choice and custom dictionary tools.

---

# 26. Testing Strategy

## 26.1 Unit tests

Required coverage:

- Shortcut validation
- State-machine transitions
- Unicode normalization
- Dictionary boundaries
- Snippet matching
- Backtrack rules
- Context joining
- Secure-field heuristics
- Protected-token validation
- Structured command parsing
- Clipboard ownership checks
- Model-manifest verification
- Retention rules

## 26.2 Integration tests

Use test doubles for:

- ASR engines
- LLM engines
- Accessibility service
- Clipboard
- Event tap
- Audio source

Verify full pipeline outputs and recovery behavior.

## 26.3 UI tests

- Onboarding permissions states
- Model download state
- Shortcut recording
- Floating panel transitions
- History actions
- Dictionary import
- Snippet creation
- Style assignment
- Command Mode preview
- Clear-data confirmation

## 26.4 Golden audio suite

Store short, consented local WAV fixtures with expected transcripts. Include noisy, whispered, accented, Urdu, and technical samples.

Never commit personal sensitive recordings to a public repository.

## 26.5 Performance tests

Record:

- Cold model load
- Warm model inference
- Streaming latency
- Final ASR latency
- LLM tokens per second
- Peak memory
- Repeated-run thermal drift
- Model switch time
- Paste latency per app

## 26.6 Soak tests

- 500 short dictations
- 50 back-to-back dictations
- 20-minute session
- 30 minutes of repeated ASR plus LLM cleanup
- Sleep and wake cycle
- Microphone disconnect and reconnect
- Permission revoke while running

---

# 27. Acceptance Criteria

## 27.1 Core dictation

- [ ] Holding configured shortcut begins recording reliably.
- [ ] Releasing stops recording and inserts text.
- [ ] Works with the built-in MacBook keyboard.
- [ ] Works with an external keyboard through fallback shortcut.
- [ ] Hands-free mode works.
- [ ] Escape cancels without clipboard changes.
- [ ] No-speech presses do not invoke models.

## 27.2 Accuracy and cleanup

- [ ] Personalized benchmark can compare installed engines.
- [ ] Pakistani English test set meets the agreed accuracy threshold.
- [ ] Names and technical terms improve through dictionary entries.
- [ ] Self-correction examples resolve correctly.
- [ ] Short clean dictations can bypass the LLM.
- [ ] LLM never changes protected numbers or identifiers in the test suite.
- [ ] Urdu uses the selected Whisper profile and produces Urdu script.

## 27.3 Context and insertion

- [ ] Mid-sentence insertion uses correct capitalization and spacing.
- [ ] Selected text can be transformed.
- [ ] Secure fields are not read.
- [ ] Failed paste leaves dictated text on clipboard.
- [ ] Successful paste restores prior clipboard when safe.
- [ ] User clipboard changes are never overwritten.
- [ ] Duplicate paste does not occur.

## 27.4 Adaptive models

- [ ] App detects actual physical memory.
- [ ] App runs benchmark and stores per-device results.
- [ ] M4 and M5 Macs may choose different profiles based on measured results.
- [ ] 24 GB and 32 GB devices can use heavier ASR and LLM models.
- [ ] Thermal serious state causes safe downshift.
- [ ] Memory pressure unloads optional heavy models.
- [ ] User can override automatic selection.

## 27.5 Privacy

- [ ] No account is required.
- [ ] No cloud key is required.
- [ ] Core app works offline after models are installed.
- [ ] No telemetry SDK is present.
- [ ] Network dashboard identifies all app network activity.
- [ ] Audio retention is off by default.
- [ ] History can be disabled.
- [ ] Clear All Data deletes database, notes, attachments, logs, and optionally models.

## 27.6 Stability

- [ ] No crash in 500-dictation soak test.
- [ ] Event tap recovers after sleep.
- [ ] Audio recovers after device switch.
- [ ] Failed model inference falls back safely.
- [ ] Temporary audio is cleaned after success.
- [ ] Interrupted jobs remain recoverable.

---

# 28. Implementation Phases

## Phase 0: Repository and engineering foundation

Deliverables:

- Native macOS project
- Swift 6 strict concurrency
- App environment and dependency injection
- OSLog categories
- Basic test targets
- CI script for local execution
- License files

Exit criteria:

- Clean build
- No warnings treated as ignored
- Unit-test target runs

## Phase 1: Minimal reliable dictation

Deliverables:

- Menu bar app
- Microphone permission
- Accessibility permission
- Global hold shortcut
- Audio capture
- One ASR engine, FluidAudio Parakeet
- Clipboard paste transaction
- Floating listening panel
- Paste last and copy last

Exit criteria:

- Works in TextEdit, Notes, Chrome, Slack, and Cursor
- Failed paste remains recoverable

## Phase 2: Processing quality

Deliverables:

- Deterministic normalization
- Backtrack processor
- Dictionary
- Snippets
- Context-aware spacing and capitalization
- SQLite history

Exit criteria:

- Rule-only pipeline is reliable without LLM
- Dictionary and snippets pass tests

## Phase 3: Embedded local LLM

Deliverables:

- MLX Swift LM adapter
- Fast cleanup model
- Conservative prompt
- Protected-token validator
- LLM bypass logic
- Style profiles

Exit criteria:

- Cleanups preserve facts in golden suite
- Fallback works if model is unloaded or fails

## Phase 4: Multilingual and adaptive engines

Deliverables:

- WhisperKit adapter
- Urdu mode
- Qwen3-ASR adapter
- Hardware profiler
- Model Center
- Per-device benchmark
- Automatic model routing
- Thermal and memory downshift

Exit criteria:

- M4 and M5 run individualized profiles
- Urdu offline test succeeds
- Heavy models are offered only when safe

## Phase 5: Command Mode

Deliverables:

- Selected-text capture
- Command ASR
- Structured local-LLM output
- Preview and confirmation
- Undo and recovery
- Safe settings proposals

Exit criteria:

- All supported command actions pass strict parser tests
- No unsupported system action can execute

## Phase 6: Product completeness

Deliverables:

- Full settings
- Privacy dashboard
- History management
- App rules
- Import and export
- Diagnostics bundle
- Launch at login
- Original polished UI

## Phase 7: Scratchpad

Deliverables:

- Notes database
- Multi-tab editor
- Search and pinning
- Version history
- Dictation to note
- Local attachments

## Phase 8: Hardening and packaging

Deliverables:

- Full app compatibility matrix
- Long-session support
- Soak tests
- Performance report for M4 and M5
- Local build script
- DMG packaging script
- Installation guide
- Third-party notices

---

# 29. Dependency and Version Policy

Initial candidates:

```swift
// Verify and pin exact tested versions before release.
.package(
    url: "https://github.com/FluidInference/FluidAudio.git",
    exact: "0.12.4"
)

.package(
    url: "https://github.com/ml-explore/mlx-swift-lm",
    exact: "3.31.3"
)
```

Also evaluate and pin:

- WhisperKit stable revision
- `ontypehq/mlx-swift-asr`
- GRDB
- KeyboardShortcuts only for standard combinations, if used

Rules:

- Do not use floating branches.
- Commit `Package.resolved`.
- Record model revision hashes.
- Run license audit on every dependency.
- Remove packages that add unnecessary network, telemetry, or binary blobs.
- Prefer Apple frameworks over dependencies for simple functionality.

---

# 30. Permissions, Entitlements, and App Configuration

## 30.1 `Info.plist`

Include:

```xml
<key>NSMicrophoneUsageDescription</key>
<string>FlowLocal needs microphone access to transcribe speech locally on this Mac.</string>

<key>LSUIElement</key>
<true/>
```

If Input Monitoring is necessary, onboarding must guide the user to the correct System Settings pane.

## 30.2 Sandbox

For the private direct-distribution build, keep App Sandbox disabled because system-wide Accessibility and event-tap behavior is easier and more reliable outside the Mac App Store sandbox.

Use least privilege regardless.

## 30.3 Stable identity

Use a stable bundle identifier and stable signing approach. macOS TCC permissions are tied to application identity, path, and signature characteristics. Randomly changing the bundle ID or signing setup can force permission reauthorization.

---

# 31. Local Build and Installation

## 31.1 Requirements

- Current Xcode supporting the selected macOS SDK
- Apple Silicon Mac
- No paid Apple Developer membership required for building and running privately on owned Macs

## 31.2 Development build

```bash
xcodebuild \
  -project FlowLocal.xcodeproj \
  -scheme FlowLocal \
  -configuration Release \
  -derivedDataPath .build/DerivedData \
  build
```

Copy the resulting `.app` to `/Applications` before granting permissions so the path remains stable.

## 31.3 Ad hoc signing

For private local use where appropriate:

```bash
codesign --force --deep --sign - /path/to/FlowLocal.app
```

A local Apple Development certificate can provide a more stable identity if available. Notarization is not required for the user's own local builds, but Gatekeeper may require right-click Open or System Settings approval on another Mac.

## 31.4 Packaging

Provide:

- `build-local.sh`
- Optional `package-dmg.sh`
- A model-free app bundle so downloads are user-controlled
- Optional offline model bundle script for transfer between the user's own Macs

When transferring models between M4 and M5:

- Copy verified model directories.
- Re-run local verification.
- Re-run benchmarks on the destination Mac.
- Do not copy the source Mac's performance choice blindly.

---

# 32. Recommended Open-Source References

These projects can reduce implementation risk, but use them according to their licenses.

## 32.1 Dictate Anywhere

Useful reference for:

- Native Swift menu bar app
- Fn hold-to-talk
- FluidAudio integration
- Local-first dictation
- MIT license

## 32.2 Presspeech

Useful reference for:

- Small, focused Parakeet dictation path
- Low idle overhead
- Native Swift and Apple Neural Engine integration
- MIT license

## 32.3 speak2

Useful reference for a modular architecture including:

- Event tap
- Audio recorder
- Whisper and Parakeet adapters
- Dictionary processor
- MLX refiner
- Floating panel
- Clipboard restoration

## 32.4 Ghost Pepper

Useful reference for:

- WhisperKit and Parakeet model choices
- Embedded local cleanup models
- Private on-device architecture
- Model download flow
- MIT license

## 32.5 Muesli

Useful reference for:

- Native local dictation
- Apple Silicon audio inference
- MIT license

## 32.6 TypeWhisper

Useful only as a product and architecture reference unless the project adopts GPLv3. Do not copy GPLv3 implementation into a private non-GPL codebase without understanding the licensing consequence.

## 32.7 Fork or start fresh?

Recommended answer: start a fresh native Swift codebase and use MIT projects as implementation references.

Reasons:

- The requested product combines multiple engines, adaptive hardware logic, secure context, Command Mode, styles, and Scratchpad.
- Forking a simple dictation app may create more migration work than building clean interfaces from the start.
- Fresh architecture avoids accidental GPL contamination and legacy assumptions.

A pragmatic alternative is to fork Dictate Anywhere or Presspeech for Phase 1, preserve their license and attribution, then refactor into the architecture in this document before adding advanced features.

---

# 33. Engineering Decisions That Must Not Be Simplified

Do not replace the required solution with any of these shortcuts:

- Electron or a browser wrapper
- Apple Speech framework as the only ASR engine
- Ollama as a mandatory external dependency
- A Python background server as the default architecture
- One hardcoded model for every machine
- Sending audio to a free cloud tier
- Calling a cloud LLM for cleanup
- Copying text to clipboard without restoring prior content
- Simulating paste without failure verification
- Reading entire windows for context
- Using screenshots by default
- Storing audio indefinitely
- Ignoring thermal state on MacBook Air
- Treating Urdu and Hindi as interchangeable
- Letting the LLM directly execute arbitrary system actions
- Claiming completion after a TextEdit-only demo

---

# 34. Final Deliverables

The development task is complete only when it produces:

1. A clean native Xcode project.
2. A release-buildable macOS app.
3. Core offline dictation with recovery.
4. Adaptive ASR routing.
5. Embedded local cleanup LLM.
6. Urdu fallback through Whisper.
7. Dictionary, snippets, styles, and app rules.
8. Command Mode with strict structured actions.
9. History and privacy controls.
10. Model Center and personalized benchmarks.
11. Thermal, memory, and power adaptation.
12. Scratchpad after core stability.
13. Unit, integration, UI, and performance tests.
14. M4 and M5 benchmark reports.
15. Local build and DMG scripts.
16. `README.md`, `ARCHITECTURE.md`, `PRIVACY.md`, `TESTING.md`, and `THIRD_PARTY_NOTICES.md`.
17. A known-issues document for apps that block paste or expose poor Accessibility metadata.
18. A final acceptance checklist with evidence for every checked item.

---

# 35. Research Sources

## Wispr Flow public product and documentation

1. Wispr Flow Features: https://wisprflow.ai/features
2. Wispr Flow Data Controls: https://wisprflow.ai/data-controls
3. Context Awareness: https://docs.wisprflow.ai/articles/4678293671-feature-context-awareness
4. Smart Formatting and Backtrack: https://docs.wisprflow.ai/articles/5373093536-how-do-i-use-smart-formatting-and-backtrack
5. Command Mode: https://docs.wisprflow.ai/articles/4816967992-how-to-use-command-mode
6. Flow Styles: https://docs.wisprflow.ai/articles/2368263928-how-to-setup-flow-styles
7. Dictionary: https://docs.wisprflow.ai/articles/4052411709-teach-flow-your-words-with-the-dictionary
8. Snippets: https://docs.wisprflow.ai/articles/5784437944-create-and-use-snippets
9. Keyboard shortcuts: https://docs.wisprflow.ai/articles/2612050838-supported-unsupported-keyboard-hotkey-shortcuts
10. Desktop navigation and Flow Bar: https://docs.wisprflow.ai/articles/5096240724-navigating-the-wispr-flow-app-desktop-ios-and-android
11. Paste recovery behavior: https://docs.wisprflow.ai/articles/7971211038-fix-text-not-pasting-after-dictation
12. Scratchpad: https://docs.wisprflow.ai/articles/9618237082-using-the-scratchpad-to-save-and-edit-notes
13. Transcript history: https://docs.wisprflow.ai/articles/4465314211-delete-transcripts-and-history-in-wispr-flow
14. Long dictation sessions: https://docs.wisprflow.ai/articles/4841123325-Longer-dictation-sessions-%E2%80%94-now-up-to-20-minutes

## ASR and local inference

15. FluidAudio: https://github.com/FluidInference/FluidAudio
16. NVIDIA Parakeet TDT 0.6B v3: https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3
17. Qwen3-ASR 0.6B: https://huggingface.co/Qwen/Qwen3-ASR-0.6B
18. Qwen3-ASR 1.7B: https://huggingface.co/Qwen/Qwen3-ASR-1.7B
19. MLX Swift ASR: https://github.com/ontypehq/mlx-swift-asr
20. Speech Swift: https://github.com/soniqo/speech-swift
21. OpenAI Whisper: https://github.com/openai/whisper
22. Whisper language list, including Urdu: https://github.com/openai/whisper/blob/main/whisper/tokenizer.py
23. WhisperKit: https://github.com/detail-co/WhisperKit
24. Voxtral Mini 4B Realtime: https://huggingface.co/mistralai/Voxtral-Mini-4B-Realtime-2602

## Local LLM runtime and models

25. MLX Swift LM: https://github.com/ml-explore/mlx-swift-lm
26. Qwen3.5 2B: https://huggingface.co/Qwen/Qwen3.5-2B
27. Qwen3.5 4B: https://huggingface.co/Qwen/Qwen3.5-4B

## Apple platform documentation

28. MacBook Air technical specifications: https://www.apple.com/macbook-air/specs/
29. `AVAudioEngine.inputNode`: https://developer.apple.com/documentation/AVFAudio/AVAudioEngine/inputNode
30. `AXUIElementCreateSystemWide`: https://developer.apple.com/documentation/applicationservices/1462095-axuielementcreatesystemwide
31. `CGEvent`: https://developer.apple.com/documentation/coregraphics/cgevent
32. `CGEvent.tapCreate`: https://developer.apple.com/documentation/coregraphics/cgevent/tapcreate(tap:place:options:eventsOfInterest:callback:userInfo:)
33. `ProcessInfo.ThermalState`: https://developer.apple.com/documentation/foundation/processinfo/thermalstate-swift.enum
34. Thermal-state change notification: https://developer.apple.com/documentation/foundation/processinfo/thermalstatedidchangenotification

## Open-source implementation references

35. Dictate Anywhere: https://github.com/hoomanaskari/mac-dictate-anywhere
36. Ghost Pepper: https://github.com/matthartman/ghost-pepper
37. Muesli: https://github.com/Muesli-HQ/muesli
38. Presspeech: https://github.com/rcourtman/presspeech
39. speak2: https://github.com/zachswift615/speak2
40. TypeWhisper, GPLv3 reference only: https://github.com/TypeWhisper/typewhisper-mac

---

# 36. Final Build Directive

Build the smallest reliable end-to-end dictation path first, then layer intelligence on top. The order of importance is:

1. Never lose dictated text.
2. Start recording immediately.
3. Insert reliably across applications.
4. Produce accurate raw transcription.
5. Apply conservative cleanup.
6. Adapt models to the Mac actually running the app.
7. Protect private context.
8. Add advanced transformations and notes only after the core is stable.

The result should feel like a native part of macOS, remain completely useful without internet access, and improve when moved from a lower-memory M4 MacBook Air to a higher-memory M5 or future Mac without requiring a separate codebase.
