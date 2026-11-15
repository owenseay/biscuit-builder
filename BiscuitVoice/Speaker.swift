import Foundation
import AVFoundation

/// Reads answers out loud.
/// Uses an OpenAI voice when one is picked and the key is set; otherwise (or if OpenAI
/// is slow or offline) it falls back to the phone's built-in Apple voice.
///
/// The OpenAI voice streams: each piece of audio is queued on a player as it arrives,
/// so speaking starts almost as soon as OpenAI starts sending.
final class Speaker: NSObject, AVSpeechSynthesizerDelegate {
    nonisolated(unsafe) private let synth = AVSpeechSynthesizer()
    private var onFinish: (() -> Void)?
    private var current: UUID?          // which answer is playing, so a stopped one can't start late

    // Streaming playback: an audio engine with one player we keep feeding pieces to.
    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 24_000,
                                       channels: 1, interleaved: false)!
    private var engineSetUp = false
    private var queued = 0              // pieces waiting to play
    private var gotAudio = false
    private var downloadDone = false

    func speak(_ text: String, openAIVoice: String? = Speaker.openAIVoice, onFinish: @escaping () -> Void) {
        stopSound()
        self.onFinish = onFinish
        let id = UUID()
        current = id

        guard let voice = openAIVoice else { return speakApple(text) }
        let key = Secrets.openAIAPIKey
        Task {
            do {
                try startEngine()
                try await OpenAIVoice.stream(text: text, voice: voice, apiKey: key) { [weak self] pcm in
                    self?.play(pcm, id: id)
                }
                downloaded(id)
            } catch {
                guard current == id else { return }
                if gotAudio {
                    downloaded(id)          // cut off partway: let what we have finish
                } else {
                    print("OpenAI voice failed, using Apple voice: \(error.localizedDescription)")
                    speakApple(text)
                }
            }
        }
    }

    private func speakApple(_ text: String) {
        synth.delegate = self
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = Self.chosenVoice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 1.05
        synth.speak(utterance)
    }

    // MARK: - Streaming playback

    private func startEngine() throws {
        if !engineSetUp {
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: format)
            engineSetUp = true
        }
        if !engine.isRunning { try engine.start() }   // the mic setup can stop it, so check every time
        node.play()
    }

    /// Queue one piece of audio. It plays right after the pieces before it.
    private func play(_ pcm: Data, id: UUID) {
        guard current == id, let buffer = Self.buffer(from: pcm, format: format) else { return }
        gotAudio = true
        queued += 1
        let speaker = self
        Self.queue(buffer, on: node) {
            Task { @MainActor in speaker.piecePlayed(id) }
        }
    }

    private func piecePlayed(_ id: UUID) {
        guard current == id else { return }
        queued -= 1
        if queued == 0 && downloadDone { done(id) }
    }

    private func downloaded(_ id: UUID) {
        guard current == id else { return }
        downloadDone = true
        if queued == 0 { done(id) }
    }

    private func done(_ id: UUID) {
        guard current == id else { return }
        current = nil
        finished()
    }

    // MARK: - Settings

    /// The OpenAI voice to use, or nil for the Apple voice.
    /// Default is Marin once the OpenAI key is set. Picking an Apple voice saves "none".
    static var openAIVoice: String? {
        guard OpenAIVoice.enabled, OpenAIVoice.hasKey(Secrets.openAIAPIKey) else { return nil }
        let picked = UserDefaults.standard.string(forKey: "openAIVoice") ?? "marin"
        return picked == "none" ? nil : picked
    }

    /// Picks the most natural US English voice downloaded on this device
    /// (Premium beats Enhanced beats the basic default).
    static let bestVoice: AVSpeechSynthesisVoice? = {
        let voices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == "en-US" }
        return voices.max { $0.quality.rawValue < $1.quality.rawValue }
            ?? AVSpeechSynthesisVoice(language: "en-US")
    }()

    /// The Apple voice picked in the app's voice settings, or the best one if none is picked.
    static var chosenVoice: AVSpeechSynthesisVoice? {
        if let id = UserDefaults.standard.string(forKey: "voiceID"),
           let voice = AVSpeechSynthesisVoice(identifier: id) {
            return voice
        }
        return bestVoice
    }

    // MARK: - Stopping

    func stop() {
        stopSound()
        finished()
    }

    private func stopSound() {
        current = nil
        queued = 0
        gotAudio = false
        downloadDone = false
        if engineSetUp { node.stop() }
        synth.stopSpeaking(at: .immediate)
    }

    private func finished() {
        let done = onFinish
        onFinish = nil
        done?()
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.finished() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.finished() }
    }

    // MARK: - Audio-thread helpers (kept off the main actor on purpose)

    /// The player calls back from its own audio thread when a piece finishes.
    nonisolated private static func queue(_ buffer: AVAudioPCMBuffer, on node: AVAudioPlayerNode,
                                          played: @escaping @Sendable () -> Void) {
        node.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { _ in played() }
    }

    /// OpenAI sends 16-bit whole numbers; the player wants decimals between -1 and 1.
    nonisolated private static func buffer(from pcm: Data, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let count = pcm.count / 2
        guard count > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)),
              let out = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = AVAudioFrameCount(count)
        pcm.withUnsafeBytes { raw in
            for i in 0..<count {
                out[i] = Float(Int16(littleEndian: raw.loadUnaligned(fromByteOffset: i * 2, as: Int16.self))) / 32_768
            }
        }
        return buffer
    }
}
