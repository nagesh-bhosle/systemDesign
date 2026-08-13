//
//  SettingsView.swift
//  VoiceDictation
//
//  Tabbed settings: General / Enhancement / Privacy / About
//

import SwiftUI
import AppKit
import Carbon.HIToolbox

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

    var icon: String {
        switch self {
        case .general: return "slider.horizontal.3"
        case .enhancement: return "sparkles"
        case .privacy: return "lock.shield"
        case .about: return "info.circle"
        }
    }
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
    @State private var vocabularyDraft: String = ""
    @State private var hotkeyMonitor: Any?
    @State private var showPrivacySheet = false

    enum APIKeyStatus {
        case unknown, connected, failed
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            VStack(spacing: 0) {
                HStack {
                    Text(selectedTab.rawValue)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)

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
                    .padding(16)
                }
            }
        }
        .frame(minWidth: 540, minHeight: 560)
        .background(.ultraThinMaterial)
        .tint(AppTheme.accent)
        .onAppear {
            endpointDraft = appState.llmEndpoint
            vocabularyDraft = appState.customVocabulary
            appState.refreshAudioInputs()
            if !appState.apiKey.isEmpty {
                apiKeyStatus = .unknown
            }
        }
        .onDisappear {
            stopHotkeyRecording()
            appState.stopMicTest()
        }
        .sheet(isPresented: $showPrivacySheet) {
            PrivacyPolicySheet()
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Voice Dictation")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(.secondary)
                .padding(.horizontal, 10)
                .padding(.bottom, 8)

            ForEach(SettingsTab.allCases) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    Label(tab.rawValue, systemImage: tab.icon)
                        .font(.system(size: 13, weight: selectedTab == tab ? .semibold : .regular))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(selectedTab == tab ? AppTheme.accentMuted : Color.clear)
                        )
                        .foregroundColor(selectedTab == tab ? .primary : .secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.rawValue)
            }
            Spacer()
        }
        .padding(12)
        .frame(width: 168)
        .background(Color.primary.opacity(0.03))
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

            Section("Microphone") {
                Text("Dictation uses “\(appState.currentInputName)”. Changing input here used to disconnect headsets, so the mic is chosen in System Settings.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Button("Open Sound Settings") {
                    AudioInputManager.openSoundSettings()
                }
                .accessibilityLabel("Open Sound Settings")

                Button("Check microphone") {
                    MicTestWindowController.shared.show(appState: appState)
                }
                .disabled(appState.status == .recording || appState.status == .transcribing)
                .accessibilityLabel("Check microphone")
            }

            Section("Global Hotkey") {
                HStack {
                    Text("Shortcut")
                    Spacer()
                    HotkeyKeycapsView(
                        keyCode: appState.hotkeyKeyCode,
                        modifiers: appState.hotkeyModifiers
                    )
                }

                Button(appState.isRecordingHotkey ? "Press keys..." : "Record shortcut") {
                    if appState.isRecordingHotkey {
                        stopHotkeyRecording()
                    } else {
                        startHotkeyRecording()
                    }
                }
                .disabled(appState.status == .recording)

                if !appState.hotkeyRecordError.isEmpty {
                    Text(appState.hotkeyRecordError)
                        .font(.caption)
                        .foregroundColor(.red)
                }

                Toggle("Push-to-talk (hold to record)", isOn: Binding(
                    get: { appState.pushToTalkEnabled },
                    set: { appState.savePushToTalk($0) }
                ))
                .accessibilityLabel("Push to talk mode")

                Text(appState.pushToTalkEnabled
                     ? "Hold the shortcut to record; release to stop and transcribe."
                     : "Press the shortcut to start and stop recording.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Sounds") {
                Toggle("Play a sound when dictation finishes", isOn: Binding(
                    get: { appState.playSounds },
                    set: { appState.savePlaySounds($0) }
                ))
                .accessibilityLabel("Play a sound when dictation finishes")
                Text("Plays after transcription, not at Start, so Bluetooth headsets stay connected.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Custom Vocabulary") {
                TextEditor(text: $vocabularyDraft)
                    .font(.body)
                    .frame(minHeight: 72)
                    .onChange(of: vocabularyDraft) { _, newValue in
                        appState.saveCustomVocabulary(newValue)
                    }
                Text("One word or phrase per line (at least two characters). Matching is whole-word and case-insensitive; pasted text uses your capitalization. Regex characters are treated as plain text.")
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

                Text("When off, text is pasted at the cursor in the app you were using. Requires Accessibility permission. After rebuilding the app, re-enable Voice Dictation in System Settings → Privacy & Security → Accessibility.")
                    .font(.caption)
                    .foregroundColor(.secondary)

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

                Text("Tone adapts for Mail vs chat when cleanup is on.")
                    .font(.caption)
                    .foregroundColor(.secondary)

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
            Section("Paste at cursor") {
                HStack {
                    Circle()
                        .fill(appState.accessibilityGranted ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    Text(appState.accessibilityGranted
                         ? "Accessibility is on for this build"
                         : "Accessibility needs a refresh for this build")
                        .font(.subheadline)
                }

                Text("macOS path: System Settings → Privacy & Security → Accessibility. Find Voice Dictation, turn it OFF, then ON again. That is what allows paste at the cursor.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Button("Open Accessibility Settings") {
                    PermissionHelper.openAccessibilitySettings()
                }
                .accessibilityLabel("Open Accessibility Settings")
            }

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

                Picker("Retention", selection: Binding(
                    get: { appState.historyRetentionDays },
                    set: { appState.saveHistoryRetentionDays($0) }
                )) {
                    Text("7 days").tag(7)
                    Text("30 days").tag(30)
                    Text("Forever").tag(0)
                }
                .accessibilityLabel("History retention")

                Text("History is encrypted on disk and excluded from Time Machine backups when possible.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            appState.refreshPermissionState()
        }
    }

    private var aboutSection: some View {
        Form {
            Section("Voice Dictation") {
                Text("Version 0.5.0")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("Speech recognition runs on your Mac. Press the global hotkey to start and stop dictation. Text is pasted at your cursor or copied to the clipboard.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("Auto-paste requires Accessibility permission. After rebuilding the app, uncheck and recheck Voice Dictation in System Settings → Privacy & Security → Accessibility.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("Undo last paste uses Cmd+Z in the target app.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("Optional LLM cleanup sends text (not audio) to Abacus AI.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack {
                    Button("Privacy") {
                        openPrivacyPolicy()
                    }
                    Button("View in app") {
                        showPrivacySheet = true
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Hotkey recording

    private func startHotkeyRecording() {
        appState.isRecordingHotkey = true
        appState.hotkeyRecordError = ""
        hotkeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let modifiers = carbonModifiers(from: event.modifierFlags)
            let keyCode = UInt32(event.keyCode)

            if keyCode == UInt32(kVK_Escape) {
                stopHotkeyRecording()
                return nil
            }

            guard modifiers != 0 || isFunctionKey(keyCode) else {
                return nil
            }

            _ = appState.applyRecordedHotkey(keyCode: keyCode, modifiers: modifiers)
            stopHotkeyRecording()
            return nil
        }
    }

    private func stopHotkeyRecording() {
        appState.isRecordingHotkey = false
        if let hotkeyMonitor {
            NSEvent.removeMonitor(hotkeyMonitor)
            self.hotkeyMonitor = nil
        }
    }

    private func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var modifiers: UInt32 = 0
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        return modifiers
    }

    private func isFunctionKey(_ keyCode: UInt32) -> Bool {
        keyCode >= UInt32(kVK_F1) && keyCode <= UInt32(kVK_F20)
    }

    private func openPrivacyPolicy() {
        if let bundled = Bundle.main.url(forResource: "PRIVACY", withExtension: "md") {
            NSWorkspace.shared.open(bundled)
            return
        }
        let devPath = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("PRIVACY.md")
        if FileManager.default.fileExists(atPath: devPath.path) {
            NSWorkspace.shared.open(devPath)
        } else {
            showPrivacySheet = true
        }
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
    let keyCode: UInt32
    let modifiers: UInt32

    var body: some View {
        HStack(spacing: 4) {
            ForEach(HotkeyDisplay.modifierLabels(modifiers), id: \.self) { label in
                KeycapView(label: label)
            }
            KeycapView(label: HotkeyDisplay.keyLabel(keyCode))
        }
        .accessibilityLabel(HotkeyDisplay.label(keyCode: keyCode, modifiers: modifiers))
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

// MARK: - Privacy policy sheet

struct PrivacyPolicySheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var policyText: String = "Loading..."

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Privacy Policy")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
            }
            ScrollView {
                Text(policyText)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
        .padding()
        .frame(width: 480, height: 420)
        .onAppear {
            if let bundled = Bundle.main.url(forResource: "PRIVACY", withExtension: "md"),
               let text = try? String(contentsOf: bundled, encoding: .utf8) {
                policyText = text
            } else {
                let devPath = URL(fileURLWithPath: #file)
                    .deletingLastPathComponent()
                    .deletingLastPathComponent()
                    .appendingPathComponent("PRIVACY.md")
                policyText = (try? String(contentsOf: devPath, encoding: .utf8)) ?? "Privacy policy unavailable."
            }
        }
    }
}
