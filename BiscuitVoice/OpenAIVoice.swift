import Foundation
import CryptoKit

/// Turns Claude's answer text into a natural-sounding voice clip using OpenAI.
/// Claude still writes every answer; OpenAI only reads it out loud.
///
/// Audio streams in and starts playing right away. Clips are saved on the phone, so an answer heard before ("Fries, button one.")
/// plays instantly and costs nothing the next time.
///
/// Note: OpenAI shuts down this model (gpt-4o-mini-tts) on Jan 6, 2027.
/// Only this file needs to change when we move to something else.
nonisolated enum OpenAIVoice {
    /// Master switch. Off since Oct 26: the extra network step made answers noticeably laggier
    /// and less consistent than the Apple voice. With this off, the app behaves exactly like
    /// before the OpenAI voice was added, whatever is saved in the voice settings.
    static let enabled = false

    static let model = "gpt-4o-mini-tts"

    /// OpenAI's built-in voices. Marin and Cedar are their best-sounding ones.
    static let voices = ["marin", "cedar", "coral", "sage", "ash", "ballad", "verse",
                         "alloy", "echo", "fable", "nova", "onyx", "shimmer"]

    /// How the voice should sound. This model takes plain-English directions.
    static let style = "A friendly coworker in a busy kitchen. Speak clearly and a little quickly, with no pause at the start."

    static let placeholderKey = "PASTE-OPENAI-KEY-HERE"

    static func hasKey(_ key: String) -> Bool {
        !key.isEmpty && key != placeholderKey
    }

    /// Streams the clip: hands over raw audio a piece at a time as it arrives,
    /// so the app can start talking before the whole answer has downloaded.
    /// A saved clip comes back in one piece, instantly.
    /// Audio is "pcm": 24,000 samples a second, 16-bit, mono, no header.
    static func stream(text: String, voice: String, apiKey: String,
                       onAudio: @MainActor (Data) -> Void) async throws {
        let file = cacheFile(text: text, voice: voice)
        if let saved = try? Data(contentsOf: file), !saved.isEmpty {
            await onAudio(saved)
            return
        }

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/speech")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 5          // too slow? fall back to the Apple voice
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "model": model,
            "voice": voice,
            "input": text,
            "instructions": style,
            "response_format": "pcm",       // raw audio: OpenAI says this is the fastest format
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            // Errors come back as {"error":{"message":...}}
            var data = Data()
            for try await byte in bytes { data.append(byte) }
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let message = (json?["error"] as? [String: Any])?["message"] as? String
            throw VoiceError.message(message ?? "OpenAI voice didn't answer.")
        }

        var all = Data()
        var piece = Data()
        var pieceSize = 2_400                // first piece: 0.05 seconds, so it starts talking right away
        for try await byte in bytes {
            piece.append(byte)
            if piece.count >= pieceSize {
                all.append(piece)
                await onAudio(piece)
                piece = Data()
                pieceSize = 9_600            // after that: 0.2-second pieces
            }
        }
        if !piece.isEmpty {
            all.append(piece)
            await onAudio(piece)
        }
        guard !all.isEmpty else { throw VoiceError.message("OpenAI sent no audio.") }
        try? all.write(to: file)
    }

    /// Opens the connection to OpenAI ahead of time (while you're still talking),
    /// so the real voice request doesn't wait on the setup handshake. Listing models is free.
    static func warmUp(apiKey: String) {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/models")!)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        URLSession.shared.dataTask(with: request).resume()
    }

    /// One file per voice + wording, named by a fingerprint (hash) of both.
    private static func cacheFile(text: String, voice: String) -> URL {
        let key = "\(model)|\(voice)|\(style)|\(text)"
        let hash = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return folder.appendingPathComponent("voice-\(hash).pcm")
    }
}

nonisolated enum VoiceError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let text): return text }
    }
}
