import SwiftUI
import UIKit

struct ContentView: View {
    @State private var assistant = Assistant()
    @State private var showingVoices = false

    var body: some View {
        ScrollView {
        VStack(spacing: 22) {
            HStack {
                Text("Biscuit Builder")
                    .font(.largeTitle.bold())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)   // shrink a little on small screens
                Spacer()
                Button {
                    showingVoices = true
                } label: {
                    Image(systemName: "speaker.wave.2.circle")
                        .font(.title)
                        .foregroundStyle(.orange)
                }
            }

            Button {
                assistant.buttonPressed()
            } label: {
                ZStack {
                    Circle()
                        .fill(buttonColor)
                        .frame(width: 180, height: 180)
                    VStack(spacing: 10) {
                        Image(systemName: buttonIcon)
                            .font(.system(size: 46, weight: .bold))
                        Text(buttonLabel)
                            .font(.title2.bold())
                    }
                    .foregroundStyle(.white)
                }
            }
            .buttonStyle(.plain)
            .disabled(assistant.phase == .thinking)
            .animation(.easeInOut(duration: 0.2), value: assistant.phase)

            VStack(alignment: .leading, spacing: 14) {
                if !assistant.heard.isEmpty {
                    Label(assistant.heard, systemImage: "ear")
                        .foregroundStyle(.secondary)
                }
                if !assistant.answer.isEmpty {
                    Label(assistant.answer, systemImage: "fork.knife")
                        .font(assistant.item == nil ? Font.title3.bold() : Font.headline)
                }
                if let item = assistant.item {
                    BuildCard(item: item)
                        .transition(.opacity)
                }
                if let error = assistant.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(.easeInOut(duration: 0.2), value: assistant.item?.name)

            Text("Tap or click your headset, ask, then pause or say \"over.\"")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true   // keep the screen on
            assistant.connectHeadset()
        }
        .sheet(isPresented: $showingVoices) { VoicePicker() }
    }

    private var buttonColor: Color {
        switch assistant.phase {
        case .idle: .orange
        case .listening: .red
        case .thinking: .gray
        case .speaking: .blue
        }
    }

    private var buttonIcon: String {
        switch assistant.phase {
        case .idle: "mic.fill"
        case .listening: "waveform"
        case .thinking: "hourglass"
        case .speaking: "speaker.wave.2.fill"
        }
    }

    private var buttonLabel: String {
        switch assistant.phase {
        case .idle: "Tap to ask"
        case .listening: "Listening…"
        case .thinking: "Checking…"
        case .speaking: "Tap to stop"
        }
    }
}

#Preview {
    ContentView()
}
