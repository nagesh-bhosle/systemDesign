//
//  SettingsView.swift
//  VoiceDictation
//
//  Tabbed settings: General / Enhancement / Privacy / About
//

import SwiftUI

enum AvailableModels {
    static let models: [(name: String, label: String, cost: String)] = [
        ("meta-llama/Meta-Llama-3.1-8B-Instruct", "Meta Llama 3.1 8B", "$0.05/M"),
        ("deepseek-ai/DeepSeek-V3", "DeepSeek V3", "$0.28/M"),
        ("gpt-4.1-nano", "GPT-4.1 Nano", "$0.40/M"),
        ("gpt-4o-mini", "GPT-4o Mini", "$0.60/M"),
        ("gemini-2.0-flash-lite", "Gemini 2.0 Flash Lite", "$1.50/M"),
        ("gemini-2.5-flash", "Gemini 2.5 Flash", "$2.50/M"),
        ("route-llm", "Route LLM (auto)", "Auto-routes"),
    ]
}

enum SpeechLocales {
    static let options: [(id: String, label: String)] = [
        ("en-US", "English (US)"),
        ("en-GB", "English (UK)"),
        ("de-DE", "German"),
        ("es-ES", "Spanish"),
        ("fr-FR", "French"),
        ("hi-IN", "Hindi"),
    ]
}

enum SettingsTab: String, CaseIterable, Identifiable {
    case general = "General"
    case enhancement = "Enhancement"
    case privacy = "Privacy"
    case about = "About"

    var id: String { rawValue }
}

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab: SettingsTab = .general
    @State private var newAPIKey: String = ""
    @State private var endpointDraft: String = ""
    @State private var apiKeyStatus: APIKeyStatus = .unknown
    @State private var isVerifyingKey = false
    @State private var showAdvancedCosts = false
    @State private var showKeySaved = false
    @State private var showKeyDeleted = false
    @State private var showEndpointSaved = false

    enum APIKeyStatus {
        case unknown, connected, failed
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Section", selection: $selectedTab) {
                ForEach(SettingsTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            Divider()

            ScrollView {
                Group {
                    switch selectedTab {
                    case .general: generalSection
                    case .enhancement: enhancementSection
                    case .privacy: privacySection
                    case .about: aboutSection
                    }
                }
                .padding()
            }
        }
        .frame(width: 520, height: 560)
        .tint(AppTheme.accent)
        .onAppear {
            endpointDraft = appState.llmEndpoint
            if !appState.apiKey.isEmpty {
                apiKeyStatus = .unknown
            }
        }
    }

    // MARK: - General

    private var generalSection: some View {
        Form {
            Section("Dictation Language") {
                Picker("Language", selection: Binding(
                    get: { appState.speechLocale },
                    set: { appState.saveSpeechLocale($0) }
                )) {
                    ForEach(SpeechLocales.options, id: \.id) { locale in
                        Text(locale.label).tag(locale.id)
                    }
                }
                .accessibilityLabel("Dictation language")
            }

            Section("Global Hotkey") {
                HStack {
                    Text("Toggle Recording")
                    Spacer()
                    HotkeyKeycapsView()
                }
                Text("Press the hotkey anywhere to start and stop recording.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Behavior") {
                Toggle("Show floating bar", isOn: Binding(
                    get: { appState.showFloatingWindow },
                    set: { appState.saveShowFloatingWindow($0) }
                ))
                .accessibilityLabel("Show floating bar")

                Toggle("Clipboard-only mode", isOn: Binding(
                    get: { appState.clipboardOnlyMode },
                    set: { appState.saveClipboardOnlyMode($0) }
                ))
                .accessibilityLabel("Clipboard only mode")

                Toggle("Restore clipboard after paste", isOn: Binding(
                    get: { appState.restoreClipboard },
                    set: { appState.saveRestoreClipboard($0) }
                ))
                .accessibilityLabel("Restore clipboard after paste")

                if #available(macOS 13.0, *) {
                    Toggle("Launch at login", isOn: Binding(
                        get: { appState.launchAtLogin },
                        set: { appState.saveLaunchAtLogin($0) }
                    ))
                    .accessibilityLabel("Launch at login")

                    if !appState.launchAtLoginError.isEmpty {
                        Text(appState.launchAtLoginError)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Enhancement

    private var enhancementSection: some View {
        Form {
            Section("API Key") {
                HStack {
                    SecureField("your-api-key...", text: $newAPIKey)
                        .textFieldStyle(.roundedBorder)
                    apiKeyStatusIndicator
                }

                HStack {
                    Button("Save Key") { saveAPIKey() }
                        .disabled(newAPIKey.isEmpty)

                    Button("Verify") { verifyAPIKey() }
                        .disabled(appState.apiKey.isEmpty && newAPIKey.isEmpty)
                        .accessibilityLabel("Verify API key")

                    Button("Delete Key") { deleteAPIKey() }
                        .disabled(appState.apiKey.isEmpty)
                }

                if showKeySaved {
                    Label("Key saved to Keychain", systemImage: "checkmark.circle.fill")
                        .font(.caption).foregroundColor(.green)
                }
                if showKeyDeleted {
                    Label("Key deleted from Keychain", systemImage: "checkmark.circle.fill")
                        .font(.caption).foregroundColor(.green)
                }

                if !appState.apiKey.isEmpty {
                    Text("Key is set (hidden for security)")
                        .font(.caption).foregroundColor(.secondary)
                }
            }

            Section("Text Cleanup") {
                Toggle("Cleaned text is sent to Abacus AI. Audio stays on your Mac.", isOn: Binding(
                    get: { appState.enhanceEnabled },
                    set: { appState.saveEnhanceEnabled($0) }
                ))
                .disabled(appState.apiKey.isEmpty)
                .accessibilityLabel("Enable LLM text cleanup")

                if appState.apiKey.isEmpty {
                    Text("Enter an API key above to enable LLM cleanup.")
                        .font(.caption).foregroundColor(.secondary)
                }

                if appState.enhanceEnabled && !appState.apiKey.isEmpty {
                    Picker("Model", selection: Binding(
                        get: { appState.llmModel },
                        set: { appState.saveLLMModel($0) }
                    )) {
                        ForEach(AvailableModels.models, id: \.name) { model in
                            Text(model.label).tag(model.name)
                        }
                    }

                    DisclosureGroup("Advanced", isExpanded: $showAdvancedCosts) {
                        ForEach(AvailableModels.models, id: \.name) { model in
                            HStack {
                                Text(model.label)
                                Spacer()
                                Text(model.cost)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        HStack {
                            TextField("Endpoint URL", text: $endpointDraft)
                                .textFieldStyle(.roundedBorder)
                            Button("Save") {
                                let trimmed = endpointDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                                if !trimmed.isEmpty {
                                    appState.saveLLMEndpoint(trimmed)
                                    showEndpointSaved = true
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                        showEndpointSaved = false
                                    }
                                }
                            }
                            .disabled(endpointDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }

                        if showEndpointSaved {
                            Label("Endpoint saved", systemImage: "checkmark.circle.fill")
                                .font(.caption).foregroundColor(.green)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Privacy

    private var privacySection: some View {
        Form {
            Section("Speech Recognition") {
                Toggle("On-device speech recognition", isOn: Binding(
                    get: { appState.onDeviceRecognition },
                    set: { appState.saveOnDeviceRecognition($0) }
                ))
                .accessibilityLabel("On-device speech recognition")

                Text("When enabled, audio is processed on your Mac. If on-device recognition is unavailable, the app falls back to Apple's server-based recognition.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("History") {
                HStack {
                    Text("Saved only on this Mac")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.green.opacity(0.12)))
                        .foregroundColor(.green)
                }

                Toggle("Save transcript history", isOn: Binding(
                    get: { appState.saveHistoryEnabled },
                    set: { appState.saveHistoryPreference($0) }
                ))
                .accessibilityLabel("Save transcript history")
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - About

    private var aboutSection: some View {
        Form {
            Section("Voice Dictation") {
                Text("Version 0.2.0")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("Speech recognition runs on your Mac. Press the global hotkey to start and stop dictation. Text is pasted at your cursor or copied to the clipboard.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("Optional LLM cleanup sends text (not audio) to Abacus AI.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - API Key Status

    @ViewBuilder
    private var apiKeyStatusIndicator: some View {
        HStack(spacing: 4) {
            if isVerifyingKey {
                ProgressView().controlSize(.small)
            } else {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(statusLabel)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var statusColor: Color {
        switch apiKeyStatus {
        case .connected: return .green
        case .failed: return .red
        case .unknown: return .secondary
        }
    }

    private var statusLabel: String {
        switch apiKeyStatus {
        case .connected: return "Connected"
        case .failed: return "Failed"
        case .unknown: return ""
        }
    }

    private func saveAPIKey() {
        let result = KeychainHelper.shared.saveAPIKey(newAPIKey)
        switch result {
        case .success:
            appState.apiKey = newAPIKey
            newAPIKey = ""
            showKeySaved = true
            apiKeyStatus = .unknown
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { showKeySaved = false }
        case .failure(let error):
            appState.errorMessage = error.localizedDescription
        }
    }

    private func deleteAPIKey() {
        let result = KeychainHelper.shared.deleteAPIKey()
        switch result {
        case .success:
            appState.apiKey = ""
            apiKeyStatus = .unknown
            showKeyDeleted = true
            showKeySaved = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { showKeyDeleted = false }
        case .failure(let error):
            appState.errorMessage = error.localizedDescription
        }
    }

    private func verifyAPIKey() {
        let key = newAPIKey.isEmpty ? appState.apiKey : newAPIKey
        guard !key.isEmpty else { return }
        isVerifyingKey = true
        AbacusLLMService().testAPIKey(apiKey: key) { result in
            DispatchQueue.main.async {
                isVerifyingKey = false
                switch result {
                case .success:
                    apiKeyStatus = .connected
                case .failure:
                    apiKeyStatus = .failed
                }
            }
        }
    }
}

// MARK: - Hotkey Keycaps

struct HotkeyKeycapsView: View {
    var body: some View {
        HStack(spacing: 4) {
            KeycapView(label: "⌥")
            KeycapView(label: "⇧")
            KeycapView(label: "Space")
        }
        .accessibilityLabel("Option Shift Space")
    }
}

struct KeycapView: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(.caption, design: .rounded))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.primary.opacity(0.06))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(AppTheme.hairlineBorder, lineWidth: 1))
            )
    }
}
