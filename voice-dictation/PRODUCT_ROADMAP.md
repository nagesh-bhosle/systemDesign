# Voice Dictation — product and distribution contract

This document is the contract for turning the working dictation app into an **installable Mac product**. Implementation can wait; do not regress the headset-safe recording path while shipping it.

**Bundle ID (stable forever):** `com.nagesh.voicedictation`  
**Known-good dictation snapshot (do not retarget):** git tags `voice-dictation-working` and `voice-dictation-working-2026-08-13` at `c1c3ee7`. Restore that audio path if headset or laptop recording breaks.

---

## What this product is

A **local Wispr Flow–style macOS dictation app**:

- Lives in the **menu bar**; optional floating capsule.
- **Global hotkey** (toggle or push-to-talk) starts and stops capture.
- **On-device speech-to-text** via Apple `SFSpeechRecognizer` (optional server fallback).
- **Optional LLM cleanup** (Abacus / RouteLLM) on **text only**, never audio.
- **Paste at cursor** (Accessibility + Cmd+V) or clipboard-only.

Audio capture is **`AVAudioRecorder`**, then **`SFSpeechURLRecognitionRequest`** on the temp file after Stop. **Do not** use `AVAudioEngine` live input or in-app HAL / default-input switching — that drops Bluetooth headsets.

Transcription happens **after Stop**, not live while talking.

---

## Goal: installable software, not a rebuild ritual

The user should treat this like any other Mac app:

- App lives in **`~/Applications/VoiceDictation.app`** or **`/Applications`**.
- Appears in **Launchpad** and Spotlight.
- **Stable identity**: same bundle ID, same (or Developer ID) signature so Accessibility and other TCC grants survive upgrades.
- Daily use is **open the installed app**, not `./run.sh` after every change.

`./run.sh` remains the **developer** build. `./run.sh install` copies the built bundle to `~/Applications/VoiceDictation.app`.

---

## Stable channel vs development

| Channel | What it is | What the user installs |
|---------|------------|------------------------|
| **Stable** | `main` after review, plus version git tags (`v0.4.0`, …) | The `.app` from that tag / zip |
| **Working audio restore** | Tags `voice-dictation-working*` | Emergency rollback of dictation only; not the product channel |
| **Development** | `feature/*` branches | Not installed as the daily driver |

Future work ships as **upgrades** of the installed app (new version numbers), not as “throw away the app and run the script again.”

---

## Versioning

- **User-facing:** `CFBundleShortVersionString` (e.g. `0.4.0`) — Settings → About, README, zip name.
- **Build:** `CFBundleVersion` (integer, monotonic: 3 → 4 → …).
- **Script:** `APP_VERSION` in `run.sh` must match the short version.
- **Notes:** `CHANGELOG.md` for every shipped version.
- **Git:** annotated tags `vMAJOR.MINOR.PATCH` on the commit that ships that version.

Do **not** move `voice-dictation-working` when tagging a product version unless the user explicitly asks.

---

## Update flow (later — Sparkle or similar)

Not implemented in 0.4.0 (needs a hosted appcast and signing). When time allows:

1. Sign the app with **Developer ID Application**.
2. Notarize and staple.
3. Host an **appcast** (Sparkle 2) with EdDSA signatures for each zip/dmg.
4. In-app **Check for Updates** against that feed.
5. Sparkle replaces `VoiceDictation.app` in place; bundle ID stays `com.nagesh.voicedictation` so:
   - Accessibility / Mic / Speech TCC survive
   - Launch at Login keeps working
   - UserDefaults and Keychain keep working

Until Sparkle exists, upgrades are: build or download the new zip, replace the `.app` in Applications (or `./run.sh install` again).

---

## Codesigning, notarization, Accessibility

- Unsigned `swiftc` rebuilds look like a **new app** to TCC. After each unsigned rebuild: System Settings → Privacy & Security → **Accessibility** → uncheck Voice Dictation, then check it again.
- `run.sh` already tries Apple Development / Developer ID if present (`CODESIGN_IDENTITY`).
- **Notarization** requires a paid Apple Developer account; out of scope until that exists.
- **Never change the bundle ID.** Changing it resets every permission.

---

## Audio / headset rules (non-negotiable)

Keep these unless a new snapshot is tagged after testing **both** laptop mic and Bluetooth headset:

1. Record with `AVAudioRecorder` (same as mic check).
2. Transcribe the `.caf` after Stop (`SFSpeechURLRecognitionRequest`).
3. No `AVAudioEngine` input graph for dictation.
4. No `kAudioHardwarePropertyDefaultInputDevice` / `kAudioOutputUnitProperty_CurrentDevice` from this app.
5. Do not play `NSSound` at **Start** (Bluetooth HFP bounce). Finish chime only after transcribe, if enabled.
6. Mic check is an `NSPanel`; audio starts only on **Start test**.

---

## When to do this work

Do productization (Sparkle, notarization, `/Applications` DMG, website) **when time allows**. This file is the contract so later work does not invent a second identity or a second audio path.
