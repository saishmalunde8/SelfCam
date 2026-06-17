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

/// A compact vertical list of the most recent snaps.
struct SnapsGalleryView: View {
    let snaps: [URL]
    let onOpen: (URL) -> Void
    let onMore: () -> Void

    private let thumb = CGSize(width: 80, height: 45) // 16:9

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(alignment: .firstTextBaseline) {
                Text("Recent Snaps")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button(action: onMore) {
                    HStack(spacing: 3) {
                        Text("All")
                        Image(systemName: "arrow.up.forward.app")
                    }
                    .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
                .help("Open the snaps folder in Finder")
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider()

            if snaps.isEmpty {
                emptyState
            } else {
                VStack(spacing: 2) {
                    ForEach(snaps, id: \.self) { url in
                        ThumbCell(url: url, size: thumb) { onOpen(url) }
                    }
                }
                .padding(.vertical, 6)
            }
        }
        .frame(width: 260)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(.secondary)
            Text("No snaps yet")
                .font(.system(size: 13, weight: .medium))
            Text("Use Take Snap to capture one.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }
}

/// A compact horizontal row: small 16:9 thumbnail on the left, relative-time label on the right.
private struct ThumbCell: View {
    let url: URL
    let size: CGSize
    let onTap: () -> Void

    @State private var image: NSImage?
    @State private var caption = ""
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if let image {
                    Image(nsImage: image).resizable().scaledToFill()
                } else {
                    Color.secondary.opacity(0.12)
                }
            }
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )

            Text(caption)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 10)
        .background(hovering ? Color.primary.opacity(0.06) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
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
