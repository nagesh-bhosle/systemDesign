//
//  AppState.swift
//  VoiceDictation
//
//  Central observable state for the app.
//

import Foundation
import SwiftUI
import Speech
import os

enum DictationStatus: String {
    case idle = "Idle"
    case recording = "Listening"
    case transcribing = "Transcribing"
    case enhancing = "Enhancing"
    case error = "Error"
}

enum UserDefaultsKey {
    static let enhanceEnabled = "enhanceEnabled"
    static let showFloatingWindow = "showFloatingWindow"
    static let onDeviceRecognition = "onDeviceRecognition"
    static let saveHistory = "saveHistory"
    static let speechLocale = "speechLocale"
    static let clipboardOnlyMode = "clipboardOnlyMode"
    static let restoreClipboard = "restoreClipboard"
    static let hasCompletedOnboarding = "hasCompletedOnboarding"
    static let launchAtLogin = "launchAtLogin"
    static let playSounds = "playSounds"
    static let historyRetentionDays = "historyRetentionDays"
    static let customVocabulary = "customVocabulary"
    static let preferredAudioInputUID = "preferredAudioInputUID"
}

@MainActor
final class AppState: ObservableObject {
    private let logger = Logger(subsystem: "com.nagesh.voicedictation", category: "AppState")

    @Published var status: DictationStatus = .idle
    @Published var lastTranscript: String = ""
    @Published var liveTranscript: String = ""
    @Published var errorMessage: String = ""
    @Published var statusMessage: String = ""
    @Published var apiKey: String = KeychainHelper.shared.loadAPIKey() ?? ""
    @Published var enhanceEnabled: Bool = UserDefaults.standard.object(forKey: UserDefaultsKey.enhanceEnabled) as? Bool ?? false
    @Published var showFloatingWindow: Bool = UserDefaults.standard.object(forKey: UserDefaultsKey.showFloatingWindow) as? Bool ?? true
    @Published var onDeviceRecognition: Bool = UserDefaults.standard.object(forKey: UserDefaultsKey.onDeviceRecognition) as? Bool ?? true
    @Published var saveHistoryEnabled: Bool = UserDefaults.standard.object(forKey: UserDefaultsKey.saveHistory) as? Bool ?? true
    @Published var speechLocale: String = UserDefaults.standard.string(forKey: UserDefaultsKey.speechLocale) ?? "en-US"
    @Published var clipboardOnlyMode: Bool = UserDefaults.standard.bool(forKey: UserDefaultsKey.clipboardOnlyMode)
    @Published var restoreClipboard: Bool = UserDefaults.standard.object(forKey: UserDefaultsKey.restoreClipboard) as? Bool ?? true
    @Published var launchAtLogin: Bool = LaunchAtLoginHelper.isEnabled
    @Published var launchAtLoginError: String = ""
    @Published var showOnboarding: Bool = false
    @Published var microphoneGranted: Bool = false
    @Published var speechGranted: Bool = false
    @Published var accessibilityGranted: Bool = false
    @Published var llmModel: String = UserDefaults.standard.string(forKey: "llmModel") ?? AbacusLLMService.defaultModel
    @Published var llmEndpoint: String = UserDefaults.standard.string(forKey: "llmEndpoint") ?? "https://routellm.abacus.ai/v1/chat/completions"
    @Published var playSounds: Bool = UserDefaults.standard.object(forKey: UserDefaultsKey.playSounds) as? Bool ?? true
    @Published var pushToTalkEnabled: Bool = HotkeyPreferences.loadPushToTalk()
    @Published var hotkeyKeyCode: UInt32 = HotkeyPreferences.loadKeyCode()
    @Published var hotkeyModifiers: UInt32 = HotkeyPreferences.loadModifiers()
    @Published var hotkeyRecordError: String = ""
    @Published var isRecordingHotkey: Bool = false
    @Published var historyRetentionDays: Int = UserDefaults.standard.object(forKey: UserDefaultsKey.historyRetentionDays) as? Int ?? 30
    @Published var customVocabulary: String = UserDefaults.standard.string(forKey: UserDefaultsKey.customVocabulary) ?? ""
    @Published var recordingDuration: String = "0:00"
    @Published var audioLevel: Double = 0
    @Published var history: [TranscriptEntry] = []
    @Published var audioInputs: [AudioInputDevice] = []
    @Published var selectedInputUID: String = UserDefaults.standard.string(forKey: UserDefaultsKey.preferredAudioInputUID) ?? ""
    @Published var isMicTestRunning: Bool = false
    @Published var micTestLevel: Double = 0

    static var shared: AppState?

    static func createPrimary() -> AppState {
        let state = AppState()
        AppState.shared = state
        return state
    }

    var statusIcon: String {
        switch status {
        case .idle: return "waveform"
        case .recording: return "waveform.circle.fill"
        case .transcribing: return "waveform.circle.fill"
        case .enhancing: return "sparkles"
        case .error: return "exclamationmark.triangle.fill"
        }
    }

    init(speechRecognizer: SpeechRecognizerService = SpeechRecognizerService(),
         llmService: AbacusLLMService = AbacusLLMService()) {
        self.speechRecognizer = speechRecognizer
        self.llmService = llmService
        history = TranscriptHistory.shared.loadHistory(retentionDays: historyRetentionDays)
        syncTextInserterPreferences()
        speechRecognizer.updateConfiguration(
            localeIdentifier: speechLocale,
            requiresOnDevice: onDeviceRecognition
        )
        refreshPermissionState()
        refreshAudioInputs()
        speechRecognizer.preferredInputUID = selectedInputUID
    }

    // MARK: - Preferences

    func saveEnhanceEnabled(_ enabled: Bool) {
        enhanceEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: UserDefaultsKey.enhanceEnabled)
    }

    func saveShowFloatingWindow(_ show: Bool) {
        showFloatingWindow = show
        UserDefaults.standard.set(show, forKey: UserDefaultsKey.showFloatingWindow)
        if show {
            FloatingWindowController.shared.showWindow(appState: self)
        } else {
            FloatingWindowController.shared.hideWindow()
        }
    }

    func saveOnDeviceRecognition(_ enabled: Bool) {
        onDeviceRecognition = enabled
        UserDefaults.standard.set(enabled, forKey: UserDefaultsKey.onDeviceRecognition)
        speechRecognizer.updateConfiguration(localeIdentifier: speechLocale, requiresOnDevice: enabled)
    }

    func saveHistoryPreference(_ enabled: Bool) {
        saveHistoryEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: UserDefaultsKey.saveHistory)
    }

    func saveSpeechLocale(_ locale: String) {
        speechLocale = locale
        UserDefaults.standard.set(locale, forKey: UserDefaultsKey.speechLocale)
        speechRecognizer.updateConfiguration(localeIdentifier: locale, requiresOnDevice: onDeviceRecognition)
    }

    func saveClipboardOnlyMode(_ enabled: Bool) {
        clipboardOnlyMode = enabled
        UserDefaults.standard.set(enabled, forKey: UserDefaultsKey.clipboardOnlyMode)
        syncTextInserterPreferences()
    }

    func saveRestoreClipboard(_ enabled: Bool) {
        restoreClipboard = enabled
        UserDefaults.standard.set(enabled, forKey: UserDefaultsKey.restoreClipboard)
        syncTextInserterPreferences()
    }

    func saveLaunchAtLogin(_ enabled: Bool) {
        launchAtLoginError = ""
        let result = LaunchAtLoginHelper.setEnabled(enabled)
        switch result {
        case .success:
            launchAtLogin = enabled
            UserDefaults.standard.set(enabled, forKey: UserDefaultsKey.launchAtLogin)
        case .failure(let error):
            launchAtLoginError = error.localizedDescription
            launchAtLogin = LaunchAtLoginHelper.isEnabled
            UserDefaults.standard.set(launchAtLogin, forKey: UserDefaultsKey.launchAtLogin)
        }
    }

    func saveLLMModel(_ model: String) {
        llmModel = model
        UserDefaults.standard.set(model, forKey: "llmModel")
    }

    func saveLLMEndpoint(_ endpoint: String) {
        llmEndpoint = endpoint
        UserDefaults.standard.set(endpoint, forKey: "llmEndpoint")
    }

    func savePlaySounds(_ enabled: Bool) {
        playSounds = enabled
        UserDefaults.standard.set(enabled, forKey: UserDefaultsKey.playSounds)
    }

    func savePushToTalk(_ enabled: Bool) {
        pushToTalkEnabled = enabled
        HotkeyPreferences.savePushToTalk(enabled)
        HotkeyManager.shared.updateConfiguration(
            keyCode: hotkeyKeyCode,
            modifiers: hotkeyModifiers,
            pushToTalk: enabled
        )
    }

    func saveHistoryRetentionDays(_ days: Int) {
        historyRetentionDays = days
        UserDefaults.standard.set(days, forKey: UserDefaultsKey.historyRetentionDays)
        history = TranscriptHistory.shared.sortEntries(
            TranscriptHistory.shared.applyRetention(history, retentionDays: days)
        )
        TranscriptHistory.shared.saveHistory(history, retentionDays: days)
    }

    func saveCustomVocabulary(_ text: String) {
        customVocabulary = text
        UserDefaults.standard.set(text, forKey: UserDefaultsKey.customVocabulary)
    }

    func applyRecordedHotkey(keyCode: UInt32, modifiers: UInt32) -> Bool {
        hotkeyRecordError = ""

        guard HotkeyManager.canRegister(keyCode: keyCode, modifiers: modifiers) else {
            hotkeyRecordError = "That shortcut is already in use. Keeping your current shortcut."
            return false
        }

        HotkeyPreferences.save(keyCode: keyCode, modifiers: modifiers)
        hotkeyKeyCode = keyCode
        hotkeyModifiers = modifiers

        HotkeyManager.shared.updateConfiguration(
            keyCode: keyCode,
            modifiers: modifiers,
            pushToTalk: pushToTalkEnabled
        )

        if !HotkeyManager.shared.reregister() {
            hotkeyRecordError = "Could not register the new shortcut. Keeping your previous shortcut."
            hotkeyKeyCode = HotkeyPreferences.loadKeyCode()
            hotkeyModifiers = HotkeyPreferences.loadModifiers()
            HotkeyManager.shared.reregister()
            return false
        }

        return true
    }

    func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: UserDefaultsKey.hasCompletedOnboarding)
        showOnboarding = false
        OnboardingWindowController.shared.hide()
    }

    func presentOnboarding() {
        showOnboarding = true
        OnboardingWindowController.shared.show(appState: self)
    }

    func evaluateOnboardingOnLaunch() {
        PermissionHelper.probePermissions { [weak self] in
            guard let self else { return }
            self.refreshPermissionState()

            if self.microphoneGranted && self.speechGranted {
                if !UserDefaults.standard.bool(forKey: UserDefaultsKey.hasCompletedOnboarding) {
                    self.completeOnboarding()
                }
                return
            }

            self.presentOnboarding()
        }
    }

    func refreshPermissionState() {
        microphoneGranted = PermissionHelper.microphoneStatus()
        speechGranted = PermissionHelper.speechStatus()
        accessibilityGranted = PermissionHelper.accessibilityStatus()
    }

    // MARK: - Hotkey handlers

    func handleHotkeyDown() {
        guard pushToTalkEnabled else { return }
        switch status {
        case .idle, .error:
            startRecording()
        default:
            break
        }
    }

    func handleHotkeyUp() {
        guard pushToTalkEnabled else { return }
        if status == .recording {
            stopRecording()
        }
    }

    // MARK: - Recording

    func toggleRecording() {
        switch status {
        case .idle, .error:
            startRecording()
        case .recording:
            stopRecording()
        case .transcribing:
            recoverToIdle(message: nil)
        case .enhancing:
            llmService.cancel()
            llmTimedOut = true
            recoverToIdle(message: nil)
        }
    }

    func refreshAudioInputs() {
        audioInputs = AudioInputManager.inputDevices()
        if selectedInputUID.isEmpty || !audioInputs.contains(where: { $0.uid == selectedInputUID }) {
            selectedInputUID = AudioInputManager.defaultInputDevice()?.uid ?? audioInputs.first?.uid ?? ""
        }
        speechRecognizer.preferredInputUID = selectedInputUID
    }

    func saveSelectedInput(_ uid: String) {
        selectedInputUID = uid
        UserDefaults.standard.set(uid, forKey: UserDefaultsKey.preferredAudioInputUID)
        speechRecognizer.preferredInputUID = uid
        if isMicTestRunning {
            startMicTest()
        }
    }

    func startMicTest() {
        guard status != .recording, status != .transcribing else { return }
        stopMicTest()
        refreshAudioInputs()
        micTester.onLevel = { [weak self] level in
            Task { @MainActor in
                self?.micTestLevel = Double(level)
            }
        }
        do {
            try micTester.start(deviceUID: selectedInputUID.isEmpty ? nil : selectedInputUID)
            isMicTestRunning = true
        } catch {
            isMicTestRunning = false
            setError("Could not start microphone test: \(error.localizedDescription)")
        }
    }

    func stopMicTest() {
        micTester.stop()
        isMicTestRunning = false
        micTestLevel = 0
    }

    private let speechRecognizer: SpeechRecognizerService
    private let llmService: AbacusLLMService
    private let micTester = MicrophoneTester()
    private var rawTranscript: String = ""
    private var llmTimedOut: Bool = false
    private var transcriptionProcessed: Bool = false
    private var isStartingRecording: Bool = false
    private var errorClearTask: Task<Void, Never>?
    private var llmTimeoutTask: Task<Void, Never>?
    private var recordingTimerTask: Task<Void, Never>?
    private var recordingStartedAt: Date?

    func toggleFloatingWindow() {
        if FloatingWindowController.shared.isVisible {
            FloatingWindowController.shared.hideWindow()
            saveShowFloatingWindow(false)
        } else {
            FloatingWindowController.shared.showWindow(appState: self)
            saveShowFloatingWindow(true)
        }
    }

    func undoLastPaste() {
        switch TextInserter.shared.undoLastPaste() {
        case .undone:
            setStatusMessage("Undid last paste")
        case .nothingToUndo:
            setStatusMessage("Nothing to undo")
        case .failed:
            setError("Could not undo in the target app")
        }
    }

    func pasteHistoryEntry(_ entry: TranscriptEntry) {
        TextInserter.shared.pasteHistoryEntry(entry.text) { [weak self] result in
            Task { @MainActor in
                if result == .needsAccessibilityRefresh {
                    self?.setError("Auto-paste needs a refresh: System Settings → Privacy & Security → Accessibility → uncheck Voice Dictation, then check it again.")
                }
            }
        }
    }

    func togglePinHistoryEntry(_ entry: TranscriptEntry) {
        guard let index = history.firstIndex(where: { $0.id == entry.id }) else { return }
        history[index].isPinned.toggle()
        history = TranscriptHistory.shared.sortEntries(history)
        TranscriptHistory.shared.saveHistory(history, retentionDays: historyRetentionDays)
    }

    private func startRecording() {
        guard !isStartingRecording else { return }

        if PermissionHelper.isMicrophoneDenied || PermissionHelper.isSpeechDenied {
            presentOnboarding()
            return
        }

        stopMicTest()
        speechRecognizer.resetSession()
        isStartingRecording = true
        clearMessages()
        liveTranscript = ""
        rawTranscript = ""
        transcriptionProcessed = false
        audioLevel = 0

        TextInserter.shared.captureInsertionTarget()

        if showFloatingWindow {
            FloatingWindowController.shared.showWindow(appState: self)
        }

        status = .recording
        startRecordingTimer()

        if playSounds {
            SoundPlayer.shared.playRecordingStart()
        }

        speechRecognizer.onAudioLevel = { [weak self] level in
            Task { @MainActor in
                self?.audioLevel = Double(level)
            }
        }

        speechRecognizer.requestAuthorization { [weak self] result in
            guard let self = self else { return }
            Task { @MainActor in
                self.isStartingRecording = false

                guard result.isGranted else {
                    self.status = .idle
                    self.stopRecordingTimer()
                    self.presentOnboarding()
                    if let message = result.errorMessage {
                        self.setError(message)
                    }
                    return
                }

                guard self.status == .recording else { return }

                self.speechRecognizer.onPartialResult = { text in
                    Task { @MainActor in
                        self.liveTranscript = text
                    }
                }

                self.speechRecognizer.startRecognition { result in
                    Task { @MainActor in
                        guard !self.transcriptionProcessed else { return }
                        guard self.status == .transcribing || self.status == .recording else { return }

                        switch result {
                        case .success(let text):
                            self.transcriptionProcessed = true
                            self.rawTranscript = text
                            self.liveTranscript = ""
                            if let fallback = self.speechRecognizer.onDeviceFallbackMessage {
                                self.statusMessage = fallback
                                self.scheduleStatusMessageAutoClear()
                            }
                            self.processTranscript(text)
                        case .failure(let error):
                            self.transcriptionProcessed = true
                            if self.status == .idle { return }
                            if let speechError = error as? SpeechRecognizerError,
                               case .cancelled = speechError {
                                self.speechRecognizer.resetSession()
                                return
                            }
                            self.speechRecognizer.resetSession()
                            self.status = .idle
                            self.stopRecordingTimer()
                            self.liveTranscript = ""
                            self.audioLevel = 0
                            self.setStatusMessage("No speech detected — try again")
                            self.logger.warning("Recognition ended: \(error.localizedDescription, privacy: .public)")
                        }
                    }
                }
            }
        }
    }

    private func stopRecording() {
        if isStartingRecording {
            isStartingRecording = false
            status = .idle
            liveTranscript = ""
            stopRecordingTimer()
            return
        }

        if playSounds {
            SoundPlayer.shared.playRecordingStop()
        }

        stopRecordingTimer()
        audioLevel = 0
        status = .transcribing
        liveTranscript = ""
        speechRecognizer.stopRecognition()

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            if self.status == .transcribing && !self.transcriptionProcessed {
                self.logger.warning("Transcription timed out — resetting to idle")
                self.recoverToIdle(message: "No speech detected")
            }
        }
    }

    private func processTranscript(_ text: String) {
        let vocabularyApplied = applyCustomVocabulary(to: text)
        let trimmed = vocabularyApplied.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            recoverToIdle(message: "No speech detected")
            hideFloatingWindow()
            return
        }

        guard enhanceEnabled, !apiKey.isEmpty else {
            finishWithText(trimmed)
            return
        }

        status = .enhancing
        llmTimedOut = false
        llmTimeoutTask?.cancel()

        let styleHint = toneStyleHint(for: TextInserter.shared.targetBundleIdentifier)

        llmTimeoutTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(AbacusLLMService.requestTimeout * 1_000_000_000))
            guard !Task.isCancelled else { return }
            guard self.status == .enhancing, !self.llmTimedOut else { return }
            self.logger.warning("LLM enhancement timed out — using raw transcript")
            self.llmTimedOut = true
            self.llmService.cancel()
            self.finishWithText(trimmed, errorNote: "LLM cleanup timed out (used raw text)")
        }

        llmService.enhanceText(
            text: trimmed,
            apiKey: apiKey,
            endpoint: llmEndpoint,
            model: llmModel,
            styleHint: styleHint
        ) { result in
            Task { @MainActor in
                guard !self.llmTimedOut else { return }

                self.llmTimeoutTask?.cancel()

                switch result {
                case .success(let enhanced):
                    self.finishWithText(enhanced)
                case .failure(let error):
                    if case AbacusLLMError.requestCancelled = error {
                        return
                    }
                    self.logger.warning("LLM enhancement failed: \(error.localizedDescription)")
                    self.finishWithText(trimmed, errorNote: "LLM cleanup failed (using raw text): \(error.localizedDescription)")
                }
            }
        }
    }

    func toneStyleHint(for bundleId: String?) -> String? {
        guard let bundleId = bundleId?.lowercased() else { return nil }
        if bundleId == "com.apple.mail" {
            return "Use a professional, formal email tone."
        }
        if bundleId.contains("slack") || bundleId.contains("messages") {
            return "Use a casual, conversational chat tone."
        }
        return nil
    }

    func applyCustomVocabulary(to text: String) -> String {
        let items = customVocabulary
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted { $0.count > $1.count }

        guard !items.isEmpty else { return text }

        var result = text
        for item in items {
            let escaped = NSRegularExpression.escapedPattern(for: item)
            let spacedPattern = escaped.replacingOccurrences(of: "\\ ", with: "\\s+")
            let patterns = [
                "(?i)\\b\(escaped)\\b",
                "(?i)\(spacedPattern)"
            ]
            for pattern in patterns {
                guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
                let range = NSRange(result.startIndex..., in: result)
                result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: item)
            }
            let collapsed = item.replacingOccurrences(of: " ", with: "")
            if collapsed != item {
                let collapsedEscaped = NSRegularExpression.escapedPattern(for: collapsed)
                if let regex = try? NSRegularExpression(pattern: "(?i)\\b\(collapsedEscaped)\\b") {
                    let range = NSRange(result.startIndex..., in: result)
                    result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: item)
                }
            }
        }
        return result
    }

    private func finishWithText(_ text: String, errorNote: String? = nil) {
        lastTranscript = text
        errorMessage = ""
        statusMessage = ""

        TextInserter.shared.insertOrCopy(text) { [weak self] result in
            Task { @MainActor in
                self?.saveToHistory(text: text)
                if result == .needsAccessibilityRefresh {
                    self?.setError("Auto-paste needs a refresh: System Settings → Privacy & Security → Accessibility → uncheck Voice Dictation, then check it again. Text is on the clipboard.")
                }
            }
        }
        status = .idle
        hideFloatingWindow()

        if let errorNote = errorNote {
            setError(errorNote)
        }
    }

    private func recoverToIdle(message: String?) {
        transcriptionProcessed = true
        isStartingRecording = false
        speechRecognizer.resetSession()
        llmTimeoutTask?.cancel()
        stopRecordingTimer()
        status = .idle
        liveTranscript = ""
        audioLevel = 0
        clearMessages()
        if let message {
            setStatusMessage(message)
        }
    }

    private func hideFloatingWindow() {
        if showFloatingWindow {
            // Keep visible if user wants floating bar
        }
    }

    private func saveToHistory(text: String) {
        guard saveHistoryEnabled else { return }
        if FocusedFieldInspector.isFocusedFieldSecure() { return }
        if let first = history.first, first.text == text { return }
        let entry = TranscriptEntry(text: text, timestamp: Date())
        history.insert(entry, at: 0)
        history = TranscriptHistory.shared.sortEntries(history)
        if history.count > 100 {
            history = Array(history.prefix(100))
        }
        TranscriptHistory.shared.saveHistory(history, retentionDays: historyRetentionDays)
    }

    func deleteHistoryEntry(_ entry: TranscriptEntry) {
        history.removeAll { $0.id == entry.id }
        TranscriptHistory.shared.saveHistory(history, retentionDays: historyRetentionDays)
    }

    func clearAllHistory() {
        TranscriptHistory.shared.clearHistory()
        history = []
    }

    // MARK: - Recording timer

    private func startRecordingTimer() {
        recordingStartedAt = Date()
        recordingDuration = "0:00"
        recordingTimerTask?.cancel()
        recordingTimerTask = Task { @MainActor in
            while !Task.isCancelled, self.status == .recording {
                if let started = self.recordingStartedAt {
                    let elapsed = Int(Date().timeIntervalSince(started))
                    let minutes = elapsed / 60
                    let seconds = elapsed % 60
                    self.recordingDuration = String(format: "%d:%02d", minutes, seconds)
                }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    private func stopRecordingTimer() {
        recordingTimerTask?.cancel()
        recordingTimerTask = nil
        recordingStartedAt = nil
        recordingDuration = "0:00"
    }

    // MARK: - Messages

    private func clearMessages() {
        errorMessage = ""
        statusMessage = ""
        errorClearTask?.cancel()
    }

    private func setError(_ message: String) {
        errorMessage = message
        scheduleErrorAutoClear()
    }

    private func setStatusMessage(_ message: String) {
        statusMessage = message
        scheduleStatusMessageAutoClear()
    }

    private func scheduleErrorAutoClear() {
        errorClearTask?.cancel()
        errorClearTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            self.errorMessage = ""
        }
    }

    private func scheduleStatusMessageAutoClear() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            self.statusMessage = ""
        }
    }

    private func syncTextInserterPreferences() {
        TextInserter.shared.clipboardOnlyMode = clipboardOnlyMode
        TextInserter.shared.restoreClipboardEnabled = restoreClipboard
    }
}
