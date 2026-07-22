import SwiftUI

struct CardFrontView: View {
    let study: StudyModel
    let word: Word
    let sentenceIndex: Int?

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 28) {
                Text(word.level.rawValue)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(word.level.tint.opacity(0.15)))
                    .foregroundStyle(word.level.tint)

                Group {
                    if let i = sentenceIndex, i < study.sentences.count {
                        Text(study.sentences[i].de)
                            .font(.title2.weight(.medium))
                            .lineSpacing(4)
                    } else {
                        Text(word.display)
                            .font(.system(size: 38, weight: .bold, design: .rounded))
                    }
                }
                .multilineTextAlignment(.center)
                .id(sentenceIndex ?? -1)
                .transition(.opacity)

                cycleDots
            }
            .padding(.horizontal, 28)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.15)) { study.tapWord() }
            }
            .accessibilityIdentifier("cardFront")

            Spacer()

            Button {
                study.playCurrent()
            } label: {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.title2)
                    .frame(width: 60, height: 60)
                    .background(Circle().fill(Color(.secondarySystemBackground)))
            }
            .buttonStyle(.plain)
            .padding(.bottom, 32)

            GradeBar(selected: nil) { grade in
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                study.select(grade)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 44)
        }
    }

    /// Position in the word → sentences cycle: filled dot = what's shown now.
    private var cycleDots: some View {
        HStack(spacing: 7) {
            ForEach(-1..<study.sentences.count, id: \.self) { i in
                Circle()
                    .fill((sentenceIndex ?? -1) == i ? Color.primary : Color(.systemGray4))
                    .frame(width: 6, height: 6)
            }
        }
        .opacity(study.sentences.isEmpty ? 0 : 1)
    }
}

extension Level {
    var tint: Color {
        switch self {
        case .a1: .green
        case .a2: .teal
        case .b1: .blue
        case .b2: .purple
        }
    }
}
