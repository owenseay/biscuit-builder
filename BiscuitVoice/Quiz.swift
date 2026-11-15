import Foundation
import Observation

/// A tappable word-bank bubble in Build It.
struct Chip: Identifiable, Equatable {
    let id = UUID()
    let text: String
}

/// One line of the after-Check review in Build It.
struct ReviewRow: Identifiable {
    enum Kind { case correct, wrong, missing, extra }
    let id = UUID()
    let kind: Kind
    let text: String          // what you picked (or what was missing)
    var shouldBe: String? = nil
}

/// A multiple-choice question (Name It, Picture, Facts).
struct Choice {
    let key: String          // what gets tracked for "practice what you miss"
    let prompt: String       // small text above, like "Melted or slice?"
    var big: String? = nil   // big text, like an item name
    var item: MenuItem? = nil
    var showCard = false     // show the build card (name hidden) as the question
    var photo: String? = nil
    let options: [String]
    let answer: String
}

enum QuizMode: String, CaseIterable, Identifiable {
    case buildIt = "Build It", nameIt = "Name It", picture = "Picture", facts = "Facts", voice = "Voice"
    var id: Self { self }
}

enum QuizSection: String, CaseIterable, Identifiable {
    case all = "Everything", biscuits = "Biscuits", flapjacksWraps = "Flapjacks & Wraps",
         platters = "Breakfast Platters", lunchDinner = "Lunch & Dinner"
    var id: Self { self }

    func includes(_ category: Category) -> Bool {
        switch self {
        case .all: true
        case .biscuits: category == .biscuit
        case .flapjacksWraps: category == .flapjack || category == .wrap
        case .platters: category == .breakfastPlatter
        case .lunchDinner: category == .lunch || category == .dinner
        }
    }
}

/// Runs the quiz: makes questions, checks answers, keeps score.
@Observable
final class Quiz {
    var mode: QuizMode = .buildIt { didSet { next() } }
    var section: QuizSection = .all { didSet { next() } }

    // Build It
    var buildItem: MenuItem?
    var bank: [Chip] = []
    var placed: [Chip] = []
    var results: [Bool]? = nil       // filled in after Check
    var lastBuildCorrect = false
    var review: [ReviewRow]? = nil   // the corrected build, shown in the box after Check

    // Multiple choice
    var choice: Choice?
    var picked: String?

    // Score
    var right = 0
    var total = 0
    var streak = 0
    var best = UserDefaults.standard.integer(forKey: "quizBest")
    var message = ""

    /// How many times each item has been missed. Missed items come up more often.
    @ObservationIgnored private var missed: [String: Int] =
        (UserDefaults.standard.dictionary(forKey: "quizMissed") as? [String: Int]) ?? [:]
    @ObservationIgnored private var lastKey = ""
    /// One shuffled "deck" per pool of items. Every item gets dealt once before any repeats.
    @ObservationIgnored private var decks: [String: [String]] = [:]

    /// Extra believable wrong amounts for Biscuits and Gravy.
    private static let gravyAmounts = [
        "1 BISCUIT", "2 BISCUITS", "3 BISCUITS",
        "1 SCOOP OF GRAVY", "1.5 SCOOPS OF GRAVY", "2 SCOOPS OF GRAVY", "3 SCOOPS OF GRAVY", "4 SCOOPS OF GRAVY",
    ]

    var answered: Bool { results != nil || picked != nil }

    /// Build It only covers things where order matters.
    /// Lunch & Dinner is parked for now (Oct 30): in Name It the item names give the answer away,
    /// and Owen hasn't settled how to quiz them. The section is kept in code for later.
    var availableSections: [QuizSection] {
        [.all, .biscuits, .flapjacksWraps, .platters]
    }

    /// Items the quiz uses: everything except lunch and dinner (see above).
    private var quizzable: [MenuItem] {
        MenuData.items.filter { $0.category != .lunch && $0.category != .dinner }
    }

    init() { next() }

    // MARK: - Making questions

    func next() {
        results = nil
        review = nil
        picked = nil
        placed = []
        message = ""
        switch mode {
        case .buildIt: makeBuild()
        case .nameIt: makeNameIt()
        case .picture: makePicture()
        case .facts: makeFact()
        case .voice: buildItem = nil; choice = nil   // the voice quiz runs itself (VoiceQuiz.swift)
        }
    }

    private func makeBuild() {
        choice = nil
        let buildable = MenuData.items.filter {
            [.biscuit, .flapjack, .wrap, .breakfastPlatter].contains($0.category) && $0.layers.count >= 2
        }
        let filtered = buildable.filter { section.includes($0.category) }
        let item = pick(from: filtered.isEmpty ? buildable : filtered)
        buildItem = item

        // Always an even number of pills, at least 6, so simple items still get real decoys.
        let correct = correctBuild
        let target = max(6, correct.count + 2)
        let needed = target + target % 2 - correct.count

        // Decoys: special amounts first (gravy), then look-alike items, then anything on the menu.
        let special = item.name.hasPrefix("Biscuits and Gravy") ? Self.gravyAmounts : []
        let lookAlikes = closest(to: item, in: buildable, count: 4).flatMap { $0.layers.map(\.boardText) }
        let anything = buildable.flatMap { $0.layers.map(\.boardText) }
        var decoys: [String] = []
        for text in special.shuffled() + lookAlikes.shuffled() + anything.shuffled()
        where !correct.contains(text) && !decoys.contains(text) {
            decoys.append(text)
            if decoys.count == needed { break }
        }
        bank = (correct + decoys).shuffled().map { Chip(text: $0) }
    }

    private func makeNameIt() {
        buildItem = nil
        let pool = quizzable.filter { section.includes($0.category) }
        let item = pick(from: pool.isEmpty ? quizzable : pool)
        choice = Choice(key: item.name, prompt: "Which item is this?", item: item, showCard: true,
                        options: options(for: item, in: quizzable), answer: item.name)
    }

    private func makePicture() {
        buildItem = nil
        let pool = MenuData.items.filter { MenuData.photo(for: $0) != nil }
        let item = pick(from: pool)
        choice = Choice(key: item.name, prompt: "Name that biscuit", item: item,
                        photo: MenuData.photo(for: item), options: options(for: item, in: pool), answer: item.name)
    }

    private func makeFact() {
        buildItem = nil
        let stacks = MenuData.items.filter { ($0.category == .biscuit || $0.category == .flapjack) && $0.layers.count > 1 }
        let meats = ["sausage", "bacon", "country ham", "Canadian bacon", "fried steak", "fried bologna", "pepperoni", "shaved ham"]

        switch Int.random(in: 0..<5) {
        case 0:
            let item = pick(from: stacks.filter { !$0.name.contains("Melt") })
            let names = item.layers.map(\.name)
            let answer = names.contains("melted cheese") ? "Melted cheese" : names.contains("cheese slice") ? "Cheese slice" : "No cheese"
            choice = Choice(key: item.name, prompt: "Melted or slice?", big: item.name, item: item,
                            options: ["Melted cheese", "Cheese slice", "No cheese"], answer: answer)
        case 1:
            let counted = MenuData.items.filter {
                [.biscuit, .flapjack, .wrap].contains($0.category) && $0.layers.contains { $0.count != nil }
            }.filter { item in !inName(item, item.layers.first { $0.count != nil }!.name) }
            let item = pick(from: counted)
            let layer = item.layers.first { $0.count != nil }!
            choice = Choice(key: item.name, prompt: "How many \(layer.name)?", big: item.name, item: item,
                            options: ["1", "2", "3", "5"], answer: String(layer.count!))
        case 2:
            let item = pick(from: stacks.filter { !inName($0, "potato") })
            let answer = item.layers.contains { $0.name == "potato" } ? "Yes" : "No"
            choice = Choice(key: item.name, prompt: "Does it get potato?", big: item.name, item: item,
                            options: ["Yes", "No"], answer: answer)
        case 3:
            let withMeat = stacks.filter { item in
                guard let meat = item.layers.first(where: { meats.contains($0.name) }) else { return false }
                return !inName(item, meat.name)
            }
            let item = pick(from: withMeat)
            let meat = item.layers.first { meats.contains($0.name) }!.name
            let others = meats.filter { $0 != meat }.shuffled().prefix(3)
            choice = Choice(key: item.name, prompt: "What meat?", big: item.name, item: item,
                            options: ([meat] + others).shuffled().map(capitalized), answer: capitalized(meat))
        default:
            var fry = MenuData.fryer.randomElement()!
            if "fryer-" + fry.item == lastKey { fry = MenuData.fryer.randomElement()! }
            lastKey = "fryer-" + fry.item
            choice = Choice(key: lastKey, prompt: "Which fryer button?", big: fry.item,
                            options: ["1", "2", "3", "4"], answer: String(fry.button))
        }
    }

    // MARK: - Answering

    /// Pills stay in the bank (dimmed) when used, so nothing shifts around.
    func place(_ chip: Chip) {
        guard results == nil, !isPlaced(chip) else { return }
        placed.append(chip)
    }

    func unplace(_ chip: Chip) {
        guard results == nil else { return }
        placed.removeAll { $0.id == chip.id }
    }

    func isPlaced(_ chip: Chip) -> Bool {
        placed.contains { $0.id == chip.id }
    }

    /// The right build, in the order you build it.
    var correctBuild: [String] { buildItem?.layers.map(\.boardText) ?? [] }

    /// Most platters: pick everything that comes on it, in any order. The Tators have an order.
    var orderMatters: Bool { buildItem?.isOrdered ?? true }

    func check() {
        guard let item = buildItem, results == nil, !placed.isEmpty else { return }
        let correct = correctBuild
        let ok: Bool
        if orderMatters {
            results = placed.indices.map { $0 < correct.count && placed[$0].text == correct[$0] }
            ok = placed.map(\.text) == correct
        } else {
            results = placed.map { correct.contains($0.text) }
            ok = Set(placed.map(\.text)) == Set(correct) && placed.count == correct.count
        }
        lastBuildCorrect = ok
        review = makeReview(correct: correct)
        score(ok, key: item.name)
        message = ok ? "Nailed it." : "Not quite. Fixes are in the box."
    }

    /// Compares your build to the right one, spot by spot (or item by item for platters).
    private func makeReview(correct: [String]) -> [ReviewRow] {
        let yours = placed.map(\.text)
        if orderMatters {
            return (0..<max(yours.count, correct.count)).map { i in
                switch (i < yours.count ? yours[i] : nil, i < correct.count ? correct[i] : nil) {
                case let (mine?, right?) where mine == right: ReviewRow(kind: .correct, text: mine)
                case let (mine?, right?): ReviewRow(kind: .wrong, text: mine, shouldBe: right)
                case let (nil, right?): ReviewRow(kind: .missing, text: right)
                case let (mine?, nil): ReviewRow(kind: .extra, text: mine)
                default: ReviewRow(kind: .extra, text: "")
                }
            }
        } else {
            let picks = yours.map { ReviewRow(kind: correct.contains($0) ? .correct : .extra, text: $0) }
            let missing = correct.filter { !yours.contains($0) }.map { ReviewRow(kind: .missing, text: $0) }
            return picks + missing
        }
    }

    func choose(_ option: String) {
        guard let choice, picked == nil else { return }
        picked = option
        let ok = option == choice.answer
        score(ok, key: choice.key)
        message = ok ? "Right." : "It's \(choice.answer)."
    }

    // MARK: - Helpers

    private func score(_ ok: Bool, key: String) {
        total += 1
        if ok {
            right += 1
            streak += 1
            if streak > best {
                best = streak
                UserDefaults.standard.set(best, forKey: "quizBest")
            }
            if let n = missed[key] { missed[key] = n > 1 ? n - 1 : nil }
        } else {
            streak = 0
            missed[key, default: 0] += 1
        }
        UserDefaults.standard.set(missed, forKey: "quizMissed")
    }

    /// Deals from a shuffled deck: every item once before any repeats, like going through flash cards.
    /// Items you've missed get an extra card or two, so they come back sooner without taking over.
    /// Never the same one twice in a row.
    private func pick(from pool: [MenuItem]) -> MenuItem {
        let names = pool.map(\.name)
        let deckKey = names.joined(separator: "|")
        var deck = decks[deckKey] ?? []
        if deck.isEmpty {
            deck = names
            for name in names where (missed[name] ?? 0) > 0 {
                deck += Array(repeating: name, count: min(missed[name]!, 2))
            }
            deck.shuffle()
        }
        let index = deck.firstIndex { $0 != lastKey } ?? 0
        let name = deck.remove(at: index)
        decks[deckKey] = deck
        lastKey = name
        return pool.first { $0.name == name }!
    }

    /// True when the answer is given away by the name, like "What meat?" for the Sausage Flapjack.
    private func inName(_ item: MenuItem, _ word: String) -> Bool {
        item.name.lowercased().contains(word.lowercased())
    }

    /// The right answer plus three look-alikes, shuffled.
    private func options(for item: MenuItem, in pool: [MenuItem]) -> [String] {
        ([item] + closest(to: item, in: pool, count: 3)).map(\.name).shuffled()
    }

    private func closest(to item: MenuItem, in pool: [MenuItem], count: Int) -> [MenuItem] {
        pool.filter { $0.name != item.name }
            .map { ($0, similarity(item, $0)) }
            .sorted { $0.1 > $1.1 }
            .prefix(count)
            .map { $0.0 }
    }

    /// How alike two items are: shared ingredients, same section, same base layer.
    private func similarity(_ a: MenuItem, _ b: MenuItem) -> Double {
        let shared = Set(a.layers.map(\.name)).intersection(b.layers.map(\.name)).count
        var score = Double(shared)
        if a.category == b.category { score += 2 }
        if a.layers.first?.name == b.layers.first?.name { score += 1 }
        return score + Double.random(in: 0..<1.5)
    }

    private func capitalized(_ text: String) -> String {
        text.prefix(1).uppercased() + text.dropFirst()
    }
}
