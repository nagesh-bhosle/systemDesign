//
//  AbacusLLMService.swift
//  VoiceDictation
//
//  Sends transcribed text to Abacus AI (routellm.abacus.ai) for cleanup.
//  Removes filler words, fixes grammar, and improves readability.
//  Uses the OpenAI-compatible /v1/chat/completions endpoint.
//

import Foundation
import os

// Issue #37: Proper error types
enum AbacusLLMError: LocalizedError {
    case invalidEndpointURL
    case noResponseData
    case apiError(String)
    case unexpectedResponse(String)
    case requestCancelled

    var errorDescription: String? {
        switch self {
        case .invalidEndpointURL:
            return "Invalid endpoint URL."
        case .noResponseData:
            return "No response data from server."
        case .apiError(let message):
            return "API error: \(message)"
        case .unexpectedResponse(let text):
            return "Unexpected response: \(text)"
        case .requestCancelled:
            return "Request was cancelled."
        }
    }
}

final class AbacusLLMService {
    private let logger = Logger(subsystem: "com.nagesh.voicedictation", category: "AbacusLLM")

    // Issue #51: Dedicated URLSession with configurable timeout
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        config.waitsForConnectivity = true
        self.session = URLSession(configuration: config)
    }

    // Issue #5: Store the data task so it can be cancelled
    private var currentDataTask: URLSessionDataTask?

    // Issue #23: Model list is defined in SettingsView.swift as AVAILABLE_MODELS.
    func enhanceText(
        text: String,
        apiKey: String,
        endpoint: String = "https://routellm.abacus.ai/v1/chat/completions",
        model: String = "gemini-3.5-flash-lite",
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        // Issue #26: No force-unwraps
        guard let url = URL(string: endpoint) else {
            completion(.failure(AbacusLLMError.invalidEndpointURL))
            return
        }

        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let systemPrompt = """
        You are a speech-to-text cleanup assistant. The user dictated text using voice recognition. \
        Your job: remove filler words (um, uh, like, you know), fix grammar, fix punctuation, \
        and make the text clean and readable. Preserve the original meaning. \
        Return ONLY the cleaned text, nothing else. No explanations, no quotes.
        """

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": text]
            ],
            "temperature": 0.3,
            "max_tokens": 4096
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            completion(.failure(error))
            return
        }

        // Issue #50: Retry logic with single retry on transient failure
        performRequest(request: request, isRetry: false, completion: completion)
    }

    /// Issue #5: Cancel any in-flight request
    func cancel() {
        currentDataTask?.cancel()
        currentDataTask = nil
    }

    // MARK: - Private

    private func performRequest(
        request: URLRequest,
        isRetry: Bool,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        let task = session.dataTask(with: request) { [weak self] data, response, error in
            // Issue #5: Check if request was cancelled
            if let error = error as? URLError, error.code == .cancelled {
                completion(.failure(AbacusLLMError.requestCancelled))
                return
            }

            if let error = error {
                self?.logger.warning("LLM request failed: \(error.localizedDescription)")
                // Issue #50: Retry once on transient network errors
                if !isRetry, self?.isTransientError(error) == true {
                    self?.logger.info("Retrying LLM request after transient error...")
                    DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) {
                        self?.performRequest(request: request, isRetry: true, completion: completion)
                    }
                    return
                }
                completion(.failure(error))
                return
            }

            guard let data = data else {
                completion(.failure(AbacusLLMError.noResponseData))
                return
            }

            // Check for HTTP error status
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode >= 400 {
                let responseText = String(data: data, encoding: .utf8) ?? ""
                if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let error = errorJson["error"] as? [String: Any],
                   let message = error["message"] as? String {
                    completion(.failure(AbacusLLMError.apiError(message)))
                } else {
                    completion(.failure(AbacusLLMError.apiError("HTTP \(httpResponse.statusCode): \(responseText.prefix(200))")))
                }
                return
            }

            // Parse success response
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let choices = json["choices"] as? [[String: Any]],
                   let firstChoice = choices.first,
                   let message = firstChoice["message"] as? [String: Any],
                   let content = message["content"] as? String {
                    let cleaned = content.trimmingCharacters(in: .whitespacesAndNewlines)
                    completion(.success(cleaned))
                } else {
                    let responseText = String(data: data, encoding: .utf8) ?? ""
                    if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let error = errorJson["error"] as? [String: Any],
                       let message = error["message"] as? String {
                        completion(.failure(AbacusLLMError.apiError(message)))
                    } else {
                        completion(.failure(AbacusLLMError.unexpectedResponse(String(responseText.prefix(200)))))
                    }
                }
            } catch {
                completion(.failure(error))
            }
        }
        currentDataTask = task
        task.resume()
    }

    private func isTransientError(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        return urlError.code == .timedOut ||
               urlError.code == .networkConnectionLost ||
               urlError.code == .notConnectedToInternet ||
               urlError.code == .dnsLookupFailed
    }

    /// Test if the API key is valid by listing models
    func testAPIKey(
        apiKey: String,
        completion: @escaping (Result<[String], Error>) -> Void
    ) {
        // Issue #26: No force-unwraps
        guard let url = URL(string: "https://routellm.abacus.ai/v1/models") else {
            completion(.failure(AbacusLLMError.invalidEndpointURL))
            return
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        session.dataTask(with: request) { data, _, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            guard let data = data else {
                completion(.failure(AbacusLLMError.noResponseData))
                return
            }

            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let models = json["data"] as? [[String: Any]] {
                    let modelIds = models.compactMap { $0["id"] as? String }
                    completion(.success(modelIds))
                } else {
                    completion(.failure(AbacusLLMError.unexpectedResponse("Could not parse models")))
                }
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }
}