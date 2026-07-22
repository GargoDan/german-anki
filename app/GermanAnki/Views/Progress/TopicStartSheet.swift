import SwiftUI

/// Shown when a topic tile is tapped: proposes a session on that topic with the
/// user's default card count (pre-filled), which they can tweak before starting.
struct TopicStartSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    let topic: TopicProgress
    let level: Level
    @State private var count = AppSettings.defaultSessionSize

    private var color: Color { TopicStyle.color(topic.topic.slug) }

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color(.systemGray4))
                .frame(width: 36, height: 5)
                .padding(.top, 8)

            VStack(spacing: 14) {
                ZStack {
                    Circle().fill(color.opacity(0.16)).frame(width: 76, height: 76)
                    Image(systemName: TopicStyle.icon(topic.topic.slug))
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(color)
                }
                .padding(.top, 20)

                VStack(spacing: 4) {
                    Text(topic.topic.en)
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                    Text("\(topic.topic.de) · \(level.rawValue)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("\(topic.learned)/\(topic.total) learned")
                        .font(.footnote)
                        .foregroundStyle(color)
                        .padding(.top, 2)
                }
            }
            .padding(.horizontal, 24)

            Stepper("Cards: \(count)", value: $count, in: 5...100, step: 5)
                .padding(.horizontal, 24)
                .padding(.top, 24)

            Spacer(minLength: 0)

            Button {
                app.study.startSession(mode: .custom, level: level,
                                       topic: topic.topic.slug, target: count)
                dismiss()
                app.page = .study
            } label: {
                Text("Start session")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(color)
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
            .accessibilityIdentifier("startTopicSession")
        }
    }
}
