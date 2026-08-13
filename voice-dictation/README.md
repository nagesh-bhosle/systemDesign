# Voice Dictation — macOS App

A WisprFlow-inspired macOS menu bar app that lets you speak and inserts the transcribed text wherever your cursor is.

**Version 0.5.0**

See `PRODUCT_ROADMAP.md` for the installable Mac app contract (Applications folder, updates, signing). See `CHANGELOG.md` for release notes.

Known-good **headset + laptop** dictation restore: `git checkout voice-dictation-working` (does not move with 0.5.0).

## One-Click Run

```bash
cd systemDesign/voice-dictation
./run.sh
```

The script builds the app and launches it. A custom waveform icon appears in your menu bar.

Press **Option+Shift+Space** anywhere to start recording. Press again to stop — transcription runs **after Stop**, then text is pasted at your cursor (or copied to clipboard). You can customize the shortcut and enable push-to-talk in Settings.

On first launch, an onboarding window guides you through Microphone, Speech Recognition, and Accessibility permissions.

**Optional:** Click the menu bar icon → **Settings** → paste your Abacus AI API key to enable LLM text cleanup.

## How It Works

```
[Global Hotkey] → Start Recording (AVAudioRecorder) → [Speak] → [Hotkey / Release] → Stop
    → On-Device Speech Recognition of the recording file (SFSpeechURLRecognitionRequest)
    → [Optional] Abacus AI LLM Cleanup (text only — audio stays on your Mac)
    → Paste at Cursor (Accessibility API + Cmd+V) — or Copy to Clipboard
```

## Privacy

- **Audio** is processed on your Mac. On-device speech recognition is enabled by default (`requiresOnDeviceRecognition`). If on-device is unavailable, the app falls back to Apple's server-based recognition.
- **Optional LLM cleanup** sends transcribed **text** (not audio) to Abacus AI when enabled.
- **History** is encrypted and saved locally in Application Support — never leaves your Mac. You can disable history saving in Settings.

## Accessibility and Undo

- **Auto-paste** requires Accessibility permission in System Settings → Privacy & Security → Accessibility.
- After **rebuilding** the app, uncheck and recheck Voice Dictation in Accessibility so macOS trusts the new binary.
- **Undo last paste** (menu bar) sends Cmd+Z to the target app to undo the last auto-paste.

## Prerequisites

- macOS 14.0+ (Sonoma)
- Swift command line tools (`xcode-select --install`)
- Optional: Abacus AI API key (for LLM text cleanup)

## Features (v0.4)

- Customizable global hotkey with Record shortcut in Settings
- Push-to-talk mode (hold to record)
- Finish sound after transcription (toggle in Settings; not played at Start)
- Recording timer and audio-reactive waveform; words appear after Stop
- Custom vocabulary (one phrase per line)
- Per-app tone hints for LLM cleanup (Mail vs chat)
- History: re-paste, pin, retention (7 / 30 / forever), encrypted on disk
- Skip history in password fields (when Accessibility is trusted)
- Undo last paste via Cmd+Z in the target app
- Custom menu bar icon (not mic.fill)
- App icon in bundle; `./run.sh build` also creates `build/VoiceDictation-0.5.0.zip`
- `./run.sh install` copies the app to `~/Applications/VoiceDictation.app`
- Privacy policy in Settings → About
- On-device speech recognition with language picker (en-US, en-GB, de-DE, es-ES, fr-FR, hi-IN)
- First-run onboarding for permissions
- Optional LLM text cleanup via Abacus AI
- Auto-paste at cursor with clipboard save/restore
- Clipboard-only mode and restore-clipboard toggle
- Menu bar app with premium UI
- Floating capsule bar with live timer and waveform
- Searchable transcript history with relative timestamps
- Launch at login (macOS 13+, requires signed build)
- Settings tabs: General / Enhancement / Privacy / About

## Build

```bash
./run.sh build          # Build only (also writes build/VoiceDictation-0.5.0.zip)
./run.sh install        # Build and copy to ~/Applications/VoiceDictation.app
./run.sh clean          # Clean rebuild and launch

# Optional codesign (does not fail build if unset):
CODESIGN_IDENTITY="-" ./run.sh build
```

## Permissions

| Permission | Why |
|-----------|-----|
| Microphone | Record your speech |
| Speech Recognition | Transcribe speech on your Mac |
| Accessibility | Simulate Cmd+V to paste at cursor (optional — clipboard fallback) |
| Notifications | Notify when text is copied to clipboard |

## License

MIT
