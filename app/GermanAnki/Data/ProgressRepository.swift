import Foundation
import GRDB

/// One past review of a word, newest-first when returned from `reviewHistory`.
struct ReviewLogEntry: Identifiable {
    let id: Int64
    let date: Date
    let grade: Grade
    let prevInterval: Double?
    let newInterval: Double?
}

/// Typed queries over the progress database.
struct ProgressRepository {
    let db: ProgressDatabase

    func allStates() throws -> [String: CardState] {
        try db.dbQueue.read { db in
            var result: [String: CardState] = [:]
            for row in try Row.fetchAll(db, sql: "SELECT * FROM card_state") {
                let state = Self.cardState(from: row)
                result[state.wordID] = state
            }
            return result
        }
    }

    func state(for wordID: String) throws -> CardState {
        try db.dbQueue.read { db in
            guard let row = try Row.fetchOne(
                db, sql: "SELECT * FROM card_state WHERE word_id = ?", arguments: [wordID])
            else { return .newCard(wordID) }
            return Self.cardState(from: row)
        }
    }

    /// Commits one graded review: upserts the card state and appends to the log.
    func commit(previous: CardState, next: CardState, grade: Grade,
                sessionID: String?, now: Date) throws {
        try db.dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO card_state
                  (word_id, state, step, due, interval_days, ease, lapses, reps, last_reviewed)
                VALUES (?,?,?,?,?,?,?,?,?)
                ON CONFLICT(word_id) DO UPDATE SET
                  state=excluded.state, step=excluded.step, due=excluded.due,
                  interval_days=excluded.interval_days, ease=excluded.ease,
                  lapses=excluded.lapses, reps=excluded.reps,
                  last_reviewed=excluded.last_reviewed
                """, arguments: [
                    next.wordID, next.state?.rawValue, next.step,
                    next.due?.timeIntervalSince1970, next.intervalDays, next.ease,
                    next.lapses, next.reps, next.lastReviewed?.timeIntervalSince1970,
                ])
            try db.execute(sql: """
                INSERT INTO review_log
                  (word_id, ts, grade, prev_state, prev_interval, new_interval, new_ease, session_id)
                VALUES (?,?,?,?,?,?,?,?)
                """, arguments: [
                    next.wordID, now.timeIntervalSince1970, grade.rawValue,
                    previous.state?.rawValue, previous.intervalDays,
                    next.intervalDays, next.ease, sessionID,
                ])
        }
    }

    func insertSession(_ info: SessionInfo, now: Date) throws {
        try db.dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO session (session_id, mode, level, topic, target_count, started_at)
                VALUES (?,?,?,?,?,?)
                """, arguments: [
                    info.id, info.mode.rawValue, info.level?.rawValue,
                    info.topic, info.target, now.timeIntervalSince1970,
                ])
        }
    }

    func endSession(id: String, now: Date) throws {
        try db.dbQueue.write { db in
            try db.execute(sql: "UPDATE session SET ended_at = ? WHERE session_id = ?",
                           arguments: [now.timeIntervalSince1970, id])
        }
    }

    /// Word IDs graded "Good" or "Easy" at least once within the last
    /// `windowDays` — the set that counts as "learned" (the immediate, decaying
    /// progress tier). Grades are ordered dontKnow(1) < hard(2) < good(3) < easy(4).
    func learnedWordIDs(now: Date,
                        windowDays: Double = SchedulerConfig.matureIntervalDays) throws -> Set<String> {
        try db.dbQueue.read { db in
            let cutoff = (now - windowDays * 86_400).timeIntervalSince1970
            let rows = try Row.fetchAll(
                db, sql: "SELECT DISTINCT word_id FROM review_log WHERE grade >= ? AND ts >= ?",
                arguments: [Grade.good.rawValue, cutoff])
            return Set(rows.map { $0["word_id"] as String })
        }
    }

    func reviewCounts(now: Date) throws -> (total: Int, today: Int) {
        try db.dbQueue.read { db in
            let total = try Int.fetchOne(db, sql: "SELECT count(*) FROM review_log") ?? 0
            let dayStart = Scheduler.srsDayStart(now).timeIntervalSince1970
            let today = try Int.fetchOne(
                db, sql: "SELECT count(*) FROM review_log WHERE ts >= ?",
                arguments: [dayStart]) ?? 0
            return (total, today)
        }
    }

    /// Past reviews of one word, newest first.
    func reviewHistory(for wordID: String, limit: Int = 50) throws -> [ReviewLogEntry] {
        try db.dbQueue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT id, ts, grade, prev_interval, new_interval
                FROM review_log WHERE word_id = ? ORDER BY ts DESC LIMIT ?
                """, arguments: [wordID, limit]).map { row in
                ReviewLogEntry(
                    id: row["id"],
                    date: Date(timeIntervalSince1970: row["ts"]),
                    grade: Grade(rawValue: row["grade"]) ?? .good,
                    prevInterval: row["prev_interval"],
                    newInterval: row["new_interval"]
                )
            }
        }
    }

    private static func cardState(from row: Row) -> CardState {
        CardState(
            wordID: row["word_id"],
            state: SRSState(rawValue: row["state"]),
            step: row["step"],
            due: (row["due"] as Double?).map(Date.init(timeIntervalSince1970:)),
            intervalDays: row["interval_days"],
            ease: row["ease"],
            lapses: row["lapses"],
            reps: row["reps"],
            lastReviewed: (row["last_reviewed"] as Double?).map(Date.init(timeIntervalSince1970:))
        )
    }
}
