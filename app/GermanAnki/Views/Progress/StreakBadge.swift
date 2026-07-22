import SwiftUI

/// 🔥 + day count. Rendered gold once the user has studied during the current
/// SRS-day, muted otherwise (streak alive but today not yet done). Optionally
/// pops when `animated` flips true, to celebrate a freshly-extended streak.
struct StreakBadge: View {
    let streak: StreakInfo
    var animated = false

    @State private var pop = false

    private var tint: Color {
        streak.studiedToday ? KnowledgeStyle.mastered : Color.secondary
    }

    var body: some View {
        HStack(spacing: 4) {
            Text("🔥")
                .font(.title3)
                .scaleEffect(pop ? 1.35 : 1.0)
                .rotationEffect(.degrees(pop ? -8 : 0))
            Text("\(streak.count)")
                .font(.title3.weight(.bold).monospacedDigit())
                .foregroundStyle(tint)
                .contentTransition(.numericText(value: Double(streak.count)))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule().fill(tint.opacity(streak.studiedToday ? 0.16 : 0.10))
        )
        .overlay(
            Capsule().strokeBorder(tint.opacity(0.35), lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(streak.count) day streak")
        .accessibilityIdentifier("streakBadge")
        .onAppear {
            guard animated else { return }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.4).delay(0.15)) {
                pop = true
            }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7).delay(0.5)) {
                pop = false
            }
        }
    }
}
