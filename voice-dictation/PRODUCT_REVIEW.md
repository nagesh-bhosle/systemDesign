# Voice Dictation — Product Review

Review of the current macOS menu-bar app (v0.1.0). **Identify only** — no code changes in this pass.

Verdict: the core loop works (hotkey → on-device STT → optional LLM cleanup → paste). It is a solid prototype, not yet a shippable product. Biggest gaps are distribution (unsigned builds), first-run permissions, privacy claims vs actual behavior, and a UI that still reads as a developer tool.

---

## What’s already strong

- Clear product loop inspired by Wispr Flow.
- On-device `SFSpeechRecognizer` so the app works without an API key.
- Keychain for the API key, file-based history (not UserDefaults), clipboard save/restore, LLM cancel + retry, hotkey registration errors, accessibility labels.
- Menu bar extra + floating pill + settings + searchable history is the right surface area for v1.

---

## Bugs and correctness issues

### P0 — ship blockers / user-facing failures

| ID | Issue | Where | Why it matters |
|----|--------|--------|----------------|
| B1 | **Unsigned / ad-hoc build.** Every `./run.sh` rebuild is a new binary. Accessibility permission resets; Gatekeeper will scare users. | `run.sh` | Real products must be Developer ID signed + notarized (Sparkle or direct `.dmg`). |
| B2 | **Privacy claim is overstated.** README says on-device STT, but `SFSpeechAudioBufferRecognitionRequest` does **not** set `requiresOnDeviceRecognition = true`. Apple may send audio to servers depending on device/settings. | `SpeechRecognizerService.swift` | Must either force on-device or disclose cloud STT. |
| B3 | **Wrong permission error.** Mic denial is reported as “Speech recognition permission denied.” | `AppState.startRecording` | Users go to the wrong System Settings pane. |
| B4 | **LLM timeout vs request timeout mismatch can double-work.** AppState times out at **12s**; URLSession is **15s** plus a 1s retry. Timeout path pastes raw text; a late success is gated by `llmTimedOut`, but cancel/retry races are still easy to get wrong. | `AppState.swift`, `AbacusLLMService.swift` | Risk of delayed paste, wasted API spend, confusing status. |
| B5 | **`cancel()` reports the wrong error.** Speech cancel completes with `recognizerUnavailable` instead of a dedicated cancelled error. | `SpeechRecognizerService.cancel()` | Callers cannot distinguish “user cancelled” from “engine down.” |
| B6 | **Accessory app + Settings.** `LSUIElement` is true (no Dock). `openSettings()` often fails to bring a window forward unless the app is activated. | `Info.plist`, `MenuBarView` | Settings feel broken on first use. |

### P1 — real bugs that hurt trust

| ID | Issue | Where |
|----|--------|--------|
| B7 | **`enhanceEnabled` is not persisted.** Defaults to `false` every launch even after the user turns it on. | `AppState.swift` |
| B8 | **`showFloatingWindow` is unused in practice.** Menu bar toggles `FloatingWindowController` directly; next recording still auto-shows because `showFloatingWindow` stays `true`. Close on the pill doesn’t stick as a preference. | `AppState`, `MenuBarView`, `FloatingWindowView` |
| B9 | **Hover vs recording resize fight.** Recording forces width `200`; hover wants `340`. Buttons clip or the pill jumps. | `FloatingWindowView`, `FloatingWindowController` |
| B10 | **`simulatePaste` returns `true` even if `CGEvent`s are nil.** Paste can silently fail; clipboard restore still runs. | `TextInserter.swift` |
| B11 | **Clipboard restore is incomplete.** Only string/RTF/PDF/file URLs. Images, HTML, Finder promises, custom types are lost. 0.3s restore window races with user copy. | `TextInserter.swift` |
| B12 | **Error banners never auto-clear.** LLM timeout / fallback messages stay in the menu until the next recording. | `AppState`, `MenuBarView` |
| B13 | **Mic vs speech auth is collapsed to one Bool.** Cannot tell which permission failed. | `SpeechRecognizerService.requestAuthorization` |
| B14 | **Default model mismatch.** Service default `gemini-3.5-flash-lite` vs AppState/Settings `meta-llama/Meta-Llama-3.1-8B-Instruct`. | `AbacusLLMService`, `AppState` |
| B15 | **`testAPIKey()` is unused.** No “Verify key” in Settings. Invalid keys only fail at dictation time. | `AbacusLLMService`, `SettingsView` |
| B16 | **History “Clear All” has no confirmation.** One click wipes 100 entries. | `HistoryView.swift` |
| B17 | **`stop.sh` hardcodes a machine-specific path** (unused) while `pkill -f` is still the real kill. Fragile if another binary shares the name. | `stop.sh` |
| B18 | **`isPrimaryInstance` is never read.** Dead state. | `AppState.swift` |
| B19 | **Notes action is a stub.** Copies text and opens `mobilenotes://`; does not create a note. Help text is honest, UX is not. | `FloatingWindowView.swift` |
| B20 | **Carbon hotkey is not customizable** and Carbon APIs are legacy. Conflict with other apps is a modal alert with no recovery (pick another combo). | `HotkeyManager`, `SettingsView` |

### P2 — quality / maintainability

| ID | Issue | Notes |
|----|--------|--------|
| B21 | No unit/UI tests despite injectable `AppState` init. | |
| B22 | LLM client uses `JSONSerialization` instead of Codable. | Fragile parsing. |
| B23 | `currentDataTask` is not synchronized. | Cancel vs retry race. |
| B24 | Locale hardcoded `en-US`. | No language picker. |
| B25 | No Xcode project / SPM package. `swiftc` glob compile. | Blocks icons, entitlements, CI, TestFlight. |
| B26 | `Info.plist` missing icon, category, high-res flag, copyright. | |
| B27 | History is plaintext JSON in Application Support. | Sensitive dictation (passwords, medical, work). |
| B28 | API key held in `@Published` memory for the session. | Acceptable, but don’t log it (currently OK). |
| B29 | `max_tokens: 4096` for short dictation. | Cost/latency. |
| B30 | Quit is `.borderedProminent` in the menu. | Easy accidental quit — death for a menu-bar utility. |

---

## Product gaps vs Wispr Flow / a shippable v1

These are not “nice to have later” if the goal is *sell or give to non-engineers*.

### 1. First-run onboarding (must-have)

Today: first hotkey fails silently or with a wrong error; accessibility is prompted once then never explained.

Need a 3-step setup window:

1. Microphone  
2. Speech Recognition  
3. Accessibility (“so we can paste where your cursor is”)  

Each row: status pill (Granted / Needs permission) + **Open Settings**. Don’t start recording until mic + speech are granted. Re-check when the app becomes active.

### 2. Distribution

- Developer ID signing + notarization  
- `.dmg` or `.zip` with a branded icon  
- Sparkle auto-update (already in Phase 3 requirements)  
- Launch at Login toggle  
- Stable bundle ID + versioning (`0.1.0` is fine; bump CFBundleVersion per build)

**App Store note:** simulating Cmd+V and requiring Accessibility often gets rejected. Direct download (like Wispr Flow) is the realistic channel.

### 3. Trust and privacy (must-have copy + behavior)

- Privacy policy URL in Settings  
- Explicit toggle: **On-device only** (`requiresOnDeviceRecognition`)  
- Explicit toggle: **Send to LLM for cleanup** with “this text leaves your Mac”  
- History: local-only badge; optional “don’t save history”; optional exclude from Time Machine  
- Never send audio to Abacus — only text (already true; say it)

### 4. Core dictation UX

| Gap | Suggestion |
|-----|------------|
| Toggle-only hotkey | Add **push-to-talk** (hold) vs **toggle** (press) |
| No audio cue | Subtle start/stop chime (and a mute toggle) |
| No recording duration | Show `0:12` on the pill |
| Empty speech = error | Softer empty state, don’t feel like a crash |
| Paste into this app | If Voice Dictation is frontmost, copy + notify (already partly handled) |
| No undo | “Undo last insert” (Cmd+Z in target app usually works; document it) |
| No dictation language | Locale picker: en-US, en-GB, de, es, fr, hi, etc. |
| No custom vocabulary | Phase 2, but even a simple “always capitalize these words” list is high leverage |

### 5. Settings that a product needs

- Remap hotkey (record a new combo)  
- Paste vs clipboard-only mode  
- Restore clipboard on/off  
- Enhancement on/off **persisted**  
- Model picker with a live **Test connection**  
- Launch at login  
- Play sounds  
- Show floating bar (persisted)  
- Language  
- Privacy / history retention (7 / 30 / forever)

### 6. History as a product surface

- Click row → copy **and** optional re-paste  
- Swipe/delete one entry  
- Confirm clear all  
- Relative timestamps (“2 min ago”)  
- Pin / favorites  
- Don’t store if user is in a password field (best-effort via AX focused role)

---

## Premium look and feel (identify only)

Current UI is functional SwiftUI defaults: gray Form, emoji checkmarks (`✅ Copied!`), generic `mic.fill`, 5pt shadow, no brand color, no icon asset.

### Visual direction

Think **quiet luxury**: dark translucent materials, one accent (warm amber or electric teal), hairline borders, no emoji, SF Pro + SF Symbols only.

**Brand**

- Name: keep “Voice Dictation” or pick a short mark (e.g. “Dictate”)  
- Custom menu-bar template icon (monochrome PDF, 18pt) — not the system mic (collides with Control Center)  
- App icon: rounded square, mic + waveform, dark glass, no skeuomorphic microphone clipart  
- Accent: single color used for recording, primary buttons, focus rings  

**Menu bar extra (replace the current VStack)**

- 280–300pt wide, 12–14pt padding, `ultraThinMaterial`  
- Header: wordmark + live status chip (`Idle` / pulsing `Listening` / `Enhancing`)  
- Primary control: full-width **capsule** — idle = fill accent “Start”, recording = red “Stop”  
- Last transcript in a nested rounded card, 3-line clamp, ghost **Copy** that becomes a checkmark symbol (not emoji)  
- Footer: icon-only Settings / History, text **Quit** in secondary color (never prominent blue)  
- Remove stacked bordered buttons; use `Divider` sparingly  

**Floating pill**

- Height 36–40, corner radius 20 (true capsule)  
- Idle: 36×36 orb, 1px white 12% stroke, shadow `black 20% / 12pt / y:4`  
- Recording: expand to ~240pt, 4-bar **audio-reactive** waveform (use input power, not fake repeatForever scale)  
- Live text in `caption2`, monospaced-ish, fade trailing  
- Hover: reveal icon buttons with 6pt hit targets, 50% opacity until hover  
- Don’t shrink to 200pt while hovered — one width for “active”, one for “idle orb”  

**Settings**

- Tabbed or sidebar: General / Enhancement / Privacy / About  
- Hotkey shown as Apple-style keycaps (`⌥` `⇧` `Space`)  
- API key: “Connected” green dot after verify; never show the key  
- Drop cost-per-million developer copy from the default picker; keep it in an Advanced disclosure  

**History**

- List rows with 8pt padding, 12pt radius cards  
- Timestamp muted; text primary  
- Empty state illustration (simple waveform glyph), not a tiny SF Symbol dump  

**Motion**

- 200ms ease-out for pill expand  
- Menu icon: `variableColor` only while recording (already started)  
- Respect Reduce Motion  

**What not to do**

- Emoji in UI  
- Rainbow gradients  
- Heavy drop shadows  
- Making Quit the visually strongest button  

---

## Suggested ship plan (still identify-only)

### v0.2 — “I can give this to a friend”

1. Sign + notarize; real app icon + menu-bar icon  
2. Onboarding for Mic / Speech / Accessibility  
3. `requiresOnDeviceRecognition` + honest privacy copy  
4. Persist enhance + floating-bar prefs  
5. Fix mic error string, paste CGEvent nil check, settings activation  
6. Premium menu + pill restyle (no new features)  
7. Confirm-before-clear history; remove prominent Quit  
8. Verify API key button  

### v0.3 — “Feels like a product”

1. Customizable hotkey + push-to-talk  
2. Language picker  
3. Launch at login, sounds, clipboard-only mode  
4. Sparkle updates  
5. History re-paste / delete one  
6. Audio-reactive waveform  

### v1.0 — competitive

1. Custom vocabulary  
2. Per-app tone (mail vs chat)  
3. Optional local Whisper  
4. Privacy mode that never writes history  
5. Website + privacy policy + crash reporting (opt-in)  

---

## File-by-file notes (for the next implementation pass)

| File | Focus |
|------|--------|
| `VoiceDictationApp.swift` | Activate app when opening Settings; custom menu icon |
| `AppState.swift` | Persist prefs; split mic vs speech errors; unify LLM timeouts; clear errors on success |
| `SpeechRecognizerService.swift` | On-device flag; cancel error type; locale |
| `TextInserter.swift` | Nil-safe CGEvent; richer clipboard; don’t restore if paste failed |
| `AbacusLLMService.swift` | Align default model; Codable; wire `testAPIKey` |
| `HotkeyManager.swift` | User-defined combo; better conflict UX |
| `FloatingWindowView.swift` | Capsule design; one resize policy; real Notes or drop the action |
| `MenuBarView.swift` | Premium layout; quiet Quit |
| `SettingsView.swift` | Tabs; keycaps; verify key; persist toggles |
| `HistoryView.swift` | Confirm clear; delete row; relative time |
| `Info.plist` | Icon, category, copyright |
| `run.sh` | `codesign` after compile |
| `stop.sh` | Derive path from script dir, not a hardcoded home folder |

---

## Out of scope for this doc

No code, assets, or Xcode project were changed. This file is the single deliverable for the review.
