import Foundation

/// UserDefaults-backed app settings. Views use @AppStorage with these keys;
/// models read through the typed accessors.
enum AppSettings {
    static let translationLangKey = "translationLang"
    static let defaultSessionSizeKey = "defaultSessionSize"
    static let goalLevelKey = "goalLevel"
    /// The level currently browsed on the Progress page ("" = follow the goal).
    static let selectedLevelKey = "selectedLevel"

    /// Sentinel for "pick the lowest incomplete level automatically".
    static let autoGoal = "auto"

    static var translationLang: TranslationLang {
        TranslationLang(rawValue: UserDefaults.standard.string(forKey: translationLangKey) ?? "en") ?? .en
    }

    static var defaultSessionSize: Int {
        let value = UserDefaults.standard.integer(forKey: defaultSessionSizeKey)
        return value > 0 ? value : 20
    }

    /// nil means auto.
    static var goalLevel: Level? {
        Level(rawValue: UserDefaults.standard.string(forKey: goalLevelKey) ?? autoGoal)
    }
}
