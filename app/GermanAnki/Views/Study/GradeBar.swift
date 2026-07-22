import SwiftUI

struct GradeBar: View {
    let selected: Grade?
    let action: (Grade) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Grade.allCases) { grade in
                Button {
                    action(grade)
                } label: {
                    Text(grade.label)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(grade.tint.opacity(dimmed(grade) ? 0.07 : 0.16))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(grade.tint, lineWidth: selected == grade ? 2 : 0)
                        )
                        .foregroundStyle(grade.tint)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func dimmed(_ grade: Grade) -> Bool {
        selected != nil && selected != grade
    }
}

extension Grade {
    var tint: Color {
        switch self {
        case .dontKnow: .red
        case .hard: .orange
        case .good: .green
        case .easy: .blue
        }
    }
}
