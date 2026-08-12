//
//  WhisperService.swift
//  VoiceDictation
//
//  Sends audio file to OpenAI Whisper API for transcription.
//  Uses the whisper-1 model for best-in-class speech-to-text.
//

import Foundation

final class WhisperService {
    private let endpoint = URL(string: "https://routellm.abacus.ai/v1/audio/transcriptions")!

    func transcribe(
        audioURL: URL,
        apiKey: String,
        language: String? = nil,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()

        // Model field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append("whisper-1\r\n".data(using: .utf8)!)

        // Response format
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"response_format\"\r\n\r\n".data(using: .utf8)!)
        body.append("text\r\n".data(using: .utf8)!)

        // Language (optional)
        if let lang = language {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"language\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(lang)\r\n".data(using: .utf8)!)
        }

        // Audio file
        let audioData: Data
        do {
            audioData = try Data(contentsOf: audioURL)
        } catch {
            completion(.failure(error))
            return
        }

        let filename = audioURL.lastPathComponent
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)

        // Close boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            guard let data = data, let text = String(data: data, encoding: .utf8) else {
                completion(.failure(NSError(domain: "WhisperService", code: -1, userInfo: [NSLocalizedDescriptionKey: "No response data"])))
                return
            }

            // Check for API error (JSON with "error" key)
            if text.contains("\"error\"") {
                completion(.failure(NSError(domain: "WhisperService", code: -2, userInfo: [NSLocalizedDescriptionKey: "API error: \(text)"])))
                return
            }

            // Clean up temp file
            try? FileManager.default.removeItem(at: audioURL)

            let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
            completion(.success(cleaned))
        }.resume()
    }
}