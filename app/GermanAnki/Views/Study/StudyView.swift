import SwiftUI

struct StudyView: View {
    @Environment(AppModel.self) private var app
    @AppStorage(AppSettings.translationLangKey) private var langRaw = TranslationLang.en.rawValue

    var body: some View {
        let study = app.study!
        let lang = TranslationLang(rawValue: langRaw) ?? .en
        VStack(spacing: 0) {
            SessionStatusBar(study: study)
            if study.sessionComplete {
                SessionCompleteView(study: study)
            } else if let word = study.word {
                switch study.phase {
                case .front(let sentenceIndex):
                    CardFrontView(study: study, word: word, sentenceIndex: sentenceIndex)
                case .reveal(let pending, _):
                    RevealView(study: study, word: word, pendingGrade: pending, lang: lang)
                        .transition(.opacity)
                }
            } else {
                Spacer()
                ProgressView()
                Spacer()
            }
        }
        .animation(.easeInOut(duration: 0.2), value: study.phase)
    }
}

struct SessionCompleteView: View {
    let study: StudyModel

    var body: some View {
        Spacer()
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
            Text("Session complete")
                .font(.title2.bold())
            if let queue = study.queue {
                Text("\(queue.completedCount) cards studied")
                    .foregroundStyle(.secondary)
            }
            Button {
                study.endSession()
            } label: {
                Text("Keep browsing")
                    .font(.headline)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 12)
        }
        Spacer()
        Spacer()
    }
}
