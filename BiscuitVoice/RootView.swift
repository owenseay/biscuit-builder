import SwiftUI

/// The tab bar: Ask (the voice assistant) and Quiz.
struct RootView: View {
    var body: some View {
        TabView {
            ContentView()
                .tabItem { Label("Ask", systemImage: "mic.fill") }
            QuizView()
                .tabItem { Label("Quiz", systemImage: "checklist") }
        }
        .tint(.orange)
    }
}
