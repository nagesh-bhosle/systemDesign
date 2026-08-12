//
//  OnboardingView.swift
//  VoiceDictation
//
//  First-run and permission onboarding.
//

import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Welcome to Voice Dictation")
                    .font(.title2.weight(.semibold))
                Text("Grant the permissions below to start dictating.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            VStack(spacing: 12) {
                ForEach(PermissionType.allCases) { permission in
                    PermissionRow(permission: permission)
                }
            }

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button("Continue") {
                    if appState.microphoneGranted && appState.speechGranted {
                        appState.completeOnboarding()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.accent)
                .disabled(!canContinue)
                .accessibilityLabel("Continue to Voice Dictation")
            }
        }
        .padding(24)
        .frame(width: 440, height: 420)
        .background(.ultraThinMaterial)
        .onAppear {
            PermissionHelper.probePermissions {
                appState.refreshPermissionState()
                if appState.microphoneGranted && appState.speechGranted {
                    appState.completeOnboarding()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            appState.refreshPermissionState()
            if appState.microphoneGranted && appState.speechGranted && appState.showOnboarding {
                appState.completeOnboarding()
            }
        }
    }

    private var canContinue: Bool {
        appState.microphoneGranted && appState.speechGranted
    }
}

private struct PermissionRow: View {
    let permission: PermissionType
    @EnvironmentObject var appState: AppState

    private var isGranted: Bool {
        switch permission {
        case .microphone: return appState.microphoneGranted
        case .speechRecognition: return appState.speechGranted
        case .accessibility: return appState.accessibilityGranted
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: iconName)
                .font(.title3)
                .foregroundColor(isGranted ? .green : AppTheme.accent)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(permission.title)
                        .font(.headline)
                    Spacer()
                    statusChip
                }
                Text(permission.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if !isGranted {
                    Button("Open System Settings") {
                        PermissionHelper.openSettings(for: permission)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityLabel("Open System Settings for \(permission.title)")
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(AppTheme.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(AppTheme.hairlineBorder, lineWidth: 1)
                )
        )
    }

    private var iconName: String {
        switch permission {
        case .microphone: return "mic.fill"
        case .speechRecognition: return "waveform"
        case .accessibility: return "hand.point.up.left.fill"
        }
    }

    private var statusChip: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(isGranted ? Color.green : Color.orange)
                .frame(width: 6, height: 6)
            Text(isGranted ? "Granted" : "Needs permission")
                .font(.caption2)
                .foregroundColor(isGranted ? .green : .orange)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill((isGranted ? Color.green : Color.orange).opacity(0.12))
        )
    }
}
