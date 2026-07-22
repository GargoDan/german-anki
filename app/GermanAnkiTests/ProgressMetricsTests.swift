import XCTest
@testable import GermanAnki

final class ProgressMetricsTests: XCTestCase {

    private func word(_ id: String, level: Level, topic: String = "t") -> Word {
        Word(id: id, lemma: id, display: id, pos: "noun", level: level,
             topic: topic, en: "x", ru: "х", audio: "word_\(id).m4a")
    }

    private func state(_ id: String, srs: SRSState, interval: Double) -> CardState {
        var c = CardState.newCard(id)
        c.state = srs
        c.intervalDays = interval
        return c
    }

    func testLearnedCountsRecentEasyOrMature() {
        let words = [word("a", level: .a1), word("b", level: .a1),
                     word("c", level: .a1), word("d", level: .a2)]
        let states = [
            "a": state("a", srs: .review, interval: 30),   // mature -> learned + mastered
            "b": state("b", srs: .review, interval: 5),    // young, but recent Easy -> learned
            "c": state("c", srs: .learning, interval: 0),  // learning, no Easy -> started only
        ]
        let learnedIDs: Set<String> = ["b"]  // graded Easy in the last 21 days
        let perLevel = ProgressMetrics.perLevel(
            wordsByLevel: Dictionary(grouping: words, by: \.level),
            states: states, learnedIDs: learnedIDs)
        let a1 = perLevel.first { $0.level == .a1 }!
        XCTAssertEqual(a1.total, 3)
        XCTAssertEqual(a1.started, 3)
        XCTAssertEqual(a1.learned, 2)   // a (mature) + b (recent Easy)
        XCTAssertEqual(a1.mastered, 1)  // a only
        XCTAssertEqual(a1.learnedFraction, 2.0 / 3.0, accuracy: 0.0001)
        let a2 = perLevel.first { $0.level == .a2 }!
        XCTAssertEqual(a2.started, 0)
    }

    func testMasteredIsAlwaysSubsetOfLearned() {
        // A word mastered by repeated Good (no recent Easy) still counts as learned.
        let words = [word("a", level: .a1)]
        let states = ["a": state("a", srs: .review, interval: 40)]
        let perLevel = ProgressMetrics.perLevel(
            wordsByLevel: Dictionary(grouping: words, by: \.level),
            states: states, learnedIDs: [])
        let a1 = perLevel.first { $0.level == .a1 }!
        XCTAssertEqual(a1.learned, 1)
        XCTAssertEqual(a1.mastered, 1)
        XCTAssertGreaterThanOrEqual(a1.learnedFraction, a1.masteredFraction)
    }

    func testAutoGoalIsLowestNotFullyMasteredLevel() {
        let words = [word("a", level: .a1), word("b", level: .a2)]
        let allMatureA1 = ["a": state("a", srs: .review, interval: 30)]
        let byLevel = Dictionary(grouping: words, by: \.level)
        let perLevel = ProgressMetrics.perLevel(wordsByLevel: byLevel, states: allMatureA1, learnedIDs: [])
        XCTAssertEqual(ProgressMetrics.autoGoal(perLevel: perLevel), .a2)
        XCTAssertEqual(ProgressMetrics.autoGoal(perLevel:
            ProgressMetrics.perLevel(wordsByLevel: byLevel, states: [:], learnedIDs: [])), .a1)
    }

    func testPerTopicCounts() {
        let topics = [Topic(level: .a1, slug: "food", de: "Essen", en: "Food", ord: 0),
                      Topic(level: .a1, slug: "home", de: "Wohnen", en: "Home", ord: 1),
                      Topic(level: .a1, slug: "empty", de: "Leer", en: "Empty", ord: 2)]
        let words = [word("a", level: .a1, topic: "food"),
                     word("b", level: .a1, topic: "food"),
                     word("c", level: .a1, topic: "home")]
        let states = ["a": state("a", srs: .review, interval: 30),
                      "b": state("b", srs: .learning, interval: 0)]
        let perTopic = ProgressMetrics.perTopic(
            level: .a1, topics: topics,
            wordsByTopicSlug: Dictionary(grouping: words, by: \.topic),
            states: states, learnedIDs: ["b"])
        XCTAssertEqual(perTopic.count, 2)  // empty topic dropped
        XCTAssertEqual(perTopic[0].topic.slug, "food")
        XCTAssertEqual(perTopic[0].learned, 2)   // a mature + b recent Easy
        XCTAssertEqual(perTopic[0].mastered, 1)  // a only
        XCTAssertEqual(perTopic[0].total, 2)
    }
}
