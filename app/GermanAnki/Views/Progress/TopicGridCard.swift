import SwiftUI

/// A tappable topic tile: colored icon, English name, and a learned-progress ring.
struct TopicGridCard: View {
    let progress: TopicProgress

    private var color: Color { TopicStyle.color(progress.topic.slug) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(color.opacity(0.16))
                        .frame(width: 44, height: 44)
                    Image(systemName: TopicStyle.icon(progress.topic.slug))
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(color)
                }
                Spacer()
                ProgressRing(fraction: progress.learnedFraction, color: color,
                             complete: progress.isComplete)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(progress.topic.en)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(progress.learned)/\(progress.total) learned")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 128, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(color.opacity(0.18), lineWidth: 1)
        )
    }
}

/// Small circular progress indicator; shows a check when the topic is complete.
private struct ProgressRing: View {
    let fraction: Double
    let color: Color
    let complete: Bool

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.15), lineWidth: 4)
            Circle()
                .trim(from: 0, to: max(0.001, fraction))
                .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if complete {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(color)
            } else {
                Text("\(Int((fraction * 100).rounded()))")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(color)
            }
        }
        .frame(width: 30, height: 30)
    }
}
