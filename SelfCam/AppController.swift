import AppKit
import SwiftUI
import Carbon.HIToolbox

/// App-wide coordinator: owns the camera, the window, the notch catcher, and all
/// persisted settings. The menu bar and the window talk to it.
@MainActor
final class AppController: ObservableObject {
    let camera = CameraManager()
    let snapStore = SnapStore()

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

    /// True once the window has been dragged off the menu bar into a floating window.
    @Published var isDetached = false

    /// True while the camera window is visible (i.e. the camera is running).
    var isCameraActive: Bool { windowController?.isVisible == true }

    weak var menuBar: MenuBarController?

    private let defaults = UserDefaults.standard
    private var windowController: CameraWindowController?
    private var notch: NotchCatcher?
    private var hotKey: GlobalHotKey?
    private var snaps: Set<SnapController> = []
    private lazy var settingsController = SettingsWindowController(app: self, camera: camera, snaps: snapStore)
    private lazy var snapsGallery = SnapsGalleryController(
        store: snapStore,
        onPreview: { [weak self] url in self?.openSnapPreview(url: url) }
    )

    init() {
        windowSize = WindowSize(rawValue: defaults.string(forKey: "windowSize") ?? "") ?? .medium
        mask = MaskShape(rawValue: defaults.string(forKey: "mask") ?? "") ?? .rounded
        iconStyle = IconStyle(rawValue: defaults.string(forKey: "iconStyle") ?? "") ?? .person
        notchEnabled = defaults.bool(forKey: "notchEnabled")
        let savedZoom = defaults.double(forKey: "zoom")
        zoom = savedZoom >= 1 ? min(savedZoom, 3) : 1
    }

    func start() {
        windowController = CameraWindowController(app: self, camera: camera)
        camera.refreshDevices()
        camera.setZoom(CGFloat(zoom))   // didSet doesn't fire from init; apply now
        updateNotch()
        // Global ⌥⌘M toggles the camera window from anywhere.
        hotKey = GlobalHotKey(keyCode: kVK_ANSI_M, modifiers: cmdKey | optionKey) { [weak self] in
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

    // MARK: - Settings & Snaps gallery

    func openSettings() {
        settingsController.show()
    }

    func showSnaps(from button: NSStatusBarButton?) {
        snapsGallery.toggle(from: button)
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
