import Foundation
import Observation

enum RootPage {
    case progress, study, settings
}

@Observable @MainActor
final class AppModel {
    private(set) var words: [Word] = []
    private(set) var wordsByID: [String: Word] = [:]
    private(set) var topics: [Topic] = []
    private(set) var meta: [String: String] = [:]
    private(set) var loaded = false
    private(set) var loadError: String?

    private var content: ContentDatabase?
    private(set) var repository: ProgressRepository?
    let audio = AudioPlayer()
    private(set) var study: StudyModel!
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
            self.topics = try content.allTopics()
            self.meta = try content.meta()
            self.study = StudyModel(app: self)
            loaded = true
            study.showRandom()
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
        #endif
    }
}
