import Foundation

struct SessionInfo: Hashable {
    let id: String
    let mode: SessionMode
    let level: Level?
    let topic: String?
    let target: Int

    var title: String {
        switch mode {
        case .goal: "Goal · \(level?.rawValue ?? "")"
        case .custom: "\(level?.rawValue ?? "All")\(topic.map { " · \($0)" } ?? "")"
        }
    }
}

/// Ordered card queue for one study session. The target is the number of
/// *distinct words to look at*: each word is shown once, and grading it with
/// any button — including "Don't know" — counts it and advances the session.
/// The SRS reschedules cards so the Anki algorithm brings them back in a later
/// session; we don't force a card to be learned before the session can finish.
@Observable
final class SessionQueue {
    let info: SessionInfo
    private(set) var pending: [String]
    private(set) var completed: Set<String> = []

    init(info: SessionInfo, pending: [String]) {
        self.info = info
        self.pending = pending
    }

    var completedCount: Int { completed.count }
    var isFinished: Bool { pending.isEmpty }

    func next() -> String? {
        pending.isEmpty ? nil : pending.removeFirst()
    }

    /// Called after committing a grade for `wordID`. Every graded word counts
    /// as looked at, whatever grade it got.
    func didGrade(wordID: String) {
        completed.insert(wordID)
    }

    // MARK: - Queue building

    static func build(info: SessionInfo, words: [Word],
                      states: [String: CardState], now: Date) -> SessionQueue {
        var rng = SystemRandomNumberGenerator()
        return build(info: info, words: words, states: states, now: now, using: &rng)
    }

    /// Seedable variant so tests get a deterministic shuffle.
    static func build<G: RandomNumberGenerator>(
        info: SessionInfo, words: [Word], states: [String: CardState],
        now: Date, using generator: inout G
    ) -> SessionQueue {
        let included: [Word]
        var newPool: [Word]
        switch info.mode {
        case .goal:
            let goal = info.level ?? .a1
            included = words.filter { $0.level <= goal }
            newPool = included.filter { $0.level == goal }
        case .custom:
            included = words.filter { w in
                (info.level == nil || w.level == info.level)
                    && (info.topic == nil || w.topic == info.topic)
            }
            newPool = included
        }

        // Cards already due (learning + review) share equal inclusion priority
        // and get shuffled so the session isn't a fixed, boring order.
        var due: [String] = []
        for word in included {
            guard let state = states[word.id], Scheduler.isDue(state, now: now) else { continue }
            due.append(word.id)
        }
        due.shuffle(using: &generator)

        // New words are picked at random rather than by frequency/alphabet.
        var newIDs = newPool.filter { states[$0.id] == nil }.map(\.id)
        newIDs.shuffle(using: &generator)

        var queue: [String]
        if due.count >= info.target {
            queue = Array(due.prefix(info.target))
        } else {
            queue = due + newIDs.prefix(info.target - due.count)
        }
        // Interleave due and new so a session reads as a varied mix.
        queue.shuffle(using: &generator)
        return SessionQueue(info: info, pending: queue)
    }
}
