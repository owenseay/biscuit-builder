import SwiftUI

private let boardRed = Color(red: 0.62, green: 0.13, blue: 0.16)
private let good = Color(red: 0.12, green: 0.62, blue: 0.33)
private let bad = Color(red: 0.84, green: 0.25, blue: 0.27)

struct QuizView: View {
    @State private var quiz = Quiz()
    @State private var voiceQuiz = VoiceQuiz()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Quiz")
                    .font(.largeTitle.bold())

                Picker("Mode", selection: $quiz.mode) {
                    ForEach(QuizMode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                HStack {
                    if quiz.mode == .buildIt || quiz.mode == .nameIt {
                        Picker("Section", selection: $quiz.section) {
                            ForEach(quiz.availableSections) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.menu)
                        .tint(.orange)
                    } else if quiz.mode == .voice {
                        Picker("Section", selection: $voiceQuiz.section) {
                            ForEach(VoiceQuiz.sections) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.menu)
                        .tint(.orange)
                    }
                    Spacer()
                    if quiz.mode != .voice {
                        Text("Right \(quiz.right)/\(quiz.total)  ·  Streak \(quiz.streak)  ·  Best \(quiz.best)")
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }

                if quiz.mode == .voice {
                    VoiceQuizView(quiz: voiceQuiz)
                } else if quiz.mode == .buildIt {
                    BuildItView(quiz: quiz)
                } else if let choice = quiz.choice {
                    ChoiceView(quiz: quiz, choice: choice)
                }

                HStack {
                    Text(quiz.message)
                        .font(.headline)
                        .foregroundStyle(quiz.streak > 0 ? good : .primary)
                    Spacer()
                    if quiz.answered {
                        Button("Next") { quiz.next() }
                            .buttonStyle(.borderedProminent)
                            .tint(.orange)
                    }
                }
            }
            .padding(20)
        }
    }
}

// MARK: - Build It

struct BuildItView: View {
    let quiz: Quiz

    var body: some View {
        if let item = quiz.buildItem {
            VStack(alignment: .leading, spacing: 14) {
                Text(item.category == .wrap ? "Build the wrap, in order"
                     : item.category.stackBase != nil ? "Build it, bottom to top"
                     : quiz.orderMatters ? "Build it, in order" : "Pick everything that comes on it")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(item.name.uppercased())
                    .font(.title.weight(.black))
                    .foregroundStyle(boardRed)

                stackArea(for: item)

                Text("Tap to add. Tap it again to take it off.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], spacing: 8) {
                    ForEach(quiz.bank) { chip in
                        let used = quiz.isPlaced(chip)
                        Button { used ? quiz.unplace(chip) : quiz.place(chip) } label: {
                            Text(chip.text)
                                .font(.subheadline.weight(.bold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.65)   // long names shrink instead of wrapping
                                .padding(.horizontal, 8)
                                .frame(maxWidth: .infinity)
                                .frame(height: 40)          // same height for every pill, even shrunk ones
                                .foregroundStyle(used ? Color.secondary : Color.primary)
                                .background(Color.orange.opacity(used ? 0 : 0.15), in: Capsule())
                                // Used pills keep a dashed outline so you can see where they were and tap to undo.
                                .overlay(Capsule().stroke(Color.orange.opacity(used ? 0.6 : 1),
                                                          style: StrokeStyle(lineWidth: 1.5, dash: used ? [5, 4] : [])))
                        }
                        .buttonStyle(.plain)
                        .disabled(quiz.results != nil)
                    }
                }

                if quiz.results == nil {
                    Button("Check") { quiz.check() }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                        .disabled(quiz.placed.isEmpty)
                }
            }
        }
    }

    /// The build so far, in a fixed-size box so nothing below it moves.
    /// Stacks sit on the bottom line and grow upward like the real thing; wraps fill top-down, numbered.
    @ViewBuilder
    private func stackArea(for item: MenuItem) -> some View {
        let rows = Array(quiz.placed.enumerated())
        let rowHeight: CGFloat = 32
        let boxHeight = CGFloat(quiz.bank.count) * rowHeight + 44
        VStack(alignment: .leading, spacing: 0) {
            if let review = quiz.review {
                reviewContent(review, item: item, rowHeight: rowHeight)
            } else if let base = item.category.stackBase {
                Text("Top of \(base) ↑").font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                ForEach(rows.reversed(), id: \.element.id) { index, chip in
                    layerRow(chip, index: index, label: chip.text)
                        .frame(height: rowHeight)
                }
                Text("Bottom of \(base) ↓").font(.caption).foregroundStyle(.secondary)
            } else if !quiz.orderMatters {
                Text("Comes on it (any order):").font(.caption).foregroundStyle(.secondary)
                ForEach(rows, id: \.element.id) { index, chip in
                    layerRow(chip, index: index, label: chip.text)
                        .frame(height: rowHeight)
                }
                Spacer(minLength: 0)
            } else {
                Text(item.category == .wrap ? "On a tortilla, in order:" : "In order:").font(.caption).foregroundStyle(.secondary)
                ForEach(rows, id: \.element.id) { index, chip in
                    layerRow(chip, index: index, label: "\(index + 1). \(chip.text)")
                        .frame(height: rowHeight)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(height: boxHeight + (quiz.review == nil ? 0 : 28))
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(boxFill, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(boxStroke, lineWidth: quiz.review == nil ? 1 : 2.5))
    }

    private var boxFill: Color {
        guard quiz.review != nil else { return .white }
        return (quiz.lastBuildCorrect ? good : bad).opacity(0.10)
    }

    private var boxStroke: Color {
        guard quiz.review != nil else { return Color(white: 0.85) }
        return quiz.lastBuildCorrect ? good : bad
    }

    /// After Check: a pass/fail banner, then each spot with its fix.
    @ViewBuilder
    private func reviewContent(_ review: [ReviewRow], item: MenuItem, rowHeight: CGFloat) -> some View {
        let ok = quiz.lastBuildCorrect
        Label(ok ? "Correct" : "Not quite", systemImage: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
            .font(.headline)
            .foregroundStyle(ok ? good : bad)
            .padding(.bottom, 6)
        if let base = item.category.stackBase {
            Text("Top of \(base) ↑").font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            ForEach(review.reversed()) { row in reviewRow(row).frame(height: rowHeight) }
            Text("Bottom of \(base) ↓").font(.caption).foregroundStyle(.secondary)
        } else {
            Text(!quiz.orderMatters ? "Comes on it (any order):"
                 : item.category == .wrap ? "On a tortilla, in order:" : "In order:")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(Array(review.enumerated()), id: \.element.id) { index, row in
                reviewRow(row, number: quiz.orderMatters ? index + 1 : nil).frame(height: rowHeight)
            }
            Spacer(minLength: 0)
        }
    }

    private func reviewRow(_ row: ReviewRow, number: Int? = nil) -> some View {
        let prefix = number.map { "\($0). " } ?? ""
        let ink = Color(white: 0.12)
        let line: Text
        let icon: String
        let iconColor: Color
        switch row.kind {
        case .correct:
            line = Text(prefix + row.text).foregroundStyle(ink)
            icon = "checkmark.circle.fill"; iconColor = good
        case .wrong:
            line = Text(prefix) + Text(row.text).strikethrough().foregroundStyle(bad)
                + Text("  →  ").foregroundStyle(.secondary) + Text(row.shouldBe ?? "").foregroundStyle(good)
            icon = "xmark.circle.fill"; iconColor = bad
        case .missing:
            line = Text(prefix + "+ " + row.text).foregroundStyle(good)
            icon = "plus.circle.fill"; iconColor = good
        case .extra:
            line = Text(prefix) + Text(row.text).strikethrough().foregroundStyle(bad)
            icon = "xmark.circle.fill"; iconColor = bad
        }
        return HStack {
            line
                .font(.title3.weight(.heavy))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Spacer(minLength: 4)
            Image(systemName: icon).foregroundStyle(iconColor)
        }
    }

    private func layerRow(_ chip: Chip, index: Int, label: String) -> some View {
        let result = quiz.results.flatMap { index < $0.count ? $0[index] : nil }
        return Button { quiz.unplace(chip) } label: {
            HStack {
                Text(label)
                    .font(.title3.weight(.heavy))
                    .foregroundStyle(Color(white: 0.12))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer()
                if let result {
                    Image(systemName: result ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(result ? good : bad)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Multiple choice

struct ChoiceView: View {
    let quiz: Quiz
    let choice: Choice

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(choice.prompt)
                .font(.title3.weight(.bold))
                .foregroundStyle(Color(white: 0.12))

            if let big = choice.big {
                Text(big)
                    .font(.largeTitle.weight(.black))
                    .foregroundStyle(boardRed)
            }

            if let photo = choice.photo {
                Image(photo)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 260)
            }

            if choice.showCard, let item = choice.item {
                BuildCard(item: item, hideName: quiz.picked == nil)
            }

            ForEach(choice.options, id: \.self) { option in
                Button { quiz.choose(option) } label: {
                    Text(option)
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(fill(for: option), in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(stroke(for: option), lineWidth: 1.5))
                }
                .buttonStyle(.plain)
                .disabled(quiz.picked != nil)
            }

            // After answering, show the full build so every question teaches something.
            if quiz.picked != nil, !choice.showCard, let item = choice.item {
                BuildCard(item: item)
            }
        }
    }

    private func fill(for option: String) -> Color {
        guard let picked = quiz.picked else { return .white }
        if option == choice.answer { return good.opacity(0.15) }
        if option == picked { return bad.opacity(0.15) }
        return .white
    }

    private func stroke(for option: String) -> Color {
        guard let picked = quiz.picked else { return Color(white: 0.85) }
        if option == choice.answer { return good }
        if option == picked { return bad }
        return Color(white: 0.85)
    }
}

#Preview {
    QuizView()
}
