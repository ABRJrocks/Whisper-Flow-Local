# FlowLocal — Test Checklist

## Automated

- `swift test` — unit suites: TextCleanup, Backtrack (incl. fuzzy name correction),
  Dictionary (boundaries, Unicode, regex safety), Snippets (full-match vs inline,
  placeholders), SpokenPunctuation, RefinementDecider, LLM guardrails, Parakeet gating.
- Headless engine checks (no permissions needed):
  ```bash
  say -o /tmp/t.aiff "The invoice total is 1250 dollars, due March 3rd."
  .build/debug/FlowLocal --transcribe /tmp/t.aiff --engine apple
  .build/debug/FlowLocal --transcribe /tmp/t.aiff --engine parakeet   # downloads ~1 GB once
  .build/debug/FlowLocal --transcribe /tmp/t.aiff --engine whisper    # downloads ~632 MB once
  ```

## Manual matrix (Accessibility + Microphone granted)

### Core dictation
1. TextEdit, hold `Fn`, speak, release → text at cursor; bar animates Listening → Transcribing → check.
2. Same with `Ctrl+Opt` (external keyboard path).
3. Mid-sentence join: type "Please send" (no space), dictate → leading space added.
4. Clipboard restore: copy "MARKER", dictate, wait 1 s → "MARKER" restored.
5. No focused field → "copied" notice; Cmd+V recovers text.
6. Secure field (browser password box) → never pasted; copied with warning.
7. Tap `Fn` < 300 ms → nothing. Esc during recording → cancelled. `Fn+←` → cancelled.
8. Silent hold 2 s → "No speech detected", no paste, no history row.

### Hands-free
9. Double-tap `Fn` → bar shows hands-free badge; speak; single tap `Fn` → finalize + paste.
10. Esc during hands-free → cancel. Typing during hands-free does NOT cancel.
11. Silence timeout (Settings → set 2 s) → auto-finalizes after silence.

### Command Mode (requires an installed LLM model)
12. Select a sentence, hold `Ctrl+Opt+Cmd`, say "make this shorter" → selection replaced.
13. Say "press enter" with nothing selected → Enter keystroke.
14. Nonsense instruction → "Didn't catch an action", nothing changed.

### Engines & languages
15. Settings → Intelligence → force Parakeet → dictate English → works, history shows engine=parakeet.
16. Language → Urdu, force Whisper → dictate Urdu → Urdu script inserted.
17. Auto routing: English + Parakeet installed → parakeet used; Urdu → whisper used.

### UI surfaces
18. History window: rows appear after dictations; search, copy, delete, Clear All work.
19. Dictionary: add "zca → ZCA", dictate "zca" → replaced.
20. Snippets: add trigger "my meeting link", dictate it alone → expansion inserted.
21. Model Center: install/delete states correct; LLM install shows progress %.
22. Onboarding appears on first run only; permission chips go green live.
23. Scratchpad: notes persist, autosave, pin, search; dictation into note works.

### Resilience
24. Turn Wi-Fi off (models installed) → dictation + refinement still work.
25. Sleep/wake → hotkeys still work (monitors survive; relaunch if not).
26. History retention: set 24 h → older rows purged on next launch.
