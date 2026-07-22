import SwiftUI

struct SessionConfigSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var level: Level = .a1
    @State private var topicSlug: String?
    @State private var count = AppSettings.defaultSessionSize

    var body: some View {
        NavigationStack {
            Form {
                Picker("Level", selection: $level) {
                    ForEach(Level.allCases) { level in
                        Text(level.rawValue).tag(level)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Topic", selection: $topicSlug) {
                    Text("All topics").tag(String?.none)
                    ForEach(app.topics.filter { $0.level == level }) { topic in
                        Text(topic.en).tag(String?.some(topic.slug))
                    }
                }

                Stepper("Cards: \(count)", value: $count, in: 5...100, step: 5)
            }
            .navigationTitle("Custom session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") {
                        app.study.startSession(mode: .custom, level: level,
                                               topic: topicSlug, target: count)
                        dismiss()
                        app.page = .study
                    }
                    .fontWeight(.semibold)
                }
            }
            .onChange(of: level) { topicSlug = nil }
        }
    }
}
