import AppKit
import SwiftUI

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

    weak var menuBar: MenuBarController?

    private let defaults = UserDefaults.standard
    private var windowController: CameraWindowController?
    private var notch: NotchCatcher?
    private var snaps: Set<SnapController> = []
    private lazy var settingsController = SettingsWindowController(app: self, camera: camera, snaps: snapStore)
    private lazy var snapsGallery = SnapsGalleryController(store: snapStore)

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

    func takeSnap() {
        let controller = SnapController { [weak self] done in self?.snaps.remove(done) }
        snaps.insert(controller)
        camera.captureSnap(mirrored: camera.isMirrored) { [weak self, weak controller] image in
            guard let self, let controller else { return }
            if let image {
                // Snapshot an immutable CGImage on the main thread, then hand THAT to
                // the background writer — the NSImage itself is only ever touched on main.
                if let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                    self.snapStore.save(cg)       // auto-save the original to the snaps folder
                }
                controller.present(image: image)  // and open the editable Polaroid
            } else {
                self.snaps.remove(controller)
            }
        }
    }
}
