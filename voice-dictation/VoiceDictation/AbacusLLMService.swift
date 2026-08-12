//
//  AbacusLLMService.swift
//  VoiceDictation
//
//  Sends transcribed text to Abacus AI (routellm.abacus.ai) for cleanup.
//  Removes filler words, fixes grammar, and improves readability.
//  Uses the OpenAI-compatible /v1/chat/completions endpoint.
//

import Foundation

final class AbacusLLMService {
    private let endpoint = URL(string: "https://routellm.abacus.ai/v1/chat/completions")!

    // ── Available models (fastest & cheapest, from routellm.abacus.ai/v1/models) ──
    // Current default:
    //   "gemini-3.5-flash-lite"                  — $0.0000025/out-token,  fastest Gemini
    //
    // Other fast/cheap options to try:
    //   "meta-llama/Meta-Llama-3.1-8B-Instruct"  — $0.00000005/out-token, very fast + cheapest
    //   "deepseek-ai/DeepSeek-V4-Flash-0731"     — $0.00000028/out-token, fast
    //   "gpt-4.1-nano"                           — $0.0000004/out-token,  fast
    //   "gpt-5-nano"                             — $0.0000004/out-token,  fast
    //   "gpt-5.4-nano"                           — $0.00000125/out-token, fast
    //   "gemini-3.1-flash-lite"                  — $0.0000015/out-token,  very fast
    //   "gpt-4o-mini"                            — $0.0000006/out-token,  (previous default)
    //   "route-llm"                               — auto-routes to best model
    func enhanceText(
        text: String,
        apiKey: String,
        model: String = "gemini-3.5-flash-lite",
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        var request = URLRequest(url: endpoint, timeoutInterval: 15)
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
            "max_tokens": 2048
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            completion(.failure(error))
            return
        }

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            guard let data = data else {
                completion(.failure(NSError(domain: "AbacusLLM", code: -1, userInfo: [NSLocalizedDescriptionKey: "No response data"])))
                return
            }

            // Parse JSON response
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let choices = json["choices"] as? [[String: Any]],
                   let firstChoice = choices.first,
                   let message = firstChoice["message"] as? [String: Any],
                   let content = message["content"] as? String {
                    let cleaned = content.trimmingCharacters(in: .whitespacesAndNewlines)
                    completion(.success(cleaned))
                } else {
                    // Check for error response
                    let responseText = String(data: data, encoding: .utf8) ?? ""
                    if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let error = errorJson["error"] as? [String: Any],
                       let message = error["message"] as? String {
                        completion(.failure(NSError(domain: "AbacusLLM", code: -2, userInfo: [NSLocalizedDescriptionKey: "API error: \(message)"])))
                    } else {
                        completion(.failure(NSError(domain: "AbacusLLM", code: -3, userInfo: [NSLocalizedDescriptionKey: "Unexpected response: \(responseText.prefix(200))"])))
                    }
                }
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    /// Test if the API key is valid by listing models
    func testAPIKey(
        apiKey: String,
        completion: @escaping (Result<[String], Error>) -> Void
    ) {
        let url = URL(string: "https://routellm.abacus.ai/v1/models")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            guard let data = data else {
                completion(.failure(NSError(domain: "AbacusLLM", code: -1, userInfo: [NSLocalizedDescriptionKey: "No response"])))
                return
            }

            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let models = json["data"] as? [[String: Any]] {
                    let modelIds = models.compactMap { $0["id"] as? String }
                    completion(.success(modelIds))
                } else {
                    completion(.failure(NSError(domain: "AbacusLLM", code: -2, userInfo: [NSLocalizedDescriptionKey: "Could not parse models"])))
                }
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }
}