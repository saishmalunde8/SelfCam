import AVFoundation
import AppKit

/// Single source of truth for the capture session: permission, device list,
/// mirroring, zoom, and snapshots.
///
/// Threading contract: the reference counter (`consumers`) and `captureDelegates`
/// are mutated on the **main thread only**. AVFoundation's photo callback fires on
/// a private thread, so it hops back to main before touching either — this is what
/// keeps the refcount deterministic (the earlier version raced across three threads
/// and drifted out of sync after a few snaps, stalling the session).
final class CameraManager: ObservableObject {
    enum Status { case notDetermined, authorized, denied }

    @Published var status: Status
    @Published var devices: [AVCaptureDevice] = []
    @Published var selectedDeviceID: String = UserDefaults.standard.string(forKey: Keys.device) ?? ""
    @Published var isMirrored: Bool = (UserDefaults.standard.object(forKey: Keys.mirror) as? Bool) ?? true {
        didSet { UserDefaults.standard.set(isMirrored, forKey: Keys.mirror) }
    }

    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let movieOutput = AVCaptureMovieFileOutput()
    private var currentInput: AVCaptureDeviceInput?
    private var audioInput: AVCaptureDeviceInput?
    private let queue = DispatchQueue(label: "selfcam.session")
    private var consumers = 0
    private var captureDelegates: [PhotoCaptureDelegate] = []

    /// True while a movie is being written. Published for the recording UI.
    @Published private(set) var isRecording = false
    /// True while the movie + audio outputs are attached (practice mode). They're
    /// added when practice opens — NOT at Record — so pressing Record never
    /// reconfigures the running session (which blanked the preview for a frame)
    /// and the audio connection is fully live before recording begins.
    private var recordingModeActive = false
    /// Whether the audio track is currently captured (the mic on/off toggle).
    @Published private(set) var micEnabled = false
    /// The system's actual mic-permission decision — read fresh, not cached, so
    /// it reflects changes made in Settings outside the app.
    var micAuthStatus: AVAuthorizationStatus { AVCaptureDevice.authorizationStatus(for: .audio) }

    private enum Keys {
        static let device = "selectedDeviceID"
        static let mirror = "isMirrored"
    }

    private static let deviceTypes: [AVCaptureDevice.DeviceType] =
        [.builtInWideAngleCamera, .external, .continuityCamera]

    private var observers: [NSObjectProtocol] = []

    init() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: status = .authorized
        case .denied, .restricted: status = .denied
        default: status = .notDetermined
        }
        setupObservers()
    }

    deinit { observers.forEach { NotificationCenter.default.removeObserver($0) } }

    // MARK: - Resilience (interruptions, errors, hot-plug)

    private func setupObservers() {
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: .AVCaptureSessionRuntimeError, object: session,
                                        queue: .main) { [weak self] _ in self?.restartIfNeeded() })
        observers.append(nc.addObserver(forName: .AVCaptureSessionInterruptionEnded, object: session,
                                        queue: .main) { [weak self] _ in self?.restartIfNeeded() })
        observers.append(nc.addObserver(forName: .AVCaptureDeviceWasConnected, object: nil,
                                        queue: .main) { [weak self] _ in self?.refreshDevices(); self?.restartIfNeeded() })
        observers.append(nc.addObserver(forName: .AVCaptureDeviceWasDisconnected, object: nil,
                                        queue: .main) { [weak self] _ in self?.refreshDevices(); self?.restartIfNeeded() })
    }

    /// Re-resolves the device and ensures the session is running again after an
    /// interruption, runtime error, or hot-plug — but only if something still wants it.
    private func restartIfNeeded() {
        guard consumers > 0 else { return }
        let id = resolvedDeviceID()
        guard !id.isEmpty else { return }
        if selectedDeviceID != id { selectedDeviceID = id }
        configureInput(deviceID: id, thenRun: true)
    }

    // MARK: - Lifecycle (reference counted)

    func acquire() {
        dispatchPrecondition(condition: .onQueue(.main)) // refcount is main-thread only
        consumers += 1
        if consumers == 1 { startSession() }
    }

    func release() {
        dispatchPrecondition(condition: .onQueue(.main)) // refcount is main-thread only
        consumers = max(0, consumers - 1)
        if consumers == 0 { stopSession() }
    }

    private func startSession() {
        switch status {
        case .authorized:
            runResolvedDevice()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.status = granted ? .authorized : .denied
                    if granted, let self, self.consumers > 0 { self.runResolvedDevice() }
                }
            }
        case .denied:
            break
        }
    }

    private func stopSession() {
        queue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
    }

    // MARK: - Devices

    /// Populates the device list for the menu/settings. Discovery (which can probe for
    /// Continuity Camera and is not always fast) runs OFF the main thread; results
    /// publish back on main. Kept off the launch critical path.
    func refreshDevices() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let discovered = AVCaptureDevice.DiscoverySession(
                deviceTypes: Self.deviceTypes, mediaType: .video, position: .unspecified
            ).devices
            DispatchQueue.main.async {
                guard let self else { return }
                self.devices = discovered
                if self.selectedDeviceID.isEmpty
                    || !discovered.contains(where: { $0.uniqueID == self.selectedDeviceID }) {
                    let fallback = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
                        ?? discovered.first
                    self.selectedDeviceID = fallback?.uniqueID ?? ""
                }
            }
        }
    }

    func select(deviceID: String) {
        guard deviceID != selectedDeviceID || currentInput == nil else { return }
        selectedDeviceID = deviceID
        UserDefaults.standard.set(deviceID, forKey: Keys.device)
        configureInput(deviceID: deviceID, thenRun: false)
    }

    private func runResolvedDevice() {
        let id = resolvedDeviceID()
        guard !id.isEmpty else { return }
        if selectedDeviceID != id { selectedDeviceID = id }
        configureInput(deviceID: id, thenRun: true)
        refreshDevices() // update the menu list in the background
    }

    /// Resolves a device to open WITHOUT a full discovery pass, so opening the window
    /// stays fast (discovery only feeds the menu list).
    private func resolvedDeviceID() -> String {
        if !selectedDeviceID.isEmpty, AVCaptureDevice(uniqueID: selectedDeviceID) != nil {
            return selectedDeviceID
        }
        return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)?.uniqueID ?? ""
    }

    private func configureInput(deviceID: String, thenRun: Bool) {
        queue.async { [weak self] in
            guard let self, let device = AVCaptureDevice(uniqueID: deviceID) else { return }
            self.session.beginConfiguration()
            self.session.sessionPreset = .high
            if let current = self.currentInput {
                self.session.removeInput(current)
                self.currentInput = nil
            }
            if let input = try? AVCaptureDeviceInput(device: device), self.session.canAddInput(input) {
                self.session.addInput(input)
                self.currentInput = input
            }
            if !self.session.outputs.contains(self.photoOutput), self.session.canAddOutput(self.photoOutput) {
                self.session.addOutput(self.photoOutput)
            }
            self.session.commitConfiguration()
            if thenRun, !self.session.isRunning { self.session.startRunning() }
        }
    }

    // MARK: - Zoom
    //
    // macOS AVCaptureDevice has no `videoZoomFactor` (iOS-only), so zoom is done in
    // software: the preview layer is scaled by `zoom`, and snaps are centre-cropped
    // by the same factor so the saved image matches what you see.

    /// Live zoom factor, observed by the preview. 1×–3×.
    @Published var zoom: CGFloat = 1

    func setZoom(_ factor: CGFloat) {
        let clamped = max(1, min(factor, 3))
        if Thread.isMainThread { zoom = clamped }
        else { DispatchQueue.main.async { self.zoom = clamped } }
    }

    /// Centre-crops an image by `factor` (≥1) to mirror the preview zoom.
    /// Works on the underlying CGImage directly (no TIFF round-trip).
    private static func centerCrop(_ image: NSImage, factor: CGFloat) -> NSImage {
        guard factor > 1.01 else { return image }
        var rect = CGRect(origin: .zero, size: image.size)
        guard let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return image }
        let w = CGFloat(cg.width), h = CGFloat(cg.height)
        let cw = (w / factor).rounded(), ch = (h / factor).rounded()
        let crop = CGRect(x: ((w - cw) / 2).rounded(), y: ((h - ch) / 2).rounded(), width: cw, height: ch)
        guard let cropped = cg.cropping(to: crop) else { return image }
        return NSImage(cgImage: cropped, size: NSSize(width: cw, height: ch))
    }

    // MARK: - Snaps

    /// Must be called on the main thread.
    func captureSnap(mirrored: Bool, completion: @escaping (NSImage?) -> Void) {
        acquire() // ensure the session is running
        let zoomFactor = zoom // read on main; applied as a centre-crop below

        // `completion`+`release` must run exactly once, on main. A 5s watchdog
        // guarantees the session is never left acquired if the capture stalls
        // (interrupted, device yanked, callback dropped) — otherwise the camera
        // would stay powered with the green light on indefinitely.
        var finished = false
        func finishOnce(_ image: NSImage?) {
            dispatchPrecondition(condition: .onQueue(.main)) // `finished`/`release` are main-only
            guard !finished else { return }
            finished = true
            completion(image)
            release()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { finishOnce(nil) }

        queue.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self else { return }
            let ready = self.session.isRunning && self.session.outputs.contains(self.photoOutput)
            guard ready else {
                DispatchQueue.main.async { finishOnce(nil) }
                return
            }
            if let connection = self.photoOutput.connection(with: .video), connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = mirrored
            }
            let delegate = PhotoCaptureDelegate { [weak self] image, delegate in
                // Fires on AVFoundation's private thread — hop to main for ALL bookkeeping.
                let zoomed = image.map { Self.centerCrop($0, factor: zoomFactor) }
                DispatchQueue.main.async {
                    self?.captureDelegates.removeAll { $0 === delegate } // always clean up by identity
                    finishOnce(zoomed)
                }
            }
            DispatchQueue.main.async { self.captureDelegates.append(delegate) }
            self.photoOutput.capturePhoto(with: AVCapturePhotoSettings(), delegate: delegate)
        }
    }

    // MARK: - Recording (movie + audio)
    //
    // All session mutation stays on `queue` — the same serial queue used for
    // input/photo config — so recording never races the rest of the session.
    // The movie + audio outputs live for the whole practice session (added by
    // `beginRecordingMode`, removed by `endRecordingMode`); Record itself changes
    // no session configuration. This is what makes Record flash-free AND ensures
    // the audio connection is already live when recording starts.

    /// Attaches the movie output — one configuration, done when practice opens,
    /// so Record itself never reconfigures the session (no preview flash). The
    /// mic input is attached here too, but ONLY if already authorized; if
    /// permission hasn't been decided yet, this does NOT prompt — the note's mic
    /// button requests it directly, in response to that tap (system permission
    /// prompts are far more reliable when triggered by a fresh user gesture
    /// rather than as a side effect of opening a window).
    func beginRecordingMode() {
        dispatchPrecondition(condition: .onQueue(.main))
        recordingModeActive = true
        let alreadyAuthorized = micAuthStatus == .authorized
        micEnabled = alreadyAuthorized
        queue.async { [weak self] in
            guard let self else { return }
            self.session.beginConfiguration()
            if alreadyAuthorized, self.audioInput == nil,
               let mic = AVCaptureDevice.default(for: .audio),
               let input = try? AVCaptureDeviceInput(device: mic),
               self.session.canAddInput(input) {
                self.session.addInput(input)
                self.audioInput = input
            }
            if !self.session.outputs.contains(self.movieOutput), self.session.canAddOutput(self.movieOutput) {
                self.session.addOutput(self.movieOutput)
            }
            self.session.commitConfiguration()
        }
    }

    /// Called directly from the note's mic-icon tap. If permission was never
    /// decided, activates the app and asks — the direct-response-to-a-click
    /// context is what makes the system dialog reliably appear. Once granted (now
    /// or previously), attaches the mic input live if it wasn't already there.
    func requestMicrophoneAccess(completion: @escaping (Bool) -> Void) {
        dispatchPrecondition(condition: .onQueue(.main))
        switch micAuthStatus {
        case .authorized:
            attachAudioInputIfNeeded { completion(true) }
        case .notDetermined:
            NSApp.activate(ignoringOtherApps: true)
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else { completion(granted); return }
                    if granted {
                        self.attachAudioInputIfNeeded { completion(true) }
                    } else {
                        completion(false)
                    }
                }
            }
        case .denied, .restricted:
            completion(false)
        @unknown default:
            completion(false)
        }
    }

    /// Adds the mic input to the already-running session if it isn't there yet
    /// (e.g. permission was granted after practice mode already opened
    /// video-only). A brief one-time reconfiguration — expected only right after
    /// granting, not on every Record.
    private func attachAudioInputIfNeeded(_ completion: @escaping () -> Void) {
        guard recordingModeActive else { completion(); return }
        queue.async { [weak self] in
            guard let self else { DispatchQueue.main.async { completion() }; return }
            if self.audioInput == nil,
               let mic = AVCaptureDevice.default(for: .audio),
               let input = try? AVCaptureDeviceInput(device: mic) {
                self.session.beginConfiguration()
                if self.session.canAddInput(input) {
                    self.session.addInput(input)
                    self.audioInput = input
                }
                self.session.commitConfiguration()
            }
            DispatchQueue.main.async {
                self.micEnabled = true
                completion()
            }
        }
    }

    /// Removes the recording outputs when practice closes.
    func endRecordingMode() {
        dispatchPrecondition(condition: .onQueue(.main))
        recordingModeActive = false
        queue.async { [weak self] in
            guard let self else { return }
            self.session.beginConfiguration()
            if let audio = self.audioInput {
                self.session.removeInput(audio)
                self.audioInput = nil
            }
            if self.session.outputs.contains(self.movieOutput) {
                self.session.removeOutput(self.movieOutput)
            }
            self.session.commitConfiguration()
        }
    }

    /// Mic on/off — flips the audio connection's `isEnabled`, which needs no
    /// reconfiguration (so it's instant and flash-free). Only meaningful once
    /// authorized and attached; an un-authorized tap is routed to
    /// `requestMicrophoneAccess` instead of here.
    func setMicEnabled(_ enabled: Bool) {
        guard micAuthStatus == .authorized, audioInput != nil else { return }
        micEnabled = enabled
        queue.async { [weak self] in
            self?.movieOutput.connection(with: .audio)?.isEnabled = enabled
        }
    }

    /// Starts writing to `url`. The outputs are already attached, so this changes
    /// NO session configuration — no preview flash. If capture can't start, the
    /// acquire is released and `onStartFailure` fires on main so the caller can
    /// unwind (otherwise it would wait forever for a delegate that never comes).
    func startRecording(to url: URL, mirrored: Bool,
                        delegate: AVCaptureFileOutputRecordingDelegate,
                        onStartFailure: @escaping () -> Void) {
        dispatchPrecondition(condition: .onQueue(.main))
        acquire()
        queue.async { [weak self] in
            guard let self else { return }
            if let connection = self.movieOutput.connection(with: .video), connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = mirrored
            }
            let ready = self.session.isRunning
                && self.session.outputs.contains(self.movieOutput)
                && !self.movieOutput.isRecording
            guard ready else {
                DispatchQueue.main.async {
                    self.isRecording = false
                    self.release()
                    onStartFailure()
                }
                return
            }
            self.movieOutput.startRecording(to: url, recordingDelegate: delegate)
            DispatchQueue.main.async { self.isRecording = true }
        }
    }

    func stopRecording() {
        queue.async { [weak self] in
            guard let self, self.movieOutput.isRecording else { return }
            self.movieOutput.stopRecording()
        }
    }

    /// Call from the recording delegate once the file is finalized. Releases the
    /// recording acquire; the outputs stay attached for the rest of the practice
    /// session (removed by `endRecordingMode`).
    func finishRecordingCleanup() {
        dispatchPrecondition(condition: .onQueue(.main))
        isRecording = false
        release()
    }
}

/// Retained per-capture; bridges AVCapturePhoto to an NSImage. Passes itself back
/// in the handler so the manager can remove it by identity (no retain cycle).
final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    private let handler: (NSImage?, PhotoCaptureDelegate) -> Void
    init(handler: @escaping (NSImage?, PhotoCaptureDelegate) -> Void) { self.handler = handler }

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        let image = photo.fileDataRepresentation().flatMap { NSImage(data: $0) }
        handler(image, self)
    }
}
