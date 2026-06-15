import AppKit
import SwiftUI

/// Shows the recent-snaps gallery as an NSPopover anchored to the menu-bar button.
@MainActor
final class SnapsGalleryController: NSObject, NSPopoverDelegate {
    private let store: SnapStore
    private var popover: NSPopover?
    private var isPresenting = false

    init(store: SnapStore) {
        self.store = store
        super.init()
    }

    func toggle(from button: NSStatusBarButton?) {
        if let popover, popover.isShown {
            popover.performClose(nil)
            self.popover = nil
            return
        }
        // The disk scan below is async, so guard against a second toggle landing in
        // that gap and spawning a duplicate popover.
        guard !isPresenting, let button else { return }
        isPresenting = true

        // Disk scan happens off-main; present the popover once results arrive.
        store.recent(limit: 5) { [weak self] snaps in
            guard let self else { return }
            self.isPresenting = false
            let view = SnapsGalleryView(
                snaps: snaps,
                onOpen: { url in NSWorkspace.shared.open(url) },
                onMore: { [weak self] in
                    self?.store.revealInFinder()
                    self?.popover?.performClose(nil)
                }
            )
            let popover = NSPopover()
            popover.behavior = .transient
            popover.delegate = self
            popover.contentViewController = NSHostingController(rootView: view)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            self.popover = popover
        }
    }

    // Release the popover (and its loaded thumbnails) once it closes.
    func popoverDidClose(_ notification: Notification) {
        popover = nil
    }
}
