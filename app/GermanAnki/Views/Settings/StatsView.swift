import SwiftUI

/// Statistics sections embedded in the Settings form.
struct StatsView: View {
    @Environment(AppModel.self) private var app
    @State private var perLevel: [LevelProgress] = []
    @State private var states: [String: CardState] = [:]
    @State private var learnedIDs: Set<String> = []
    @State private var reviewsTotal = 0
    @State private var reviewsToday = 0

    var body: some View {
        Section("Statistics") {
            LabeledContent("Words learned",
                           value: "\(perLevel.map(\.learned).reduce(0, +)) / \(app.words.count)")
            LabeledContent("Words mastered",
                           value: "\(perLevel.map(\.mastered).reduce(0, +)) / \(app.words.count)")
            LabeledContent("Reviews today", value: "\(reviewsToday)")
            LabeledContent("Total reviews", value: "\(reviewsTotal)")
        }
        Section("By level") {
            ForEach(perLevel) { progress in
                DisclosureGroup {
                    ForEach(ProgressMetrics.perTopic(level: progress.level, words: app.words,
                                                     topics: app.topics, states: states,
                                                     learnedIDs: learnedIDs)) { topicProgress in
                        LabeledContent(topicProgress.topic.en,
                                       value: "\(topicProgress.learned)/\(topicProgress.total)")
                            .font(.subheadline)
                    }
                } label: {
                    LabeledContent(progress.level.rawValue,
                                   value: "\(progress.learned) learned · \(progress.mastered) mastered")
                }
            }
        }
        .onAppear(perform: refresh)
        // The Settings tab stays alive in the paged TabView, so onAppear only
        // fires once. Re-read whenever it scrolls back into view so reviews
        // logged during a study session show up immediately.
        .onChange(of: app.page) { _, page in
            if page == .settings { refresh() }
        }
    }

    private func refresh() {
        states = (try? app.repository?.allStates()) ?? [:]
        learnedIDs = (try? app.repository?.learnedWordIDs(now: .now)) ?? []
        perLevel = ProgressMetrics.perLevel(words: app.words, states: states, learnedIDs: learnedIDs)
        if let counts = try? app.repository?.reviewCounts(now: .now) {
            reviewsTotal = counts.total
            reviewsToday = counts.today
        }
    }
}
