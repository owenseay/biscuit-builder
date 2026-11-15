import SwiftUI
import AVFoundation

/// Voice settings. Tap a voice to hear it and select it.
/// AI voices (OpenAI) are on top when the OpenAI key is set; the phone's own voices are below.
struct VoicePicker: View {
    @AppStorage("voiceID") private var voiceID = ""            // Apple voice
    @AppStorage("openAIVoice") private var openAIVoice = "marin" // "none" = use the Apple voice
    @AppStorage("useHeadsetMic") private var useHeadsetMic = true  // false = always the iPhone mic
    @Environment(\.dismiss) private var dismiss
    @State private var previewer = Speaker()

    private let sample = "Porch Light, three Canadian bacon, egg, then melted cheese."
    private let hasKey = OpenAIVoice.enabled && OpenAIVoice.hasKey(Secrets.openAIAPIKey)

    private var appleVoices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") }
            .sorted { ($0.quality.rawValue, $0.name) > ($1.quality.rawValue, $1.name) }
    }

    private var usingOpenAI: Bool { hasKey && openAIVoice != "none" }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button { useHeadsetMic = true } label: {
                        row(title: "Headset mic",
                            detail: "Uses a Bluetooth headset's mic when one is connected",
                            selected: useHeadsetMic)
                    }
                    Button { useHeadsetMic = false } label: {
                        row(title: "iPhone mic",
                            detail: "For Bluetooth speakers: always listens through the phone",
                            selected: !useHeadsetMic)
                    }
                } header: {
                    Text("Microphone")
                }

                Section {
                    if hasKey {
                        ForEach(OpenAIVoice.voices, id: \.self) { name in
                            Button {
                                openAIVoice = name
                                previewer.speak(sample, openAIVoice: name) {}
                            } label: {
                                row(title: name.capitalized,
                                    detail: name == "marin" || name == "cedar" ? "OpenAI · Best quality" : "OpenAI",
                                    selected: usingOpenAI && openAIVoice == name)
                            }
                        }
                    } else {
                        Text(OpenAIVoice.enabled ? "Add your OpenAI key in Secrets.swift to use AI voices."
                                                 : "AI voices are turned off for now.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("AI voices")
                } footer: {
                    Text("About a tenth of a cent per new answer. Answers heard before are saved on the phone and play free.")
                }

                Section("Built-in voices (free, work offline)") {
                    ForEach(appleVoices, id: \.identifier) { voice in
                        Button {
                            voiceID = voice.identifier
                            openAIVoice = "none"
                            previewer.speak(sample, openAIVoice: nil) {}
                        } label: {
                            row(title: voice.name,
                                detail: "\(voice.language) · \(qualityName(voice.quality))",
                                selected: !usingOpenAI && voice.identifier == selectedAppleID)
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                Button("Done") { dismiss() }
            }
            .onDisappear { previewer.stop() }
        }
    }

    private func row(title: String, detail: String, selected: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if selected {
                Image(systemName: "checkmark").foregroundStyle(.orange)
            }
        }
        .foregroundStyle(.primary)
    }

    /// The Apple voice in use: the saved pick, or the automatic best voice.
    private var selectedAppleID: String {
        voiceID.isEmpty ? (Speaker.bestVoice?.identifier ?? "") : voiceID
    }

    private func qualityName(_ quality: AVSpeechSynthesisVoiceQuality) -> String {
        switch quality {
        case .premium: "Premium"
        case .enhanced: "Enhanced"
        default: "Basic"
        }
    }
}
