import SwiftUI
import ImageIO

/// Loads a downsampled thumbnail off the main thread so the gallery never decodes
/// full-resolution images during view rendering.
enum Thumbnail {
    static func load(_ url: URL, maxPixel: CGFloat) async -> NSImage? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let options: [CFString: Any] = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: maxPixel,
                    kCGImageSourceCreateThumbnailWithTransform: true
                ]
                let image = CGImageSourceCreateWithURL(url as CFURL, nil)
                    .flatMap { CGImageSourceCreateThumbnailAtIndex($0, 0, options as CFDictionary) }
                    .map { NSImage(cgImage: $0, size: .zero) }
                continuation.resume(returning: image)
            }
        }
    }
}

/// An elegant popover of the most recent snaps, with a "More…" link to the folder.
struct SnapsGalleryView: View {
    let snaps: [URL]
    let onOpen: (URL) -> Void
    let onMore: () -> Void

    private let thumb = CGSize(width: 176, height: 99) // 16:9

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text("Recent Snaps")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Button(action: onMore) {
                    HStack(spacing: 4) {
                        Text("All Snaps")
                        Image(systemName: "arrow.up.forward.app")
                    }
                    .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
                .help("Open the snaps folder in Finder")
            }

            if snaps.isEmpty {
                emptyState
            } else {
                HStack(spacing: 14) {
                    ForEach(snaps, id: \.self) { url in
                        ThumbCell(url: url, size: thumb) { onOpen(url) }
                    }
                }
            }
        }
        .padding(20)
        .frame(width: snaps.isEmpty ? 320 : CGFloat(snaps.count) * (thumb.width + 14) + 26)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.secondary)
            Text("No snaps yet")
                .font(.system(size: 13, weight: .medium))
            Text("Use Take Snap to capture one.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
    }
}

/// A single thumbnail with a hover lift and a relative-time caption.
/// The image is decoded (downsampled) asynchronously; the caption is computed once.
private struct ThumbCell: View {
    let url: URL
    let size: CGSize
    let onTap: () -> Void

    @State private var image: NSImage?
    @State private var caption = ""
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Group {
                if let image {
                    Image(nsImage: image).resizable().scaledToFill()
                } else {
                    Color.secondary.opacity(0.12)
                }
            }
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: .black.opacity(hovering ? 0.28 : 0.16), radius: hovering ? 8 : 4, y: hovering ? 3 : 1)
            .scaleEffect(hovering ? 1.03 : 1)

            Text(caption)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .help(url.lastPathComponent)
        .task(id: url) {
            caption = Self.caption(for: url)
            image = await Thumbnail.load(url, maxPixel: size.width * 2)
        }
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    private static func caption(for url: URL) -> String {
        let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
        return relativeFormatter.localizedString(for: date, relativeTo: Date())
    }
}
