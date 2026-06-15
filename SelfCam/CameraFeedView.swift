import SwiftUI

/// The live feed plus permission states. The camera lifecycle is driven by the
/// window controller (acquire on show / release on close), NOT by this view's
/// appearance — otherwise the session would start the moment the hosting view is
/// attached to the (still-hidden) panel at launch.
struct CameraFeedView: View {
    @EnvironmentObject var camera: CameraManager

    var body: some View {
        Group {
            switch camera.status {
            case .authorized:
                CameraPreviewView(session: camera.session, isMirrored: camera.isMirrored, zoom: camera.zoom)
            case .notDetermined:
                ProgressView()
            case .denied:
                denied
            }
        }
    }

    private var denied: some View {
        VStack(spacing: 8) {
            Image(systemName: "video.slash")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Camera access denied")
                .font(.headline)
            Button("Open Privacy Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }
}
