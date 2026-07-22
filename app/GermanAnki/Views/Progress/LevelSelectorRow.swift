import SwiftUI

/// Horizontal "I'm learning …" level picker. Each chip shows the level's learned
/// percentage; tapping one selects it and drives which topics are shown below.
struct LevelSelectorRow: View {
    let progress: [LevelProgress]
    @Binding var selected: Level

    private func percent(for level: Level) -> Int {
        progress.first { $0.level == level }?.percent ?? 0
    }

    var body: some View {
        HStack(spacing: 10) {
            ForEach(Level.allCases) { level in
                let isSelected = level == selected
                Button {
                    withAnimation(.snappy(duration: 0.25)) { selected = level }
                } label: {
                    VStack(spacing: 3) {
                        Text(level.rawValue)
                            .font(.headline)
                        Text("\(percent(for: level))%")
                            .font(.caption.weight(.semibold))
                            .opacity(0.9)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(isSelected ? level.tint : level.tint.opacity(0.12))
                    )
                    .foregroundStyle(isSelected ? Color.white : level.tint)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(level.tint.opacity(isSelected ? 0 : 0.25), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("level-\(level.rawValue)")
            }
        }
    }
}
