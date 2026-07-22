import Foundation
import GRDB

struct Word: Identifiable, Hashable, FetchableRecord {
    let id: String
    let lemma: String
    let display: String
    let pos: String
    let gender: String?
    let plural: String?
    let verbForms: String?
    let level: Level
    let topic: String
    let en: String
    let ru: String
    let freqRank: Int?
    let audio: String

    init(id: String, lemma: String, display: String, pos: String,
         gender: String? = nil, plural: String? = nil, verbForms: String? = nil,
         level: Level, topic: String, en: String, ru: String,
         freqRank: Int? = nil, audio: String) {
        self.id = id
        self.lemma = lemma
        self.display = display
        self.pos = pos
        self.gender = gender
        self.plural = plural
        self.verbForms = verbForms
        self.level = level
        self.topic = topic
        self.en = en
        self.ru = ru
        self.freqRank = freqRank
        self.audio = audio
    }

    init(row: Row) {
        self.init(
            id: row["word_id"], lemma: row["lemma"], display: row["display"],
            pos: row["pos"], gender: row["gender"], plural: row["plural"],
            verbForms: row["verb_forms"],
            level: Level(rawValue: row["level"]) ?? .a1,
            topic: row["topic"], en: row["en"], ru: row["ru"],
            freqRank: row["freq_rank"], audio: row["audio"]
        )
    }

    func translation(_ lang: TranslationLang) -> String {
        lang == .en ? en : ru
    }

    /// "noun · Pl. Abende" / "verb · fährt, fuhr, ist gefahren" — grammar hint for the answer view.
    var grammarLine: String? {
        var parts: [String] = []
        if let plural, !plural.isEmpty { parts.append("Pl. \(plural)") }
        if let verbForms, !verbForms.isEmpty { parts.append(verbForms) }
        guard !parts.isEmpty else { return pos == "noun" || pos == "verb" ? nil : pos }
        return parts.joined(separator: " · ")
    }
}
