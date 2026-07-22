import Foundation

/// Pure SM-2 scheduling logic. No I/O — takes a card state, returns the next one.
enum Scheduler {

    static func apply(_ grade: Grade, to card: CardState, now: Date) -> CardState {
        var c = card
        c.reps += 1
        c.lastReviewed = now
        switch card.state {
        case nil:
            c.state = .learning
            c.step = 0
            answerLearning(&c, grade: grade, now: now)
        case .learning, .relearning:
            answerLearning(&c, grade: grade, now: now)
        case .review:
            answerReview(&c, grade: grade, now: now)
        }
        return c
    }

    // MARK: - Learning / relearning

    private static func answerLearning(_ c: inout CardState, grade: Grade, now: Date) {
        let steps = c.state == .relearning
            ? SchedulerConfig.relearningSteps : SchedulerConfig.learningSteps
        switch grade {
        case .dontKnow:
            c.step = 0
            c.due = now + steps[0]
        case .hard:
            c.due = now + steps[min(c.step, steps.count - 1)]
        case .good:
            if c.step + 1 < steps.count {
                c.step += 1
                c.due = now + steps[c.step]
            } else {
                graduate(&c, now: now, easy: false)
            }
        case .easy:
            graduate(&c, now: now, easy: true)
        }
    }

    private static func graduate(_ c: inout CardState, now: Date, easy: Bool) {
        if c.state == .relearning {
            // Post-lapse interval was already set when the lapse happened.
            c.intervalDays = max(1, c.intervalDays)
        } else {
            c.intervalDays = easy
                ? SchedulerConfig.easyIntervalDays : SchedulerConfig.graduatingIntervalDays
        }
        c.state = .review
        c.step = 0
        c.due = reviewDue(after: c.intervalDays, now: now)
    }

    // MARK: - Review

    private static func answerReview(_ c: inout CardState, grade: Grade, now: Date) {
        switch grade {
        case .dontKnow:
            c.lapses += 1
            c.ease = max(SchedulerConfig.easeFloor, c.ease + SchedulerConfig.lapseEaseDelta)
            c.state = .relearning
            c.step = 0
            c.intervalDays = max(1, c.intervalDays * SchedulerConfig.lapseIntervalMultiplier)
            c.due = now + SchedulerConfig.relearningSteps[0]
            return
        case .hard:
            c.ease = max(SchedulerConfig.easeFloor, c.ease + SchedulerConfig.hardEaseDelta)
            reschedule(&c, rawInterval: c.intervalDays * SchedulerConfig.hardIntervalMultiplier, now: now)
        case .good:
            reschedule(&c, rawInterval: c.intervalDays * c.ease, now: now)
        case .easy:
            let raw = c.intervalDays * c.ease * SchedulerConfig.easyBonus
            c.ease += SchedulerConfig.easyEaseDelta
            reschedule(&c, rawInterval: raw, now: now)
        }
    }

    private static func reschedule(_ c: inout CardState, rawInterval: Double, now: Date) {
        var interval = max(c.intervalDays + 1, rawInterval)
        interval *= fuzzFactor(wordID: c.wordID, reps: c.reps)
        interval = min(SchedulerConfig.maxIntervalDays, max(1, interval))
        c.intervalDays = interval
        c.due = reviewDue(after: interval, now: now)
    }

    /// Deterministic per (wordID, reps) so tests are stable and repeated
    /// computation of a pending grade gives the same projection.
    static func fuzzFactor(wordID: String, reps: Int) -> Double {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in wordID.utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x100000001b3
        }
        hash = (hash ^ UInt64(reps)) &* 0x100000001b3
        let unit = Double(hash % 10_000) / 10_000.0
        return 1.0 + (unit * 2 - 1) * SchedulerConfig.fuzz
    }

    // MARK: - SRS day boundaries (04:00 rollover)

    static func srsDayStart(_ now: Date, calendar: Calendar = .current) -> Date {
        let boundary = calendar.date(
            bySettingHour: SchedulerConfig.rolloverHour, minute: 0, second: 0, of: now)!
        return boundary <= now ? boundary : calendar.date(byAdding: .day, value: -1, to: boundary)!
    }

    static func nextRollover(_ now: Date, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: 1, to: srsDayStart(now, calendar: calendar))!
    }

    private static func reviewDue(after days: Double, now: Date) -> Date {
        srsDayStart(now) + days * 86_400
    }

    /// Learning cards are due at their exact timestamp; review cards are due
    /// any time within their SRS day.
    static func isDue(_ card: CardState, now: Date) -> Bool {
        guard let state = card.state, let due = card.due else { return false }
        switch state {
        case .learning, .relearning: return due <= now
        case .review: return due < nextRollover(now)
        }
    }
}
