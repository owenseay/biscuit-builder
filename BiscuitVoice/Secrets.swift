import Foundation

/// Paste your Anthropic API key between the quotes (from console.anthropic.com).
/// Keep this file private: anyone with the key can spend your credits.
/// Once your real key is in here, never commit, push, screenshot, or share this file.
enum Secrets {
    static let anthropicAPIKey = "PASTE-YOUR-KEY-HERE"

    /// Optional. Paste an OpenAI API key here to try the cloud voice (it's off by default).
    /// Leave as is to use the Apple voice.
    static let openAIAPIKey = "PASTE-YOUR-KEY-HERE"
}
