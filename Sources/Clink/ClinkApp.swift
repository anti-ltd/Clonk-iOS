/**
 App entry point. Boots into `RootView` in production, with debug hooks for the
 `appstage` marketing pipeline and the `SHOWCASE` typing simulator.
 

 Module: app-ui · Target: Clink
 Learn: docs/09-app-ui.md
 */
import SwiftUI

@main
struct ClinkApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            rootView
                .environment(model)
                .onOpenURL { url in
                    if url.pathExtension == "clinkconfig" {
                        model.importConfigurationFromURL(url)
                    } else {
                        model.importTheme(from: url)
                    }
                }
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
