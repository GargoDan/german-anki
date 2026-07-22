import Foundation
import GRDB

/// Read-only access to the bundled content.sqlite built by pipeline/09_build_app_db.py.
final class ContentDatabase {
    private let dbQueue: DatabaseQueue

    init() throws {
        guard let url = Bundle.main.url(forResource: "content", withExtension: "sqlite") else {
            throw DatabaseError(message: "content.sqlite missing from app bundle")
        }
        var config = Configuration()
        config.readonly = true
        dbQueue = try DatabaseQueue(path: url.path, configuration: config)
    }

    func allWords() throws -> [Word] {
        try dbQueue.read { db in
            try Word.fetchAll(db, sql: "SELECT * FROM word")
        }
    }

    func sentences(for wordID: String) throws -> [Sentence] {
        try dbQueue.read { db in
            try Sentence.fetchAll(db, sql: """
                SELECT s.* FROM sentence s
                JOIN word_sentence ws ON ws.sent_id = s.sent_id
                WHERE ws.word_id = ? ORDER BY ws.ord
                """, arguments: [wordID])
        }
    }

    func allTopics() throws -> [Topic] {
        try dbQueue.read { db in
            try Topic.fetchAll(db, sql: "SELECT * FROM topic ORDER BY level, ord")
        }
    }

    func meta() throws -> [String: String] {
        try dbQueue.read { db in
            var result: [String: String] = [:]
            for row in try Row.fetchAll(db, sql: "SELECT key, value FROM meta") {
                result[row["key"]] = row["value"]
            }
            return result
        }
    }
}
