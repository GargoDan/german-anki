import SwiftUI

/// Statistics sections embedded in the Settings form.
struct StatsView: View {
    @Environment(AppModel.self) private var app

    private var perLevel: [LevelProgress] { app.progress.perLevel }

    var body: some View {
        Section("Statistics") {
            LabeledContent("Words learned",
                           value: "\(perLevel.map(\.learned).reduce(0, +)) / \(app.words.count)")
            LabeledContent("Words mastered",
                           value: "\(perLevel.map(\.mastered).reduce(0, +)) / \(app.words.count)")
            LabeledContent("Reviews today", value: "\(app.progress.reviewsToday)")
            LabeledContent("Total reviews", value: "\(app.progress.reviewsTotal)")
        }
        Section("By level") {
            ForEach(perLevel) { progress in
                DisclosureGroup {
                    ForEach(app.progress.topicsByLevel[progress.level] ?? []) { topicProgress in
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
        .onAppear { app.progress.reloadIfNeeded() }
        // The Settings tab stays alive in the paged TabView, so onAppear only
        // fires once. Re-check whenever it scrolls back into view so reviews
        // logged during a study session show up immediately (the store no-ops
        // unless a grade was actually committed).
        .onChange(of: app.page) { _, page in
            if page == .settings { app.progress.reloadIfNeeded() }
        }
    }
}
