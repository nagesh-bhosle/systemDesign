# Changelog

## 0.5.1 — 2026-08-13

- Fix auto-paste inserting the **previous** take: do not restore the old clipboard until the focused field actually contains this transcript. A timed restore was racing Cmd+V. False Accessibility "success" now falls through to Cmd+V.

## 0.5.0 — 2026-08-13

Correctness and visual polish. Audio path unchanged (`AVAudioRecorder` + file STT after Stop).

- Clipboard restore: after Accessibility insert, restore immediately. After Cmd+V, wait until the target field contains the text (or 2.5s). Never restore if the user already copied something else.
- History and Settings open in dedicated windows (same pattern as Check microphone), not sheets on the menu extra.
- Custom vocabulary uses whole-word matching, escaped replacements (`$` / `\` are literal), and skips one-character / punctuation-only lines.
- Richer menu extra, Settings sidebar, History cards, and floating pill.

## 0.4.0 — 2026-08-13

Installable-product contract and safe correctness fixes on the headset-safe recorder path. Dictation is still `AVAudioRecorder` + `SFSpeechURLRecognitionRequest` after Stop.

- Documented the professional Mac app goal (`PRODUCT_ROADMAP.md`): Applications folder, stable bundle id `com.nagesh.voicedictation`, versioning, Sparkle later, codesign/notarization/Accessibility.
- `./run.sh install` copies the built app to `~/Applications/VoiceDictation.app`.
- Delete leftover `voicedictation-*.caf` temp recordings on launch, quit, and after transcribe (privacy).
- UI copy: words appear after Stop; “Transcribing after you stop…”.
- Transcribe timeout scales with recording length (about 12s minimum, up to 60s).
- Finish sound plays **after** transcription (not at Start) so Bluetooth does not drop. Settings toggle wording updated.
- Short takes: no longer discarded at a 2000-byte cutoff; only header-only / accidental clicks are skipped.
- Version: `CFBundleShortVersionString` 0.4.0, `CFBundleVersion` 4.

## 0.3.0

Product polish: customizable hotkey, push-to-talk, history, vocabulary, onboarding, distribution zip.

## 0.2.0

Earlier menu-bar dictation MVP.

## Headset-safe restore point

Git tags `voice-dictation-working` and `voice-dictation-working-2026-08-13` remain at `c1c3ee7` and are not moved by this release.
