import Foundation

/// One layer of a biscuit, like "bacon (3)" or "melted cheese".
struct Layer {
    let name: String
    let count: Int?

    init(_ name: String, _ count: Int? = nil) {
        self.name = name
        self.count = count
    }

    /// How it reads on the build board: "CANADIAN BACON (3)"
    var boardText: String {
        name.uppercased() + (count.map { " (\($0))" } ?? "")
    }

    /// How it reads to Claude: "three Canadian bacon"
    var promptText: String {
        guard let count else { return name }
        let words = [1: "one", 2: "two", 3: "three", 4: "four", 5: "five"]
        return "\(words[count] ?? String(count)) \(name)"
    }
}

/// Menu sections. Each one decides how its items are described and drawn.
enum Category: CaseIterable {
    case biscuit, flapjack, wrap, breakfastPlatter, lunch, dinner

    /// Shown small above the item name on the card.
    var label: String {
        switch self {
        case .biscuit: "Biscuit"
        case .flapjack: "Flapjack"
        case .wrap: "Breakfast Wrap"
        case .breakfastPlatter: "Breakfast Platter"
        case .lunch: "Lunch"
        case .dinner: "Dinner Platter"
        }
    }

    /// Section heading in Claude's menu.
    var promptHeading: String {
        switch self {
        case .biscuit: "Biscuits (bottom of biscuit to top):"
        case .flapjack: "Flapjack sandwiches (bottom flapjack to top):"
        case .wrap: "Breakfast wraps (on a tortilla, in the order you add them):"
        case .breakfastPlatter: "Breakfast platters (what comes on it):"
        case .lunch: "Lunch (what comes on it):"
        case .dinner: "Dinner platters (what comes with it):"
        }
    }

    /// Stacked items (biscuits, flapjacks) list top to bottom like the board.
    /// Wraps list in the order you add things. Everything else is an "includes" list.
    var stackBase: String? {
        switch self {
        case .biscuit: "Biscuit"
        case .flapjack: "Flapjack"
        default: nil
        }
    }
}

/// A menu item. For biscuits and flapjacks, layers go bottom first, top last.
/// For wraps, they go in the order you add them. For everything else, it's what's included.
struct MenuItem {
    let name: String
    var category: Category = .biscuit
    let layers: [Layer]
    var note: String? = nil
    /// Set to true for a platter that's built in a set order (the Tators).
    var ordered: Bool? = nil

    /// Does the order of the layers matter? Stacks and wraps always; other items only if marked.
    var isOrdered: Bool { ordered ?? [.biscuit, .flapjack, .wrap].contains(category) }
}

/// The whole menu. This is the single source of truth:
/// Claude's instructions and the on-screen build cards are both made from it.
enum MenuData {
    static let items: [MenuItem] = [
        // SAMPLE MENU. These are made-up diner items so the app builds and runs.
        // Replace them with your own. Biscuits: bottom of the biscuit first, top last.
        MenuItem(name: "Sausage Biscuit", layers: [Layer("sausage", 1)]),
        MenuItem(name: "Sunrise", layers: [Layer("sausage", 1), Layer("cheese slice"), Layer("egg")]),
        MenuItem(name: "Riverside", layers: [Layer("country ham", 1), Layer("cheese slice"), Layer("egg")]),
        MenuItem(name: "Hilltop", layers: [Layer("bacon", 3), Layer("potato"), Layer("cheese slice"), Layer("egg")]),
        MenuItem(name: "Porch Light", layers: [Layer("Canadian bacon", 3), Layer("egg"), Layer("melted cheese")]),
        MenuItem(name: "Coal Car", layers: [Layer("bacon", 3), Layer("potato"), Layer("melted cheese")]),
        MenuItem(name: "Pepperoni Melt", layers: [Layer("pepperoni", 5), Layer("melted cheese")]),

        // Flapjack sandwiches: bottom to top
        MenuItem(name: "Bacon Flapjack", category: .flapjack, layers: [Layer("bacon", 3), Layer("cheese slice"), Layer("egg")]),

        // Breakfast wraps: in the order you add them
        MenuItem(name: "Sausage Wrap", category: .wrap, layers: [Layer("cheese slice"), Layer("scrambled eggs"), Layer("sausage", 1)]),

        // Breakfast platters
        MenuItem(name: "Biscuits and Gravy", category: .breakfastPlatter, layers: [Layer("1 biscuit"), Layer("2 scoops of gravy")]),
        MenuItem(name: "Two Egg Breakfast", category: .breakfastPlatter, layers: [Layer("eggs", 2), Layer("choice of meat"), Layer("biscuit or toast")]),
        MenuItem(name: "Hash Brown Stack", category: .breakfastPlatter, layers: [Layer("hash browns"), Layer("scrambled eggs"), Layer("melted cheese"), Layer("crumbled bacon")], ordered: true),

        // Lunch
        MenuItem(name: "BLT", category: .lunch, layers: [Layer("bacon"), Layer("lettuce"), Layer("tomato"), Layer("toast")]),
        MenuItem(name: "Hamburger", category: .lunch, layers: [Layer("hamburger patty"), Layer("ketchup"), Layer("mustard"), Layer("pickle"), Layer("bun")]),

        // Dinner platters
        MenuItem(name: "Meatloaf", category: .dinner, layers: [Layer("meatloaf"), Layer("country sides", 2), Layer("biscuit or cornbread")]),
    ]

    /// The menu as text for Claude, one section per category:
    /// "Porch Light: three Canadian bacon, egg, melted cheese."
    static var promptLines: String {
        Category.allCases.map { category in
            let lines = items.filter { $0.category == category }.map { item in
                let build = item.layers.map(\.promptText).joined(separator: ", ")
                return "\(item.name): \(build)." + (item.note.map { " \($0)" } ?? "")
            }
            return ([category.promptHeading] + lines).joined(separator: "\n")
        }
        .joined(separator: "\n\n")
    }

    /// "Which ones have X" lookup for Claude, built from the biscuit, flapjack, and wrap builds:
    /// "potato: Hilltop, Coal Car." Listing it out means Claude reads one line
    /// instead of scanning the whole menu, which is where it was missing items.
    static var ingredientLines: String {
        let stacked = items.filter { [.biscuit, .flapjack, .wrap].contains($0.category) }
        var order: [String] = []
        var byIngredient: [String: [String]] = [:]
        for item in stacked {
            for layer in item.layers {
                if byIngredient[layer.name] == nil { order.append(layer.name) }
                byIngredient[layer.name, default: []].append(item.name)
            }
        }
        return order.map { "\($0): \(byIngredient[$0]!.joined(separator: ", "))." }.joined(separator: "\n")
    }

    /// Photo asset for an item, if we have one (biscuits only).
    /// Add an image set named "photo-<item name in lowercase, dashes for spaces>" in Assets.xcassets.
    /// The sample photos are plain placeholders. Use your own photos.
    static func photo(for item: MenuItem) -> String? {
        guard item.category == .biscuit else { return nil }
        return "photo-" + item.name.lowercased().replacingOccurrences(of: " ", with: "-")
    }

    /// Fryer timer buttons, for the quiz.
    static let fryer: [(item: String, button: Int)] = [
        ("Fries", 1), ("Hash browns", 1),
        ("Tator rounds", 2),
        ("Chicken", 3),
    ]

    /// Finds an item from Claude's tag, forgiving "Politician" vs "The Politician" (names that start with "The").
    static func item(named raw: String) -> MenuItem? {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)).lowercased()
        guard !name.isEmpty, name != "none" else { return nil }
        return items.first { $0.name.lowercased() == name }
            ?? items.first { $0.name.lowercased().replacingOccurrences(of: "the ", with: "") == name.replacingOccurrences(of: "the ", with: "") }
    }
}
