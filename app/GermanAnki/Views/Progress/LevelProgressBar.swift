import SwiftUI

/// Overlaid two-tier bar: green = learned (recent Easy), gold = mastered (mature)
/// drawn on top. Tap to toggle the exact numbers.
struct LevelProgressBar: View {
    let progress: LevelProgress
    @State private var showNumbers = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(progress.level.rawValue)
                    .font(.headline)
                if progress.isComplete {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(KnowledgeStyle.mastered)
                }
                Spacer()
                if showNumbers {
                    Text("\(progress.learned) learned · \(progress.mastered) mastered · \(progress.total) words")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .transition(.opacity)
                } else {
                    Text("\(progress.percent)% learned")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(KnowledgeStyle.learned)
                        .contentTransition(.numericText())
                        .transition(.opacity)
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(.systemGray5))
                    Capsule()
                        .fill(KnowledgeStyle.learned)
                        .frame(width: max(0, geo.size.width * progress.learnedFraction))
                    Capsule()
                        .fill(KnowledgeStyle.mastered)
                        .frame(width: max(0, geo.size.width * progress.masteredFraction))
                }
            }
            .frame(height: 14)

            HStack(spacing: 14) {
                LegendDot(color: KnowledgeStyle.learned, label: "Learned")
                LegendDot(color: KnowledgeStyle.mastered, label: "Mastered")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.15)) { showNumbers.toggle() }
        }
    }
}

private struct LegendDot: View {
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label)
        }
    }
}
