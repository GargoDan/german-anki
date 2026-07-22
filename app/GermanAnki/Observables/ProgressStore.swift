import Foundation
import Observation
import SwiftUI

/// Single source of the app's derived progress: per-level and per-topic
/// aggregates, the study streak, review counts, and the raw card states used by
/// the word list. It is recomputed **off the main thread** and only when
/// something actually changed (a grade was committed), so swiping to the
/// Progress or Settings page never blocks on a full-corpus scan or a DB read.
@Observable @MainActor
final class ProgressStore {
    private unowned let app: AppModel

    private(set) var perLevel: [LevelProgress] = []
    private(set) var topicsByLevel: [Level: [TopicProgress]] = [:]
    private(set) var streak: StreakInfo = .none
    private(set) var reviewsTotal = 0
    private(set) var reviewsToday = 0
    /// Full card states, needed by `WordListView` for its per-row knowledge dots.
    private(set) var states: [String: CardState] = [:]
    private(set) var learnedIDs: Set<String> = []

    private var dirty = true
    private var loading = false

    init(app: AppModel) {
        self.app = app
    }

    /// Mark the derived data stale; the next `reloadIfNeeded()` recomputes it.
    func markDirty() {
        dirty = true
    }

    /// Recompute if something changed since the last load and no load is already
    /// in flight — a cheap no-op otherwise, so views may call it freely on
    /// appearance or page change.
    func reloadIfNeeded() {
        guard dirty, !loading else { return }
        reload()
    }

    private func reload() {
        guard let repo = app.repository else { return }
        loading = true
        dirty = false
        // Capture the immutable inputs on the main actor, then compute on a
        // background task and publish the result back on the main actor.
        let wordsByLevel = app.wordsByLevel
        let wordsByTopic = app.wordsByTopic
        let topics = app.topics
        let now = Date.now
        Task.detached(priority: .userInitiated) {
            let snapshot = Self.compute(repo: repo, wordsByLevel: wordsByLevel,
                                        wordsByTopic: wordsByTopic, topics: topics, now: now)
            await MainActor.run { [weak self] in
                self?.apply(snapshot)
            }
        }
    }

    private func apply(_ snapshot: Snapshot) {
        perLevel = snapshot.perLevel
        topicsByLevel = snapshot.topicsByLevel
        reviewsTotal = snapshot.reviewsTotal
        reviewsToday = snapshot.reviewsToday
        states = snapshot.states
        learnedIDs = snapshot.learnedIDs
        withAnimation(.easeInOut(duration: 0.3)) {
            streak = snapshot.streak
        }
        loading = false
        // A grade committed while we were computing re-dirties us; catch up.
        if dirty { reload() }
    }

    private struct Snapshot: Sendable {
        let perLevel: [LevelProgress]
        let topicsByLevel: [Level: [TopicProgress]]
        let streak: StreakInfo
        let reviewsTotal: Int
        let reviewsToday: Int
        let states: [String: CardState]
        let learnedIDs: Set<String>
    }

    /// Pure, main-actor-free aggregation over the pre-grouped word buckets.
    private nonisolated static func compute(repo: ProgressRepository,
                                wordsByLevel: [Level: [Word]],
                                wordsByTopic: [Level: [String: [Word]]],
                                topics: [Topic], now: Date) -> Snapshot {
        let states = (try? repo.allStates()) ?? [:]
        let learnedIDs = (try? repo.learnedWordIDs(now: now)) ?? []
        let streak = (try? repo.streak(now: now)) ?? .none
        let counts = (try? repo.reviewCounts(now: now)) ?? (total: 0, today: 0)

        let perLevel = ProgressMetrics.perLevel(
            wordsByLevel: wordsByLevel, states: states, learnedIDs: learnedIDs)
        var topicsByLevel: [Level: [TopicProgress]] = [:]
        for level in Level.allCases {
            topicsByLevel[level] = ProgressMetrics.perTopic(
                level: level, topics: topics, wordsByTopicSlug: wordsByTopic[level] ?? [:],
                states: states, learnedIDs: learnedIDs)
        }
        return Snapshot(perLevel: perLevel, topicsByLevel: topicsByLevel, streak: streak,
                        reviewsTotal: counts.total, reviewsToday: counts.today,
                        states: states, learnedIDs: learnedIDs)
    }
}
