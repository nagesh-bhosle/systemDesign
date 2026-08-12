# Voice Dictation — macOS App

A WisprFlow-inspired macOS menu bar app that lets you speak and inserts the transcribed text wherever your cursor is.

**Version 0.2.0**

## One-Click Run

```bash
cd systemDesign/voice-dictation
./run.sh
```

The script builds the app and launches it. A mic icon appears in your menu bar.

Press **Option+Shift+Space** anywhere to start recording. Press again to stop — your speech is transcribed and pasted at your cursor (or copied to clipboard).

On first launch, an onboarding window guides you through Microphone, Speech Recognition, and Accessibility permissions.

**Optional:** Click the mic icon → **Settings** → paste your Abacus AI API key to enable LLM text cleanup.

## How It Works

```
[Option+Shift+Space] → Start Recording → [Speak] → [Option+Shift+Space] → Stop
    → On-Device Speech Recognition (SFSpeechRecognizer, on-device by default)
    → [Optional] Abacus AI LLM Cleanup (text only — audio stays on your Mac)
    → Paste at Cursor (Accessibility API + Cmd+V) — or Copy to Clipboard
```

## Privacy

- **Audio** is processed on your Mac. On-device speech recognition is enabled by default (`requiresOnDeviceRecognition`). If on-device is unavailable, the app falls back to Apple's server-based recognition.
- **Optional LLM cleanup** sends transcribed **text** (not audio) to Abacus AI when enabled.
- **History** is saved locally in Application Support — never leaves your Mac. You can disable history saving in Settings.

## Prerequisites

- macOS 14.0+ (Sonoma)
- Swift command line tools (`xcode-select --install`)
- Optional: Abacus AI API key (for LLM text cleanup)

## Features (v0.2)

- Global hotkey (Option+Shift+Space) with Apple-style keycaps in Settings
- On-device speech recognition with language picker (en-US, en-GB, de-DE, es-ES, fr-FR, hi-IN)
- First-run onboarding for permissions
- Optional LLM text cleanup via Abacus AI
- Auto-paste at cursor with clipboard save/restore (HTML, images supported)
- Clipboard-only mode and restore-clipboard toggle
- Menu bar app with premium UI (warm amber accent, SF Symbols only)
- Floating capsule bar with idle orb / expanded active state
- Searchable transcript history with relative timestamps
- Launch at login (macOS 13+, requires signed build)
- API key verify with connected/failed indicator
- Settings tabs: General / Enhancement / Privacy / About

## Build

```bash
./run.sh build          # Build only
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
