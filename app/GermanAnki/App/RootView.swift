import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app
        Group {
            if let error = app.loadError {
                ContentUnavailableView("Something broke", systemImage: "exclamationmark.triangle",
                                       description: Text(error))
            } else if app.loaded {
                TabView(selection: $app.page) {
                    LevelsView()
                        .tag(RootPage.progress)
                    StudyView()
                        .tag(RootPage.study)
                    SettingsView()
                        .tag(RootPage.settings)
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .background(Color(.systemBackground))
            } else {
                ProgressView()
            }
        }
    }
}
