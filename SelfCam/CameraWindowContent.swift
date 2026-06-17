import SwiftUI

/// Unions the base mask shape with a small upward-pointing triangle at the
/// top centre so the camera feed renders through the attachment protrusion.
private struct MaskWithArrow: Shape {
    let base: AnyShape
    private let arrowWidth: CGFloat = 18
    private let arrowHeight: CGFloat = 11

    func path(in rect: CGRect) -> Path {
        // Base mask in lower portion; arrow occupies the top arrowHeight pixels.
        // Everything stays within rect so SwiftUI doesn't clip it away.
        let bodyRect = CGRect(x: rect.minX, y: rect.minY + arrowHeight,
                              width: rect.width, height: rect.height - arrowHeight)
        var p = base.path(in: bodyRect)
        let ax = rect.midX
        let arrowBase = rect.minY + arrowHeight
        let leftX = ax - arrowWidth / 2
        let rightX = ax + arrowWidth / 2
        // Arc-tangent rounding: produces a smooth curve at the tip instead of a sharp point
        p.move(to: CGPoint(x: leftX, y: arrowBase))
        p.addArc(tangent1End: CGPoint(x: ax, y: rect.minY),
                 tangent2End: CGPoint(x: rightX, y: arrowBase),
                 radius: 5)
        p.addLine(to: CGPoint(x: rightX, y: arrowBase))
        p.closeSubpath()
        return p
    }
}

/// Contents of the camera window: live feed clipped to the chosen shape
/// (plus an attachment-arrow protrusion when docked), and shape-aware hover controls.
struct CameraWindowContent: View {
    @ObservedObject var app: AppController
    let onClose: () -> Void
    @State private var hovering = false

    private var effectiveShape: AnyShape {
        app.isDetached
            ? app.mask.anyShape
            : AnyShape(MaskWithArrow(base: app.mask.anyShape))
    }

    var body: some View {
        CameraFeedView()
            .clipShape(effectiveShape)
            .animation(.easeInOut(duration: 0.18), value: app.isDetached)
            // Hover controls — placement is shape-aware
            .overlay {
                if hovering && app.isDetached {
                    GeometryReader { geo in
                        let isCircle = app.mask == .circle
                        let inset = app.mask.safeInset(for: geo.size)
                        Color.clear
                            // Close ✕: top-center for circle, top-trailing for others
                            .overlay(alignment: isCircle ? .top : .topTrailing) {
                                hoverButton(systemName: "xmark.circle.fill") { onClose() }
                                    .padding(isCircle ? .top : .trailing,
                                             isCircle ? 8 : inset)
                            }
                    }
                }
            }
            .onHover { hovering = $0 }
    }

    private func hoverButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 18))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .black.opacity(0.45))
        }
        .buttonStyle(.plain)
        .padding(8)
    }
}
