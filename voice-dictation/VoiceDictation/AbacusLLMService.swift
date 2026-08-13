//
//  AbacusLLMService.swift
//  VoiceDictation
//
//  Sends transcribed text to Abacus AI for cleanup.
//

import Foundation
import os

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

// MARK: - Codable response types

private struct ChatCompletionResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String?
        }
        let message: Message?
    }
    let choices: [Choice]?
}

private struct APIErrorResponse: Decodable {
    struct ErrorDetail: Decodable {
        let message: String?
    }
    let error: ErrorDetail?
}

private struct ModelsListResponse: Decodable {
    struct Model: Decodable {
        let id: String?
    }
    let data: [Model]?
}

final class AbacusLLMService {
    private let logger = Logger(subsystem: "com.nagesh.voicedictation", category: "AbacusLLM")

    private let session: URLSession
    private let taskQueue = DispatchQueue(label: "com.nagesh.voicedictation.llm-task")
    private var currentDataTask: URLSessionDataTask?

    static let defaultModel = "meta-llama/Meta-Llama-3.1-8B-Instruct"
    static let requestTimeout: TimeInterval = 15

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = Self.requestTimeout
        config.timeoutIntervalForResource = 30
        config.waitsForConnectivity = true
        self.session = URLSession(configuration: config)
    }

    func enhanceText(
        text: String,
        apiKey: String,
        endpoint: String = "https://routellm.abacus.ai/v1/chat/completions",
        model: String = AbacusLLMService.defaultModel,
        styleHint: String? = nil,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        guard let url = URL(string: endpoint) else {
            completion(.failure(AbacusLLMError.invalidEndpointURL))
            return
        }

        var request = URLRequest(url: url, timeoutInterval: Self.requestTimeout)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var systemPrompt = """
        You are a speech-to-text cleanup assistant. The user dictated text using voice recognition. \
        Your job: remove filler words (um, uh, like, you know), fix grammar, fix punctuation, \
        and make the text clean and readable. Preserve the original meaning. \
        Return ONLY the cleaned text, nothing else. No explanations, no quotes.
        """
        if let styleHint, !styleHint.isEmpty {
            systemPrompt += " \(styleHint)"
        }

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

        performRequest(request: request, isRetry: false, completion: completion)
    }

    func cancel() {
        taskQueue.sync {
            currentDataTask?.cancel()
            currentDataTask = nil
        }
    }

    func testAPIKey(
        apiKey: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard let url = URL(string: "https://routellm.abacus.ai/v1/models") else {
            completion(.failure(AbacusLLMError.invalidEndpointURL))
            return
        }

        var request = URLRequest(url: url, timeoutInterval: Self.requestTimeout)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let task = session.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            guard let data = data else {
                completion(.failure(AbacusLLMError.noResponseData))
                return
            }

            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode >= 400 {
                if let errorResponse = try? JSONDecoder().decode(APIErrorResponse.self, from: data),
                   let message = errorResponse.error?.message {
                    completion(.failure(AbacusLLMError.apiError(message)))
                } else {
                    completion(.failure(AbacusLLMError.apiError("HTTP \(httpResponse.statusCode)")))
                }
                return
            }

            if let modelsResponse = try? JSONDecoder().decode(ModelsListResponse.self, from: data),
               modelsResponse.data != nil {
                completion(.success(()))
            } else {
                completion(.failure(AbacusLLMError.unexpectedResponse("Could not parse models response")))
            }
        }
        task.resume()
    }

    // MARK: - Private

    private func performRequest(
        request: URLRequest,
        isRetry: Bool,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        let task = session.dataTask(with: request) { [weak self] data, response, error in
            if let error = error as? URLError, error.code == .cancelled {
                completion(.failure(AbacusLLMError.requestCancelled))
                return
            }

            if let error = error {
                self?.logger.warning("LLM request failed: \(error.localizedDescription)")
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

            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode >= 400 {
                if let errorResponse = try? JSONDecoder().decode(APIErrorResponse.self, from: data),
                   let message = errorResponse.error?.message {
                    completion(.failure(AbacusLLMError.apiError(message)))
                } else {
                    let responseText = String(data: data, encoding: .utf8) ?? ""
                    completion(.failure(AbacusLLMError.apiError("HTTP \(httpResponse.statusCode): \(responseText.prefix(200))")))
                }
                return
            }

            do {
                let decoded = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
                if let content = decoded.choices?.first?.message?.content {
                    let cleaned = content.trimmingCharacters(in: .whitespacesAndNewlines)
                    completion(.success(cleaned))
                } else if let errorResponse = try? JSONDecoder().decode(APIErrorResponse.self, from: data),
                          let message = errorResponse.error?.message {
                    completion(.failure(AbacusLLMError.apiError(message)))
                } else {
                    let responseText = String(data: data, encoding: .utf8) ?? ""
                    completion(.failure(AbacusLLMError.unexpectedResponse(String(responseText.prefix(200)))))
                }
            } catch {
                completion(.failure(error))
            }
        }

        taskQueue.sync {
            currentDataTask?.cancel()
            currentDataTask = task
        }
        task.resume()
    }

    private func isTransientError(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        return urlError.code == .timedOut ||
               urlError.code == .networkConnectionLost ||
               urlError.code == .notConnectedToInternet ||
               urlError.code == .dnsLookupFailed
    }
}
