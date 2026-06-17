import AppKit
import SwiftUI

/// The single camera window. Opens "attached" under the menu bar with an emerge
/// animation; auto-detaches into a floating, always-on-top window when dragged.
@MainActor
final class CameraWindowController: NSObject, NSWindowDelegate {
    private let panel: CameraPanel
    private weak var app: AppController?
    private let camera: CameraManager
    private var ignoreMove = false

    var isVisible: Bool { panel.isVisible }

    init(app: AppController, camera: CameraManager) {
        self.app = app
        self.camera = camera
        panel = CameraPanel(
            contentRect: NSRect(origin: .zero, size: app.windowSize.dimensions),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()

        panel.level = .floating
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.delegate = self

        let content = CameraWindowContent(app: app, onClose: { [weak self] in self?.close() })
            .environmentObject(camera)
        let hosting = NSHostingView(rootView: content)
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
    }

    // MARK: - Show / close

    func showAttached(from button: NSStatusBarButton?) {
        let wasVisible = panel.isVisible
        if !wasVisible { camera.acquire() }

        let screen = button?.window?.screen ?? NSScreen.main
        let size = clampedSize(app?.windowSize.dimensions ?? NSSize(width: 480, height: 270), on: screen)
        let target = attachedFrame(size: size, button: button)

        ignoreMove = true
        let startSize = NSSize(width: size.width * 0.35, height: size.height * 0.35)
        let startFrame = NSRect(
            x: target.midX - startSize.width / 2,
            y: target.maxY - startSize.height,
            width: startSize.width, height: startSize.height
        )
        panel.setFrame(startFrame, display: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.24
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(target, display: true)
            panel.animator().alphaValue = 1
        }, completionHandler: { [weak self] in
            Task { @MainActor in
                self?.ignoreMove = false
                self?.panel.invalidateShadow()
            }
        })

    }

    func close() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        camera.release()
        app?.isDetached = false
    }

    // MARK: - Size / shape

    func applySize() {
        guard panel.isVisible else { return }
        let size = clampedSize(app?.windowSize.dimensions ?? panel.frame.size, on: panel.screen)
        ignoreMove = true
        let frame: NSRect
        if app?.isDetached == true {
            let center = NSPoint(x: panel.frame.midX, y: panel.frame.midY)
            frame = NSRect(x: center.x - size.width / 2, y: center.y - size.height / 2,
                           width: size.width, height: size.height)
        } else {
            frame = attachedFrame(size: size, button: app?.menuBar?.button)
        }
        // Animate asynchronously — `setFrame(display:animate:)` runs a nested run loop
        // and would block the main thread for the whole animation.
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(frame, display: true)
        }, completionHandler: { [weak self] in
            Task { @MainActor in
                self?.ignoreMove = false
                self?.panel.invalidateShadow()
            }
        })
    }

    func refreshShadow() {
        DispatchQueue.main.async { [weak self] in self?.panel.invalidateShadow() }
    }

    // MARK: - Geometry

    /// Keeps a chosen size within ~90% of the screen so "Large" never overflows
    /// a smaller monitor, preserving the 16:9 aspect ratio.
    private func clampedSize(_ size: NSSize, on screen: NSScreen?) -> NSSize {
        guard let visible = (screen ?? NSScreen.main)?.visibleFrame else { return size }
        let maxW = visible.width * 0.9
        let maxH = visible.height * 0.9
        let scale = min(1, maxW / size.width, maxH / size.height)
        return NSSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
    }

    private func attachedFrame(size: NSSize, button: NSStatusBarButton?) -> NSRect {
        guard let button, let buttonWindow = button.window else {
            let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
            return NSRect(x: screen.midX - size.width / 2, y: screen.maxY - size.height - 8,
                          width: size.width, height: size.height)
        }
        let rectInWindow = button.convert(button.bounds, to: nil)
        let rectOnScreen = buttonWindow.convertToScreen(rectInWindow)
        var x = rectOnScreen.midX - size.width / 2
        let y = rectOnScreen.minY - size.height - 6
        if let visible = (buttonWindow.screen ?? NSScreen.main)?.visibleFrame {
            x = min(max(x, visible.minX + 8), visible.maxX - size.width - 8)
        }
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    // MARK: - Drag to detach

    func windowDidMove(_ notification: Notification) {
        guard !ignoreMove, app?.isDetached == false else { return }
        app?.markDetached()
    }
}

/// Borderless panels can't become key by default; allow it so the close button
/// works. Non-activating so it never steals focus from your video call.
final class CameraPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}
