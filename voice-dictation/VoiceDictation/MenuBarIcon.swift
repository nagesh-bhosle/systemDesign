//
//  MenuBarIcon.swift
//  VoiceDictation
//
//  Custom template menu-bar mark (avoids mic.fill / Control Center collision).
//

import SwiftUI
import AppKit

enum MenuBarIconRenderer {
    /// Three-bar waveform mark for idle menu extra (template image).
    static func makeTemplateImage(size: NSSize = NSSize(width: 18, height: 18)) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()

        NSColor.black.setFill()
        let barWidth: CGFloat = 2.5
        let spacing: CGFloat = 2
        let heights: [CGFloat] = [6, 10, 7]
        let totalWidth = CGFloat(heights.count) * barWidth + CGFloat(heights.count - 1) * spacing
        var x = (size.width - totalWidth) / 2

        for height in heights {
            let y = (size.height - height) / 2
            let rect = NSRect(x: x, y: y, width: barWidth, height: height)
            NSBezierPath(roundedRect: rect, xRadius: 0.8, yRadius: 0.8).fill()
            x += barWidth + spacing
        }

        image.unlockFocus()
        image.isTemplate = true
        return image
    }
}

struct MenuBarIdleIcon: View {
    var body: some View {
        Image(nsImage: MenuBarIconRenderer.makeTemplateImage())
            .renderingMode(.template)
            .accessibilityLabel("Voice Dictation")
    }
}
