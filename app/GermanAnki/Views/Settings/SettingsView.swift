import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @AppStorage(AppSettings.translationLangKey) private var langRaw = TranslationLang.en.rawValue
    @AppStorage(AppSettings.defaultSessionSizeKey) private var defaultSize = 20
    @AppStorage(AppSettings.goalLevelKey) private var goalRaw = AppSettings.autoGoal

    var body: some View {
        NavigationStack {
            Form {
                Section("Defaults") {
                    Picker("Translations", selection: $langRaw) {
                        ForEach(TranslationLang.allCases) { lang in
                            Text(lang.label).tag(lang.rawValue)
                        }
                    }
                    Stepper("Cards per session: \(defaultSize)",
                            value: $defaultSize, in: 5...100, step: 5)
                    Picker("Goal level", selection: $goalRaw) {
                        Text("Auto").tag(AppSettings.autoGoal)
                        ForEach(Level.allCases) { level in
                            Text(level.rawValue).tag(level.rawValue)
                        }
                    }
                }

                Section("Browse words") {
                    ForEach(Level.allCases) { level in
                        NavigationLink(value: level) {
                            LabeledContent(level.rawValue,
                                           value: "\(app.wordCountByLevel[level] ?? 0) words")
                        }
                    }
                }

                StatsView()

                Section {
                } footer: {
                    Text(footerText)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .multilineTextAlignment(.center)
                }
            }
            .navigationTitle("Settings")
            .navigationDestination(for: Level.self) { level in
                WordListView(level: level)
            }
        }
    }

    private var footerText: String {
        let built = app.meta["built_at"] ?? "?"
        let count = app.meta["word_count"] ?? "?"
        return """
        \(count) words · content built \(built)
        Example sentences from Tatoeba (CC-BY 2.0 FR) and generated.
        """
    }
}
