# Smoke tests — Voice Dictation

Run after `./run.sh`. Do these in order. Fail the build mentally if any step crashes or wedges Start.

1. Launch the app. Menu extra appears. No crash.
2. **Check microphone** opens a separate titled window (not a sheet on the menu).
3. Window opens idle. Meter does not move until **Start test**.
4. Start test, speak normally. Meter moves. Stop test. Meter idle. Start test again. Stop works.
5. Close the window with the red close button while a test is running. App stays up. Open Check microphone again. **Start test** works (not frozen).
6. Done / close, then **Start** dictation, speak, **Stop**. Text appears (or clipboard).
7. Start dictation, stay silent, Stop. Status returns to Idle. Start again and speak. Recording works.
8. Open Check microphone, pick a different input if you have a headset, Start test, confirm meter. Close. Dictate once more.
9. While Idle, Option+Shift+Space (or your shortcut) starts/stops recording.
10. Quit from the menu. No leftover “Listening” state on relaunch.

Do **not** expect a crawler to click every control. These ten paths cover the crashes we actually hit.
