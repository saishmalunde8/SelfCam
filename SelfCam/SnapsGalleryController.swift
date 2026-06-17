import AppKit
import SwiftUI

/// Shows the recent-snaps gallery as a floating, draggable panel.
@MainActor
final class SnapsGalleryController: NSObject, NSWindowDelegate {
    private let store: SnapStore
    private let onPreview: (URL) -> Void
    private var panel: NSPanel?
    private var isPresenting = false

    init(store: SnapStore, onPreview: @escaping (URL) -> Void) {
        self.store = store
        self.onPreview = onPreview
        super.init()
    }

    var isOpen: Bool { panel?.isVisible == true }

    func toggle(from button: NSStatusBarButton?) {
        isOpen ? close() : show(from: button)
    }

    func close() {
        panel?.close()
        panel = nil
    }

    /// Opens the gallery, re-scanning from disk each time so the list is always
    /// fresh (a snap edited a moment ago shows as the newest entry).
    func show(from button: NSStatusBarButton?) {
        if isOpen { close() }
        guard !isPresenting else { return }
        isPresenting = true

        store.recent(limit: 5) { [weak self] snaps in
            guard let self else { return }
            self.isPresenting = false

            let panel = NSPanel(
                contentRect: .zero,
                styleMask: [.titled, .closable, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.title = ""
            panel.isReleasedWhenClosed = false
            panel.level = .floating
            panel.isMovableByWindowBackground = true
            panel.delegate = self
            panel.contentViewController = NSHostingController(rootView: self.makeView(snaps))

            // Position below the menu-bar button. contentViewController assignment
            // triggers a synchronous layout so panel.frame.size is valid here.
            if let button, let buttonWindow = button.window {
                let buttonFrame = buttonWindow.convertToScreen(button.frame)
                let sz = panel.frame.size
                let x = buttonFrame.midX - sz.width / 2
                let y = buttonFrame.minY - sz.height - 6
                panel.setFrameOrigin(NSPoint(x: x, y: y))
            } else {
                panel.center()
            }

            panel.makeKeyAndOrderFront(nil)
            self.panel = panel
        }
    }

    private func makeView(_ snaps: [URL]) -> SnapsGalleryView {
        SnapsGalleryView(
            snaps: snaps,
            onOpen: { [weak self] url in self?.onPreview(url) },
            onMore: { [weak self] in
                self?.store.revealInFinder()
                self?.close()
            }
        )
    }

    func windowWillClose(_ notification: Notification) {
        panel = nil
    }
}
