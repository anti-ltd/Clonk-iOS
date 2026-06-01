import SwiftUI
import iUXiOS

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Text("AppTemplate")
            .font(.largeTitle)
    }
}
