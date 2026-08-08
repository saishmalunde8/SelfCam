import AppKit

/// Soft, optional audio cues for the practice recorder. Off by default; the
/// user opts in via Settings. Uses the built-in macOS system sounds so there
/// are no bundled assets to ship. Reads the enabled flag live from
/// `UserDefaults` at play time, so toggling Settings takes effect immediately.
enum SoundCue {
    static let enabledKey = "soundCuesEnabled"

    private static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }

    /// A gentle tick as recording begins.
    static func playStart() { play("Tink") }

    /// A soft confirmation on save.
    static func playSave() { play("Glass") }

    private static func play(_ name: String) {
        guard isEnabled, let sound = NSSound(named: name) else { return }
        sound.stop()   // restart cleanly if it's still ringing from a rapid repeat
        sound.play()
    }
}
