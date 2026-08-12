# Voice Dictation — macOS App

A WisprFlow-inspired macOS menu bar app that lets you speak and inserts the transcribed text wherever your cursor is.

## One-Click Run

```bash
cd systemDesign/voice-dictation
./run.sh
```

That's it. The script builds the app and launches it. A 🎤 icon appears in your menu bar.

Then press **⌥⇧Space** (Option+Shift+Space) anywhere to start recording. Press again to stop — your speech is transcribed on-device and pasted at your cursor (or copied to clipboard).

**Optional:** Click the 🎤 icon → **Settings** → paste your Abacus AI API key to enable LLM text cleanup (removes filler words, fixes grammar). Without a key, raw speech-to-text is used.

## How It Works

```
[⌥⇧Space] → Start Recording → [Speak] → [⌥⇧Space] → Stop
    → On-Device Speech Recognition (SFSpeechRecognizer)
    → [Optional] Abacus AI LLM Cleanup (filler removal, grammar fix)
    → Paste at Cursor (Accessibility API + Cmd+V) — or Copy to Clipboard
```

## Prerequisites

- macOS 14.0+ (Sonoma)
- Swift command line tools (`xcode-select --install`)
- Optional: Abacus AI API key (for LLM text cleanup — works without it)

## Features

### MVP (Current)
- ✅ Global hotkey (⌥⇧Space) to toggle recording
- ✅ On-device speech recognition via Apple SFSpeechRecognizer (no API key needed)
- ✅ Optional LLM text cleanup via Abacus AI (remove filler words, fix grammar)
- ✅ Auto-paste at cursor position (Accessibility API + Cmd+V simulation)
- ✅ Clipboard fallback with notification
- ✅ Menu bar app with status indicator
- ✅ Floating window with live transcript preview
- ✅ Secure API key storage in macOS Keychain
- ✅ Last transcript preview in menu bar
- ✅ Searchable transcript history

### Phase 2 (Future)
- Spelling correction
- Auto punctuation
- Rewording via LLM
- Tone/style per app
- Custom vocabulary
- Multi-language support

### Phase 3 (Future)
- On-device Whisper (whisper.cpp) for offline privacy mode
- App-specific formatting
- Voice commands
- Auto-update via Sparkle

## Architecture

| File | Responsibility |
|------|---------------|
| `VoiceDictationApp.swift` | App entry, menu bar setup |
| `AppState.swift` | Central state, orchestrates recording → transcription → enhancement → insertion |
| `AppDelegate.swift` | App lifecycle, hotkey registration |
| `HotkeyManager.swift` | Global hotkey via Carbon framework |
| `SpeechRecognizerService.swift` | On-device speech recognition via SFSpeechRecognizer |
| `AbacusLLMService.swift` | Optional LLM text cleanup via Abacus AI API |
| `TextInserter.swift` | Text insertion at cursor (clipboard + Cmd+V) |
| `FloatingWindowController.swift` | Manages floating window lifecycle |
| `FloatingWindowView.swift` | Floating bar UI with live transcript |
| `MenuBarView.swift` | Menu bar dropdown UI |
| `SettingsView.swift` | API key settings, LLM model/endpoint config, hotkey info |
| `HistoryView.swift` | Searchable transcript history |
| `TranscriptHistory.swift` | Local persistence of past dictations |
| `KeychainHelper.swift` | Secure API key storage |

## Permissions

| Permission | Why |
|-----------|-----|
| Microphone | Record your speech |
| Speech Recognition | On-device transcription via SFSpeechRecognizer |
| Accessibility | Simulate Cmd+V to paste at cursor |
| Notifications | Notify when text is copied to clipboard |

## Tech Stack
- **Swift** + **SwiftUI** (native macOS)
- **Speech** — on-device speech recognition (SFSpeechRecognizer)
- **AVFoundation** — audio recording
- **Carbon** — global hotkey registration
- **ApplicationServices** — accessibility for text insertion
- **Security** — Keychain for API key
- **Abacus AI** — optional LLM text cleanup (OpenAI-compatible API)

## License
MIT