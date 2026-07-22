import Foundation
import GRDB

struct Sentence: Identifiable, Hashable, FetchableRecord {
    let id: String
    let de: String
    let en: String
    let ru: String
    let audio: String?

    init(id: String, de: String, en: String, ru: String, audio: String? = nil) {
        self.id = id
        self.de = de
        self.en = en
        self.ru = ru
        self.audio = audio
    }

    init(row: Row) {
        self.init(id: row["sent_id"], de: row["de"], en: row["en"],
                  ru: row["ru"], audio: row["audio"])
    }

    func translation(_ lang: TranslationLang) -> String {
        lang == .en ? en : ru
    }
}
