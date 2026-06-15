import AppKit

/// Manages where snaps are written on disk and lists the most recent ones.
/// The app is not sandboxed (Hardened Runtime only), so a plain folder path works —
/// no security-scoped bookmarks needed.
@MainActor
final class SnapStore: ObservableObject {
    private let defaults = UserDefaults.standard
    private let key = "snapsDirectory"

    /// Where snaps are saved. Defaults to ~/Pictures/SelfCam.
    @Published private(set) var directory: URL

    init() {
        if let saved = UserDefaults.standard.string(forKey: "snapsDirectory") {
            directory = URL(fileURLWithPath: saved, isDirectory: true)
        } else {
            let pictures = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
                ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures")
            directory = pictures.appendingPathComponent("SelfCam", isDirectory: true)
        }
        ensureDirectory()
    }

    func setDirectory(_ url: URL) {
        directory = url
        defaults.set(url.path, forKey: key)
        ensureDirectory()
        objectWillChange.send()
    }

    private func ensureDirectory() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Encodes + writes the PNG on a background queue so the main thread never
    /// stalls on image encoding or disk I/O. Takes an immutable `CGImage` (not an
    /// `NSImage`) so there's no shared, non-thread-safe object being read on two
    /// threads at once. The filename carries milliseconds so two snaps in the same
    /// second can't overwrite each other.
    func save(_ cgImage: CGImage) {
        let dir = directory
        let url = dir.appendingPathComponent("Snap \(Self.stamp()).png")
        Self.ioQueue.async {
            let rep = NSBitmapImageRep(cgImage: cgImage)
            guard let png = rep.representation(using: .png, properties: [:]) else { return }
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try? png.write(to: url)
        }
    }

    /// Most recent snaps (newest first), up to `limit`. Enumeration runs off-main
    /// so opening the gallery never blocks, regardless of how many snaps exist.
    func recent(limit: Int, completion: @escaping ([URL]) -> Void) {
        let dir = directory
        Self.ioQueue.async {
            let urls = Self.scan(dir, limit: limit)
            DispatchQueue.main.async { completion(urls) }
        }
    }

    func revealInFinder() {
        ensureDirectory()
        NSWorkspace.shared.open(directory)
    }

    // Pure file-system helpers — run on the background `ioQueue`, touch no actor state.
    private nonisolated static func scan(_ dir: URL, limit: Int) -> [URL] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
        let files = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])) ?? []
        return files
            .filter { ["png", "jpg", "jpeg", "tiff", "heic"].contains($0.pathExtension.lowercased()) }
            .sorted { modified($0) > modified($1) }
            .prefix(limit)
            .map { $0 }
    }

    private nonisolated static func modified(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }

    private static let ioQueue = DispatchQueue(label: "selfcam.snapstore.io", qos: .utility)

    private static let stampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss.SSS"
        return f
    }()

    private static func stamp() -> String { stampFormatter.string(from: Date()) }
}
