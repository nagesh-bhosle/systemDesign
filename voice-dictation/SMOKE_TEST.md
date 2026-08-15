# Smoke tests — Voice Dictation

Known-good restore: `git checkout voice-dictation-working` then `./run.sh`.

**Mandatory product tests (5 min record, paste at cursor, optional LLM, hotkey + floating window):** `MANDATORY_FEATURES.md`. Run that suite after every feature.

Run after `./run.sh`. Fail if any step crashes, wedges Start, or drops the headset.

1. **Headset (if you have one):** System Settings → Sound → Input = headset. Check microphone → Start test → meter moves. Done. **Start** dictation → speak → **Stop**. Headset stays connected. Text appears.
2. **Laptop mic:** Sound → Input = MacBook microphone. Same as (1).
3. Check microphone opens a separate window. Meter idle until Start test. Close while testing; app stays up; Start test works again.
4. Silent dictation (Start, say nothing, Stop) returns to Idle. Start again and speak — works.
5. Option+Shift+Space (or your shortcut) starts/stops.
6. Quit from the menu. Relaunch. Idle, not stuck Listening.

