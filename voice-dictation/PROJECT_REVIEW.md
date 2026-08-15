# Voice Dictation — full project review (0.5.3)

**Date:** 2026-08-15  
**Tree:** `main` @ `4d9c3c8` (tag `v0.5.3` if present)  
**Bundle:** `com.nagesh.voicedictation`  
**Install:** `./run.sh install` → `~/Applications/VoiceDictation.app`

This review is against the **mandatory** product in `MANDATORY_FEATURES.md`. Run those tests after any change.

---

## What the app is

Menu-bar macOS 14+ dictation: hotkey → record file → transcribe after Stop → optional LLM on **text** → paste at caret.

```
Hotkey / menu / pill
    → AVAudioRecorder (.caf in temp)
    → Stop
    → split ~20s chunks (2s overlap) → SFSpeechURLRecognitionRequest
    → join full transcript
    → optional Abacus/RouteLLM cleanup
    → TextInserter (AX splice at caret, else Cmd+V)
```

**Headset rule:** no `AVAudioEngine` input, no HAL default-input hijack, no NSSound at Start.

---

## Mandatory features vs code

### M1 — Record up to 5 minutes

| | |
|--|--|
| **Status** | **Implemented.** Recorder auto-stops at 5:00 (`maxRecordingSeconds = 300`); a 4:50 warning timer fires first. STT is chunked because Apple ~1 minute/request. 0.5.2–0.5.3 exist specifically because long takes dropped or kept only the last line. |
| **Risk** | 5-minute takes mean many chunks and a long wait. Chunk merge / AX replace bugs can still look like “only last line.” No XCTest; only manual `MANDATORY_FEATURES.md`. |
| **Gap** | No progress “transcribing chunk 3/15.” Users may think the app died during STT. |

### M2 — Paste at cursor

| | |
|--|--|
| **Status** | **Implemented.** Target captured at Start. AX inserts by splicing `kAXValue` at selected range (0.5.3 avoided `kAXSelectedText` replace-all). Cmd+V fallback. Clipboard restore waits until the field confirms this take. |
| **Risk** | Unsigned `swiftc` rebuilds reset Accessibility TCC. Slow apps vs clipboard restore. Electron/Chrome AX still flaky → Cmd+V. Clipboard-only is a valid escape hatch. |
| **Gap** | No automated proof of caret insert. |

### M3 — Optional LLM

| | |
|--|--|
| **Status** | **Implemented.** Off by default. Keychain key, Verify, persisted toggle, text-only, timeout → raw paste. Prompt: do not return only the last sentence. `max_tokens` 8192. |
| **Risk** | Timeout now scales with transcript length (15 s base + 1 s per ~200 chars, capped at 60 s). Model may still summarize. Needs network. |
| **Gap** | No offline local LLM. |

### M4 — Hotkey and floating window

| | |
|--|--|
| **Status** | **Implemented.** Default ⌥⇧Space, remap, PTT. Floating capsule with timer; hide/show persisted. Menu Start/Stop if hotkey fails. |
| **Risk** | Carbon hotkeys are legacy; conflict alert is OK. Pill on `MenuBarExtra` was moved; History/Settings are panels. Secure input fields swallow hotkeys (OS). |

---

## Architecture (what is solid)

- **Audio:** Same recorder path as mic test. Empty takes recover to Idle.
- **Permissions:** Onboarding for Mic / Speech / Accessibility.
- **Privacy:** On-device STT default, encrypted local history, LLM text-only, temp `.caf` cleanup.
- **Product surface:** Settings sidebar, history pin/re-paste, vocabulary, launch at login, install script.
- **Versioning:** `CHANGELOG.md`, `run.sh` `APP_VERSION`, git tags. Daily driver is Applications, not `./run.sh`.

---

## Remaining issues (not blockers for the gate, but real)

1. **5-minute wait UX** — Transcribe can run several minutes with little feedback beyond “Transcribing…”.
2. **5:00 auto-stop** — **Implemented in 0.5.3.** Recorder stops at 5:00 (`maxRecordingSeconds = 300`) with a 4:50 warning. No longer a gap.
3. **Accessibility after unsigned install** — Still a support footgun.
4. **Two app icons** — `~/Applications` vs `voice-dictation/build/` if you also run `./run.sh`.
5. **No automated tests** — `swiftc` glob; no XCTest. Gate is manual (`MANDATORY_FEATURES.md`).
6. **Sparkle / notarization** — Documented only (`PRODUCT_ROADMAP.md`).
7. **Live transcript while talking** — Intentionally absent (headset-safe).

---

## Inventory (optional, must not break M1–M4)

Push-to-talk, language picker, on-device toggle, history encryption/retention, skip password fields, vocabulary, per-app LLM tone, undo last paste, mic check panel, finish sound after STT, launch at login.

---

## Verdict

**0.5.3 is a working menu-bar dictation product** if M1–M4 pass on a machine with Mic + Speech + Accessibility. The last year of bugs (headset silence, previous-clipboard paste, last-line-only STT) all sit on M1/M2 — that is why this gate exists.

**Do not merge** audio, STT, paste, LLM, or hotkey/pill changes without the checklist in `MANDATORY_FEATURES.md`.
