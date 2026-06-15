import AppKit
import SwiftUI

/// Hosts a single Snap window. Kept alive by AppController until it closes.
@MainActor
final class SnapController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let onClose: (SnapController) -> Void
    private let id = UUID()

    init(onClose: @escaping (SnapController) -> Void) {
        self.onClose = onClose
        super.init()
    }

    func present(image: NSImage) {
        let view = SnapView(image: image, onDone: { [weak self] in self?.window?.close() })
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = "Snap"
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
        onClose(self)
    }
}

extension SnapController {
    override var hash: Int { id.hashValue }
    override func isEqual(_ object: Any?) -> Bool {
        (object as? SnapController)?.id == id
    }
}
