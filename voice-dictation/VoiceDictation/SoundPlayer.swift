//
//  SoundPlayer.swift
//  VoiceDictation
//
//  Plays short system sounds on recording start/stop.
//

import AppKit

final class SoundPlayer {
    static let shared = SoundPlayer()

    private init() {}

    func playRecordingStart() {
        if let sound = NSSound(named: "Tink") {
            sound.play()
        } else {
            NSSound.beep()
        }
    }

    func playRecordingStop() {
        if let sound = NSSound(named: "Pop") {
            sound.play()
        } else {
            NSSound.beep()
        }
    }
}
