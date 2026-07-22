import Foundation

enum Level: String, CaseIterable, Codable, Identifiable, Comparable {
    case a1 = "A1", a2 = "A2", b1 = "B1", b2 = "B2"

    var id: String { rawValue }
    private var rank: Int { Self.allCases.firstIndex(of: self)! }
    static func < (lhs: Level, rhs: Level) -> Bool { lhs.rank < rhs.rank }
}

enum Grade: Int, CaseIterable, Identifiable {
    case dontKnow = 1, hard, good, easy

    var id: Int { rawValue }
    var label: String {
        switch self {
        case .dontKnow: "Don't know"
        case .hard: "Hard"
        case .good: "Good"
        case .easy: "Easy"
        }
    }
}

enum SRSState: Int {
    case learning = 1, review = 2, relearning = 3
}

enum TranslationLang: String, CaseIterable, Identifiable {
    case en, ru

    var id: String { rawValue }
    var label: String {
        switch self {
        case .en: "English"
        case .ru: "Русский"
        }
    }
}

enum SessionMode: String {
    case goal, custom
}
