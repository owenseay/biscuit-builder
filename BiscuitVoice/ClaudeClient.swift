import Foundation

/// Sends a question to Claude and returns the text answer.
/// This is the same request your Shortcut's "Get Contents of URL" step sends.
nonisolated struct ClaudeClient {
    let apiKey: String
    let model = "claude-haiku-5-5"

    func ask(system: String, messages: [[String: String]]) async throws -> String {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        // Headers: the "envelope"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        // Body: the "letter"
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 150,
            "thinking": ["type": "disabled"],
            "system": system,
            "messages": messages
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await URLSession.shared.data(for: request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ClaudeError.message("Couldn't read the response.")
        }
        // Errors come back as {"type":"error","error":{"message":...}}
        if let error = json["error"] as? [String: Any], let message = error["message"] as? String {
            throw ClaudeError.message(message)
        }
        // Answers come back in "content": pick the item whose type is "text"
        if let content = json["content"] as? [[String: Any]],
           let text = content.first(where: { $0["type"] as? String == "text" })?["text"] as? String {
            return text
        }
        throw ClaudeError.message("No answer in the response.")
    }
}

nonisolated enum ClaudeError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let text): return text }
    }
}
