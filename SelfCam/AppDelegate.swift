import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: AppController!
    private var menuBar: MenuBarController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory) // no Dock icon; lives in the menu bar

        LocalPaths.sweepStaleTmp() // clear recordings orphaned by crashes/quits

        let controller = AppController()
        let menuBar = MenuBarController(app: controller)
        controller.menuBar = menuBar
        controller.start()

        self.controller = controller
        self.menuBar = menuBar
    }
}
