import Foundation
import Observation

/// One spoken quiz question.
struct VoiceQuestion {
    enum Kind { case build, cheese, potato, fryer }
    let kind: Kind
    let spoken: String          // what the app asks out loud
    let answer: String          // the right answer, short ("Cheese slice."), for checking
    let explain: String         // said out loud when you miss it ("The Hilltop gets a cheese slice.")
    var item: MenuItem? = nil   // for builds and item facts; shown as a build card afterward
    var fryerButton: Int? = nil
}

/// The voice quiz: the app asks out loud, you answer out loud, and it tells you if you're right.
///
/// One click (headset or on-screen button) asks the next question, then it listens.
/// Quick facts (cheese, potato, fryer buttons) are graded on the phone: free and instant.
/// Full builds are graded on the phone too, by BuildGrader (a word list, not AI), so grading is
/// instant, free, and the same answer always gets the same result.
@Observable
final class VoiceQuiz {
    enum Phase { case idle, asking, listening, grading, answering }

    var phase: Phase = .idle
    var question: VoiceQuestion?
    var heard = ""
    var feedback = ""
    var wasRight: Bool?          // nil = not graded (didn't catch it)
    var errorMessage: String?
    var unrecognized: [String] = []   // words in the answer the grader didn't know (shown on screen)
    @ObservationIgnored var isOnScreen = false

    /// Which part of the menu to practice. Same choices as Build It (the voice quiz only asks builds).
    var section: QuizSection = .all
    static let sections: [QuizSection] = [.all, .biscuits, .flapjacksWraps, .platters]

    var right = 0
    var total = 0
    var streak = 0

    private let listener = SpeechListener()
    private let speaker = Speaker()
    private var hasPermission = false
    @ObservationIgnored private var decks: [String: [String]] = [:]
    @ObservationIgnored private var lastName = ""

    init() {
        // Finish an answer by clicking or saying "over". These limits are only a safety net,
        // long enough that you'd rarely reach them while thinking through a build.
        listener.pauseLength = 15
        listener.maxLength = 30
    }

    // MARK: - The button

    func buttonPressed() {
        guard isOnScreen else { return }
        switch phase {
        case .idle: Task { await ask() }
        case .listening: listener.finish()                    // "I'm done answering"
        case .asking, .answering: phase = .idle; speaker.stop() // stop talking
        case .grading: break
        }
    }

    /// Leaving the screen: stop talking and listening.
    func stop() {
        if phase == .listening { phase = .idle; listener.finish() }
        phase = .idle
        speaker.stop()
    }

    // MARK: - Asking and listening

    private func ask() async {
        errorMessage = nil
        if !hasPermission {
            hasPermission = await SpeechListener.requestPermissions()
            guard hasPermission else {
                errorMessage = "Mic or speech permission is off. Turn it on in Settings > Biscuit Builder."
                return
            }
        }
        let question = makeQuestion()
        self.question = question
        heard = ""
        feedback = ""
        wasRight = nil
        unrecognized = []
        phase = .asking
        speaker.speak(question.spoken) { [weak self] in
            guard let self, self.phase == .asking else { return }   // stopped instead of finished
            self.listen()
        }
    }

    private func listen() {
        do {
            phase = .listening
            try listener.start(hints: Self.hints,
                               onPartial: { [weak self] text in self?.heard = text },
                               onDone: { [weak self] text in self?.grade(text) })
        } catch {
            phase = .idle
            errorMessage = error.localizedDescription
        }
    }

    /// Words the speech recognizer should expect: menu names plus every ingredient.
    private static let hints: [String] = Menu.speechHints
        + Array(Set(MenuData.items.flatMap { $0.layers.map(\.name) }))
        + ["melted", "slice", "yes", "no"]

    // MARK: - Grading

    private func grade(_ text: String) {
        guard phase == .listening, let question else { return }
        let answer = text.trimmingCharacters(in: .whitespacesAndNewlines)
        heard = answer
        if answer.isEmpty {
            return finish(nil, "Didn't catch that. \(question.explain)")
        }
        switch question.kind {
        case .build:
            guard let item = question.item else { return }
            let result = BuildGrader.grade(answer, item: item)
            unrecognized = result.unrecognized
            guard result.understood else { return finish(nil, "Didn't catch that. \(question.explain)") }
            finish(result.right, result.feedback)
        case .cheese:
            let words = Set(SpeechListener.words(in: answer))
            let said: String? =
                words.contains(where: { $0.hasPrefix("melt") }) && !words.contains("slice") ? "Melted cheese."
                : !words.isDisjoint(with: ["slice", "sliced", "regular", "american"]) ? "Cheese slice."
                : !words.isDisjoint(with: ["none", "nope"]) || answer.lowercased().contains("no cheese") ? "No cheese."
                : nil
            check(said, question)
        case .potato:
            let words = Set(SpeechListener.words(in: answer))
            let no = !words.isDisjoint(with: ["no", "nope", "nah", "not", "doesn", "none"])
            let yes = !words.isDisjoint(with: ["yes", "yeah", "yep", "yup", "does", "sure", "correct"])
            check(no == yes ? nil : (yes ? "Yes." : "No."), question)
        case .fryer:
            let numbers: [Int: Set<String>] = [
                1: ["one", "1", "won", "first"], 2: ["two", "2", "to", "too", "second"],
                3: ["three", "3", "third", "tree"], 4: ["four", "4", "for", "fore", "fourth"],
            ]
            let words = Set(SpeechListener.words(in: answer))
            let found = numbers.filter { !$0.value.isDisjoint(with: words) }.map { $0.key }
            check(found.count == 1 ? "Button \(found[0])." : nil, question)
        }
    }

    /// Quick facts: compare what you said to the right answer.
    private func check(_ said: String?, _ question: VoiceQuestion) {
        guard let said else { return finish(nil, "Didn't catch that. \(question.explain)") }
        let ok = said == question.answer
        finish(ok, ok ? "Right." : "Not quite. \(question.explain)")
    }

    /// Scores the answer (nil = not scored) and says the feedback out loud.
    private func finish(_ ok: Bool?, _ text: String) {
        wasRight = ok
        feedback = text
        if let ok {
            total += 1
            if ok { right += 1; streak += 1 } else { streak = 0 }
        }
        phase = .answering
        // Short pause first: a Bluetooth headset needs a moment to switch back from the mic
        // before it plays sound, or a short answer like "Right." gets cut off.
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard let self, self.phase == .answering else { return }
            self.speaker.speak(text) { [weak self] in
                guard let self, self.phase == .answering else { return }
                self.phase = .idle
            }
        }
    }

    private static func orderWords(for item: MenuItem) -> String {
        if item.category.stackBase != nil { return "bottom to top" }
        return item.isOrdered ? "in order" : "any order"
    }

    // MARK: - Making questions

    private func makeQuestion() -> VoiceQuestion {
        // Everything comes from the chosen section. Quick facts only exist for some sections
        // (cheese and potato for biscuits/flapjacks, fryer buttons only in Everything),
        // so when a section has none, the question is a full build instead.
        let stacks = MenuData.items.filter {
            ($0.category == .biscuit || $0.category == .flapjack) && $0.layers.count > 1 && section.includes($0.category)
        }
        let cheesePool = stacks.filter { !$0.name.contains("Melt") }
        let potatoPool = stacks.filter { !$0.name.lowercased().contains("potato") }
        var roll = Int.random(in: 0..<10)
        if (roll == 0 && cheesePool.isEmpty) || (roll == 1 && potatoPool.isEmpty) || (roll == 2 && section != .all) {
            roll = 9
        }
        switch roll {
        case 0:   // melted or slice (skip the "Melt" biscuits, the name gives it away)
            let item = deal(cheesePool)
            let names = item.layers.map(\.name)
            let answer = names.contains("melted cheese") ? "Melted cheese." : names.contains("cheese slice") ? "Cheese slice." : "No cheese."
            let kind = answer == "Melted cheese." ? "melted cheese" : answer == "Cheese slice." ? "a cheese slice" : "no cheese"
            return VoiceQuestion(kind: .cheese, spoken: "Melted cheese or cheese slice on the \(Self.short(item))?",
                                 answer: answer, explain: "The \(Self.short(item)) gets \(kind).", item: item)
        case 1:   // potato or not
            let item = deal(potatoPool)
            let has = item.layers.contains { $0.name == "potato" }
            return VoiceQuestion(kind: .potato, spoken: "Does the \(Self.short(item)) get potato?",
                                 answer: has ? "Yes." : "No.",
                                 explain: has ? "The \(Self.short(item)) gets potato." : "No potato on the \(Self.short(item)).",
                                 item: item)
        case 2:   // fryer button
            let fry = MenuData.fryer.randomElement()!
            let name = (fry.item.components(separatedBy: " (").first ?? fry.item).lowercased()   // drop "(steak)"
            return VoiceQuestion(kind: .fryer, spoken: "What button for \(name)?",
                                 answer: "Button \(fry.button).", explain: "Button \(fry.button) for \(name).",
                                 fryerButton: fry.button)
        default:  // full build (most questions)
            let pool = MenuData.items.filter {
                [.biscuit, .flapjack, .wrap, .breakfastPlatter].contains($0.category) && $0.layers.count >= 2
                    && section.includes($0.category)
            }
            let item = deal(pool)
            let ask: String
            switch item.category {
            case .wrap: ask = "What goes in the \(Self.short(item))?"
            case .breakfastPlatter: ask = "What comes with the \(Self.short(item))?"
            default: ask = "What's on the \(Self.short(item))?"
            }
            let build = Self.buildSentence(item)
            return VoiceQuestion(kind: .build, spoken: ask, answer: build, explain: build, item: item)
        }
    }

    /// Deals from a shuffled deck so every item comes up once before any repeats.
    private func deal(_ pool: [MenuItem]) -> MenuItem {
        let names = pool.map(\.name)
        let key = names.joined(separator: "|")
        var deck = decks[key] ?? []
        if deck.isEmpty { deck = names.shuffled() }
        let index = deck.firstIndex { $0 != lastName } ?? 0
        let name = deck.remove(at: index)
        decks[key] = deck
        lastName = name
        return pool.first { $0.name == name }!
    }

    /// "The Politician" reads better as "Politician" after "the".
    private static func short(_ item: MenuItem) -> String {
        item.name.hasPrefix("The ") ? String(item.name.dropFirst(4)) : item.name
    }

    /// "Three bacon, potato, cheese slice, then egg." (or "and" when order doesn't matter)
    static func buildSentence(_ item: MenuItem) -> String {
        let parts = item.layers.map(\.promptText)
        guard parts.count > 1 else { return (parts.first ?? "").capitalizedFirst + "." }
        let joiner = item.isOrdered ? "then" : "and"
        return (parts.dropLast().joined(separator: ", ") + ", \(joiner) " + parts.last!).capitalizedFirst + "."
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
