import SwiftUI
import AVFoundation

/// Hosts an AVCaptureVideoPreviewLayer and mirrors / zooms it when requested.
struct CameraPreviewView: NSViewRepresentable {
    let session: AVCaptureSession
    let isMirrored: Bool
    var zoom: CGFloat = 1

    func makeNSView(context: Context) -> PreviewNSView {
        let view = PreviewNSView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        view.mirrored = isMirrored
        view.zoom = zoom
        return view
    }

    func updateNSView(_ nsView: PreviewNSView, context: Context) {
        nsView.mirrored = isMirrored
        nsView.zoom = zoom
    }
}

final class PreviewNSView: NSView {
    let previewLayer = AVCaptureVideoPreviewLayer()
    var mirrored: Bool = true { didSet { if mirrored != oldValue { applyMirror() } } }
    var zoom: CGFloat = 1 { didSet { if zoom != oldValue { applyZoom() } } }

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
        applyZoom()
        applyMirror()
    }

    private func applyZoom() {
        // Scale around the layer centre (anchor 0.5,0.5) with no implicit animation.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        previewLayer.transform = CATransform3DMakeScale(max(1, zoom), max(1, zoom), 1)
        CATransaction.commit()
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
