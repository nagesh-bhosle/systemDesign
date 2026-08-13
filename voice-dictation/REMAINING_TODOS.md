# Remaining PRODUCT_REVIEW items — Composer source of truth

**Worker:** Composer  
**Orchestrator:** Grok 4.6 (reviews + `./run.sh build` after you finish)  
**Branch:** `feature/voice-dictation-product-polish` (stay on it)  
**App:** `/Users/nageshbhosle/Documents/Nagesh/projects/ds-algo/systemDesign/voice-dictation`  
**Build:** `./run.sh build` must exit 0  

Already done in prior passes (do **not** reimplement): B2–B20 except B20 remap, B22–B24, B26 fields except icon, B29–B30, onboarding, premium menu/pill, language, launch-at-login, clipboard-only, persist prefs, paste-to-target-app, AX prompt removal.

## Rules

1. Implement **only** items below. Check `[x]` only when **Done when** is true.
2. New Swift files go in `VoiceDictation/` (run.sh compiles `VoiceDictation/*.swift`).
3. No emoji in UI. Do not commit/push/merge.
4. Do not rewrite working paste/onboarding/permission code unless a todo requires a small hook.
5. If an asset is missing, draw a template menu-bar icon in Swift; copy any `Resources/` icon into the app bundle from `run.sh`.

## SKIP (do not implement)

- [ ] Notarization / buy Developer ID — cannot without Apple account
- [ ] Sparkle auto-update — needs a hosted appcast URL
- [ ] On-device Whisper / whisper.cpp
- [ ] Crash reporting (Sentry/etc.)
- [ ] Public website
- [ ] Full Xcode project / SPM app target (keep `swiftc` + `run.sh`)
- [ ] XCTest module (no Xcode target)

---

## R1. Customizable hotkey (PRODUCT B20 + v0.3)

- [x] **Files:** `HotkeyManager.swift`, `SettingsView.swift`, `AppState.swift`, `AppDelegate.swift`
- **Change:** Persist `hotkeyKeyCode` (UInt32) and `hotkeyModifiers` (UInt32) in UserDefaults. Default remains Option+Shift+Space. Settings: button **Record shortcut** — next keypress (with modifiers) becomes the hotkey; show keycaps from the stored combo. On conflict, keep old combo, show error in Settings (not only a modal). `registerHotkey()` must unregister previous then register new. Call register from AppDelegate using saved combo.
- **Done when:** Changing the shortcut in Settings actually toggles recording with the new combo after save; default still works if never changed.

## R2. Push-to-talk vs toggle (v0.3)

- [x] **Files:** `HotkeyManager.swift`, `AppState.swift`, `SettingsView.swift`
- **Change:** Persist `pushToTalkEnabled` (default false). Toggle mode = press to start, press to stop (current). PTT = key **down** starts, key **up** stops. Carbon `RegisterEventHotKey` is press-only — for PTT also listen to `kEventHotKeyReleased` if available, or a local/global `NSEvent` monitor for the same keyCode+modifiers keyUp (does not require a new Accessibility prompt if possible). If key-up cannot be detected without AX, document that PTT needs Accessibility and use `NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged/.keyUp)`.
- **Done when:** With PTT on, holding the hotkey records and releasing stops+transcribes. Toggle mode unchanged when PTT off.

## R3. Start/stop sounds + mute (v0.3)

- [x] **Files:** `AppState.swift`, `SettingsView.swift` (General), new `SoundPlayer.swift` optional
- **Change:** Persist `playSounds` (default true). On recording start / stop, play a short system sound (`NSSound(named: "Tink")` / `"Pop"` or `NSSound.beep()` variants). Respect `accessibilityReduceMotion` is not required; respect mute toggle. No bundled audio files required.
- **Done when:** Toggle off → silent. Toggle on → audible start and stop.

## R4. Recording duration on pill (v0.3)

- [x] **Files:** `AppState.swift`, `FloatingWindowView.swift`
- **Change:** While `status == .recording`, publish elapsed `mm:ss` starting at `0:00`. Show it on the expanded pill. Reset on stop.
- **Done when:** Pill shows live timer during listening.

## R5. Audio-reactive waveform (v0.3)

- [x] **Files:** `SpeechRecognizerService.swift`, `AppState.swift`, `FloatingWindowView.swift`
- **Change:** In the existing input tap, compute RMS/power of the buffer (0...1). Publish `audioLevel` to AppState on main. Waveform bars scale with `audioLevel` (plus a small floor). If Reduce Motion, use static bars.
- **Done when:** Bars move with voice, not only a fake repeatForever animation.

## R6. History re-paste + pin (review §6)

- [x] **Files:** `HistoryView.swift`, `TranscriptHistory.swift`, `AppState.swift`, `TextInserter.swift`
- **Change:** Each row: Copy, **Paste at cursor** (calls `captureInsertionTarget` if needed + `insertOrCopy`), Delete. Optional pin: persist `isPinned` on `TranscriptEntry` (add Codable field with default false for old JSON). Pinned entries stay at top. Confirm still required for Clear All (already done).
- **Done when:** Paste from history inserts into the last captured target app (or frontmost non-self app). Old history.json still loads.

## R7. History retention + Time Machine exclude (review §3, §5)

- [x] **Files:** `TranscriptHistory.swift`, `AppState.swift`, `SettingsView.swift` Privacy
- **Change:** Persist retention: `7` / `30` / `0` (forever). On save/load, drop entries older than N days (never drop pinned if you implemented pins). Set `URLResourceValues.isExcludedFromBackup = true` on the history file and app support folder.
- **Done when:** Choosing 7 days removes older unpinned entries; file has backup-excluded flag.

## R8. Skip history in password fields (review §6)

- [x] **Files:** `TextInserter.swift` or new `FocusedFieldInspector.swift`, `AppState.saveToHistory`
- **Change:** Best-effort: if AX trusted, read focused element `kAXRoleAttribute`; if `AXSecureTextField` or role contains Secure, skip `saveToHistory`. Never crash if AX fails.
- **Done when:** Dictating into a password field does not add a history row (when AX is trusted).

## R9. Custom vocabulary (v1.0 lite)

- [x] **Files:** `AppState.swift`, `SettingsView.swift` (new General or Enhancement section)
- **Change:** Persist a newline-separated list of words/phrases. After transcription (before LLM and before paste), apply case-insensitive replace so each vocabulary item appears as typed (preserve user’s capitalization from the list).
- **Done when:** Adding `OpenAI` makes spoken “open ai” / “openai” paste as `OpenAI` when it matches as a token/phrase.

## R10. Per-app tone lite (v1.0 lite)

- [x] **Files:** `AppState.swift`, `AbacusLLMService.swift`, `SettingsView.swift`
- **Change:** When LLM enhance is on, if frontmost/target bundle is `com.apple.mail` or contains `slack` / `messages`, append a one-line style hint to the system prompt (formal email vs casual chat). No UI required beyond a Privacy/Enhancement caption “Tone adapts for Mail vs chat when cleanup is on.”
- **Done when:** `enhanceText` receives an optional style hint string from AppState based on insertion target bundle id.

## R11. Privacy policy in Settings (review §3)

- [x] **Files:** `SettingsView.swift` About, new `PRIVACY.md` in `voice-dictation/`
- **Change:** Short privacy policy: audio on-device by default; optional LLM sends **text only**; history local; no analytics. Settings About: button **Privacy** that opens the markdown in NSWorkspace (file URL) or shows the same text in a scroll view.
- **Done when:** User can read the policy from Settings without a website.

## R12. Undo last insert (review §4)

- [x] **Files:** `MenuBarView.swift`, `TextInserter.swift`
- **Change:** Menu action **Undo last paste** — if last insert was `.pasted`, post Cmd+Z to the same target pid. If last was clipboard-only, do nothing but status “Nothing to undo”. Document in About: “Undo uses Cmd+Z in the target app.”
- **Done when:** After a successful auto-paste, Undo last paste removes it in the target app (standard undo).

## R13. Menu bar brand icon (review Brand)

- [x] **Files:** `VoiceDictationApp.swift`, optional `MenuBarIcon.swift`
- **Change:** Do **not** use `mic.fill` (collides with Control Center). Draw a template waveform/mark `NSImage` (`isTemplate = true`) or use `waveform` only while idle is a **custom** 2–3 bar mark. Recording can still use red waveform animation.
- **Done when:** Idle menu extra is not `mic.fill`.

## R14. App icon in bundle (review Brand + B26)

- [x] **Files:** `run.sh`, `Info.plist`, `VoiceDictation/Resources/`
- **Change:** If `VoiceDictation/Resources/AppIcon.icns` exists, copy it to `Contents/Resources/` and set `CFBundleIconFile` = `AppIcon`. If no icns, generate a simple icon with `sips`/`iconutil` from any PNG in Resources, or skip icns and set nothing rather than a broken key.
- **Done when:** `Info.plist` has icon key only if the file is actually copied into the built app.

## R15. Version bump + zip (review Distribution)

- [x] **Files:** `Info.plist`, `run.sh`, `README.md`
- **Change:** Version **0.3.0**, `CFBundleVersion` increment (e.g. 3). `run.sh build` also writes `build/VoiceDictation-0.3.0.zip` of the `.app` (`ditto -c -k --keepParent`). README version 0.3.0.
- **Done when:** zip exists after `./run.sh build`; plist says 0.3.0.

## R16. History encryption lite (B27)

- [x] **Files:** `TranscriptHistory.swift`, `KeychainHelper.swift`
- **Change:** Encrypt `history.json` with CryptoKit AES.GCM. Store 256-bit key in Keychain (`history-aes-key`). On load: if file is legacy plaintext JSON array, import then rewrite encrypted. Never log plaintext history.
- **Done when:** File on disk is not a readable JSON array of transcripts; app still shows history after relaunch.

## R17. About copy: undo + AX rebuild note

- [x] **Files:** `SettingsView.swift` About, `README.md`
- **Change:** Mention: auto-paste needs Accessibility; after rebuild uncheck/check Voice Dictation; Cmd+Z undoes last paste; optional LLM sends text not audio.
- **Done when:** README and About both say this.

---

## G. Finish

- [x] `./run.sh build` exit 0, no Swift errors
- [x] Check off every completed R-item in **this** file
- [x] Notes at bottom: anything skipped with reason

## Notes (Composer)

- **R2 PTT:** Uses Carbon `kEventHotKeyReleased` for key-up; no extra Accessibility prompt required for PTT vs toggle.
- **R12 Undo:** Posts session-wide Cmd+Z via `CGEvent.post(tap: .cghidEventTap)`; works with the existing AX-first insert path in `TextInserter`.
- **R14:** `AppIcon.icns` generated from `VoiceDictation/Resources/AppIcon.png` on first build via `sips` + `iconutil`.
- **SKIP section:** Left unchanged per instructions (notarization, Sparkle, Whisper, Sentry, website, Xcode target, XCTest).
- **No commit/push/merge** per worker instructions.

## Orchestrator verify (Grok 4.6)

`./run.sh build` exit 0. Caret insert path in `TextInserter` (AX focused field, then session Cmd+V) is still present. Hotkey-conflict alert now uses the saved shortcut label, not a hardcoded ⌥⇧Space.
