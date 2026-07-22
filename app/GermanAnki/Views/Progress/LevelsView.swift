import SwiftUI

struct LevelsView: View {
    @Environment(AppModel.self) private var app
    @AppStorage(AppSettings.defaultSessionSizeKey) private var defaultSize = 20
    @AppStorage(AppSettings.selectedLevelKey) private var selectedRaw = ""

    @State private var progress: [LevelProgress] = []
    @State private var states: [String: CardState] = [:]
    @State private var learnedIDs: Set<String> = []
    @State private var showCustomSheet = false
    @State private var pendingTopic: TopicProgress?

    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    private var autoGoal: Level {
        AppSettings.goalLevel ?? ProgressMetrics.autoGoal(perLevel: progress)
    }

    /// The level the user is currently browsing (persisted; defaults to the goal).
    private var selectedLevel: Level {
        Level(rawValue: selectedRaw) ?? autoGoal
    }

    private var selectedProgress: LevelProgress? {
        progress.first { $0.level == selectedLevel }
    }

    private var topics: [TopicProgress] {
        ProgressMetrics.perTopic(level: selectedLevel, words: app.words,
                                 topics: app.topics, states: states, learnedIDs: learnedIDs)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Learn German")
                    .font(.largeTitle.bold())
                    .padding(.top, 20)

                VStack(alignment: .leading, spacing: 10) {
                    Text("I'm learning")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    LevelSelectorRow(progress: progress, selected: selectedBinding)
                }

                if let selectedProgress {
                    LevelProgressBar(progress: selectedProgress)
                        .padding(.top, 2)
                }

                HStack(alignment: .firstTextBaseline) {
                    Text("Topics")
                        .font(.title2.bold())
                    Spacer()
                    Text("Tap one to study")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 4)

                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(topics) { topicProgress in
                        Button {
                            pendingTopic = topicProgress
                        } label: {
                            TopicGridCard(progress: topicProgress)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("topic-\(topicProgress.topic.slug)")
                    }
                }

                startButtons
                    .padding(.top, 8)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
        .background(Color(.systemGroupedBackground))
        .onAppear(perform: refresh)
        .sheet(isPresented: $showCustomSheet) {
            SessionConfigSheet()
                .presentationDetents([.medium])
        }
        .sheet(item: $pendingTopic) { topic in
            TopicStartSheet(topic: topic, level: selectedLevel)
                .presentationDetents([.medium])
        }
    }

    private var startButtons: some View {
        VStack(spacing: 12) {
            Button {
                app.study.startSession(mode: .goal, level: selectedLevel, topic: nil,
                                       target: defaultSize)
                app.page = .study
            } label: {
                VStack(spacing: 2) {
                    Text("Start \(selectedLevel.rawValue) session")
                        .font(.headline)
                    Text("All topics · \(defaultSize) cards")
                        .font(.caption)
                        .opacity(0.85)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(selectedLevel.tint)
            .accessibilityIdentifier("startSession")

            Button("Custom session…") {
                showCustomSheet = true
            }
            .font(.subheadline)
        }
    }

    private var selectedBinding: Binding<Level> {
        Binding(get: { selectedLevel }, set: { selectedRaw = $0.rawValue })
    }

    private func refresh() {
        states = (try? app.repository?.allStates()) ?? [:]
        learnedIDs = (try? app.repository?.learnedWordIDs(now: .now)) ?? []
        progress = ProgressMetrics.perLevel(words: app.words, states: states, learnedIDs: learnedIDs)
    }
}
