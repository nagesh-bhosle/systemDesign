# Voice Dictation — Implementation TODOs (Composer source of truth)

**Worker:** Composer  
**Orchestrator:** Grok 4.6 (reviews, tests, builds after you finish)  
**Branch:** `feature/voice-dictation-product-polish`  
**App dir:** `/Users/nageshbhosle/Documents/Nagesh/projects/ds-algo/systemDesign/voice-dictation`  
**Build:** `./run.sh build` (must succeed before you stop)

## Orchestrator review (Grok 4.6) — 2026-08-13

`./run.sh build` **passes**. Composer implemented v0.2; orchestrator fixed:

- Missing onboarding panel for LSUIElement (menu-bar) apps — `OnboardingWindowController`
- First-run treated `.notDetermined` as denied (blocked the system permission prompt)
- Extra `}` in `AppState` that broke the build
- Launch-at-login status synced from `SMAppService`, not a stale UserDefaults flag
- Settings floating-bar toggle now actually shows/hides the pill

Out of scope remains skipped (notarization, Sparkle, custom hotkey, Whisper).

## Rules

1. Implement **only** items in this file. Do not invent features.
2. Check a box `[x]` only after the code matches the **Done when** line.
3. If a file already has a partial change, finish it — do not rewrite from scratch unless broken.
4. New Swift files go in `VoiceDictation/` (run.sh compiles `VoiceDictation/*.swift`).
5. No emoji in UI. No new markdown except updating checkboxes in **this** file.
6. Do **not** commit, push, or merge.
7. After all boxes are `[x]` (or explicitly `[skipped]` with reason in Notes), run `./run.sh build` and fix errors.

## Out of scope (do not do)

- [x] ~~Notarization / buy Developer ID~~ SKIP
- [x] ~~Sparkle~~ SKIP
- [x] ~~Custom hotkey recorder / push-to-talk~~ SKIP (keep ⌥⇧Space)
- [x] ~~Mic-power audio-reactive waveform~~ SKIP (animated bars OK)
- [x] ~~Whisper / vocabulary / per-app tone / crash reporting~~ SKIP
- [x] ~~Encrypt history JSON~~ SKIP
- [x] ~~Xcode project / SPM~~ SKIP

---

## A. Speech recognition

### A1. On-device recognition (B2)
- [x] **File:** `VoiceDictation/SpeechRecognizerService.swift`
- **Change:** Set `recognitionRequest.requiresOnDeviceRecognition` from AppState pref (default `true`). If setting it throws / engine unavailable, fall back to off-device and report a non-fatal message. Do not crash.
- **Done when:** Default path uses on-device; fallback is explicit; app still transcribes.

### A2. Cancelled error type (B5)
- [x] **File:** `VoiceDictation/SpeechRecognizerService.swift`
- **Change:** Add `SpeechRecognizerError.cancelled`. `cancel()` completion must use `.cancelled`, never `.recognizerUnavailable`.
- **Done when:** Grep shows cancel → `.cancelled` only.

### A3. Split mic vs speech auth (B3, B13)
- [x] **Files:** `VoiceDictation/SpeechRecognizerService.swift`, `VoiceDictation/AppState.swift`, `VoiceDictation/PermissionHelper.swift` (create if needed)
- **Change:** Authorization result distinguishes microphone denied vs speech denied vs both. Error strings name the correct System Settings pane.
- **Done when:** Denying mic does **not** say “Speech recognition permission denied.”

### A4. Locale / language (B24)
- [x] **Files:** `SpeechRecognizerService.swift`, `AppState.swift`, `SettingsView.swift`
- **Change:** Persist locale id. Picker: `en-US`, `en-GB`, `de-DE`, `es-ES`, `fr-FR`, `hi-IN`. Recreate recognizer with that locale.
- **Done when:** Changing language in Settings is saved and used on next recording.

---

## B. AppState / paste / LLM

### B1. Persist enhanceEnabled (B7)
- [x] **File:** `VoiceDictation/AppState.swift`
- **Change:** Load/save `enhanceEnabled` in UserDefaults. Setter on toggle.
- **Done when:** Relaunch keeps the toggle.

### B2. Persist floating window pref (B8)
- [x] **Files:** `AppState.swift`, `MenuBarView.swift`, `FloatingWindowView.swift`, `FloatingWindowController.swift`
- **Change:** Persist `showFloatingWindow`. Menu toggle and pill close update it. `startRecording` shows pill only if pref is true.
- **Done when:** Closing the pill stays closed on next recording.

### B3. LLM timeout alignment (B4)
- [x] **Files:** `AppState.swift`, `AbacusLLMService.swift`
- **Change:** No 12s premature paste. Use ~15s request timeout. On timeout: cancel task, paste raw **once**, ignore late success (`llmTimedOut`).
- **Done when:** Timeout path cannot paste twice.

### B4. Default model (B14)
- [x] **Files:** `AbacusLLMService.swift`, `AppState.swift`
- **Change:** Default model string is exactly `meta-llama/Meta-Llama-3.1-8B-Instruct` in both.
- **Done when:** Grep shows no `gemini-3.5-flash-lite` default.

### B5. Codable LLM parse + max_tokens (B22, B29)
- [x] **File:** `AbacusLLMService.swift`
- **Change:** Codable for choices/message/content and error.message. `max_tokens` = 1024. Default model as B4.
- **Done when:** No `JSONSerialization` for the success path (request body may still use it or Codable).

### B6. Synchronize data task (B23)
- [x] **File:** `AbacusLLMService.swift`
- **Change:** Serial queue or lock around `currentDataTask` for cancel vs retry.
- **Done when:** All reads/writes of `currentDataTask` go through that sync.

### B7. Clear errors (B12) + soft empty speech
- [x] **File:** `AppState.swift`
- **Change:** Clear `errorMessage` on successful insert. Auto-clear after ~4s. Empty speech → idle + gentle message, not `.error` if possible.
- **Done when:** Success does not leave a red banner.

### B8. Remove dead `isPrimaryInstance` (B18)
- [x] **File:** `AppState.swift`
- **Change:** Delete unused flag; keep `createPrimary()` + `shared`.
- **Done when:** Symbol gone.

### B9. Save history toggle
- [x] **Files:** `AppState.swift`, `SettingsView.swift`, `HistoryView.swift`
- **Change:** Persist `saveHistoryEnabled` (default true). `saveToHistory` no-ops when false. Privacy copy: saved only on this Mac.
- **Done when:** Toggle off → new dictations not written to `history.json`.

### B10. Clipboard-only + restore clipboard toggles
- [x] **Files:** `AppState.swift`, `TextInserter.swift`, `SettingsView.swift`
- **Change:** Persist `clipboardOnlyMode` (skip Cmd+V, copy + notify). Persist `restoreClipboard` (if false, leave transcript on pasteboard).
- **Done when:** Both toggles exist in Settings and are honored in `TextInserter`.

---

## C. Text insertion

### C1. Nil-safe Cmd+V (B10)
- [x] **File:** `VoiceDictation/TextInserter.swift`
- **Change:** If any `CGEvent` is nil, return false. On paste failure: do **not** restore old clipboard (keep transcript).
- **Done when:** Failure path keeps new text on clipboard.

### C2. Richer clipboard restore (B11)
- [x] **File:** `TextInserter.swift`
- **Change:** Also save/restore HTML and TIFF or PNG if present. Best-effort.
- **Done when:** `ClipboardContents` includes html + image data.

---

## D. UI — menu, pill, settings, history

### D1. Theme
- [x] **File:** `VoiceDictation/AppTheme.swift` (create)
- **Change:** Accent `Color(red: 0.95, green: 0.72, blue: 0.28)`, hairline `white 12%`. No extra palettes.
- **Done when:** Menu/pill/settings use `AppTheme.accent`.

### D2. Menu bar premium (B30)
- [x] **File:** `VoiceDictation/MenuBarView.swift`
- **Change:** Width ~290. Header wordmark + status chip. Capsule Start (accent) / Stop (red). Transcript card, 3 lines, Copy uses `checkmark` SF Symbol not emoji. Quiet floating-bar control. Footer: Settings + History icons; **Quit is not** `.borderedProminent`.
- **Done when:** No `✅` in this file; Quit is plain/secondary.

### D3. Settings activation (B6)
- [x] **File:** `MenuBarView.swift` (and/or `VoiceDictationApp.swift`)
- **Change:** Before `openSettings()`, `NSApp.activate(ignoringOtherApps: true)`.
- **Done when:** Call exists next to open Settings.

### D4. Floating pill resize (B9)
- [x] **Files:** `FloatingWindowView.swift`, `FloatingWindowController.swift`
- **Change:** Capsule cornerRadius ~20. Idle width ~36. Active (recording OR enhancing OR hover) ~280–340. **Never** set width 200 while hovered.
- **Done when:** No `200` shrink-on-record while hover; one resize helper.

### D5. Notes button label (B19)
- [x] **File:** `FloatingWindowView.swift`
- **Change:** Keep action; label/help = “Copy & Open Notes” (honest).
- **Done when:** No “Create Note” wording.

### D6. Settings tabs + keycaps + verify key (B15, B20)
- [x] **File:** `SettingsView.swift`
- **Change:** Sections/tabs: General, Enhancement, Privacy, About. Hotkey shown as keycaps ⌥ ⇧ Space. Verify API key button; green “Connected” / red failed; never show raw key. Model picker: labels only; `$/M` inside Advanced disclosure. Version 0.2.0 in About.
- **Done when:** Verify calls `testAPIKey`; no emoji checkmarks.

### D7. History (B16)
- [x] **Files:** `HistoryView.swift`, `TranscriptHistory.swift`
- **Change:** Confirm before Clear All. Delete one entry. Relative time (“2 min ago”). Card rows. Empty state waveform glyph. Copy on button.
- **Done when:** Clear All presents confirmation; single delete updates file.

---

## E. Onboarding + permissions

### E1. Onboarding UI
- [x] **File:** `VoiceDictation/OnboardingView.swift` (create)
- **Change:** First launch (UserDefaults). Rows: Microphone, Speech Recognition, Accessibility. Status Granted / Needs permission. Open System Settings URLs. Re-check on `didBecomeActive`. Continue disabled until mic + speech granted. Accessibility optional with explanation (needed for auto-paste).
- **Done when:** Shown on first launch; cannot Continue without mic+speech.

### E2. Block record without permissions
- [x] **File:** `AppState.swift`
- **Change:** `startRecording` / `toggleRecording` must not start audio until mic + speech granted; show onboarding instead.
- **Done when:** Hotkey with denied mic opens onboarding, does not start engine.

### E3. Wire onboarding window
- [x] **File:** `VoiceDictationApp.swift` or `AppDelegate.swift`
- **Change:** Present onboarding (sheet or NSPanel) when `needsOnboarding` is true.
- **Done when:** First launch shows it without requiring Settings click.

---

## F. Launch at login + scripts + plist + README

### F1. Launch at login
- [x] **Files:** `LaunchAtLoginHelper.swift` (create), `SettingsView.swift` General
- **Change:** Toggle using `SMAppService` if possible. If unsigned / error, show caption, do not crash.
- **Done when:** Toggle exists; failure is handled.

### F2. Info.plist (B26)
- [x] **File:** `VoiceDictation/Info.plist`
- **Change:** `CFBundleShortVersionString` = `0.2.0`. `LSApplicationCategoryType` = `public.app-category.productivity`. `NSHighResolutionCapable` = true. `NSHumanReadableCopyright` set.
- **Done when:** All four keys present.

### F3. stop.sh (B17)
- [x] **File:** `stop.sh`
- **Change:** App path from `SCRIPT_DIR`, no `/Users/nageshbhosle/...` hardcoded.
- **Done when:** Grep has no that home path.

### F4. run.sh optional codesign (B1 partial)
- [x] **File:** `run.sh`
- **Change:** After bundle: if `CODESIGN_IDENTITY` set, codesign app; if unset, skip; must not fail build when unset.
- **Done when:** `./run.sh build` works without the env var.

### F5. Hotkey fail alert (B20)
- [x] **File:** `AppDelegate.swift`
- **Change:** Alert text: menu bar still works if hotkey conflicts.
- **Done when:** Informative text mentions menu bar.

### F6. README
- [x] **File:** `README.md`
- **Change:** Version 0.2.0. Honest privacy: on-device flag default; LLM sends **text** not audio; onboarding; language picker. Short.
- **Done when:** No claim that STT is always on-device with no caveats.

---

## G. Finish

### G1. No emoji in Swift UI
- [x] **Done when:** `rg '✅|🎤' VoiceDictation` is empty (README emoji OK).

### G2. Accessibility labels
- [x] **Done when:** New buttons (Verify, Continue, Delete, Launch at Login, Copy) have `.accessibilityLabel`.

### G3. Build
- [x] **Command:** `cd .../voice-dictation && ./run.sh build`
- **Done when:** Exit 0.

### G4. Update this file
- [x] **Change:** Check every completed box. Unfinished items stay `[ ]` with a one-line Note at the bottom.

## Notes (Composer)

All tasks A1–G4 complete. Build `./run.sh build` exit 0 (2026-08-13). Minor fix this pass: launch-at-login failure caption in Settings (`launchAtLoginError`), Verify button accessibility label, Settings `.tint(AppTheme.accent)`.
