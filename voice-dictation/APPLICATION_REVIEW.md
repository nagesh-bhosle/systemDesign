# Application review — Voice Dictation

Date: 2026-08-13 (updated after known-good merge)  
Snapshot: `main` @ `c1c3ee7`, tags **`voice-dictation-working`** and **`voice-dictation-working-2026-08-13`**

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

1. **No live transcript while talking**  
   Text appears after Stop, when the file is transcribed. The floating bar will show a timer/meter but not words until then. Expected with the headset-safe design; say so in the UI (“Transcribing after you stop…”).

2. **Speech is written to a temp `.caf` before STT**  
   `voicedictation-*.caf` and `voicedictation-mic-test-*.caf` in the temp directory. Deleted after success, left behind on crash. Privacy-sensitive; delete in `deinit` and on terminate (`applicationWillTerminate`).

3. **Very short takes can be dropped**  
   Files under 2000 bytes are treated as no speech. A quick phrase might be discarded.

4. **8 second transcribe timeout**  
   Long recordings may still be processing when the timeout finishes with whatever partial exists (possibly empty). Scale timeout with duration, or wait for `isFinal`.

5. **Start/stop sounds are skipped**  
   They were switching the Bluetooth route. Settings still has “Play start/stop sounds,” which now does nothing for dictation. Hide the toggle or play only after transcribe completes.

6. **Unsigned `./run.sh` rebuilds still break paste-at-cursor**  
   Accessibility TCC is per signature. After each rebuild: uncheck/check Voice Dictation, or codesign with a stable identity.

7. **Clipboard restore at 1.2s**  
   Slow apps can paste the old clipboard. Prefer restoring only after a successful AX insert, or wait longer.

### P2 — Robustness / polish

8. **History / Settings sheets still sit on `MenuBarExtra`**  
   Mic test was moved to a panel for that reason. History and Settings can glitch when the extra closes. Same `NSPanel` pattern if they misbehave.

9. **`ExceptionCatcher` is unused** by the recorder path. Harmless; can stay as a guard if engine code returns.

10. **Custom vocabulary** interpolates user lines into regex; odd characters are skipped or over-replaced.

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

1. Delete temp recordings on quit and after transcribe.  
2. UI copy: listening vs transcribing-the-file.  
3. Transcribe timeout based on recording length.  
4. Codesign in `run.sh` when an identity exists (already attempted).  
5. Optional: live partials **only** for built-in mic, keep recorder path for Bluetooth — easy to regress; keep one path unless you tag again after testing both mics.

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
