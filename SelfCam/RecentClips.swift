import AppKit
import AVFoundation

/// Reads the newest recorded clips (for the menu-bar recent-clips popover) and
/// generates their poster-frame thumbnails. Read-only — `ClipWriter` produces
/// clips; this just surfaces the latest few for quick review.
enum RecentClips {
    /// One clip plus the sidecar metadata the popover needs.
    struct Clip: Identifiable, Hashable {
        let id: String
        let url: URL
        let title: String
        let createdAt: Date
    }

    /// The `limit` newest clips, sorted by the sidecar's `createdAt` (the source
    /// of truth). A `.mov` with no sidecar is skipped — a clip only "exists" once
    /// its sidecar has been written, which is what makes saves atomic.
    static func load(limit: Int, completion: @escaping ([Clip]) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let fm = FileManager.default
            let movs = (try? fm.contentsOfDirectory(
                at: LocalPaths.recordings, includingPropertiesForKeys: nil)) ?? []
            var clips: [Clip] = []
            for mov in movs where mov.pathExtension == "mov" {
                let json = mov.deletingPathExtension().appendingPathExtension("json")
                guard let data = try? Data(contentsOf: json),
                      let sc = try? SidecarCodec.decoder.decode(RecordingSidecar.self, from: data)
                else { continue }
                clips.append(Clip(id: sc.id, url: mov, title: sc.title, createdAt: sc.createdAt))
            }
            let recent = Array(clips.sorted { $0.createdAt > $1.createdAt }.prefix(limit))
            DispatchQueue.main.async { completion(recent) }
        }
    }
}

/// Poster-frame thumbnails for clips. AVFoundation (not ImageIO) because these
/// are movies — mirrors `Thumbnail` for snaps.
enum VideoThumbnail {
    static func load(_ url: URL, maxPixel: CGFloat) async -> NSImage? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
                generator.appliesPreferredTrackTransform = true
                generator.maximumSize = CGSize(width: maxPixel, height: maxPixel)
                // A little past the very start avoids the black first frame.
                let time = CMTime(seconds: 0.5, preferredTimescale: 600)
                let image = (try? generator.copyCGImage(at: time, actualTime: nil))
                    .map { NSImage(cgImage: $0, size: .zero) }
                continuation.resume(returning: image)
            }
        }
    }
}
