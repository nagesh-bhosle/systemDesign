//
//  SettingsView.swift
//  VoiceDictation
//
//  Settings window — API key entry, LLM model/endpoint config, hotkey display.
//

import SwiftUI

// All available models on routellm.abacus.ai (fast/cheap ones for text cleanup)
let AVAILABLE_MODELS: [(name: String, label: String, cost: String)] = [
    ("meta-llama/Meta-Llama-3.1-8B-Instruct", "Meta Llama 3.1 8B", "$0.05/M — very fast + cheapest"),
    ("deepseek-ai/DeepSeek-V4-Flash-0731", "DeepSeek V4 Flash", "$0.28/M — fast"),
    ("gpt-4.1-nano", "GPT-4.1 Nano", "$0.40/M — fast"),
    ("gpt-5-nano", "GPT-5 Nano", "$0.40/M — fast"),
    ("gpt-5.4-nano", "GPT-5.4 Nano", "$1.25/M — fast"),
    ("gemini-3.1-flash-lite", "Gemini 3.1 Flash Lite", "$1.50/M — very fast"),
    ("gemini-3.5-flash-lite", "Gemini 3.5 Flash Lite", "$2.50/M — fastest Gemini"),
    ("gpt-4o-mini", "GPT-4o Mini", "$0.60/M — previous default"),
    ("route-llm", "Route LLM (auto)", "Auto-routes to best model"),
]

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var newAPIKey: String = ""
    @State private var showSavedAlert: Bool = false
    @State private var endpointDraft: String = ""

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

                if appState.enhanceEnabled && !appState.apiKey.isEmpty {
                    // Model dropdown
                    Picker("Model", selection: Binding(
                        get: { appState.llmModel },
                        set: { appState.saveLLMModel($0) }
                    )) {
                        ForEach(AVAILABLE_MODELS, id: \.name) { model in
                            VStack(alignment: .leading) {
                                Text(model.label)
                                Text(model.cost)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .tag(model.name)
                        }
                    }

                    // Endpoint
                    HStack {
                        TextField("Endpoint URL", text: Binding(
                            get: { appState.llmEndpoint },
                            set: { endpointDraft = $0 }
                        ), prompt: Text("https://routellm.abacus.ai/v1/chat/completions"))
                        .textFieldStyle(.roundedBorder)

                        Button("Save") {
                            let trimmed = endpointDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !trimmed.isEmpty {
                                appState.saveLLMEndpoint(trimmed)
                            }
                        }
                        .disabled(endpointDraft.isEmpty)
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
                Text("Voice Dictation v0.3")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("Speech recognition runs on-device. Press ⌥⇧Space to start/stop. Text is copied to clipboard — paste with Cmd+V.")
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