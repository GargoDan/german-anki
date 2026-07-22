import Foundation

/// Two progress tiers per group:
/// - `learned` (green): word graded Good or Easy within the last 21 days —
///   immediate, and decays if you go 21 days without a passing grade. Mature
///   words always count as learned too, so `mastered` is always a subset (gold
///   sits inside green).
/// - `mastered` (gold): the rigorous bar — review state with interval ≥ 21 days.
struct LevelProgress: Identifiable {
    let level: Level
    let total: Int
    let started: Int
    let learned: Int
    let mastered: Int

    var id: String { level.rawValue }
    var learnedFraction: Double { total > 0 ? Double(learned) / Double(total) : 0 }
    var masteredFraction: Double { total > 0 ? Double(mastered) / Double(total) : 0 }
    var startedFraction: Double { total > 0 ? Double(started) / Double(total) : 0 }
    /// Headline percentage tracks the immediate "learned" tier.
    var percent: Int { Int((learnedFraction * 100).rounded()) }
    var isComplete: Bool { total > 0 && mastered == total }
}

struct TopicProgress: Identifiable {
    let topic: Topic
    let total: Int
    let started: Int
    let learned: Int
    let mastered: Int

    var id: String { topic.id }
    var learnedFraction: Double { total > 0 ? Double(learned) / Double(total) : 0 }
    var masteredFraction: Double { total > 0 ? Double(mastered) / Double(total) : 0 }
    var percent: Int { Int((learnedFraction * 100).rounded()) }
    var isComplete: Bool { total > 0 && mastered == total }
}

enum ProgressMetrics {

    static func perLevel(words: [Word], states: [String: CardState],
                         learnedIDs: Set<String>) -> [LevelProgress] {
        Level.allCases.map { level in
            let levelWords = words.filter { $0.level == level }
            var started = 0, learned = 0, mastered = 0
            for word in levelWords {
                let mature = states[word.id]?.isMature == true
                if learnedIDs.contains(word.id) || mature { learned += 1 }
                if mature { mastered += 1 }
                if states[word.id] != nil { started += 1 }
            }
            return LevelProgress(level: level, total: levelWords.count,
                                 started: started, learned: learned, mastered: mastered)
        }
    }

    static func perTopic(level: Level, words: [Word], topics: [Topic],
                         states: [String: CardState],
                         learnedIDs: Set<String>) -> [TopicProgress] {
        topics
            .filter { $0.level == level }
            .sorted { $0.ord < $1.ord }
            .map { topic in
                let topicWords = words.filter { $0.level == level && $0.topic == topic.slug }
                var started = 0, learned = 0, mastered = 0
                for word in topicWords {
                    let mature = states[word.id]?.isMature == true
                    if learnedIDs.contains(word.id) || mature { learned += 1 }
                    if mature { mastered += 1 }
                    if states[word.id] != nil { started += 1 }
                }
                return TopicProgress(topic: topic, total: topicWords.count,
                                     started: started, learned: learned, mastered: mastered)
            }
            .filter { $0.total > 0 }
    }

    /// The lowest level that isn't fully mastered yet — the default session goal.
    static func autoGoal(perLevel: [LevelProgress]) -> Level {
        perLevel.first { !$0.isComplete }?.level ?? .b2
    }
}
