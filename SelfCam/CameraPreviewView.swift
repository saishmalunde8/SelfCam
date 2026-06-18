import SwiftUI
import AVFoundation

/// Hosts an AVCaptureVideoPreviewLayer and mirrors it when requested.
/// (Zoom is a SwiftUI `.scaleEffect` on this view — see CameraFeedView.)
struct CameraPreviewView: NSViewRepresentable {
    let session: AVCaptureSession
    let isMirrored: Bool

    func makeNSView(context: Context) -> PreviewNSView {
        let view = PreviewNSView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        view.mirrored = isMirrored
        return view
    }

    func updateNSView(_ nsView: PreviewNSView, context: Context) {
        nsView.mirrored = isMirrored
    }
}

final class PreviewNSView: NSView {
    let previewLayer = AVCaptureVideoPreviewLayer()
    var mirrored: Bool = true { didSet { if mirrored != oldValue { applyMirror() } } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer = CALayer()
        layer?.masksToBounds = true   // clip the scaled preview
        layer?.addSublayer(previewLayer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    override func layout() {
        super.layout()
        previewLayer.frame = bounds
        applyMirror()
    }

    private func applyMirror() {
        guard let connection = previewLayer.connection,
              connection.isVideoMirroringSupported else { return }
        connection.automaticallyAdjustsVideoMirroring = false
        if connection.isVideoMirrored != mirrored {
            connection.isVideoMirrored = mirrored
        }
    }
}
