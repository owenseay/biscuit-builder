import SwiftUI

/// The Voice mode screen in the Quiz tab.
/// One click (headset or the big button) asks a question; answer out loud.
struct VoiceQuizView: View {
    let quiz: VoiceQuiz

    private let boardRed = Color(red: 0.62, green: 0.13, blue: 0.16)
    private let good = Color(red: 0.12, green: 0.62, blue: 0.33)
    private let bad = Color(red: 0.84, green: 0.25, blue: 0.27)

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Click your headset for a question. Answer out loud, then click or say \"over.\"")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Right \(quiz.right)/\(quiz.total)  ·  Streak \(quiz.streak)")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if let question = quiz.question {
                Text(question.spoken)
                    .font(.title.weight(.black))
                    .foregroundStyle(boardRed)
            }

            Button { quiz.buttonPressed() } label: {
                ZStack {
                    Circle().fill(buttonColor).frame(width: 150, height: 150)
                    VStack(spacing: 8) {
                        Image(systemName: buttonIcon).font(.system(size: 38, weight: .bold))
                        Text(buttonLabel).font(.headline)
                    }
                    .foregroundStyle(.white)
                }
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .disabled(quiz.phase == .grading)
            .animation(.easeInOut(duration: 0.2), value: quiz.phase)

            if !quiz.heard.isEmpty {
                Label(quiz.heard, systemImage: "ear")
                    .foregroundStyle(.secondary)
            }

            if !quiz.feedback.isEmpty {
                Label(quiz.feedback, systemImage: feedbackIcon)
                    .font(.headline)
                    .foregroundStyle(feedbackColor)
            }

            // Words the grader didn't know. If one should count, it goes in BuildGrader's word list.
            if !quiz.feedback.isEmpty, !quiz.unrecognized.isEmpty {
                Text("Didn't recognize: \(quiz.unrecognized.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // After grading, show the right build so every question teaches something.
            if !quiz.feedback.isEmpty, let item = quiz.question?.item {
                BuildCard(item: item)
            }

            if let error = quiz.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            }
        }
        .onAppear {
            // Borrow the headset button while this screen is showing.
            quiz.isOnScreen = true
            HeadsetButton.shared.start()
            HeadsetButton.shared.onPress = { quiz.buttonPressed() }
        }
        .onDisappear {
            // Clicks are ignored until this screen shows again (the Ask tab takes the button back when it appears).
            quiz.isOnScreen = false
            quiz.stop()
        }
    }

    private var feedbackIcon: String {
        switch quiz.wasRight {
        case true?: "checkmark.circle.fill"
        case false?: "xmark.circle.fill"
        case nil: "questionmark.circle"
        }
    }

    private var feedbackColor: Color {
        switch quiz.wasRight {
        case true?: good
        case false?: bad
        case nil: .primary
        }
    }

    private var buttonColor: Color {
        switch quiz.phase {
        case .idle: .orange
        case .asking, .answering: .blue
        case .listening: .red
        case .grading: .gray
        }
    }

    private var buttonIcon: String {
        switch quiz.phase {
        case .idle: "questionmark.bubble.fill"
        case .asking, .answering: "speaker.wave.2.fill"
        case .listening: "waveform"
        case .grading: "hourglass"
        }
    }

    private var buttonLabel: String {
        switch quiz.phase {
        case .idle: quiz.total == 0 && quiz.question == nil ? "Start" : "Next question"
        case .asking: "Asking…"
        case .listening: "Listening…"
        case .grading: "Checking…"
        case .answering: "Tap to stop"
        }
    }
}
