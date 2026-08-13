# Application review — Voice Dictation

Date: 2026-08-13  
Scope: current `feature/mic-check-and-recovery` code under `voice-dictation/`  
Method: full source read of recording, mic test, paste, permissions, UI, and persistence. Not an automated UI crawl.

**Status:** P0/P1 items below were implemented after this review (mic-test `NSPanel`, no auto-start, no system-default hijack, picker guard, capture-session meter, engine start without layout `prepare()`, Int16 RMS, smoke list in `SMOKE_TEST.md`). Keep this file as the original finding list.

The user still reports that **Check microphone crashes / closes the app**. That is treated as **open**, not fixed, even though later commits moved the meter off `AVAudioEngine`.

---

## Open P0 — Check microphone still unsafe

### 1. Sheet hosted in `MenuBarExtra` (most likely remaining crash)

`MenuBarView` presents `MicTestView` as a SwiftUI `.sheet` on the menu-bar extra window (`VoiceDictationApp`: `.menuBarExtraStyle(.window)`).

On macOS this pattern is unstable:

- Opening a sheet often dismisses or recreates the extra window.
- `onAppear` / `onDisappear` can fire more than once.
- Layout of the sheet runs inside `NSHostingView.layout` (the 2026-08-13 02:58 crash stack was exactly that).

A later `DispatchQueue.main.async` around `startMicTest()` does **not** remove the sheet-from-menu-bar problem.

**Fix direction:** present Check microphone in a dedicated `NSPanel` (same approach as onboarding / floating bar), not as a sheet on the extra.

### 2. Mic test still auto-starts when the UI appears

`MicTestView.onAppear` always starts the test. Combined with (1), audio I/O still begins while SwiftUI is presenting a window.

`AVAudioRecorder.prepareToRecord()` / `record()` can also fail hard. It is safer than `AVAudioEngine.prepare()`, but it is not crash-proof, especially if the system default input is being changed at the same time (see 3).

**Fix direction:** default the sheet/panel to idle. Start only on an explicit **Start test** click, after the window has finished laying out.

### 3. Changing the Mac’s default input on every test

`AudioInputManager.setDefaultInput` writes `kAudioHardwarePropertyDefaultInputDevice` (system-wide). `startMicTest()` and `saveSelectedInput()` both do this, then immediately start `AVAudioRecorder`.

HAL reconfiguration while opening a recorder is a known abort/hang. It also changes the user’s input for FaceTime, Zoom, and every other app.

**Fix direction:** do not change the system default. Either use the current default and tell the user to pick the mic in System Settings, or set the device only on the capture unit you own.

### 4. SwiftUI `Picker` with a selection that is not in the list

```swift
Picker("Input", selection: selectedInputUID) {
    ForEach(audioInputs) { Text(device.name).tag(device.uid) }
}
```

If `audioInputs` is empty on first frame, or `selectedInputUID` from UserDefaults is not in the list yet, macOS Pickers can crash. Same picker exists in Settings.

**Fix direction:** include an explicit empty/`None` tag, or do not render the Picker until the selection is a member of `audioInputs`.

### 5. Appear/disappear race leaves the recorder running

Sequence:

1. `onAppear` schedules `startMicTest()` asynchronously.
2. User closes the window → `onDisappear` / `onDismiss` calls `stopMicTest()` (session++).
3. The delayed `startMicTest()` runs anyway, increments the session again, and **starts a new recorder with no UI**.

That matches “Stop is frozen / test won’t stop after I close the window.”

**Fix direction:** delayed start must capture a session id and no-op if it no longer matches; or do not auto-start at all.

---

## Open P0 / P1 — Recording still fragile

### 6. Format check before the engine has a real format

`startRecognition` reads `inputNode.outputFormat(forBus: 0)` **without** `prepare()`, then refuses to start if channel count or sample rate is 0.

`prepare()` was removed because it aborted. On many Macs the format is 0 until the graph initializes. Result: **Start appears to do nothing** or immediately shows “invalid audio format” / recover-to-idle.

`ExceptionCatcher` around `start()` helps only if you get past this guard.

### 7. Dictation still uses `AVAudioEngine` + `installTap`

`beginInputTap` can still hit `AVAudioEngineGraph::Initialize` inside `start()`. The catcher converts some `NSException`s to errors, but:

- exceptions on the I/O thread inside the tap are not wrapped
- `removeTap` when the graph is already dead can still be dangerous
- accessing `inputNode` on a menu-bar agent app with no `AVAudioSession` (macOS) is historically flaky

### 8. On-device recognition is strict (original “must shout” bug)

`requiresOnDeviceRecognition = true` by default. Apple’s on-device model often ignores quiet first utterances and then ends the task with `kAFAssistantErrorDomain` (1110 / 203 / 1101). Empty results become “No speech detected.” That can feel like “recording doesn’t work.”

### 9. Stop during start-up abandons state

```swift
if isStartingRecording {
    isStartingRecording = false
    status = .idle
    return  // does not cancel the recognizer / engine
}
```

If Stop is hit while authorization is in flight, a late `startRecognition` is skipped (`status != .recording`), which is OK. If Stop is hit after the engine started but before `isStartingRecording` is cleared, the engine can keep running with UI showing Idle.

### 10. RMS meter ignores non-float buffers

`publishAudioLevel` only reads `floatChannelData`. Built-in mics often deliver Int16. The waveform stays at 0 even when speech is captured, so users think the mic is dead.

---

## P1 — Product / correctness

### 11. Mic test writes speech to a temp `.caf` file

`MicrophoneTester` records linearly to `voicedictation-mic-test-*.caf` in the temp directory. That is a privacy issue (test audio on disk) and can fail if the disk/temp path is blocked. Delete-on-stop can lose the race on crash.

### 12. Device list includes virtual inputs

`inputDevices()` returns every Core Audio device with input channels (Zoom, Teams, aggregate devices, iPhone mics). Picking the wrong one looks like “mic doesn’t work.” Prefer hardware devices, or highlight the system default.

### 13. Paste-at-cursor still depends on unsigned rebuilds

Each `./run.sh` produces a new binary. Accessibility TCC is per-code-signature. Unsigned builds will keep showing “needs Accessibility” after every rebuild. Codesign is optional in `run.sh` and currently logs “No Apple codesign identity found.”

### 14. Clipboard restore can beat paste

`TextInserter` restores the previous clipboard 0.7s after a claimed paste. Slow target apps still paste the old clipboard.

### 15. `SoundPlayer` at record start

`NSSound` (`Tink` / `Pop`) starts as the engine starts and can steal the HAL briefly (first buffers silent / engine fail).

### 16. Status `.error` is mostly dead

Recovery paths set `.idle`. The menu-bar error icon almost never appears; failures are a caption that auto-clears in 4 seconds.

---

## P2 — Robustness

### 17. Status message auto-clear is not cancellable

`scheduleStatusMessageAutoClear` starts a new `Task` every time and never cancels the previous one. An old timer can blank a newer message.

### 18. Custom vocabulary regex

User lines are interpolated into `NSRegularExpression`. Unusual characters can make a pattern fail (silently skipped) or over-replace (e.g. short tokens inside longer words via the spaced pattern).

### 19. History key vs Keychain lock

History AES key is `kSecAttrAccessibleWhenUnlocked`. Saving/loading history while the Mac is locked fails open (empty or skip save).

### 20. LLM cancel vs timeout

Enhancement cancel sets `llmTimedOut = true` then idle. A late success is ignored (good). A late failure after cancel is also ignored. Fine, but `currentDataTask` cancel must stay in sync (`AbacusLLMService.cancel`).

### 21. No tests

There is no XCTest / XCUITest target. The crash and “can’t record after no speech” bugs are exactly the paths a 20-case smoke list would cover. See previous discussion: do not try to click every control; cover mic-test × dictation crossings.

### 22. Stale comments

`SpeechRecognizerService` and `AudioInputManager` headers still say dictation and mic test share one `AVAudioEngine`. They do not.

---

## What looks solid

- Onboarding uses `AVAudioApplication` for mic status (not the misleading `AVCaptureDevice` path alone).
- Empty / no-speech recognition is mapped to idle instead of a sticky `.error` that disabled Start (that older bug is addressed in `AppState`).
- Cancel is available during transcribing/enhancing.
- Paste tries AX selected text, then activate-target, then session Cmd+V, then clipboard.
- History is AES-GCM in Application Support, excluded from backup; API key is in Keychain.
- Secure fields are skipped for history when AX reports `AXSecureTextField`.
- Info.plist has microphone and speech usage strings; `LSUIElement` is correct for a menu-bar agent.

---

## Recommended fix order

1. **Replace the mic-test sheet with an `NSPanel`.** Do not auto-start audio. Do not change the system default input.
2. **Guard the input `Picker`** so selection is always in the device list.
3. **Fix delayed `startMicTest` vs dismiss** (session id on the scheduled block, or no auto-start).
4. **Recording:** initialize the graph without calling `prepare()` on the layout path; if format is 0, `start()` inside `ExceptionCatcher` and read format after; show the real error, not “no speech.”
5. **Level meter:** compute RMS for Int16 as well as Float32.
6. **Add a tiny smoke list** (manual or XCUITest): open/close mic panel, start/stop test, test then dictate, dictate with silence then dictate again.

Until (1)–(3) land, treat Check microphone as **still broken**. Rebuild with `./run.sh` after those changes; the 02:58 crash report is from the old `AVAudioEngine.prepare()` path and does not prove the recorder path is safe.
