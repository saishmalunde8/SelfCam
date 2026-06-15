import SwiftUI

@main
struct SelfCamApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        // Menu-bar-only agent app: no main window. The status item is created
        // by AppDelegate. An empty Settings scene satisfies the App protocol.
        Settings { EmptyView() }
    }
}
