import AppKit

/// A transparent click target placed under the notch. Clicking it toggles the
/// camera window (your camera physically lives in the notch, so it's intuitive).
@MainActor
final class NotchCatcher {
    private var window: NSWindow?
    private var screenObserver: NSObjectProtocol?
    private let onTrigger: () -> Void

    init(onTrigger: @escaping () -> Void) { self.onTrigger = onTrigger }

    deinit {
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
    }

    /// The built-in notched display, found by scanning ALL screens (not just the
    /// key-window screen) so this works on multi-monitor / clamshell setups.
    private static var notchScreen: NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 }
    }

    static var hasNotch: Bool { notchScreen != nil }

    func enable() {
        rebuild()
        if screenObserver == nil {
            // Reposition if the display arrangement / resolution changes.
            screenObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil, queue: .main
            ) { [weak self] _ in MainActor.assumeIsolated { self?.rebuild() } }
        }
    }

    func disable() {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
        }
        window?.orderOut(nil)
        window = nil
    }

    private func rebuild() {
        window?.orderOut(nil)
        window = nil
        guard let rect = Self.notchRect() else { return }
        let window = NSWindow(contentRect: rect, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .statusBar
        window.ignoresMouseEvents = false
        window.hasShadow = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        let view = NotchClickView()
        view.autoresizingMask = [.width, .height]
        view.onClick = { [weak self] in self?.onTrigger() }
        window.contentView = view
        window.orderFrontRegardless()
        self.window = window
    }

    private static func notchRect() -> NSRect? {
        guard let screen = notchScreen,
              let left = screen.auxiliaryTopLeftArea,
              let right = screen.auxiliaryTopRightArea else { return nil }
        let width = right.minX - left.maxX
        guard width > 0 else { return nil }
        return NSRect(x: left.maxX, y: left.minY, width: width, height: left.height)
    }
}

final class NotchClickView: NSView {
    var onClick: (() -> Void)?
    // The app is an .accessory (non-activating) agent, so without this the first
    // click on the notch window is swallowed by activation and never reaches mouseDown.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { onClick?() }
}
