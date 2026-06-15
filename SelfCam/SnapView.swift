import SwiftUI

/// A captured still you can mark up with a marker, in a clean editor.
struct SnapView: View {
    let image: NSImage
    let onDone: () -> Void

    private struct Stroke { var points: [CGPoint]; var color: Color }

    @State private var strokes: [Stroke] = []
    @State private var current: Stroke?
    @State private var color: Color = .red

    // 16:9 to match the camera feed (shows the full snap, no cropping).
    private let photoWidth: CGFloat = 460
    private var photoHeight: CGFloat { (photoWidth * 9 / 16).rounded() }
    private let palette: [Color] = [.red, .orange, .yellow, .green, .blue, .black, .white]

    var body: some View {
        VStack(spacing: 18) {
            photoCard

            HStack(spacing: 16) {
                swatches
                Spacer(minLength: 12)
                toolbar
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(22)
        .frame(width: photoWidth + 44)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Photo

    private var photoCard: some View {
        ZStack {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: photoWidth, height: photoHeight)
                .clipped()

            Canvas { context, _ in
                for stroke in strokes { draw(stroke, in: context) }
                if let current { draw(current, in: context) }
            }
            .frame(width: photoWidth, height: photoHeight)
            .allowsHitTesting(false)
        }
        .frame(width: photoWidth, height: photoHeight)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if current == nil { current = Stroke(points: [], color: color) }
                    current?.points.append(value.location)
                }
                .onEnded { _ in
                    if let current { strokes.append(current) }
                    current = nil
                }
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.22), radius: 14, y: 6)
    }

    // MARK: - Controls

    private var swatches: some View {
        HStack(spacing: 9) {
            ForEach(palette, id: \.self) { swatch in
                Circle()
                    .fill(swatch)
                    .frame(width: 20, height: 20)
                    .overlay(Circle().stroke(Color.secondary.opacity(0.35), lineWidth: 0.5))
                    .overlay(
                        Circle()
                            .stroke(Color.accentColor, lineWidth: 2)
                            .padding(-3)
                            .opacity(color == swatch ? 1 : 0)
                    )
                    .contentShape(Circle())
                    .onTapGesture { color = swatch }
                    .help("Marker colour")
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Button("Clear") { strokes.removeAll() }
                .disabled(strokes.isEmpty)
            Button("Copy") { copyToClipboard() }
            Button("Save") { save() }
            Button("Done", action: onDone)
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
        }
        .controlSize(.large)
        .fixedSize()   // never truncate the labels
    }

    private func draw(_ stroke: Stroke, in context: GraphicsContext) {
        guard stroke.points.count > 1 else { return }
        var path = Path()
        path.addLines(stroke.points)
        context.stroke(path, with: .color(stroke.color),
                       style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
    }

    // MARK: - Export

    @MainActor private func render() -> NSImage? {
        let renderer = ImageRenderer(content: photoCard)
        renderer.scale = 2
        return renderer.nsImage
    }

    private func copyToClipboard() {
        guard let image = render() else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
    }

    private func save() {
        guard let image = render(),
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "Snap.png"
        if panel.runModal() == .OK, let url = panel.url {
            try? png.write(to: url)
        }
    }
}
