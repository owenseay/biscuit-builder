import SwiftUI

/// Shows an item's build the way the kitchen board does.
/// Biscuits and flapjacks: top to bottom with "Top of… / Bottom of…".
/// Wraps: numbered, in the order you add things.
/// Platters, lunch, dinner: an "Includes" list.
struct BuildCard: View {
    let item: MenuItem
    var hideName = false   // the quiz hides the name until you answer

    private let boardRed = Color(red: 0.62, green: 0.13, blue: 0.16)
    private let ink = Color(white: 0.12)

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.category.label.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(ink.opacity(0.5))

            Text(hideName ? "? ? ?" : item.name.uppercased())
                .font(.title2.weight(.black))
                .foregroundStyle(boardRed)

            if let base = item.category.stackBase {
                caption("Top of \(base) ↑")
                ForEach(Array(item.layers.reversed().enumerated()), id: \.offset) { _, layer in
                    row(layer.boardText)
                }
                caption("Bottom of \(base) ↓")
            } else if item.isOrdered {
                caption(item.category == .wrap ? "On a tortilla, in this order:" : "In this order:")
                ForEach(Array(item.layers.enumerated()), id: \.offset) { index, layer in
                    row("\(index + 1). \(layer.boardText)")
                }
            } else {
                caption("Includes:")
                ForEach(Array(item.layers.enumerated()), id: \.offset) { _, layer in
                    row(layer.boardText)
                }
            }

            if let note = item.note {
                Text(note)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(boardRed)
                    .padding(.top, 2)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(white: 0.85), lineWidth: 1))
        .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(ink.opacity(0.6))
    }

    private func row(_ text: String) -> some View {
        Text(text)
            .font(.title3.weight(.heavy))
            .foregroundStyle(ink)
    }
}

#Preview {
    ScrollView {
        VStack(spacing: 16) {
            ForEach(["Porch Light", "Bacon Flapjack", "Sausage Wrap", "Hash Brown Stack"], id: \.self) { name in
                BuildCard(item: MenuData.items.first { $0.name == name }!)
            }
        }
        .padding()
    }
}
