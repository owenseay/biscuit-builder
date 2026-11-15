import Foundation
import AVFoundation
import Speech

/// Listens to the mic and turns speech into text.
/// Stops when you say "over", when you pause, or after the time limit.
final class SpeechListener {
    nonisolated enum ListenerError: LocalizedError {
        case unavailable
        var errorDescription: String? { "Speech recognition isn't available right now." }
    }

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var silenceTimer: Task<Void, Never>?
    private var maxTimer: Task<Void, Never>?
    private var latest = ""
    private var isListening = false
    private var onPartial: ((String) -> Void)?
    private var onDone: ((String) -> Void)?

    /// Seconds of quiet after you stop talking before it sends the question.
    var pauseLength: Double = 1.3

    /// Longest it will listen, no matter what. A safety net in case you walk away.
    var maxLength: Double = 10

    /// Mic setting, picked in the settings sheet. true = Bluetooth headset mic when one is
    /// connected (default), false = always the iPhone's own mic.
    nonisolated static var useHeadsetMic: Bool {
        UserDefaults.standard.object(forKey: "useHeadsetMic") as? Bool ?? true
    }

    nonisolated static func requestPermissions() async -> Bool {
        let speechOK = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status == .authorized)
            }
        }
        let micOK = await AVAudioApplication.requestRecordPermission()
        return speechOK && micOK
    }

    func start(hints: [String],
               onPartial: @escaping (String) -> Void,
               onDone: @escaping (String) -> Void) throws {
        guard let recognizer, recognizer.isAvailable else { throw ListenerError.unavailable }
        self.onPartial = onPartial
        self.onDone = onDone
        latest = ""
        isListening = true

        // Turn on the headset mic. For Bluetooth headsets this is "call mode", which takes
        // the button away from the app, so it's only on while listening (see HeadsetButton).
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true   // stream words as you talk
        request.contextualStrings = hints           // boost menu names
        self.request = request
        do {
            let session = AVAudioSession.sharedInstance()
            // Mic setting (settings sheet): "Headset" allows a Bluetooth mic (HFP, "call mode"),
            // "iPhone" never asks for one, so a Bluetooth speaker stays in music mode and the
            // iPhone mic listens. .allowBluetoothA2DP keeps Bluetooth audio connected while
            // listening either way; without it, iOS pulls audio off a speaker mid-question.
            var options: AVAudioSession.CategoryOptions = [.allowBluetoothA2DP, .defaultToSpeaker]
            if Self.useHeadsetMic { options.insert(.allowBluetoothHFP) }
            try session.setCategory(.playAndRecord, mode: .default, options: options)
            try session.setActive(true)
            Self.installTap(on: engine.inputNode, feeding: request)
            engine.prepare()
            try engine.start()
        } catch {
            isListening = false
            self.request = nil
            HeadsetButton.shared.useHeadphoneMode()
            throw error
        }

        task = Self.recognize(with: recognizer, request: request) { [weak self] text, isFinal, failed in
            let listener = self
            Task { @MainActor in listener?.handle(text: text, isFinal: isFinal, failed: failed) }
        }

        let limit = maxLength
        maxTimer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(limit))
            if !Task.isCancelled { self?.finish() }
        }
    }

    /// Stop listening and hand back whatever was heard.
    func finish() {
        guard isListening else { return }
        isListening = false
        silenceTimer?.cancel()
        maxTimer?.cancel()
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        HeadsetButton.shared.useHeadphoneMode()     // mic off: give the button back to the app
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
        let done = onDone
        onDone = nil
        onPartial = nil
        done?(Self.removingStopWord(latest))
    }

    private func handle(text: String?, isFinal: Bool, failed: Bool) {
        guard isListening else { return }
        if let text {
            latest = text
            if Self.endsWithStopWord(text) { finish(); return }
            onPartial?(Self.removingStopWord(text))
            restartSilenceTimer()
        }
        if isFinal || failed { finish() }
    }

    private func restartSilenceTimer() {
        silenceTimer?.cancel()
        let wait = pauseLength
        silenceTimer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            if !Task.isCancelled { self?.finish() }
        }
    }

    // MARK: - Audio-thread helpers (kept off the main actor on purpose)

    nonisolated private static func installTap(on input: AVAudioInputNode,
                                               feeding request: SFSpeechAudioBufferRecognitionRequest) {
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
    }

    nonisolated private static func recognize(with recognizer: SFSpeechRecognizer,
                                              request: SFSpeechAudioBufferRecognitionRequest,
                                              update: @escaping @Sendable (String?, Bool, Bool) -> Void) -> SFSpeechRecognitionTask {
        recognizer.recognitionTask(with: request) { result, error in
            update(result?.bestTranscription.formattedString,
                   result?.isFinal ?? false,
                   error != nil)
        }
    }

    // MARK: - "over" handling

    nonisolated static func words(in text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    nonisolated static func endsWithStopWord(_ text: String) -> Bool {
        words(in: text).last == "over"
    }

    nonisolated static func removingStopWord(_ text: String) -> String {
        guard endsWithStopWord(text),
              let range = text.range(of: "over", options: [.caseInsensitive, .backwards]) else { return text }
        return String(text[..<range.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    }
}
