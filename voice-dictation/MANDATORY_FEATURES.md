# Voice Dictation — mandatory features and test cases

**Version reviewed:** 0.5.3  
**Rule:** After **every** feature, bugfix, or refactor, run this suite **before** merge. If any mandatory case fails, the change does not ship.

These four capabilities are the product. Everything else (history, vocabulary, sounds, Sparkle) is optional.

---

## Gate (must all pass)

| ID | Mandatory feature | Pass means |
|----|-------------------|------------|
| **M1** | Record voice **up to 5 minutes** | User can speak continuously up to 5:00, Stop, and get the **full** transcript (not only the last line or last ~30s). |
| **M2** | Paste **at the cursor** | After Stop (and transcribe), text is inserted where the caret was in the other app, not only onto the clipboard (unless clipboard-only is on). |
| **M3** | **Optional** LLM integration | Cleanup is off by default. With an API key and the toggle on, text (never audio) is cleaned then pasted. With the toggle off or no key, raw STT still pastes. |
| **M4** | **Hotkey** record **and** **floating window** | Global hotkey starts and stops recording. Floating bar shows listening / timer / transcribing and can be shown or hidden without breaking M1–M3. |

**Non-negotiable audio path:** `AVAudioRecorder` then `SFSpeechURLRecognitionRequest` after Stop. Do **not** use `AVAudioEngine` live input or in-app default-mic switching (Bluetooth headset regression).

---

## How to run

1. Quit any running Voice Dictation.
2. `cd voice-dictation && ./run.sh install`
3. Open **`~/Applications/VoiceDictation.app`** (not `build/` from a leftover `./run.sh`).
4. Settings → About shows the version you intend to test.
5. Grant Microphone, Speech Recognition, and Accessibility (toggle off/on after unsigned rebuilds).
6. Execute **M1–M4** below. Record pass/fail.

Headset and laptop mic: if you have a Bluetooth headset, run M1 and M4 once on each input (System Settings → Sound).

---

## M1 — Record up to 5 minutes

**Code today:** `AVAudioRecorder.record()` has no 5-minute cap. STT splits audio into ~20s chunks with 2s overlap (Apple ~1 minute limit per request). Timeout scales with length (cap 15 minutes of wait). There is **no auto-stop at 5:00**.

### Test cases

| ID | Steps | Expected | Fail if |
|----|--------|----------|---------|
| M1.1 | Start, speak **~20s** of distinct words, Stop. Wait for paste. | Full sentence(s) you said. | Empty, “no speech”, or only last few words. |
| M1.2 | Start, speak **~45s**, include a unique word at the **start** (“alpha”) and **end** (“omega”). Stop. | Transcript contains both alpha and omega. | Only omega / last line. |
| M1.3 | Start, speak **~2 minutes**, unique marker every ~20s (one, two, three…). Stop. Wait (transcribe can take minutes). | All markers present in order. | Missing early markers; only last chunk. |
| M1.4 | Start, speak **5 minutes** (or as close as practical). Unique first sentence and last sentence. Stop. Wait until Idle. | First and last sentences both in the pasted text. Menu last-transcript / History match paste. | Truncated to last line, last 30s, or timeout “no speech”. |
| M1.5 | Start, remain silent 3s, Stop. | Idle, gentle empty message, Start still works. | App stuck on Listening/Transcribing. |
| M1.6 | After M1.4, Start again and speak 10s. | New take pastes; previous take not required in the new paste. | Frozen Start, or always pastes previous take. |

---

## M2 — Paste at cursor

**Code today:** Capture frontmost app at Start. After STT, Accessibility splices at caret, else session Cmd+V. Clipboard-only mode copies and notifies. Unsigned rebuilds may need Accessibility toggle.

### Test cases

| ID | Steps | Expected | Fail if |
|----|--------|----------|---------|
| M2.1 | Focus Notes (or TextEdit). Place caret mid-sentence. Hotkey Start, say “hello cursor”, Stop. | “hello cursor” appears **at caret**, surrounding text kept. | Whole field replaced; text only on clipboard; paste in Voice Dictation. |
| M2.2 | Repeat in Safari address bar or Slack message box. | Insert at caret in that field. | Wrong app, or previous clipboard contents. |
| M2.3 | Two takes in the same field: “first take” then “second take”. | Both appear (second after first, or as two inserts). | Second take is only “second take” **replacing** “first take” when you did not select all. |
| M2.4 | Settings → Clipboard-only **on**. Dictate into Notes. | Notification / clipboard has text; Notes does **not** auto-insert. Toggle off restores auto-paste. | Auto-paste still happens, or nothing copied. |
| M2.5 | After unsigned `./run.sh install`, if paste fails: Accessibility off then on. Retry M2.1. | Paste works after refresh. | Permanent clipboard-only with no Settings hint. |

---

## M3 — Optional LLM integration

**Code today:** Settings → Enhancement. Key in Keychain. Toggle persisted. Sends **text only**. Timeout falls back to raw STT. Prompt says keep the entire dictation. `max_tokens` 8192. Default off.

### Test cases

| ID | Steps | Expected | Fail if |
|----|--------|----------|---------|
| M3.1 | No API key, or cleanup **off**. Dictate “um hello world”. | Raw-ish STT pastes. No hang on Enhancing. | App stuck Enhancing; nothing pasted. |
| M3.2 | Save key, **Verify** succeeds, turn cleanup **on**. Dictate a sentence with “um”. | Status Enhancing, then paste cleaned text (fillers reduced). Audio not uploaded (copy: text only). | Audio required; paste empty; key shown in UI. |
| M3.3 | Disconnect network (or bad key), cleanup on, dictate. | Error/fallback, **raw transcript still pasted**. | Total loss of text. |
| M3.4 | Cleanup on. Speak **~1 minute** with a unique first and last phrase. | Cleaned result still contains first **and** last phrase (not a one-line summary). | Only last sentence after LLM. |
| M3.5 | Quit and relaunch. | Cleanup toggle and key still set (key hidden). | Toggle resets every launch. |

---

## M4 — Hotkey record and floating window

**Code today:** Default ⌥⇧Space, remappable, push-to-talk optional. Carbon `RegisterEventHotKey`. Floating `NSPanel` capsule; pref `showFloatingWindow` (default on). Menu Start/Stop also works if hotkey conflicts.

### Test cases

| ID | Steps | Expected | Fail if |
|----|--------|----------|---------|
| M4.1 | Focus another app. Press default (or your) hotkey. Speak. Press again. | Recording starts/stops **without** clicking the menu. Then M2 paste. | Hotkey does nothing; only menu works. |
| M4.2 | Settings → Record shortcut to a new combo. Use it. | New combo toggles record. Old combo does not (unless still bound). | Settings shows combo but hotkey unchanged. |
| M4.3 | Enable push-to-talk. Hold hotkey, speak, release. | Records while held; transcribes on release. | Toggle behavior still; or no key-up. |
| M4.4 | Floating bar **on**. Start recording. | Capsule expands, timer `0:00` counting, “Stop to transcribe”. | No window, or Start kills headset. |
| M4.5 | Hide floating bar (menu toggle or pill X). Dictate via hotkey. | No pill; M1–M3 still work. Show again; pill returns next Start. | Hiding bar disables recording. |
| M4.6 | Click Start/Stop on the **menu** with floating bar on. | Same as hotkey; pill updates. | Menu and hotkey disagree; two recordings. |

---

## After-every-feature checklist

Copy this into the PR / commit notes:

```
Mandatory gate (MANDATORY_FEATURES.md)
- [ ] M1.1 short take
- [ ] M1.2 45s start+end markers
- [ ] M1.4 5 min (or note why skipped + M1.3 2 min done)
- [ ] M2.1 paste at caret in Notes
- [ ] M2.3 two sequential takes
- [ ] M3.1 LLM off still pastes
- [ ] M3.2 LLM on cleans (if key available) or M3.3 fallback
- [ ] M4.1 hotkey start/stop
- [ ] M4.4 floating window while recording
- [ ] Headset still connected (if tested)
```

Minimum for a small UI-only change: **M1.1, M2.1, M3.1, M4.1, M4.4**.  
Any change to STT, paste, LLM, hotkey, or audio: **full table** for that ID plus M1.1 and M2.1.

---

## Out of scope for this gate

Sparkle, notarization, live words while talking, snippets, Xcode/SPM tests. Those must not break M1–M4.
