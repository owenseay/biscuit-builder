import Foundation

/// Grades a spoken build answer on the phone. No AI: the same answer always gets the same result.
///
/// How it works:
/// 1. Read the answer into ingredients using the word list below
///    ("slice of cheese" -> cheese slice, "hash brown" -> potato). Filler words are skipped,
///    and a word said twice in a row (a common speech-to-text glitch) counts once.
/// 2. Match each ingredient to the item's build, then check for anything missing,
///    anything extra, wrong counts ("two bacon" when it's three), and order.
///
/// To teach it a new way of saying something, add it to `phrases`.
/// Words it didn't recognize show on screen under the answer.
enum BuildGrader {
    struct Result {
        let right: Bool
        let feedback: String
        let unrecognized: [String]
        let understood: Bool        // false = heard no ingredients at all
    }

    // MARK: - The word list

    /// Every way of saying each ingredient. Longer phrases are checked first,
    /// so "sausage gravy" is gravy, not sausage.
    static let phrases: [String: [String]] = [
        "canadian bacon": ["canadian bacon", "canadian"],
        "crumbled bacon": ["crumbled bacon", "bacon crumbles", "bacon bits", "crumbled"],
        "bacon": ["bacon"],
        "sausage": ["sausage", "sausage patty"],
        "shaved ham": ["shaved ham"],
        "country ham": ["country ham", "ham"],
        "fried bologna": ["fried bologna", "bologna", "baloney"],
        "fried steak": ["fried steak", "steak", "rocket meat", "rocket steak"],
        "pepperoni": ["pepperoni", "pepperonis"],
        "potato": ["potato", "potatoes", "hash brown", "hash browns", "hashbrown", "hashbrowns"],
        "chunkies": ["chunkies", "chunky", "chunky potatoes", "diced potatoes"],
        "cheese slice": ["cheese slice", "slice of cheese", "sliced cheese", "american cheese",
                         "american", "regular cheese", "slice"],
        "melted cheese": ["melted cheese", "melted"],
        "cheese": ["cheese"],                                   // either kind: right, with a note
        "egg": ["egg", "eggs", "scrambled eggs", "scrambled egg", "scrambled"],
        "tator rounds": ["tator rounds", "tater rounds", "tator tots", "tater tots", "rounds", "tots"],
        "mixed veggies": ["mixed veggies", "veggies", "veggie", "vegetables", "mixed vegetables"],
        "apples": ["apples", "apple", "country apples", "fried apples"],
        "gravy": ["gravy", "sausage gravy"],
        "scoops": ["scoops of gravy", "scoop of gravy", "scoops", "scoop"],
        "meat": ["choice of meat", "meat", "meats"],
        "biscuit": ["biscuit", "biscuits"],
        "toast": ["toast"],
        "pancakes": ["pancakes", "pancake", "hotcakes"],
    ]

    /// Which of the words above each build layer accepts (besides its own name).
    private static let accepts: [String: Set<String>] = [
        "cheese slice": ["cheese slice", "cheese"],
        "melted cheese": ["melted cheese", "cheese"],
        "scrambled eggs": ["egg"],
        "eggs": ["egg"],
        "1 biscuit": ["biscuit"],
        "2 biscuits": ["biscuit"],
        "2 scoops of gravy": ["scoops", "gravy"],
        "3 scoops of gravy": ["scoops", "gravy"],
        "gravy": ["gravy", "scoops"],
        "chunkies": ["chunkies", "potato"],
        "choice of meat": ["meat"],
        "choice of 2 meats": ["meat"],
        "biscuit or toast": ["biscuit", "toast"],
        "apples or chunkies": ["apples", "chunkies", "potato"],
        "melted cheese or gravy": ["melted cheese", "cheese", "gravy"],
        "crumbled bacon": ["crumbled bacon", "bacon"],
    ]

    /// Words that don't change the answer.
    private static let filler: Set<String> = [
        "and", "then", "on", "top", "of", "the", "a", "an", "with", "uh", "um", "it", "its", "s",
        "gets", "get", "has", "have", "is", "bottom", "over", "choice", "your", "plus", "also", "or",
        "fried", "piece", "pieces", "strip", "strips", "slices", "patty", "side", "some", "so", "okay",
        "first", "next", "last", "goes", "put", "in", "at", "i", "think", "like", "that", "comes",
    ]

    private static let numbers: [String: Int] = [
        "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
        "1": 1, "2": 2, "3": 3, "4": 4, "5": 5,
    ]

    private static let phraseList: [(words: [String], key: String)] = phrases
        .flatMap { key, list in list.map { (words: $0.split(separator: " ").map(String.init), key: key) } }
        .sorted { $0.words.count > $1.words.count }

    // MARK: - Reading the answer

    struct Token {
        let key: String
        let count: Int?
    }

    static func read(_ answer: String) -> (tokens: [Token], unknown: [String]) {
        let words = SpeechListener.words(in: answer)
        var tokens: [Token] = []
        var unknown: [String] = []
        var count: Int?
        var i = 0
        while i < words.count {
            let word = words[i]
            if let n = numbers[word] {
                count = n
                i += 1
                continue
            }
            if let match = phraseList.first(where: { phrase in
                i + phrase.words.count <= words.count && Array(words[i..<(i + phrase.words.count)]) == phrase.words
            }) {
                if tokens.last?.key != match.key {             // "cheese cheese" counts once
                    tokens.append(Token(key: match.key, count: count))
                }
                count = nil
                i += match.words.count
            } else {
                if !filler.contains(word) { unknown.append(word) }
                i += 1
            }
        }
        return (tokens, unknown)
    }

    // MARK: - Grading

    static func grade(_ answer: String, item: MenuItem) -> Result {
        let (tokens, unknown) = read(answer)
        guard !tokens.isEmpty else {
            return Result(right: false, feedback: "", unrecognized: unknown, understood: false)
        }
        let layers = item.layers
        var saidFor = Array(repeating: [String](), count: layers.count)   // what was said for each layer
        var firstSaid = Array(repeating: Int?.none, count: layers.count)  // when each layer was first said
        var extras: [String] = []
        var countProblems: [String] = []

        for (position, token) in tokens.enumerated() {
            let fits = layers.indices.filter { accepted(by: layers[$0]).contains(token.key) }
            guard !fits.isEmpty else {
                if !extras.contains(token.key) { extras.append(token.key) }
                continue
            }
            // First layer it fits that's still empty. If they're all filled, it's a repeat: ignore it.
            let index = fits.first { saidFor[$0].isEmpty } ?? fits[0]
            saidFor[index].append(token.key)
            if firstSaid[index] == nil { firstSaid[index] = position }
            if let said = token.count, let needed = expectedCount(layers[index]), said != needed {
                countProblems.append("It's \(word(needed)) \(nice(layers[index].name)), not \(word(said)).")
            }
        }

        let sentence = VoiceQuiz.buildSentence(item)
        let missing = layers.indices.filter { saidFor[$0].isEmpty }.map { nice(layers[$0].name) }
        if !missing.isEmpty || !extras.isEmpty || !countProblems.isEmpty {
            var problems: [String] = []
            if !missing.isEmpty { problems.append("Missing \(list(missing)).") }
            if !extras.isEmpty { problems.append("No \(list(extras.map { nice($0) })) on it.") }
            problems += countProblems
            return Result(right: false, feedback: "Not quite. " + problems.joined(separator: " ") + " " + sentence,
                          unrecognized: unknown, understood: true)
        }

        var notes: [String] = []
        let order = firstSaid.compactMap { $0 }
        if item.isOrdered && order != order.sorted() {
            notes.append("The order is " + sentence.prefix(1).lowercased() + sentence.dropFirst())
        }
        for i in layers.indices where Set(saidFor[i]) == ["cheese"] {
            notes.append(layers[i].name.contains("melted") ? "That's melted cheese." : "That's a cheese slice.")
        }
        let feedback = notes.isEmpty ? "Right." : "Right. " + notes.joined(separator: " ")
        return Result(right: true, feedback: feedback, unrecognized: unknown, understood: true)
    }

    // MARK: - Helpers

    private static func accepted(by layer: Layer) -> Set<String> {
        let name = layer.name.lowercased()
        return (accepts[name] ?? []).union([name])
    }

    /// A layer's count: "bacon (3)", or the number in its name ("2 scoops of gravy").
    private static func expectedCount(_ layer: Layer) -> Int? {
        layer.count ?? layer.name.split(separator: " ").compactMap { Int($0) }.first
    }

    private static func word(_ n: Int) -> String {
        [1: "one", 2: "two", 3: "three", 4: "four", 5: "five"][n] ?? String(n)
    }

    private static func nice(_ text: String) -> String {
        text.replacingOccurrences(of: "canadian", with: "Canadian")
    }

    /// "a", "a and b", "a, b, and c"
    private static func list(_ items: [String]) -> String {
        switch items.count {
        case 0: return ""
        case 1: return items[0]
        case 2: return "\(items[0]) and \(items[1])"
        default: return items.dropLast().joined(separator: ", ") + ", and " + items.last!
        }
    }
}
