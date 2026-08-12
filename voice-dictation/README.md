# Voice Dictation — macOS App

A WisprFlow-inspired macOS menu bar app that lets you speak and inserts the transcribed text wherever your cursor is.

## One-Click Run

```bash
cd systemDesign/voice-dictation
./run.sh
```

That's it. The script builds the app and launches it. A 🎤 icon appears in your menu bar.

**First time only:** Click the 🎤 icon → **Settings** → paste your OpenAI API key.

Then press **⌥⇧Space** (Option+Shift+Space) anywhere to start recording. Press again to stop — your speech is transcribed and pasted at your cursor.

## How It Works

```
[⌥⇧Space] → Start Recording → [Speak] → [⌥⇧Space] → Stop
    → Whisper API Transcription → Paste at Cursor (or Copy to Clipboard)
```

## Prerequisites

- macOS 14.0+ (Sonoma)
- Swift command line tools (`xcode-select --install`)
- OpenAI API key (for Whisper transcription)

## Features

### MVP (Current)
- ✅ Global hotkey (⌥⇧Space) to toggle recording
- ✅ High-quality transcription via OpenAI Whisper API
- ✅ Auto-paste at cursor position (Accessibility API + Cmd+V simulation)
- ✅ Clipboard fallback with notification
- ✅ Menu bar app with status indicator
- ✅ Secure API key storage in macOS Keychain
- ✅ Last transcript preview in menu bar

### Phase 2 (Future)
- Filler word removal ("um", "uh", "like")
- Spelling correction
- Auto punctuation
- Rewording via Gemini Flash LLM
- Tone/style per app
- Custom vocabulary
- Multi-language support

### Phase 3 (Future)
- On-device Whisper (whisper.cpp) for offline privacy mode
- App-specific formatting
- Voice commands
- Transcript history
- Auto-update via Sparkle

## Architecture

| File | Responsibility |
|------|---------------|
| `VoiceDictationApp.swift` | App entry, menu bar setup |
| `AppState.swift` | Central state, orchestrates recording → transcription → insertion |
| `AppDelegate.swift` | App lifecycle, hotkey registration |
| `HotkeyManager.swift` | Global hotkey via Carbon framework |
| `AudioRecorder.swift` | Microphone capture via AVAudioEngine |
| `WhisperService.swift` | OpenAI Whisper API client |
| `TextInserter.swift` | Text insertion at cursor (clipboard + Cmd+V) |
| `MenuBarView.swift` | Menu bar dropdown UI |
| `SettingsView.swift` | API key settings, hotkey info |
| `KeychainHelper.swift` | Secure API key storage |

## Permissions

| Permission | Why |
|-----------|-----|
| Microphone | Record your speech |
| Accessibility | Simulate Cmd+V to paste at cursor |
| Network | Call OpenAI Whisper API |

## Tech Stack
- **Swift** + **SwiftUI** (native macOS)
- **AVFoundation** — audio recording
- **Carbon** — global hotkey registration
- **ApplicationServices** — accessibility for text insertion
- **Security** — Keychain for API key
- **OpenAI Whisper API** — speech-to-text

## License
MIT