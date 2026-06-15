import SwiftUI

/// Contents of the camera window: clean live feed, masked to the chosen shape.
/// On hover it shows a gear (settings) while attached, or a close ✕ while detached.
struct CameraWindowContent: View {
    @ObservedObject var app: AppController
    let onClose: () -> Void
    @State private var hovering = false

    var body: some View {
        CameraFeedView()
            .clipShape(app.mask.anyShape)   // clip the feed only…
            .overlay {                        // …so the hover buttons are never cut off
                if hovering && !app.isDetached {
                    hoverButton(systemName: "gearshape.fill", alignment: .topLeading) {
                        app.openSettings()
                    }
                }
                if hovering && app.isDetached {
                    hoverButton(systemName: "xmark.circle.fill", alignment: .topTrailing) {
                        onClose()
                    }
                }
            }
            .onHover { hovering = $0 }
    }

    private func hoverButton(systemName: String, alignment: Alignment,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 18))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .black.opacity(0.45))
        }
        .buttonStyle(.plain)
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
    }
}
