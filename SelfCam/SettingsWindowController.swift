import AppKit
import SwiftUI

/// Owns the single Settings window; reuses it if already open.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private weak var app: AppController?
    private let camera: CameraManager
    private let snaps: SnapStore
    private var window: NSWindow?

    init(app: AppController, camera: CameraManager, snaps: SnapStore) {
        self.app = app
        self.camera = camera
        self.snaps = snaps
        super.init()
    }

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        guard let app else { return }
        let view = SettingsView(app: app, camera: camera, snaps: snaps)
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = "SelfCam Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.delegate = self
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}
