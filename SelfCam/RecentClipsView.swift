import SwiftUI

/// A compact vertical list of the most recent clips — the menu-bar counterpart
/// to `SnapsGalleryView`. Tapping a row plays the clip.
struct RecentClipsView: View {
    let clips: [RecentClips.Clip]
    let onOpen: (RecentClips.Clip) -> Void
    let onMore: () -> Void

    private let thumb = CGSize(width: 80, height: 45) // 16:9

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Recent Clips")
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
                .help("Open the recordings folder in Finder")
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider()

            if clips.isEmpty {
                emptyState
            } else {
                VStack(spacing: 2) {
                    ForEach(clips) { clip in
                        ClipCell(clip: clip, size: thumb) { onOpen(clip) }
                    }
                }
                .padding(.vertical, 6)
            }
        }
        .frame(width: 300)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "film")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(.secondary)
            Text("No clips yet")
                .font(.system(size: 13, weight: .medium))
            Text("Record a table topic to see it here.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }
}

/// A row: 16:9 poster thumbnail, then the clip title over a relative-time label.
private struct ClipCell: View {
    let clip: RecentClips.Clip
    let size: CGSize
    let onTap: () -> Void

    @State private var image: NSImage?
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

            VStack(alignment: .leading, spacing: 2) {
                Text(clip.title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Text(Self.relativeFormatter.localizedString(for: clip.createdAt, relativeTo: Date()))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

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
        .help(clip.title)
        .task(id: clip.url) {
            image = await VideoThumbnail.load(clip.url, maxPixel: size.width * 2)
        }
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()
}
