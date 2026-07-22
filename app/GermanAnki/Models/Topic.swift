import Foundation
import GRDB

struct Topic: Identifiable, Hashable, FetchableRecord {
    let level: Level
    let slug: String
    let de: String
    let en: String
    let ord: Int

    var id: String { "\(level.rawValue)/\(slug)" }

    init(level: Level, slug: String, de: String, en: String, ord: Int) {
        self.level = level
        self.slug = slug
        self.de = de
        self.en = en
        self.ord = ord
    }

    init(row: Row) {
        self.init(level: Level(rawValue: row["level"]) ?? .a1, slug: row["slug"],
                  de: row["de"], en: row["en"], ord: row["ord"])
    }
}
