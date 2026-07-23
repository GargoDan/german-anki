import XCTest
@testable import GermanAnki

final class SchedulerTests: XCTestCase {
    // A fixed noon "now" keeps SRS-day math (04:00 rollover) predictable.
    let noon = Calendar.current.date(
        bySettingHour: 12, minute: 0, second: 0, of: Date(timeIntervalSince1970: 1_750_000_000))!

    func testNewCardDontKnowEntersFirstStep() {
        let next = Scheduler.apply(.dontKnow, to: .newCard("w"), now: noon)
        XCTAssertEqual(next.state, .learning)
        XCTAssertEqual(next.step, 0)
        XCTAssertEqual(next.due, noon + 60)
    }

    func testNewCardGoodAdvancesToSecondStep() {
        let next = Scheduler.apply(.good, to: .newCard("w"), now: noon)
        XCTAssertEqual(next.state, .learning)
        XCTAssertEqual(next.step, 1)
        XCTAssertEqual(next.due, noon + 600)
    }

    func testGoodOnLastStepGraduatesAtOneDay() {
        var card = Scheduler.apply(.good, to: .newCard("w"), now: noon)
        card = Scheduler.apply(.good, to: card, now: noon + 600)
        XCTAssertEqual(card.state, .review)
        XCTAssertEqual(card.intervalDays, 1)
        let dayStart = Scheduler.srsDayStart(noon + 600)
        XCTAssertEqual(card.due, dayStart + 86_400)
    }

    func testEasyOnNewCardGraduatesAtFourDays() {
        let next = Scheduler.apply(.easy, to: .newCard("w"), now: noon)
        XCTAssertEqual(next.state, .review)
        XCTAssertEqual(next.intervalDays, 4)
    }

    func testHardRepeatsCurrentStep() {
        var card = Scheduler.apply(.good, to: .newCard("w"), now: noon)  // step 1
        card = Scheduler.apply(.hard, to: card, now: noon + 300)
        XCTAssertEqual(card.state, .learning)
        XCTAssertEqual(card.step, 1)
        XCTAssertEqual(card.due, noon + 300 + 600)
    }

    private func reviewCard(interval: Double, ease: Double = 2.5, reps: Int = 5) -> CardState {
        var card = CardState.newCard("w")
        card.state = .review
        card.intervalDays = interval
        card.ease = ease
        card.reps = reps
        // A real graduated review card always carries a due date; put it in the
        // past so the card is due and grades follow the normal scheduling path.
        card.due = noon - 86_400
        return card
    }

    func testGoodOnReviewMultipliesByEase() {
        let next = Scheduler.apply(.good, to: reviewCard(interval: 10), now: noon)
        // 10 × 2.5 = 25, ±5 % fuzz
        XCTAssertEqual(next.intervalDays, 25, accuracy: 25 * 0.051)
        XCTAssertEqual(next.ease, 2.5)
    }

    func testHardOnReviewReducesEase() {
        let next = Scheduler.apply(.hard, to: reviewCard(interval: 10), now: noon)
        XCTAssertEqual(next.intervalDays, 12, accuracy: 12 * 0.051)
        XCTAssertEqual(next.ease, 2.35, accuracy: 0.001)
    }

    func testEasyOnReviewAddsBonusAndEase() {
        let next = Scheduler.apply(.easy, to: reviewCard(interval: 10), now: noon)
        // 10 × 2.5 × 1.3 = 32.5 with old ease, then ease bumps
        XCTAssertEqual(next.intervalDays, 32.5, accuracy: 32.5 * 0.051)
        XCTAssertEqual(next.ease, 2.65, accuracy: 0.001)
    }

    func testLapseHalvesIntervalAndEntersRelearning() {
        let next = Scheduler.apply(.dontKnow, to: reviewCard(interval: 10), now: noon)
        XCTAssertEqual(next.state, .relearning)
        XCTAssertEqual(next.lapses, 1)
        XCTAssertEqual(next.intervalDays, 5)
        XCTAssertEqual(next.ease, 2.3, accuracy: 0.001)
        XCTAssertEqual(next.due, noon + 600)
    }

    func testRelearningGoodReturnsToReviewWithHalvedInterval() {
        var card = Scheduler.apply(.dontKnow, to: reviewCard(interval: 10), now: noon)
        card = Scheduler.apply(.good, to: card, now: noon + 600)
        XCTAssertEqual(card.state, .review)
        XCTAssertEqual(card.intervalDays, 5)
    }

    func testEaseNeverDropsBelowFloor() {
        var card = reviewCard(interval: 50, ease: 1.35)
        card = Scheduler.apply(.dontKnow, to: card, now: noon)
        XCTAssertEqual(card.ease, SchedulerConfig.easeFloor)
    }

    func testIntervalCappedAtMax() {
        let next = Scheduler.apply(.good, to: reviewCard(interval: 300), now: noon)
        XCTAssertEqual(next.intervalDays, SchedulerConfig.maxIntervalDays)
    }

    func testFuzzIsDeterministic() {
        XCTAssertEqual(Scheduler.fuzzFactor(wordID: "abend-n", reps: 3),
                       Scheduler.fuzzFactor(wordID: "abend-n", reps: 3))
        let a = Scheduler.apply(.good, to: reviewCard(interval: 10), now: noon)
        let b = Scheduler.apply(.good, to: reviewCard(interval: 10), now: noon)
        XCTAssertEqual(a.intervalDays, b.intervalDays)
    }

    func testSRSDayRolloverAtFourAM() {
        let calendar = Calendar.current
        let base = Date(timeIntervalSince1970: 1_750_000_000)
        let at359 = calendar.date(bySettingHour: 3, minute: 59, second: 0, of: base)!
        let at401 = calendar.date(bySettingHour: 4, minute: 1, second: 0, of: base)!
        let boundary = calendar.date(bySettingHour: 4, minute: 0, second: 0, of: base)!
        XCTAssertEqual(Scheduler.srsDayStart(at401), boundary)
        XCTAssertEqual(Scheduler.srsDayStart(at359),
                       calendar.date(byAdding: .day, value: -1, to: boundary))
    }

    // MARK: - Early-practice guard

    /// A card reviewed well before its due date is not in the review helper's
    /// past-due default, so build one due in the future.
    private func notDueReviewCard(interval: Double, ease: Double = 2.5) -> CardState {
        var card = reviewCard(interval: interval, ease: ease)
        card.due = noon + interval * 86_400
        return card
    }

    func testEarlyGoodDoesNotAdvanceSchedule() {
        let card = notDueReviewCard(interval: 30)
        let next = Scheduler.apply(.good, to: card, now: noon)
        // Interval, ease, and due are untouched — only the rep is logged.
        XCTAssertEqual(next.intervalDays, 30)
        XCTAssertEqual(next.ease, card.ease)
        XCTAssertEqual(next.due, card.due)
        XCTAssertEqual(next.reps, card.reps + 1)
        XCTAssertEqual(next.lastReviewed, noon)
    }

    func testEarlyEasyCannotInflateInterval() {
        let card = notDueReviewCard(interval: 30)
        let next = Scheduler.apply(.easy, to: card, now: noon)
        XCTAssertEqual(next.intervalDays, 30, "cramming an easy card early can't push it out")
        XCTAssertEqual(next.due, card.due)
    }

    func testRepeatedEarlyReviewNeverMovesDueDate() {
        var card = notDueReviewCard(interval: 30)
        let originalDue = card.due
        for i in 0..<10 {
            card = Scheduler.apply(.good, to: card, now: noon + Double(i) * 60)
        }
        XCTAssertEqual(card.due, originalDue, "ten early reviews leave the schedule fixed")
        XCTAssertEqual(card.intervalDays, 30)
    }

    func testEarlyDontKnowStillLapses() {
        let card = notDueReviewCard(interval: 30)
        let next = Scheduler.apply(.dontKnow, to: card, now: noon)
        // Forgetting is a real signal even when reviewing early: the card lapses.
        XCTAssertEqual(next.state, .relearning)
        XCTAssertEqual(next.lapses, 1)
        XCTAssertEqual(next.due, noon + SchedulerConfig.relearningSteps[0])
    }

    func testNewCardStillProgressesWhenNotDue() {
        // A brand-new card has no due date (isDue == false) but must still learn.
        let next = Scheduler.apply(.good, to: .newCard("w"), now: noon)
        XCTAssertEqual(next.state, .learning)
        XCTAssertEqual(next.step, 1)
    }

    func testDueReviewStillReschedulesNormally() {
        // The guard must not touch genuinely-due cards.
        let next = Scheduler.apply(.good, to: reviewCard(interval: 10), now: noon)
        XCTAssertEqual(next.intervalDays, 25, accuracy: 25 * 0.051)
    }

    func testReviewDueWithinSRSDay() {
        // Graduated today -> due tomorrow, not today.
        var card = Scheduler.apply(.good, to: .newCard("w"), now: noon)
        card = Scheduler.apply(.good, to: card, now: noon)
        XCTAssertFalse(Scheduler.isDue(card, now: noon + 3600))
        XCTAssertTrue(Scheduler.isDue(card, now: noon + 86_400))
    }
}
