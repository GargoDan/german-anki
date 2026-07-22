import SwiftUI

/// Full detail for one word: the card, how well it's known, when it was last
/// answered and how, plus its example sentences.
struct WordDetailView: View {
    @Environment(AppModel.self) private var app
    @AppStorage(AppSettings.translationLangKey) private var langRaw = TranslationLang.en.rawValue

    let word: Word
    @State private var state: CardState = .newCard("")
    @State private var history: [ReviewLogEntry] = []
    @State private var sentences: [Sentence] = []

    private var lang: TranslationLang { TranslationLang(rawValue: langRaw) ?? .en }

    var body: some View {
        List {
            headerSection
            knowledgeSection
            historySection
            if !sentences.isEmpty { sentencesSection }
        }
        .navigationTitle(word.display)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: load)
    }

    // MARK: - Header

    private var headerSection: some View {
        Section {
            VStack(spacing: 10) {
                Text(word.level.rawValue)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().fill(word.level.tint.opacity(0.15)))
                    .foregroundStyle(word.level.tint)

                Text(word.display)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)

                if let grammar = word.grammarLine {
                    Text(grammar)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Text(word.translation(lang))
                    .font(.title3)
                Text(word.translation(lang == .en ? .ru : .en))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Button {
                    app.audio.play(word.audio)
                } label: {
                    Label("Play", systemImage: "speaker.wave.2.fill")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Knowledge

    /// "Learned" (green) if graded Good or Easy within the mature window (21 days).
    private var hasRecentPass: Bool {
        let cutoff = Date.now.addingTimeInterval(-SchedulerConfig.matureIntervalDays * 86_400)
        return history.contains { $0.grade.rawValue >= Grade.good.rawValue && $0.date >= cutoff }
    }

    private var knowledgeSection: some View {
        Section("How well you know it") {
            HStack {
                Circle().fill(KnowledgeStyle.color(state, learned: hasRecentPass))
                    .frame(width: 12, height: 12)
                Text(KnowledgeStyle.label(state, learned: hasRecentPass)).font(.headline)
                Spacer()
                Text("\(Int((state.strength * 100).rounded()))%")
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: state.strength)
                .tint(KnowledgeStyle.color(state, learned: hasRecentPass))

            LabeledContent("Last answered", value: relativeLastReviewed)
            if let due = state.due, !state.isNew {
                LabeledContent("Next review", value: due.formatted(date: .abbreviated, time: .omitted))
            }
            LabeledContent("Reviews", value: "\(state.reps)")
            LabeledContent("Lapses", value: "\(state.lapses)")
            if !state.isNew {
                LabeledContent("Interval", value: intervalText(state.intervalDays))
                LabeledContent("Ease", value: "\(Int((state.ease * 100).rounded()))%")
            }
        }
    }

    private var historySection: some View {
        Section("Answer history") {
            if history.isEmpty {
                Text("Not answered yet")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(history) { entry in
                    HStack {
                        Text(entry.grade.label)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(entry.grade.tint)
                        Spacer()
                        Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var sentencesSection: some View {
        Section("Examples") {
            ForEach(sentences) { sentence in
                VStack(alignment: .leading, spacing: 3) {
                    Text(sentence.de).font(.subheadline)
                    Text(lang == .en ? sentence.en : sentence.ru)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: - Helpers

    private var relativeLastReviewed: String {
        guard let last = state.lastReviewed else { return "Never" }
        return last.formatted(.relative(presentation: .named))
    }

    private func intervalText(_ days: Double) -> String {
        if days < 1 { return "< 1 day" }
        let rounded = Int(days.rounded())
        return rounded == 1 ? "1 day" : "\(rounded) days"
    }

    private func load() {
        state = (try? app.repository?.state(for: word.id)) ?? .newCard(word.id)
        history = (try? app.repository?.reviewHistory(for: word.id)) ?? []
        sentences = app.sentences(for: word.id)
    }
}
