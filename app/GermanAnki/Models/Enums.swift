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

    /// Compact code for tight UI (e.g. the direction picker): "EN" / "RU".
    var short: String {
        switch self {
        case .en: "EN"
        case .ru: "RU"
        }
    }
}

/// Which side of a card is the prompt. Progress is keyed by word, so both
/// directions feed the same SRS state — reversing only flips what's shown.
enum StudyDirection: String, CaseIterable, Identifiable {
    /// See the German word, recall its meaning (the default).
    case deToTranslation
    /// See the meaning, recall the German word.
    case translationToDe

    var id: String { rawValue }

    /// Short "DE → EN" style label for the segmented picker.
    func shortLabel(_ lang: TranslationLang) -> String {
        switch self {
        case .deToTranslation: "DE → \(lang.short)"
        case .translationToDe: "\(lang.short) → DE"
        }
    }

    /// True when the card front shows the translation instead of German.
    var showsTranslationFirst: Bool { self == .translationToDe }
}

enum SessionMode: String {
    case goal, custom
}
