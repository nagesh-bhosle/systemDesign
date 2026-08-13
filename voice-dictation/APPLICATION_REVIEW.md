# Application review — Voice Dictation

Date: 2026-08-13 (updated for v0.4.0)  
Headset restore snapshot: `voice-dictation-working` @ `c1c3ee7` (unchanged)  
Product line: `main` @ v0.4.0 / v0.5.0 — see `PRODUCT_ROADMAP.md` and `CHANGELOG.md`.

Restore that build:

```
git checkout voice-dictation-working
cd voice-dictation && ./run.sh
```

User confirmed: **laptop mic and Bluetooth headset both record.**

---

## What this snapshot got right

- Dictation uses `AVAudioRecorder` then `SFSpeechURLRecognitionRequest` (same capture path as the mic test). `AVAudioEngine` input is not used; that path switched headsets into HFP and went silent.
- Check microphone is an `NSPanel`, not a sheet on the menu extra. Audio starts only on **Start test**.
- The app does not change the Mac’s default input device.
- Empty / no-speech takes return to Idle and rebuild the session so Start keeps working.
- Paste-at-cursor, history encryption, onboarding mic/speech checks, and Accessibility helper are still in place.

---

## Remaining issues (review of the working code)

### P1 — Product / correctness

1. **No live transcript while talking** — **Addressed in 0.4.0 (copy).** Text still appears after Stop (headset-safe design). UI now says “Stop to transcribe” / “Transcribing after you stop…”.

2. **Temp `.caf` files** — **Addressed in 0.4.0.** `TempRecordingCleanup` deletes `voicedictation-*.caf` on launch, quit, transcribe finish, mic-test stop, and `deinit`.

3. **Very short takes** — **Addressed in 0.4.0.** Dropped the 2000-byte cutoff. Only header-only / sub-80ms click files are skipped.

4. **Transcribe timeout** — **Addressed in 0.4.0.** Timeout scales with recording length (`max(12, duration×2.5+6)`, cap 60s).

5. **Start/stop sounds** — **Addressed in 0.4.0.** No sound at Start. Optional Pop after transcription finishes.

6. **Unsigned `./run.sh` rebuilds still break paste-at-cursor**  
   Accessibility TCC is per signature. After each rebuild: uncheck/check Voice Dictation, or codesign with a stable identity. Documented in `PRODUCT_ROADMAP.md`. `./run.sh install` is the stable daily install path.

7. **Clipboard restore** — **Addressed in 0.5.1.** Restore only after the focused field contains this take. Do not restore on a timer (that raced Cmd+V and pasted the previous transcript). False AX insert success falls through to Cmd+V.

### P2 — Robustness / polish

8. **History / Settings sheets** — **Addressed in 0.5.0.** Dedicated `NSPanel` windows, same as mic test.

9. **`ExceptionCatcher` is unused** by the recorder path. Harmless; can stay as a guard if engine code returns.

10. **Custom vocabulary** — **Addressed in 0.5.0.** Whole-word lookarounds, escaped templates, skip 1-character / punctuation-only lines.

11. **`DictationStatus.error` is mostly unused** — failures go to Idle plus a caption.

12. **No automated smoke tests.** Manual list: `SMOKE_TEST.md`. Add headset Start/Stop as item 1.

13. **Mic choice is System Settings only**  
   Intentional (avoids disconnects). The UI should keep saying that; do not bring back in-app device switching.

### Not bugs

- On-device STT still needs Speech Recognition permission.
- Push-to-talk and the global hotkey do not fire in secure input fields (password prompts).
- Accessibility is optional; without it, text goes to the clipboard.

---

## Suggested next work (do not mix into the working tag)

1. Sparkle + notarization when a Developer ID and appcast host exist (`PRODUCT_ROADMAP.md`).
2. Codesign every `run.sh` build with a stable identity so Accessibility survives.
3. Optional: live partials **only** for built-in mic, keep recorder path for Bluetooth — easy to regress; keep one path unless you tag again after testing both mics.

---

## Archive — findings from before the working snapshot

The sections below described bugs that were fixed before `voice-dictation-working`. Kept for history.

### Fixed: Check microphone sheet crash

Was a SwiftUI `.sheet` on `MenuBarExtra` calling audio during layout (`AVAudioEngine.prepare()` abort). Now a dedicated panel + `AVAudioRecorder`.

### Fixed: System default mic hijack

`kAudioHardwarePropertyDefaultInputDevice` / `kAudioOutputUnitProperty_CurrentDevice` dropped Bluetooth. Dictation no longer force-selects a device.

### Fixed: App freeze after empty takes

`AVCaptureSession.stopRunning()` on the main thread and a reused dead `AVAudioEngine`. Recorder + session generation + Idle recovery.

### Fixed: Headset silent on Start

`AVAudioEngine` + live `SFSpeechAudioBufferRecognitionRequest` switched HFP. Replaced with recorder + `SFSpeechURLRecognitionRequest`.
