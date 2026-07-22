import SwiftUI

struct SessionStatusBar: View {
    let study: StudyModel

    var body: some View {
        HStack(spacing: 8) {
            if let queue = study.queue {
                Label(queue.info.title, systemImage: "target")
                    .font(.footnote.weight(.semibold))
                Spacer()
                Text("\(queue.completedCount)/\(queue.info.target)")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("sessionCounter")
                Button {
                    study.endSession()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .accessibilityIdentifier("endSession")
            } else {
                Label("Browsing · all levels", systemImage: "shuffle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }
}
