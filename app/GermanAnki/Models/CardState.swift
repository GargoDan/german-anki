import Foundation

/// SRS state of one word. A word with no stored row is "new" (`state == nil`).
struct CardState: Hashable {
    var wordID: String
    var state: SRSState?
    var step: Int = 0
    var due: Date?
    var intervalDays: Double = 0
    var ease: Double = SchedulerConfig.startingEase
    var lapses: Int = 0
    var reps: Int = 0
    var lastReviewed: Date?

    static func newCard(_ wordID: String) -> CardState {
        CardState(wordID: wordID)
    }

    var isNew: Bool { state == nil }
    var isMature: Bool {
        state == .review && intervalDays >= SchedulerConfig.matureIntervalDays
    }

    /// Human-readable knowledge level, e.g. "Mastered", "Reviewing", "Learning", "New".
    var knowledgeLabel: String {
        if isNew { return "New" }
        switch state {
        case .review: return isMature ? "Mastered" : "Reviewing"
        case .learning: return "Learning"
        case .relearning: return "Relearning"
        case .none: return "New"
        }
    }

    /// 0…1 confidence estimate for a simple meter (grows toward the mature interval).
    var strength: Double {
        guard !isNew else { return 0 }
        let capped = min(intervalDays, SchedulerConfig.matureIntervalDays)
        return max(0.05, capped / SchedulerConfig.matureIntervalDays)
    }
}
