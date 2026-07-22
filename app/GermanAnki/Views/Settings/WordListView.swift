import SwiftUI

/// All words in a level, grouped by topic and searchable. Each row opens a
/// `WordDetailView` with that word's knowledge stats and review history.
struct WordListView: View {
    @Environment(AppModel.self) private var app
    @AppStorage(AppSettings.translationLangKey) private var langRaw = TranslationLang.en.rawValue

    let level: Level
    @State private var search = ""

    private var lang: TranslationLang { TranslationLang(rawValue: langRaw) ?? .en }

    private var states: [String: CardState] { app.progress.states }
    private var learnedIDs: Set<String> { app.progress.learnedIDs }

    /// This level's topics in defined order (small — ~13 items).
    private var levelTopics: [Topic] {
        app.topics.filter { $0.level == level }.sorted { $0.ord < $1.ord }
    }

    /// Words in a topic, already sorted by `display` at load — here we only
    /// apply the search predicate, so typing never re-scans or re-sorts the
    /// full corpus.
    private func words(in slug: String) -> [Word] {
        (app.wordsByTopic[level]?[slug] ?? []).filter(matches)
    }

    private func matches(_ word: Word) -> Bool {
        guard !search.isEmpty else { return true }
        return word.display.localizedCaseInsensitiveContains(search)
            || word.translation(lang).localizedCaseInsensitiveContains(search)
    }

    var body: some View {
        List {
            ForEach(levelTopics) { topic in
                let items = words(in: topic.slug)
                if !items.isEmpty {
                    Section(topic.en) {
                        ForEach(items) { word in
                            NavigationLink(value: word) {
                                WordRow(word: word, state: states[word.id],
                                        learned: learnedIDs.contains(word.id), lang: lang)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("\(level.rawValue) words")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, prompt: "Search words")
        .navigationDestination(for: Word.self) { word in
            WordDetailView(word: word)
        }
        .onAppear { app.progress.reloadIfNeeded() }
    }
}

/// One row in the word list: German word, translation, and a knowledge dot.
private struct WordRow: View {
    let word: Word
    let state: CardState?
    let learned: Bool
    let lang: TranslationLang

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(KnowledgeStyle.color(state, learned: learned))
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(word.display)
                    .font(.body)
                Text(word.translation(lang))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
    }
}

/// Shared color/label mapping for a word's knowledge state.
enum KnowledgeStyle {
    /// Green = "learned" (recent Easy). Gold = "mastered" (mature).
    static let learned = Color.green
    static let mastered = Color(red: 0.90, green: 0.71, blue: 0.16)

    /// `learned` is the recent-Easy flag, which a bare `CardState` can't know.
    static func color(_ state: CardState?, learned: Bool = false) -> Color {
        guard let state, !state.isNew else { return Color(.systemGray3) }
        if state.isMature { return mastered }
        if learned { return Self.learned }
        switch state.state {
        case .review: return .blue
        case .learning: return .orange
        case .relearning: return .red
        case .none: return Color(.systemGray3)
        }
    }

    static func label(_ state: CardState, learned: Bool = false) -> String {
        if state.isNew { return "New" }
        if state.isMature { return "Mastered" }
        if learned { return "Learned" }
        return state.knowledgeLabel
    }
}
