//
//  SettingsView.swift
//  VoiceDictation
//
//  Settings window — API key entry, LLM model/endpoint config, hotkey display.
//

import SwiftUI

// Issue #41: Encapsulate in an enum namespace instead of global let
enum AvailableModels {
    // Issue #15: Use realistic model names that exist on the Abacus AI API
    static let models: [(name: String, label: String, cost: String)] = [
        ("meta-llama/Meta-Llama-3.1-8B-Instruct", "Meta Llama 3.1 8B", "$0.05/M — very fast + cheapest"),
        ("deepseek-ai/DeepSeek-V3", "DeepSeek V3", "$0.28/M — fast"),
        ("gpt-4.1-nano", "GPT-4.1 Nano", "$0.40/M — fast"),
        ("gpt-4o-mini", "GPT-4o Mini", "$0.60/M — balanced"),
        ("gemini-2.0-flash-lite", "Gemini 2.0 Flash Lite", "$1.50/M — very fast"),
        ("gemini-2.5-flash", "Gemini 2.5 Flash", "$2.50/M — fast Gemini"),
        ("route-llm", "Route LLM (auto)", "Auto-routes to best model"),
    ]
}

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var newAPIKey: String = ""
    @State private var showSavedAlert: Bool = false
    @State private var showDeletedAlert: Bool = false
    @State private var endpointDraft: String = ""
    // Issue #46: Endpoint save feedback
    @State private var showEndpointSaved: Bool = false

    var body: some View {
        Form {
            Section("Abacus AI API Key (Optional — for text cleanup)") {
                SecureField("your-api-key...", text: $newAPIKey)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Button("Save Key") {
                        // Issue #11: Check Keychain save result
                        let result = KeychainHelper.shared.saveAPIKey(newAPIKey)
                        switch result {
                        case .success:
                            appState.apiKey = newAPIKey
                            newAPIKey = ""
                            showSavedAlert = true
                            // Issue #45: Auto-dismiss after 2 seconds
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                showSavedAlert = false
                            }
                        case .failure(let error):
                            appState.errorMessage = error.localizedDescription
                        }
                    }
                    .disabled(newAPIKey.isEmpty)

                    Button("Delete Key") {
                        let result = KeychainHelper.shared.deleteAPIKey()
                        switch result {
                        case .success:
                            appState.apiKey = ""
                            showDeletedAlert = true
                            showSavedAlert = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                showDeletedAlert = false
                            }
                        case .failure(let error):
                            appState.errorMessage = error.localizedDescription
                        }
                    }
                    .disabled(appState.apiKey.isEmpty)
                }

                if showSavedAlert {
                    Text("✅ Key saved to Keychain")
                        .font(.caption)
                        .foregroundColor(.green)
                }

                if showDeletedAlert {
                    Text("✅ Key deleted from Keychain")
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
                // Issue #19: Show clear state when disabled
                Toggle("Enable LLM cleanup (remove filler words, fix grammar)", isOn: $appState.enhanceEnabled)
                    .disabled(appState.apiKey.isEmpty)

                if appState.apiKey.isEmpty {
                    Text("Enter an API key above to enable LLM cleanup.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else if !appState.enhanceEnabled {
                    Text("LLM cleanup is disabled. Raw speech-to-text will be used.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if appState.enhanceEnabled && !appState.apiKey.isEmpty {
                    Picker("Model", selection: Binding(
                        get: { appState.llmModel },
                        set: { appState.saveLLMModel($0) }
                    )) {
                        ForEach(AvailableModels.models, id: \.name) { model in
                            VStack(alignment: .leading) {
                                Text(model.label)
                                Text(model.cost)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .tag(model.name)
                        }
                    }

                    HStack {
                        TextField("Endpoint URL", text: $endpointDraft, prompt: Text("https://routellm.abacus.ai/v1/chat/completions"))
                            .textFieldStyle(.roundedBorder)

                        Button("Save") {
                            let trimmed = endpointDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !trimmed.isEmpty {
                                appState.saveLLMEndpoint(trimmed)
                                // Issue #46: Show save confirmation
                                showEndpointSaved = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                    showEndpointSaved = false
                                }
                            }
                        }
                        .disabled(endpointDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                    // Issue #46: Endpoint save feedback
                    if showEndpointSaved {
                        Text("✅ Endpoint saved")
                            .font(.caption)
                            .foregroundColor(.green)
                    }

                    Text("Current: \(appState.llmModel)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
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
                Text("Voice Dictation v0.1.0")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("Speech recognition runs on-device. Press ⌥⇧Space to start/stop. Text is pasted at cursor (or copied to clipboard).")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 500, height: 520)
        .onAppear {
            endpointDraft = appState.llmEndpoint
        }
    }
}