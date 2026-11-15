import Foundation
import Observation
import UIKit

/// Runs the whole loop: listen -> ask Claude -> speak.
@Observable
final class Assistant {
    enum Phase { case idle, listening, thinking, speaking }

    var phase: Phase = .idle
    var heard = ""
    var answer = ""
    var item: MenuItem?          // the biscuit to show as a build card
    var errorMessage: String?

    private let listener = SpeechListener()
    private let speaker = Speaker()
    private let claude = ClaudeClient(apiKey: Secrets.anthropicAPIKey)
    private var history: [[String: String]] = []   // last question + answer, for follow-ups
    private var lastAnswerAt = Date.distantPast
    private var hasPermission = false

    /// Lets the headset button act like the big on-screen button.
    /// Called every time the Ask tab appears, since the voice quiz borrows the button too.
    func connectHeadset() {
        HeadsetButton.shared.start()
        HeadsetButton.shared.onPress = { [weak self] in self?.buttonPressed() }
    }

    /// The one big button does whatever makes sense right now.
    func buttonPressed() {
        switch phase {
        case .idle: Task { await startListening() }
        case .listening: listener.finish()          // tap again = "I'm done talking"
        case .speaking: speaker.stop()              // tap while talking = stop
        case .thinking: break
        }
    }

    private func startListening() async {
        errorMessage = nil
        guard Secrets.anthropicAPIKey != "PASTE-YOUR-KEY-HERE" else {
            errorMessage = "Add your API key in Secrets.swift."
            return
        }
        if !hasPermission {
            hasPermission = await SpeechListener.requestPermissions()
            guard hasPermission else {
                errorMessage = "Mic or speech permission is off. Turn it on in Settings > Biscuit Builder."
                return
            }
        }
        heard = ""
        answer = ""
        item = nil
        // Open the connection to OpenAI now, while you're talking, so the voice starts faster.
        if Speaker.openAIVoice != nil { OpenAIVoice.warmUp(apiKey: Secrets.openAIAPIKey) }
        do {
            phase = .listening
            try listener.start(hints: Menu.speechHints,
                               onPartial: { [weak self] text in self?.heard = text },
                               onDone: { [weak self] text in self?.ask(text) })
        } catch {
            phase = .idle
            errorMessage = error.localizedDescription
        }
    }

    private func ask(_ question: String) {
        let question = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { phase = .idle; return }
        heard = question
        phase = .thinking

        // Forget the previous item after 90 seconds so old orders don't confuse it.
        if Date().timeIntervalSince(lastAnswerAt) > 90 { history = [] }
        let messages = history + [["role": "user", "content": question]]

        Task {
            do {
                let reply = try await claude.ask(system: Menu.systemPrompt, messages: messages)
                let parsed = Menu.parse(reply)
                answer = parsed.spoken
                item = parsed.item
                history = Array((messages + [["role": "assistant", "content": reply]]).suffix(4))
                lastAnswerAt = Date()
                say(parsed.spoken)
            } catch {
                errorMessage = error.localizedDescription
                say("Sorry, I couldn't get an answer.")
            }
        }
    }

    private func say(_ text: String) {
        phase = .speaking
        speaker.speak(text) { [weak self] in self?.phase = .idle }
    }
}
