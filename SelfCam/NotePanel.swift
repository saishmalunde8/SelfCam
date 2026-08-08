import AppKit
import SwiftUI

/// Hosts the sticky-note practice panel, positioned flush against the camera
/// window's edge. Reposition is driven by the camera controller's settle/drag
/// callbacks rather than following its animation frame-by-frame.
@MainActor
final class NotePanel: NSObject, NSWindowDelegate {
    /// Clear margin around the note inside the panel — room for the drop
    /// shadow, which the window would otherwise clip away.
    static let contentInset: CGFloat = 20
    private static let contentSize = NSSize(width: 220 + contentInset * 2,
                                            height: 260 + contentInset * 2)

    private var panel: NSPanel?
    private let topics: TopicStore
    private let recording: RecordingManager
    private let camera: CameraManager

    var isVisible: Bool { panel?.isVisible == true }

    init(topics: TopicStore, recording: RecordingManager, camera: CameraManager) {
        self.topics = topics
        self.recording = recording
        self.camera = camera
        super.init()
    }

    func show(besideCamera cameraWindow: NSWindow) {
        if panel == nil {
            let panel = NSPanel(
                contentRect: NSRect(origin: .zero, size: Self.contentSize),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.level = .floating
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false // NoteView draws its own shadow inside the inset
            panel.isReleasedWhenClosed = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.delegate = self
            panel.contentView = NSHostingView(
                rootView: NoteView(topics: topics, recording: recording, camera: camera)
            )
            self.panel = panel
        }
        guard let panel else { return }
        // Attach as a child so the note glides with the camera automatically and
        // orders *below* it — its inner edge tucks behind the camera window.
        if panel.parent !== cameraWindow {
            panel.parent?.removeChildWindow(panel)
            cameraWindow.addChildWindow(panel, ordered: .below)
        }
        reposition(beside: cameraWindow)
    }

    func reposition(beside cameraWindow: NSWindow) {
        guard let panel else { return }
        let cameraFrame = cameraWindow.frame
        let size = panel.frame.size
        let inset = Self.contentInset
        // Negative = tuck the visible note's edge behind the camera (it sits `.below`).
        let overlap: CGFloat = -8

        // Position so the *visible note* (inset inside the panel) sits `overlap`
        // from the camera edge. Prefer the right side; flip left if the visible
        // note would leave the screen.
        var x = cameraFrame.maxX + overlap - inset
        if let visible = (cameraWindow.screen ?? NSScreen.main)?.visibleFrame,
           x + size.width - inset > visible.maxX {
            x = cameraFrame.minX - size.width - overlap + inset
        }
        let y = cameraFrame.midY - size.height / 2
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    func hide() {
        // Never lose a take because the note went away: cancels a countdown,
        // auto-saves an active recording or a parked one.
        recording.stopAndAutoSave()
        if let panel { panel.parent?.removeChildWindow(panel) }
        panel?.orderOut(nil)
    }

    func windowWillClose(_ notification: Notification) {
        panel = nil
    }
}
