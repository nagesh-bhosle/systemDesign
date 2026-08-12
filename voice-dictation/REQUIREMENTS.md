# Voice Dictation — macOS App Requirements

> A WisprFlow-inspired macOS app that lets you speak and inserts the transcribed text wherever your cursor is.

## Inspiration

[Wispr Flow](https://wisprflow.ai/) is a voice-to-text AI that:
- Works in **every app** — types wherever your cursor is (Gmail, Slack, iMessage, Notion, terminal, code editors, etc.)
- Removes **filler words** ("um", "uh", "like"), adds punctuation, and formats writing
- Supports **100+ languages** with automatic detection
- Learns your **vocabulary** (names, jargon, snippets)
- Adapts **tone/style** per app (formal in email, casual in chat)
- Offers **Privacy Mode** (no dictation stored on servers)
- 4x faster than typing (220 wpm vs 45 wpm)

## MVP (Phase 1) — Basic Speech-to-Text

### Goal
Press a global hotkey → speak → transcribed text is inserted at cursor position (or copied to clipboard with paste option).

### Features
1. **Global Hotkey** — press a key combo (e.g., ⌥⇧Space) anywhere to start/stop recording
2. **Audio Recording** — capture microphone input while recording
3. **Speech-to-Text** — send audio to OpenAI Whisper API for high-quality transcription
4. **Text Insertion** — paste transcribed text at cursor position using Accessibility API or clipboard paste
5. **Menu Bar App** — lives in the menu bar with status indicator (idle / recording / transcribing)
6. **Floating UI** — small floating window showing recording status and transcribed text preview
7. **Copy & Paste Fallback** — if auto-insert fails, copy text to clipboard and show a notification

### Tech Stack
- **Language:** Swift (native macOS)
- **UI:** SwiftUI for menu bar + floating window
- **Audio:** AVFoundation (AVAudioEngine for recording)
- **Transcription:** OpenAI Whisper API (whisper-1) — best-in-class STT
- **Global Hotkey:** Carbon framework (RegisterEventHotKey)
- **Text Insertion:** Accessibility API (AXUIElement) with clipboard fallback
- **Minimum macOS:** 14.0 (Sonoma)

## Phase 2 — AI Enhancement (Future)

1. **Filler Word Removal** — use LLM to clean up "um", "uh", "like", repetitions
2. **Spelling Correction** — fix misspelled words and proper nouns
3. **Auto Punctuation** — add commas, periods, paragraph breaks
4. **Rewording** — use fast LLM (Gemini Flash) to reword for clarity
5. **Tone/Style** — formal vs casual per app context
6. **Vocabulary** — custom words, names, jargon dictionary
7. **Snippets** — speak a shortcut, expand to full text
8. **Multi-language** — auto-detect and transcribe 100+ languages

## Phase 3 — Polish (Future)

1. **Privacy Mode** — on-device Whisper model (whisper.cpp) for offline transcription
2. **App-specific styles** — different formatting per app
3. **Command palette** — voice commands for editing, formatting
4. **History** — searchable transcript history
5. **Settings UI** — configure hotkey, API key, language, style
6. **Auto-update** — Sparkle framework
7. **Menu bar icon** — animated waveform while recording

## Architecture

```
voice-dictation/
├── VoiceDictation.xcodeproj     # Xcode project
├── VoiceDictation/
│   ├── VoiceDictationApp.swift  # App entry point, menu bar
│   ├── AppDelegate.swift        # Global hotkey registration
│   ├── AudioRecorder.swift      # AVAudioEngine recording
│   ├── WhisperService.swift     # OpenAI Whisper API client
│   ├── TextInserter.swift       # Accessibility API text insertion
│   ├── MenuBarView.swift        # Menu bar UI
│   ├── FloatingWindow.swift     # Floating recording indicator
│   ├── SettingsView.swift       # Settings window
│   ├── HotkeyManager.swift      # Global hotkey via Carbon
│   ├── KeychainHelper.swift     # Secure API key storage
│   └── Assets.xcassets/         # App icon
├── REQUIREMENTS.md              # This file
└── README.md                    # Setup & usage guide
```

## Data Flow

```
[Hotkey Press] → [Start Recording] → [Audio Buffer]
     ↓
[Hotkey Press Again] → [Stop Recording] → [WAV File]
     ↓
[Send to Whisper API] → [Transcribed Text]
     ↓
[Insert at Cursor via AX API] — or — [Copy to Clipboard + Notify]
```

## API Key

- OpenAI API key stored in macOS Keychain
- User enters key on first launch via Settings
- Key is never logged or stored in plaintext

## Permissions Required

- **Microphone Access** — `NSMicrophoneUsageDescription`
- **Accessibility** — for simulating keystrokes / text insertion at cursor
- **Network** — to call Whisper API

## Non-Goals (for MVP)

- No on-device model (Phase 3)
- No LLM rewording (Phase 2)
- No multi-language UI (Phase 2)
- No cloud sync
- No team features