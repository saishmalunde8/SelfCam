import AppKit
import SwiftUI

/// Hosts a single Snap window. Kept alive by AppController until it closes.
@MainActor
final class SnapController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let onClose: (SnapController) -> Void
    private let id = UUID()

    // Held for the lifetime of the window so we can save on X-close.
    private var originalImage: NSImage?
    private var snapStore: SnapStore?
    private var doneCalled = false

    init(onClose: @escaping (SnapController) -> Void) {
        self.onClose = onClose
        super.init()
    }

    func present(image: NSImage, mask: MaskShape, snapStore: SnapStore?, saveOnXClose: Bool = true) {
        originalImage = saveOnXClose ? image : nil
        self.snapStore = snapStore
        doneCalled = false

        let view = SnapView(
            image: image,
            mask: mask,
            onDone: { [weak self] rendered in
                guard let self else { return }
                self.doneCalled = true
                // Save the annotated render (includes any scribbles), then close the
                // window only once the PNG is on disk — so a reopened gallery sees it.
                if let rendered,
                   let cg = rendered.cgImage(forProposedRect: nil, context: nil, hints: nil),
                   let store = self.snapStore {
                    store.save(cg) { [weak self] in self?.window?.close() }
                } else {
                    self.window?.close()
                }
            }
        )

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
        // User dismissed via the red ✕ without pressing Done — save the original.
        if !doneCalled,
           let original = originalImage,
           let cg = original.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            snapStore?.save(cg)
        }
        window = nil
        originalImage = nil
        snapStore = nil
        onClose(self)
    }
}

extension SnapController {
    override var hash: Int { id.hashValue }
    override func isEqual(_ object: Any?) -> Bool {
        (object as? SnapController)?.id == id
    }
}
