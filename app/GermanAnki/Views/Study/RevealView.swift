import SwiftUI

/// Answer side: word with translation and all sentences, pending grade
/// adjustable, prominent Continue.
struct RevealView: View {
    let study: StudyModel
    let word: Word
    let pendingGrade: Grade
    let lang: TranslationLang

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(word.display)
                            .font(.system(.title, design: .rounded, weight: .bold))
                        Spacer()
                        speaker(word.audio)
                    }
                    if let grammar = word.grammarLine {
                        Text(grammar)
                            .font(.footnote)
                            .foregroundStyle(.tertiary)
                    }
                    Text(word.translation(lang))
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                Divider()

                ForEach(study.sentences) { sentence in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(alignment: .top) {
                            Text(sentence.de)
                                .font(.body.weight(.medium))
                                .lineSpacing(2)
                            Spacer(minLength: 12)
                            speaker(sentence.audio)
                        }
                        Text(sentence.translation(lang))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(20)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 12) {
                GradeBar(selected: pendingGrade) { grade in
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    study.select(grade)
                }
                Button {
                    study.commitAndContinue()
                } label: {
                    Text("Continue")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("continueButton")
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 34)
            .background(.ultraThinMaterial)
        }
    }

    private func speaker(_ filename: String?) -> some View {
        Button {
            study.play(filename)
        } label: {
            Image(systemName: "speaker.wave.2")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .opacity(filename == nil ? 0 : 1)
    }
}
