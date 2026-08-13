//
//  SoundPlayer.swift
//  VoiceDictation
//
//  Plays a short system sound after transcription finishes.
//  Do not play at record start — NSSound can bounce Bluetooth headsets into HFP.
//

import AppKit

final class SoundPlayer {
    static let shared = SoundPlayer()

    private init() {}

    func playDictationFinished() {
        if let sound = NSSound(named: "Pop") {
            sound.play()
        } else {
            NSSound.beep()
        }
    }
}
