import Foundation
import GRDB

/// The mutable SRS-state database in Application Support. App updates replace
/// the bundle (content DB) but never touch this file.
final class ProgressDatabase: Sendable {
    let dbQueue: DatabaseQueue

    /// - Parameter path: override for tests (":memory:" style via `inMemory`).
    init(path: String? = nil) throws {
        if let path {
            dbQueue = try DatabaseQueue(path: path)
        } else {
            let dir = try FileManager.default
                .url(for: .applicationSupportDirectory, in: .userDomainMask,
                     appropriateFor: nil, create: true)
                .appendingPathComponent("GermanAnki", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            dbQueue = try DatabaseQueue(path: dir.appendingPathComponent("progress.sqlite").path)
        }
        try Self.migrator.migrate(dbQueue)
    }

    static func inMemory() throws -> ProgressDatabase {
        try ProgressDatabase(path: ":memory:")
    }

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.execute(sql: """
                CREATE TABLE card_state (
                  word_id       TEXT PRIMARY KEY,
                  state         INTEGER NOT NULL,
                  step          INTEGER NOT NULL DEFAULT 0,
                  due           REAL,
                  interval_days REAL NOT NULL DEFAULT 0,
                  ease          REAL NOT NULL DEFAULT 2.5,
                  lapses        INTEGER NOT NULL DEFAULT 0,
                  reps          INTEGER NOT NULL DEFAULT 0,
                  last_reviewed REAL
                );
                CREATE INDEX idx_cs_due ON card_state(due);

                CREATE TABLE review_log (
                  id INTEGER PRIMARY KEY AUTOINCREMENT,
                  word_id TEXT NOT NULL,
                  ts REAL NOT NULL,
                  grade INTEGER NOT NULL,
                  prev_state INTEGER,
                  prev_interval REAL,
                  new_interval REAL,
                  new_ease REAL,
                  session_id TEXT
                );
                CREATE INDEX idx_log_word ON review_log(word_id);
                CREATE INDEX idx_log_ts ON review_log(ts);

                CREATE TABLE session (
                  session_id TEXT PRIMARY KEY,
                  mode TEXT NOT NULL,
                  level TEXT,
                  topic TEXT,
                  target_count INTEGER NOT NULL,
                  started_at REAL NOT NULL,
                  ended_at REAL
                );
                """)
        }
        return migrator
    }
}
