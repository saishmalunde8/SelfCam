import AppKit
import Carbon.HIToolbox

/// Registers a single system-wide hotkey via the Carbon Event Manager. Unlike
/// `NSEvent` global monitors this needs no Accessibility / Input-Monitoring
/// permission, and the key press is consumed rather than merely observed.
///
/// `keyCode` / `modifiers` are Carbon virtual key codes and modifier masks
/// (e.g. `kVK_ANSI_M`, `cmdKey | optionKey`). The app registers one hotkey for
/// its lifetime, so a single static router is enough.
@MainActor
final class GlobalHotKey {
    private var ref: EventHotKeyRef?
    private let action: () -> Void
    private static var current: GlobalHotKey?

    init?(keyCode: Int, modifiers: Int, action: @escaping () -> Void) {
        self.action = action
        Self.current = self
        Self.installHandlerOnce()

        let id = EventHotKeyID(signature: OSType(0x53434D31), id: 1) // 'SCM1'
        let status = RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), id,
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr else { return nil }
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
    }

    private static var handlerInstalled = false
    private static func installHandlerOnce() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        // Carbon delivers hotkey events on the main thread, so it's safe to hop
        // into the main actor. The closure captures nothing → C-function-pointer.
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ -> OSStatus in
            MainActor.assumeIsolated { GlobalHotKey.current?.action() }
            return noErr
        }, 1, &spec, nil, nil)
    }
}
