import Foundation
import AVFoundation
import MediaPlayer

/// Makes the EarPods (or Bluetooth headset) button work like the big on-screen button.
///
/// The headset's middle button sends the same "play/pause" signal music apps use.
/// iOS only delivers that signal to the app that's currently playing audio, so
/// this quietly plays silence to keep Biscuit Builder as the "now playing" app.
///
/// There's one shared headset button for the whole app. Whichever screen is showing
/// (the Ask tab or the voice quiz) sets `onPress` to its own action when it appears.
final class HeadsetButton {
    static let shared = HeadsetButton()

    /// What a click does right now. Set by the screen that's showing.
    var onPress: (() -> Void)?

    private var player: AVAudioPlayer?
    private var lastPress = Date.distantPast
    private var started = false

    func start() {
        guard !started else { return }
        started = true

        playSilence()
        useHeadphoneMode()

        Self.listenForButton { [weak self] in
            let button = self
            Task { @MainActor in button?.pressed() }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [MPMediaItemPropertyTitle: "Biscuit Builder"]
    }

    /// Normal headphone mode, used whenever the app isn't listening.
    ///
    /// Why: to use a Bluetooth headset's mic (like the Shokz), iOS puts the headset in
    /// "phone call" mode, and during a call the iPhone keeps the button for itself
    /// (answer/hang up) instead of passing the click to the app. So the app only turns
    /// on call mode while it's listening (SpeechListener), and comes back here right after.
    /// Wired earbuds aren't affected either way.
    func useHeadphoneMode() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default)
        try? session.setActive(true)
        if player?.isPlaying == false { player?.play() }   // keep the silence going after the switch
    }

    private func pressed() {
        // Ignore double signals from a single click.
        guard Date().timeIntervalSince(lastPress) > 0.4 else { return }
        lastPress = Date()
        onPress?()
    }

    /// One second of silence, looped forever.
    private func playSilence() {
        let sampleRate = 44_100
        let samples = [Int16](repeating: 0, count: sampleRate)
        var wav = Data()
        func append<T>(_ value: T) { withUnsafeBytes(of: value) { wav.append(contentsOf: $0) } }
        let dataSize = UInt32(samples.count * 2)
        wav.append(contentsOf: Array("RIFF".utf8)); append(UInt32(36 + dataSize).littleEndian)
        wav.append(contentsOf: Array("WAVE".utf8))
        wav.append(contentsOf: Array("fmt ".utf8)); append(UInt32(16).littleEndian)
        append(UInt16(1).littleEndian); append(UInt16(1).littleEndian)            // PCM, mono
        append(UInt32(sampleRate).littleEndian); append(UInt32(sampleRate * 2).littleEndian)
        append(UInt16(2).littleEndian); append(UInt16(16).littleEndian)           // block align, bits
        wav.append(contentsOf: Array("data".utf8)); append(dataSize.littleEndian)
        samples.withUnsafeBytes { wav.append(contentsOf: $0) }

        player = try? AVAudioPlayer(data: wav)
        player?.numberOfLoops = -1
        player?.play()
    }

    nonisolated private static func listenForButton(_ handler: @escaping @Sendable () -> Void) {
        let center = MPRemoteCommandCenter.shared()
        for command in [center.togglePlayPauseCommand, center.playCommand, center.pauseCommand] {
            command.isEnabled = true
            command.addTarget { _ in
                handler()
                return .success
            }
        }
    }
}
