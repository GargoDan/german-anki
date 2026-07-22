import XCTest
import GRDB
@testable import GermanAnki

final class StreakTests: XCTestCase {
    private var db: ProgressDatabase!
    private var repo: ProgressRepository!
    private let cal = Calendar.current

    override func setUpWithError() throws {
        db = try ProgressDatabase.inMemory()
        repo = ProgressRepository(db: db)
    }

    /// Logs one review during the SRS-day that contains `date` (noon-ish, safely
    /// past the 04:00 rollover).
    private func logReview(on date: Date) throws {
        let ts = (Scheduler.srsDayStart(date, calendar: cal) + 12 * 3600).timeIntervalSince1970
        try db.dbQueue.write { db in
            try db.execute(
                sql: "INSERT INTO review_log (word_id, ts, grade) VALUES (?,?,?)",
                arguments: ["w", ts, Grade.good.rawValue])
        }
    }

    private func day(_ offset: Int, from now: Date) -> Date {
        cal.date(byAdding: .day, value: offset, to: now)!
    }

    func testNoReviewsIsEmptyStreak() throws {
        XCTAssertEqual(try repo.streak(now: .now), .none)
    }

    func testConsecutiveDaysCountAndTodayIsGold() throws {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        for offset in -2...0 { try logReview(on: day(offset, from: now)) }
        let streak = try repo.streak(now: now, calendar: cal)
        XCTAssertEqual(streak.count, 3)
        XCTAssertTrue(streak.studiedToday)
    }

    func testYesterdayOnlyKeepsStreakAliveButNotGold() throws {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        try logReview(on: day(-2, from: now))
        try logReview(on: day(-1, from: now))
        let streak = try repo.streak(now: now, calendar: cal)
        XCTAssertEqual(streak.count, 2)
        XCTAssertFalse(streak.studiedToday, "hasn't studied today yet")
    }

    func testGapBreaksStreak() throws {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        try logReview(on: day(-5, from: now))  // stale, gap after it
        try logReview(on: day(0, from: now))   // today
        let streak = try repo.streak(now: now, calendar: cal)
        XCTAssertEqual(streak.count, 1)
        XCTAssertTrue(streak.studiedToday)
    }

    /// Many reviews within a single SRS-day must collapse to one active day —
    /// guards the SQL `GROUP BY date(...)` dedup against `srsDayStart` semantics.
    func testMultipleReviewsSameDayCountAsOneDay() throws {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let dayStart = Scheduler.srsDayStart(now, calendar: cal)
        for hourOffset in [1.0, 5.0, 9.0, 15.0] {  // all inside today's SRS-day
            let ts = (dayStart + hourOffset * 3600).timeIntervalSince1970
            try db.dbQueue.write { db in
                try db.execute(
                    sql: "INSERT INTO review_log (word_id, ts, grade) VALUES (?,?,?)",
                    arguments: ["w", ts, Grade.good.rawValue])
            }
        }
        try logReview(on: day(-1, from: now))  // one more, yesterday
        let streak = try repo.streak(now: now, calendar: cal)
        XCTAssertEqual(streak.count, 2)  // today + yesterday, today counted once
        XCTAssertTrue(streak.studiedToday)
    }

    func testTwoDayGapWithNoTodayResetsToZero() throws {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        try logReview(on: day(-3, from: now))
        let streak = try repo.streak(now: now, calendar: cal)
        XCTAssertEqual(streak, .none)
    }
}
