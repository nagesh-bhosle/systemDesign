# Voice Dictation — macOS App

A WisprFlow-inspired macOS menu bar app that lets you speak and inserts the transcribed text wherever your cursor is.

## Quick Start

### Prerequisites
- macOS 14.0+ (Sonoma)
- Xcode 15+ (or Swift 5.9+ command line tools)
- OpenAI API key (for Whisper transcription)

### Build & Run

```bash
cd systemDesign/voice-dictation
swiftc -framework Cocoa -framework SwiftUI -framework AVFoundation \
  -framework Carbon -framework ApplicationServices -framework Security \
  -parse-as-library \
  VoiceDictation/*.swift \
  -o VoiceDictation.app/Contents/MacOS/VoiceDictation
```

Or open in Xcode:
```bash
open VoiceDictation.xcodeproj
```

### First Launch
1. The app appears as a **microphone icon** in the menu bar
2. Click it → **Settings** → enter your OpenAI API key
3. Grant **Microphone** and **Accessibility** permissions when prompted
4. Press **⌥⇧Space** (Option+Shift+Space) anywhere to start recording
5. Press again to stop — text is transcribed and pasted at your cursor

## How It Works

```
[⌥⇧Space] → Start Recording → [Speak] → [⌥⇧Space] → Stop
    → Whisper API Transcription → Paste at Cursor (or Copy to Clipboard)
```

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