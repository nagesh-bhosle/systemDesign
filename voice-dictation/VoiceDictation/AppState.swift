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
    @Published var history: [TranscriptEntry] = TranscriptHistory.shared.loadHistory()

    static var shared: AppState?

    static func createPrimary() -> AppState {
        let state = AppState()
        AppState.shared = state
        return state
    }

    var statusIcon: String {
        switch status {
        case .idle: return "mic.fill"
        case .recording: return "mic.circle.fill"
        case .transcribing: return "waveform.circle.fill"
        case .enhancing: return "sparkles"
        case .error: return "exclamationmark.triangle.fill"
        }
    }

    init(speechRecognizer: SpeechRecognizerService = SpeechRecognizerService(),
         llmService: AbacusLLMService = AbacusLLMService()) {
        self.speechRecognizer = speechRecognizer
        self.llmService = llmService
        syncTextInserterPreferences()
        speechRecognizer.updateConfiguration(
            localeIdentifier: speechLocale,
            requiresOnDevice: onDeviceRecognition
        )
        refreshPermissionState()
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

    // MARK: - Recording

    func toggleRecording() {
        switch status {
        case .idle, .error:
            startRecording()
        case .recording:
            stopRecording()
        case .transcribing:
            speechRecognizer.cancel()
            status = .idle
            clearMessages()
            liveTranscript = ""
        case .enhancing:
            llmService.cancel()
            llmTimedOut = true
            status = .idle
            clearMessages()
        }
    }

    private let speechRecognizer: SpeechRecognizerService
    private let llmService: AbacusLLMService
    private var rawTranscript: String = ""
    private var llmTimedOut: Bool = false
    private var transcriptionProcessed: Bool = false
    private var isStartingRecording: Bool = false
    private var errorClearTask: Task<Void, Never>?
    private var llmTimeoutTask: Task<Void, Never>?

    func toggleFloatingWindow() {
        if FloatingWindowController.shared.isVisible {
            FloatingWindowController.shared.hideWindow()
            saveShowFloatingWindow(false)
        } else {
            FloatingWindowController.shared.showWindow(appState: self)
            saveShowFloatingWindow(true)
        }
    }

    private func startRecording() {
        guard !isStartingRecording else { return }

        // Only block when the user already denied; .notDetermined still goes through
        // requestAuthorization so macOS can show the system prompt.
        if PermissionHelper.isMicrophoneDenied || PermissionHelper.isSpeechDenied {
            presentOnboarding()
            return
        }

        isStartingRecording = true
        clearMessages()
        liveTranscript = ""
        rawTranscript = ""
        transcriptionProcessed = false

        // Remember the focused app before our floating bar can take clicks.
        TextInserter.shared.captureInsertionTarget()

        if showFloatingWindow {
            FloatingWindowController.shared.showWindow(appState: self)
        }

        status = .recording

        speechRecognizer.requestAuthorization { [weak self] result in
            guard let self = self else { return }
            Task { @MainActor in
                self.isStartingRecording = false

                guard result.isGranted else {
                    self.status = .idle
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
                                return
                            }
                            self.status = .error
                            self.setError("Recognition failed: \(error.localizedDescription)")
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
            return
        }

        status = .transcribing
        liveTranscript = ""
        speechRecognizer.stopRecognition()

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            if self.status == .transcribing && !self.transcriptionProcessed {
                self.logger.warning("Transcription timed out — resetting to idle")
                self.transcriptionProcessed = true
                self.speechRecognizer.cancel()
                self.status = .idle
                self.setStatusMessage("No speech detected")
                self.liveTranscript = ""
            }
        }
    }

    private func processTranscript(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            status = .idle
            setStatusMessage("No speech detected")
            liveTranscript = ""
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

        llmTimeoutTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(AbacusLLMService.requestTimeout * 1_000_000_000))
            guard !Task.isCancelled else { return }
            guard self.status == .enhancing, !self.llmTimedOut else { return }
            self.logger.warning("LLM enhancement timed out — using raw transcript")
            self.llmTimedOut = true
            self.llmService.cancel()
            self.finishWithText(trimmed, errorNote: "LLM cleanup timed out (used raw text)")
        }

        llmService.enhanceText(text: trimmed, apiKey: apiKey, endpoint: llmEndpoint, model: llmModel) { result in
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

    private func finishWithText(_ text: String, errorNote: String? = nil) {
        lastTranscript = text
        errorMessage = ""
        statusMessage = ""

        TextInserter.shared.insertOrCopy(text) { [weak self] _ in
            Task { @MainActor in
                self?.saveToHistory(text: text)
            }
        }
        status = .idle
        hideFloatingWindow()

        if let errorNote = errorNote {
            setError(errorNote)
        }
    }

    private func hideFloatingWindow() {
        if showFloatingWindow {
            // Keep visible if user wants floating bar — only hide during processing end if they closed it
        }
        // Don't auto-hide — user controls via preference
    }

    private func saveToHistory(text: String) {
        guard saveHistoryEnabled else { return }
        if let first = history.first, first.text == text { return }
        let entry = TranscriptEntry(text: text, timestamp: Date())
        history.insert(entry, at: 0)
        if history.count > 100 {
            history.removeLast()
        }
        TranscriptHistory.shared.saveHistory(history)
    }

    func deleteHistoryEntry(_ entry: TranscriptEntry) {
        history.removeAll { $0.id == entry.id }
        TranscriptHistory.shared.saveHistory(history)
    }

    func clearAllHistory() {
        TranscriptHistory.shared.clearHistory()
        history = []
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
