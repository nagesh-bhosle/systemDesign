//
//  SettingsView.swift
//  VoiceDictation
//
//  Settings window — API key entry, hotkey display, language selection.
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var newAPIKey: String = ""
    @State private var showSavedAlert: Bool = false

    var body: some View {
        Form {
            Section("Abacus AI API Key (Optional — for text cleanup)") {
                SecureField("your-api-key...", text: $newAPIKey)
                    .textFieldStyle(.roundedBorder)

                Button("Save Key") {
                    KeychainHelper.shared.saveAPIKey(newAPIKey)
                    appState.apiKey = newAPIKey
                    newAPIKey = ""
                    showSavedAlert = true
                }
                .disabled(newAPIKey.isEmpty)

                if showSavedAlert {
                    Text("✅ Key saved to Keychain")
                        .font(.caption)
                        .foregroundColor(.green)
                }

                if !appState.apiKey.isEmpty {
                    Text("Key is set (hidden for security)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("Without a key, raw speech-to-text will be pasted without cleanup.")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }

            Section("AI Text Enhancement") {
                Toggle("Enable LLM cleanup (remove filler words, fix grammar)", isOn: $appState.enhanceEnabled)
                    .disabled(appState.apiKey.isEmpty)
            }

            Section("Global Hotkey") {
                HStack {
                    Text("Toggle Recording")
                    Spacer()
                    Text("⌥⇧Space")
                        .font(.system(.body, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(6)
                }
            }

            Section("About") {
                Text("Voice Dictation v0.2")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("Speech recognition runs on-device. Press ⌥⇧Space to start/stop. Text is pasted at your cursor.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 450, height: 400)
    }
}