import AppKit
import AVKit
import SwiftUI

/// Shows the 5 newest clips as a floating popover below the menu-bar button,
/// re-scanning from disk each time so the list is always fresh. Mirrors
/// `SnapsGalleryController`. Clicking a clip plays it in an in-app mini player.
@MainActor
final class RecentClipsController: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private var isPresenting = false
    private let clipPlayer = ClipPlayer()

    var isOpen: Bool { panel?.isVisible == true }

    func toggle(from button: NSStatusBarButton?) {
        isOpen ? close() : show(from: button)
    }

    func close() {
        panel?.close()
        panel = nil
    }

    func show(from button: NSStatusBarButton?) {
        if isOpen { close() }
        guard !isPresenting else { return }
        isPresenting = true

        RecentClips.load(limit: 5) { [weak self] clips in
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
            panel.contentViewController = NSHostingController(rootView: self.makeView(clips))

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

    private func makeView(_ clips: [RecentClips.Clip]) -> RecentClipsView {
        RecentClipsView(
            clips: clips,
            onOpen: { [weak self] clip in
                self?.close()
                self?.clipPlayer.play(clip)
            },
            onMore: { [weak self] in
                LocalPaths.ensureExists()   // so Finder always has something to open
                NSWorkspace.shared.activateFileViewerSelecting([LocalPaths.recordings])
                self?.close()
            }
        )
    }

    func windowWillClose(_ notification: Notification) {
        panel = nil
    }
}

/// A small in-app movie player window. Uses AppKit's `AVPlayerView` (never
/// SwiftUI `VideoPlayer`, which crashes on macOS here) and reuses one window
/// across clips so opening a second clip just swaps the player.
@MainActor
final class ClipPlayer: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private var playerView: AVPlayerView?
    private var player: AVPlayer?

    func play(_ clip: RecentClips.Clip) {
        let player = AVPlayer(url: clip.url)
        self.player = player

        if panel == nil {
            let view = AVPlayerView()
            view.controlsStyle = .inline
            view.videoGravity = .resizeAspect
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 480, height: 300),
                styleMask: [.titled, .closable, .resizable, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.isReleasedWhenClosed = false
            panel.level = .floating
            panel.delegate = self
            panel.contentView = view
            panel.center()
            self.panel = panel
            self.playerView = view
        }

        panel?.title = clip.title
        playerView?.player = player
        panel?.makeKeyAndOrderFront(nil)
        player.play()
    }

    /// Stop playback when the window is closed so audio doesn't keep running.
    func windowWillClose(_ notification: Notification) {
        player?.pause()
        player = nil
        playerView?.player = nil
        panel = nil
        playerView = nil
    }
}
