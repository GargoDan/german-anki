import Foundation
import Observation

enum RootPage {
    case progress, study, settings
}

@Observable @MainActor
final class AppModel {
    private(set) var words: [Word] = []
    private(set) var wordsByID: [String: Word] = [:]
    /// Immutable groupings of the word set, built once at load so views never
    /// re-`filter` the full corpus. `wordsByTopic[level][slug]` is sorted by
    /// `display`; topic slugs repeat across levels, hence the nested keying.
    private(set) var wordsByLevel: [Level: [Word]] = [:]
    private(set) var wordsByTopic: [Level: [String: [Word]]] = [:]
    private(set) var wordCountByLevel: [Level: Int] = [:]
    private(set) var topics: [Topic] = []
    private(set) var meta: [String: String] = [:]
    private(set) var loaded = false
    private(set) var loadError: String?

    private var content: ContentDatabase?
    private(set) var repository: ProgressRepository?
    let audio = AudioPlayer()
    private(set) var study: StudyModel!
    /// Derived progress (per-level/-topic aggregates, streak, card states),
    /// computed off the main thread and only when it changed.
    private(set) var progress: ProgressStore!
    var page: RootPage = .study

    func load() async {
        guard !loaded else { return }
        do {
            let content = try ContentDatabase()
            let progressDB = try ProgressDatabase()
            let words = try content.allWords()
            self.content = content
            self.repository = ProgressRepository(db: progressDB)
            self.words = words
            self.wordsByID = Dictionary(uniqueKeysWithValues: words.map { ($0.id, $0) })
            let byLevel = Dictionary(grouping: words, by: \.level)
            self.wordsByLevel = byLevel
            self.wordsByTopic = byLevel.mapValues { levelWords in
                Dictionary(grouping: levelWords, by: \.topic).mapValues {
                    $0.sorted { $0.display.localizedCaseInsensitiveCompare($1.display) == .orderedAscending }
                }
            }
            self.wordCountByLevel = byLevel.mapValues(\.count)
            self.topics = try content.allTopics()
            self.meta = try content.meta()
            self.study = StudyModel(app: self)
            self.progress = ProgressStore(app: self)
            loaded = true
            study.showRandom()
            progress.reloadIfNeeded()
            applyDebugLaunchArguments()
        } catch {
            loadError = "Failed to load card data: \(error.localizedDescription)"
        }
    }

    func sentences(for wordID: String) -> [Sentence] {
        (try? content?.sentences(for: wordID)) ?? []
    }

    /// Debug hooks for screenshot automation: "-page progress|settings", "-reveal".
    private func applyDebugLaunchArguments() {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of: "-page"), index + 1 < args.count {
            switch args[index + 1] {
            case "progress": page = .progress
            case "settings": page = .settings
            default: break
            }
        }
        if args.contains("-reveal") {
            study.select(.good)
        }
        if args.contains("-session-complete") {
            study.debugShowSampleSummary()
        }
        #endif
    }
}
