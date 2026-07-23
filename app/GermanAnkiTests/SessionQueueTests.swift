import XCTest
@testable import GermanAnki

/// Deterministic RNG (SplitMix64) so shuffled queues are stable across runs.
private struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

final class SessionQueueTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_750_000_000)

    private func word(_ id: String, level: Level, topic: String = "t", freq: Int? = nil) -> Word {
        Word(id: id, lemma: id, display: id, pos: "noun", level: level,
             topic: topic, en: "x", ru: "х", freqRank: freq, audio: "word_\(id).m4a")
    }

    private func learningState(_ id: String, dueOffset: TimeInterval) -> CardState {
        var c = CardState.newCard(id)
        c.state = .learning
        c.due = now + dueOffset
        return c
    }

    private func reviewState(_ id: String, dueOffset: TimeInterval, interval: Double = 5) -> CardState {
        var c = CardState.newCard(id)
        c.state = .review
        c.due = now + dueOffset
        c.intervalDays = interval
        return c
    }

    private func goalInfo(_ level: Level, target: Int) -> SessionInfo {
        SessionInfo(id: "s", mode: .goal, level: level, topic: nil, target: target)
    }

    private func build(_ info: SessionInfo, words: [Word], states: [String: CardState]) -> SessionQueue {
        var rng = SeededGenerator(seed: 42)
        return SessionQueue.build(info: info, words: words, states: states, now: now, using: &rng)
    }

    func testGoalIncludesDueAndNewWords() {
        let words = [
            word("new1", level: .a1, freq: 2),
            word("new2", level: .a1, freq: 1),
            word("rev", level: .a1),
            word("learn", level: .a1),
        ]
        let states = [
            "rev": reviewState("rev", dueOffset: -86_400),
            "learn": learningState("learn", dueOffset: -60),
        ]
        let queue = build(goalInfo(.a1, target: 10), words: words, states: states)
        XCTAssertEqual(Set(queue.pending), ["learn", "rev", "new1", "new2"])
    }

    func testGoalIncludesLowerLevelDueButOnlyGoalLevelNew() {
        let words = [
            word("a1rev", level: .a1),
            word("a1new", level: .a1),
            word("a2new", level: .a2, freq: 1),
        ]
        let states = ["a1rev": reviewState("a1rev", dueOffset: -86_400)]
        let queue = build(goalInfo(.a2, target: 10), words: words, states: states)
        // A1 due review included; new cards only from A2 (a1new excluded).
        XCTAssertEqual(Set(queue.pending), ["a1rev", "a2new"])
    }

    func testNotDueCardsUsedAsFillerBehindNewWords() {
        let words = [word("future", level: .a1), word("new", level: .a1)]
        let states = ["future": reviewState("future", dueOffset: 5 * 86_400)]
        let queue = build(goalInfo(.a1, target: 10), words: words, states: states)
        // New words still get in, and a not-due learned card fills the rest of
        // the session rather than being dropped.
        XCTAssertEqual(Set(queue.pending), ["new", "future"])
    }

    func testNotDueCardsRankBehindNewWhenTargetIsTight() {
        let words = [word("future", level: .a1), word("new", level: .a1)]
        let states = ["future": reviewState("future", dueOffset: 5 * 86_400)]
        let queue = build(goalInfo(.a1, target: 1), words: words, states: states)
        XCTAssertEqual(queue.pending, ["new"], "unseen words fill before not-due filler")
    }

    func testLearnedTopicFillsToTargetWithNotDueCards() {
        // A topic of 25 words, 20 learned-but-not-due, 5 due, session of 10.
        // The session should prioritise the 5 due cards and then fill up to the
        // target from the learned pool — not stop at 5.
        var words: [Word] = []
        var states: [String: CardState] = [:]
        for i in 0..<5 {
            let id = "due\(i)"
            words.append(word(id, level: .a1, topic: "food"))
            states[id] = reviewState(id, dueOffset: -86_400)
        }
        for i in 0..<20 {
            let id = "learned\(i)"
            words.append(word(id, level: .a1, topic: "food"))
            states[id] = reviewState(id, dueOffset: 5 * 86_400)
        }
        let info = SessionInfo(id: "s", mode: .custom, level: .a1, topic: "food", target: 10)
        let queue = build(info, words: words, states: states)
        XCTAssertEqual(queue.pending.count, 10, "session fills to its target")
        XCTAssertEqual(Set(queue.pending).count, 10, "no duplicates")
        for i in 0..<5 {
            XCTAssertTrue(queue.pending.contains("due\(i)"), "all due cards are included")
        }
    }

    func testTargetCapsQueue() {
        let words = (0..<30).map { (i: Int) in word("w\(i)", level: .a1, freq: i) }
        let queue = build(goalInfo(.a1, target: 10), words: words, states: [:])
        XCTAssertEqual(queue.pending.count, 10)
        XCTAssertEqual(Set(queue.pending).count, 10, "no duplicates")
    }

    func testDueCardsPrioritizedOverNewWhenTargetIsTight() {
        let words = [word("rev", level: .a1), word("new", level: .a1)]
        let states = ["rev": reviewState("rev", dueOffset: -86_400)]
        let queue = build(goalInfo(.a1, target: 1), words: words, states: states)
        XCTAssertEqual(queue.pending, ["rev"], "due cards fill the target before new ones")
    }

    func testCustomSessionFiltersLevelAndTopic() {
        let words = [
            word("a1food", level: .a1, topic: "food"),
            word("a1home", level: .a1, topic: "home"),
            word("a2food", level: .a2, topic: "food"),
        ]
        let info = SessionInfo(id: "s", mode: .custom, level: .a1, topic: "food", target: 10)
        let queue = build(info, words: words, states: [:])
        XCTAssertEqual(queue.pending, ["a1food"])
    }

    func testGradingCompletesCardRegardlessOfState() {
        let words = (0..<6).map { (i: Int) in word("w\(i)", level: .a1, freq: i) }
        let queue = build(goalInfo(.a1, target: 6), words: words, states: [:])
        let before = queue.pending.count
        let first = queue.next()!
        // A still-learning "Don't know" card still counts as looked at, and is
        // not re-inserted into this session.
        queue.didGrade(wordID: first)
        XCTAssertEqual(queue.completedCount, 1)
        XCTAssertFalse(queue.pending.contains(first))
        XCTAssertEqual(queue.pending.count, before - 1)
    }
}
