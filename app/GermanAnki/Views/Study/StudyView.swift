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
        ScrollView {
            VStack(spacing: 22) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.green)
                Text("Session complete")
                    .font(.title2.bold())

                if let summary = study.summary {
                    StreakCelebration(summary: summary)
                    SessionStatsCard(summary: summary)
                }

                Button {
                    study.endSession()
                } label: {
                    Text("Keep browsing")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 4)
            }
            .padding(.horizontal, 24)
            .padding(.top, 32)
            .padding(.bottom, 40)
        }
    }
}

/// Streak line with the fire badge; celebrates when this session extended it.
private struct StreakCelebration: View {
    let summary: SessionSummary

    var body: some View {
        VStack(spacing: 8) {
            StreakBadge(streak: summary.streak, animated: summary.streakExtended)
                .scaleEffect(1.15)
            Text(summary.streakExtended
                 ? (summary.streak.count == 1 ? "Streak started!" : "\(summary.streak.count)-day streak!")
                 : "Streak: \(summary.streak.count) days")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(summary.streakExtended ? KnowledgeStyle.mastered : .secondary)
        }
    }
}

/// Time-taken headline plus a per-grade breakdown of the session's answers.
private struct SessionStatsCard: View {
    let summary: SessionSummary

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                stat(value: "\(summary.total)", label: "words")
                Divider().frame(height: 34)
                stat(value: summary.durationText, label: "time")
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: 8) {
                ForEach(Grade.allCases) { grade in
                    gradeRow(grade)
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private func stat(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title2.bold().monospacedDigit())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func gradeRow(_ grade: Grade) -> some View {
        let count = summary.count(grade)
        let fraction = summary.total > 0 ? Double(count) / Double(summary.total) : 0
        HStack(spacing: 10) {
            Text(grade.label)
                .font(.subheadline.weight(.medium))
                .frame(width: 82, alignment: .leading)
            GeometryReader { geo in
                Capsule()
                    .fill(grade.tint.opacity(count > 0 ? 0.9 : 0.15))
                    .frame(width: max(count > 0 ? 6 : 0, geo.size.width * fraction))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 10)
            Text("\(count)")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(count > 0 ? .primary : .secondary)
                .frame(width: 24, alignment: .trailing)
        }
    }
}
