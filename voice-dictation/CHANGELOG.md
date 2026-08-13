# Changelog

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
