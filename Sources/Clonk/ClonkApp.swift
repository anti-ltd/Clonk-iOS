import SwiftUI

@main
struct ClonkApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            rootView
                .environment(model)
                .onChange(of: scenePhase) { _, phase in
                    // Re-read enable / Full Access status when returning from
                    // the Settings app, where the user toggles the keyboard on.
                    if phase == .active { model.refreshStatus() }
                }
        }
    }

    @ViewBuilder private var rootView: some View {
        #if SHOWCASE
        // `make device-showcase` boots straight into the typing simulator.
        ShowcaseView()
        #elseif DEBUG
        if let slug = AppStage.slug {
            StagedRoot(slug: slug)
        } else {
            RootView()
        }
        #else
        RootView()
        #endif
    }
}
