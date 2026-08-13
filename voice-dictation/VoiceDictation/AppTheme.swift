//
//  AppTheme.swift
//  VoiceDictation
//
//  Shared visual constants for the premium UI.
//

import SwiftUI

enum AppTheme {
    static let accent = Color(red: 0.95, green: 0.72, blue: 0.28)
    static let accentMuted = Color(red: 0.95, green: 0.72, blue: 0.28).opacity(0.16)
    static let hairlineBorder = Color.white.opacity(0.12)
    static let cardBackground = Color.primary.opacity(0.045)
    static let recording = Color(red: 0.92, green: 0.28, blue: 0.28)
    static let success = Color(red: 0.35, green: 0.78, blue: 0.48)

    static let menuWidth: CGFloat = 300
    static let cardRadius: CGFloat = 12
    static let pillHeight: CGFloat = 40

    static func cardShape() -> RoundedRectangle {
        RoundedRectangle(cornerRadius: cardRadius, style: .continuous)
    }
}

struct ThemeCard<Content: View>: View {
    var padding: CGFloat = 12
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                AppTheme.cardShape()
                    .fill(AppTheme.cardBackground)
                    .overlay(
                        AppTheme.cardShape()
                            .stroke(AppTheme.hairlineBorder, lineWidth: 1)
                    )
            )
    }
}
