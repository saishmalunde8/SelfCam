import AppKit
import SwiftUI

/// App-wide coordinator: owns the camera, the window, the notch catcher, and all
/// persisted settings. The menu bar and the window talk to it.
@MainActor
final class AppController: ObservableObject {
    let camera = CameraManager()
    let snapStore = SnapStore()
    /// Lazy: creating it eagerly at launch used to burn a topic draw before the
    /// user ever opened practice mode.
    lazy var topicStore = TopicStore()
    lazy var recordingManager = RecordingManager(camera: camera)

    @Published var windowSize: WindowSize {
        didSet { defaults.set(windowSize.rawValue, forKey: "windowSize"); windowController?.applySize() }
    }
    @Published var mask: MaskShape {
        didSet { defaults.set(mask.rawValue, forKey: "mask"); windowController?.refreshShadow() }
    }
    @Published var iconStyle: IconStyle {
        didSet { defaults.set(iconStyle.rawValue, forKey: "iconStyle"); menuBar?.updateIcon() }
    }
    @Published var notchEnabled: Bool {
        didSet { defaults.set(notchEnabled, forKey: "notchEnabled"); updateNotch() }
    }
    /// Camera zoom, 1×–3×. Applied live to preview and to snaps.
    @Published var zoom: Double {
        didSet { defaults.set(zoom, forKey: "zoom"); camera.setZoom(CGFloat(zoom)) }
    }
    /// Global shortcut that toggles the camera window.
    @Published var hotKeyPreset: HotKeyPreset {
        didSet { defaults.set(hotKeyPreset.rawValue, forKey: "hotKeyPreset"); applyHotKey() }
    }
    /// Soft sound cues on record-start and save. Off by default.
    @Published var soundCuesEnabled: Bool {
        didSet { defaults.set(soundCuesEnabled, forKey: SoundCue.enabledKey) }
    }

    /// True once the window has been dragged off the menu bar into a floating window.
    @Published var isDetached = false

    /// True while the camera window is visible (i.e. the camera is running).
    var isCameraActive: Bool { windowController?.isVisible == true }
    /// True while the practice note is attached and showing.
    @Published var isPracticeOpen = false

    weak var menuBar: MenuBarController?

    private let defaults = UserDefaults.standard
    private var windowController: CameraWindowController?
    private var notch: NotchCatcher?
    private var hotKey: GlobalHotKey?
    private var snaps: Set<SnapController> = []
    private lazy var notePanel = NotePanel(topics: topicStore, recording: recordingManager, camera: camera)
    /// One-shot: openPractice was asked to show the note, but the camera window
    /// is still animating in — show on the next settle instead of against a
    /// transient mid-animation frame.
    private var pendingNoteShow = false
    private lazy var settingsController = SettingsWindowController(app: self, camera: camera, snaps: snapStore)
    private lazy var snapsGallery = SnapsGalleryController(
        store: snapStore,
        onPreview: { [weak self] url in self?.openSnapPreview(url: url) }
    )
    private lazy var recentClips = RecentClipsController()

    init() {
        windowSize = WindowSize(rawValue: defaults.string(forKey: "windowSize") ?? "") ?? .medium
        mask = MaskShape(rawValue: defaults.string(forKey: "mask") ?? "") ?? .rounded
        iconStyle = IconStyle(rawValue: defaults.string(forKey: "iconStyle") ?? "") ?? .person
        notchEnabled = defaults.bool(forKey: "notchEnabled")
        let savedZoom = defaults.double(forKey: "zoom")
        zoom = savedZoom >= 1 ? min(savedZoom, 3) : 1
        hotKeyPreset = HotKeyPreset(rawValue: defaults.string(forKey: "hotKeyPreset") ?? "") ?? .optCmdM
        soundCuesEnabled = defaults.bool(forKey: SoundCue.enabledKey)   // defaults false
    }

    func start() {
        let controller = CameraWindowController(app: self, camera: camera)
        controller.onSettled = { [weak self] in
            guard let self else { return }
            if self.pendingNoteShow {
                self.pendingNoteShow = false
                self.showNoteNow()
            } else {
                self.repositionNoteIfNeeded()
            }
        }
        controller.onClosed = { [weak self] in self?.closePractice() }
        windowController = controller
        camera.refreshDevices()
        camera.setZoom(CGFloat(zoom))   // didSet doesn't fire from init; apply now
        updateNotch()
        applyHotKey()                   // didSet doesn't fire from init; apply now
    }

    /// (Re)registers the global toggle hotkey for the current preset. Tears down
    /// the old registration first so two hotkeys never share a Carbon EventHotKeyID.
    private func applyHotKey() {
        hotKey = nil
        guard let c = hotKeyPreset.carbon else { return }   // "Off"
        hotKey = GlobalHotKey(keyCode: c.keyCode, modifiers: c.modifiers) { [weak self] in
            self?.toggleWindow(from: self?.menuBar?.button)
        }
    }

    // MARK: - Window

    func toggleWindow(from button: NSStatusBarButton?) {
        if windowController?.isVisible == true {
            closeWindow()
        } else {
            openWindow(from: button)
        }
    }

    private func openWindow(from button: NSStatusBarButton?) {
        isDetached = false
        windowController?.showAttached(from: button)
    }

    func closeWindow() {
        windowController?.close()
        isDetached = false
    }

    /// Called by the window controller when the user drags it off the menu bar.
    func markDetached() {
        isDetached = true
    }

    // MARK: - Practice mode (camera + sticky-note table topics)

    /// Opens the camera (if needed) and attaches the practice note beside it.
    /// If the camera has to animate in first, the note waits for the settle so
    /// it never attaches against a transient mid-animation frame.
    ///
    /// Mic permission is NOT requested here — attaching recording outputs
    /// without prompting keeps this a passive open. The note's own mic-icon tap
    /// requests permission directly, since system prompts are far more reliable
    /// as the direct result of a fresh user gesture than as a side effect of a
    /// window opening.
    func openPractice(from button: NSStatusBarButton?) {
        isPracticeOpen = true
        camera.beginRecordingMode()
        if windowController?.isVisible == true {
            showNoteNow()
        } else {
            pendingNoteShow = true
            openWindow(from: button)
        }
    }

    /// Called whenever the camera window closes, by whichever path. The guard
    /// keeps ordinary camera use free of practice-mode side effects — without it,
    /// closing the window would build the (lazy) topic store and create
    /// ~/Movies/SelfCam even if Table Topics was never opened.
    func closePractice() {
        guard isPracticeOpen else { return }
        pendingNoteShow = false
        notePanel.hide()
        camera.endRecordingMode()
        isPracticeOpen = false
    }

    private func showNoteNow() {
        guard let windowController, windowController.isVisible else { return }
        notePanel.show(besideCamera: windowController.cameraWindow)
    }

    private func repositionNoteIfNeeded() {
        guard isPracticeOpen, notePanel.isVisible, let windowController, windowController.isVisible else { return }
        notePanel.reposition(beside: windowController.cameraWindow)
    }

    // MARK: - Settings & Snaps gallery

    func openSettings() {
        settingsController.show()
    }

    /// Shows the standard macOS About panel (app icon, name, version, copyright).
    /// Activates first because this agent app is non-activating.
    func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    func showSnaps(from button: NSStatusBarButton?) {
        snapsGallery.toggle(from: button)
    }

    func showRecentClips(from button: NSStatusBarButton?) {
        recentClips.toggle(from: button)
    }

    func openSnapPreview(url: URL) {
        guard let image = NSImage(contentsOf: url) else { return }
        // Close the gallery so the editor is the sole foreground window (otherwise the
        // two floating windows compete and the first Done click gets swallowed).
        snapsGallery.close()
        let controller = makeSnapController(returnToGallery: true)
        // saveOnXClose:false — the original is already on disk; only save if the user clicks Done.
        controller.present(image: image, mask: mask, snapStore: snapStore, saveOnXClose: false)
    }

    // MARK: - Notch trigger

    private func updateNotch() {
        if notchEnabled {
            if notch == nil {
                notch = NotchCatcher { [weak self] in
                    self?.toggleWindow(from: self?.menuBar?.button)
                }
            }
            notch?.enable()
        } else {
            notch?.disable()
        }
    }

    // MARK: - Snaps

    /// Creates and tracks a snap-editor controller. When it closes, the gallery is
    /// reopened if `returnToGallery` is set (the snap was opened *from* the gallery)
    /// or if it's already open — so the freshly saved snap shows on top.
    private func makeSnapController(returnToGallery: Bool) -> SnapController {
        let controller = SnapController { [weak self] done in
            guard let self else { return }
            self.snaps.remove(done)
            if returnToGallery || self.snapsGallery.isOpen {
                self.snapsGallery.show(from: self.menuBar?.button)
            }
        }
        snaps.insert(controller)
        return controller
    }

    func takeSnap() {
        let controller = makeSnapController(returnToGallery: false)
        camera.captureSnap(mirrored: camera.isMirrored) { [weak self, weak controller] image in
            guard let self, let controller else { return }
            if let image {
                // Save happens when the user taps Done (with any annotations),
                // or on window-close without Done (saves the original).
                controller.present(image: image, mask: self.mask, snapStore: self.snapStore)
            } else {
                self.snaps.remove(controller)
            }
        }
    }
}
