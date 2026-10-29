import SwiftUI

@main
struct WalkscapeApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(model)
                // The art direction is a warm night-forest palette; the app
                // keeps that look regardless of the system appearance.
                .preferredColorScheme(.dark)
                .task { model.start() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.didBecomeActive() }
            if phase == .background { model.didEnterBackground() }
        }
    }
}
