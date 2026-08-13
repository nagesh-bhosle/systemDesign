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
1. **Global Hotkey** — press a key combo (⌥⇧Space) anywhere to start/stop recording
2. **Audio Recording** — capture microphone input via AVAudioRecorder (headset-safe; no live AVAudioEngine input)
3. **On-Device Speech-to-Text** — after Stop, transcribe the recording with SFSpeechURLRecognitionRequest / SFSpeechRecognizer
4. **Optional LLM Cleanup** — send transcript to Abacus AI for filler word removal and grammar correction
5. **Text Insertion** — paste transcribed text at cursor position using Accessibility API + Cmd+V simulation
6. **Clipboard Save/Restore** — previous clipboard contents are preserved after paste
7. **Menu Bar App** — lives in the menu bar with status indicator (idle / recording / transcribing / enhancing)
8. **Floating UI** — small floating window showing recording status and live transcript preview
9. **Copy & Paste Fallback** — if auto-insert fails, copy text to clipboard and show a notification
10. **Transcript History** — searchable history of past dictations (file-based persistence)

### Tech Stack
- **Language:** Swift (native macOS)
- **UI:** SwiftUI for menu bar + floating window
- **Audio:** AVFoundation (`AVAudioRecorder` for capture; do not use AVAudioEngine input — Bluetooth HFP regression)
- **Speech Recognition:** Apple SFSpeechRecognizer via `SFSpeechURLRecognitionRequest` after Stop
- **LLM Cleanup (Optional):** Abacus AI (routellm.abacus.ai) — OpenAI-compatible API
- **Global Hotkey:** Carbon framework (RegisterEventHotKey)
- **Text Insertion:** Accessibility API (AXUIElement) + Cmd+V simulation with clipboard fallback
- **Key Storage:** macOS Keychain (with `kSecAttrAccessibleWhenUnlocked`)
- **Logging:** os.Logger for leveled, privacy-aware logging
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
6. **Auto-update** — Sparkle framework (documented in PRODUCT_ROADMAP.md; not in MVP)
7. **Menu bar icon** — animated waveform while recording

## Architecture

```
voice-dictation/
├── run.sh                      # Build & launch script
├── stop.sh                     # Stop running instance
├── VoiceDictation/
│   ├── VoiceDictationApp.swift # App entry point, menu bar
│   ├── AppDelegate.swift       # Global hotkey registration with error reporting
│   ├── AppState.swift          # Central state, orchestrates flow
│   ├── HotkeyManager.swift     # Global hotkey via Carbon (with error checking)
│   ├── SpeechRecognizerService.swift  # On-device SFSpeechRecognizer (thread-safe)
│   ├── AbacusLLMService.swift  # Optional LLM text cleanup (with retry + cancellation)
│   ├── TextInserter.swift      # Accessibility API + Cmd+V text insertion (clipboard save/restore)
│   ├── FloatingWindowController.swift  # Floating window lifecycle (position persistence)
│   ├── FloatingWindowView.swift # Floating bar UI
│   ├── MenuBarView.swift       # Menu bar dropdown UI
│   ├── SettingsView.swift      # Settings window (API key, model, endpoint)
│   ├── HistoryView.swift       # Searchable transcript history
│   ├── TranscriptHistory.swift # Local persistence (file-based in Application Support)
│   ├── KeychainHelper.swift    # Secure API key storage (with error checking)
│   └── Info.plist              # App metadata & permissions
├── REQUIREMENTS.md             # This file
└── README.md                   # Setup & usage guide
```

## Data Flow

```
[Hotkey Press] → [Start Recording] → [AVAudioRecorder → temp .caf]
     ↓
[Hotkey Press Again] → [Stop Recording] → [SFSpeechURLRecognitionRequest]
     ↓
[On-Device Transcription] → [Transcribed Text]
     ↓
[Optional: Abacus AI LLM Cleanup] → [Enhanced Text]
     ↓
[Insert at Cursor via AX API + Cmd+V] — or — [Copy to Clipboard + Notify]
     ↓
[Save to History] (after paste completes)
```

## API Key

- Abacus AI API key (optional — for LLM text cleanup only) stored in macOS Keychain
- User enters key via Settings on first launch (optional)
- Key is never logged or stored in plaintext
- Keychain item uses `kSecAttrAccessibleWhenUnlocked` for explicit accessibility
- Without a key, raw on-device speech-to-text is used directly

## Permissions Required

- **Microphone Access** — `NSMicrophoneUsageDescription`
- **Speech Recognition** — `NSSpeechRecognitionUsageDescription`
- **Accessibility** — for simulating keystrokes / text insertion at cursor
- **Notifications** — `NSUserNotificationsUsageDescription` — notify when text is copied

## Non-Goals (for MVP)

- No on-device Whisper model (Phase 3)
- No multi-language UI (Phase 2)
- No cloud sync
- No team features