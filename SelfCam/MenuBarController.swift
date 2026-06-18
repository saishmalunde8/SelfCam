import AppKit
import AVFoundation

/// Owns the menu-bar status item. Left-click toggles the camera window;
/// right-click (or control-click) opens the settings menu.
@MainActor
final class MenuBarController: NSObject {
    private let statusItem: NSStatusItem
    private weak var app: AppController?
    private var camera: CameraManager? { app?.camera }

    var button: NSStatusBarButton? { statusItem.button }

    init(app: AppController) {
        self.app = app
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        updateIcon()
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(handleClick)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    func updateIcon() {
        guard let app else { return }
        statusItem.button?.image = NSImage(
            systemSymbolName: app.iconStyle.symbol,
            accessibilityDescription: "SelfCam"
        )
    }

    @objc private func handleClick() {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            showMenu()
        } else {
            app?.toggleWindow(from: statusItem.button)
        }
    }

    private func showMenu() {
        statusItem.menu = buildMenu()
        statusItem.button?.performClick(nil)
        statusItem.menu = nil // restore left-click toggle behavior
    }

    // MARK: - Menu

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        guard let app, let camera else { return menu }

        menu.addItem(submenu("Camera", items: camera.devices.map { device in
            item(device.localizedName, action: #selector(selectCamera(_:)),
                 represented: device.uniqueID, on: device.uniqueID == camera.selectedDeviceID)
        }, emptyTitle: "No cameras found"))

        menu.addItem(item("Mirror", action: #selector(toggleMirror), on: camera.isMirrored))

        menu.addItem(submenu("Size", items: WindowSize.allCases.map { size in
            item(size.label, action: #selector(selectSize(_:)),
                 represented: size, on: size == app.windowSize)
        }))

        menu.addItem(submenu("Shape", items: MaskShape.allCases.map { shape in
            item(shape.label, action: #selector(selectShape(_:)),
                 represented: shape, on: shape == app.mask)
        }))

        menu.addItem(submenu("Menu Bar Icon", items: IconStyle.allCases.map { style in
            let it = item(style.label, action: #selector(selectIcon(_:)),
                          represented: style, on: style == app.iconStyle)
            it.image = NSImage(systemSymbolName: style.symbol, accessibilityDescription: nil)
            return it
        }))

        menu.addItem(.separator())

        menu.addItem(item("Snaps", action: #selector(showSnaps)))
        menu.addItem(item("Settings…", action: #selector(openSettings), keyEquivalent: ","))

        menu.addItem(.separator())

        let notch = item("Notch Trigger", action: #selector(toggleNotch), on: app.notchEnabled)
        notch.isEnabled = NotchCatcher.hasNotch
        menu.addItem(notch)

        // Enablement is handled by validateMenuItem (automatic menu validation).
        menu.addItem(item("Take Snap", action: #selector(takeSnap), keyEquivalent: "s"))
        menu.addItem(item("Launch at Login", action: #selector(toggleLogin), on: LaunchAtLogin.isEnabled))

        menu.addItem(.separator())
        menu.addItem(item("Quit SelfCam", action: #selector(quit), keyEquivalent: "q"))
        return menu
    }

    // MARK: - Menu builders

    private func item(_ title: String, action: Selector,
                      represented: Any? = nil, on: Bool = false,
                      keyEquivalent: String = "") -> NSMenuItem {
        let it = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        it.target = self
        it.representedObject = represented
        it.state = on ? .on : .off
        return it
    }

    private func submenu(_ title: String, items: [NSMenuItem], emptyTitle: String? = nil) -> NSMenuItem {
        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let sub = NSMenu()
        if items.isEmpty, let emptyTitle {
            let placeholder = NSMenuItem(title: emptyTitle, action: nil, keyEquivalent: "")
            placeholder.isEnabled = false
            sub.addItem(placeholder)
        } else {
            items.forEach { sub.addItem($0) }
        }
        parent.submenu = sub
        return parent
    }

    // MARK: - Actions

    @objc func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(takeSnap) { return app?.isCameraActive == true }
        if menuItem.action == #selector(toggleNotch) { return NotchCatcher.hasNotch }
        return true
    }

    @objc private func selectCamera(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? String { camera?.select(deviceID: id) }
    }
    @objc private func toggleMirror() { camera?.isMirrored.toggle() }
    @objc private func selectSize(_ sender: NSMenuItem) {
        if let size = sender.representedObject as? WindowSize { app?.windowSize = size }
    }
    @objc private func selectShape(_ sender: NSMenuItem) {
        if let shape = sender.representedObject as? MaskShape { app?.mask = shape }
    }
    @objc private func selectIcon(_ sender: NSMenuItem) {
        if let style = sender.representedObject as? IconStyle { app?.iconStyle = style }
    }
    @objc private func showSnaps() { app?.showSnaps(from: statusItem.button) }
    @objc private func openSettings() { app?.openSettings() }
    @objc private func toggleNotch() { app?.notchEnabled.toggle() }
    @objc private func takeSnap() { app?.takeSnap() }
    @objc private func toggleLogin() { LaunchAtLogin.set(!LaunchAtLogin.isEnabled) }
    @objc private func quit() { NSApp.terminate(nil) }
}
