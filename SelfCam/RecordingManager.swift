import AVFoundation

/// Owns the recording state machine and the save. Drives `CameraManager` for
/// capture; the recording delegate hands back the finished file, which sits in
/// `.pendingSave` until the user saves or discards — stopping never silently
/// commits or drops a take. The one exception is `stopAndAutoSave()`, used when
/// the note/camera is closing, where losing the take would be worse.
///
/// Phase machine: idle → countingDown(3…1) → recording → pendingSave → idle.
/// The 3-2-1 countdown lives *here*, not in the view, so closing the note
/// cancels it — a view-owned countdown kept running invisibly and started a
/// headless recording after the panel was hidden.
@MainActor
final class RecordingManager: NSObject, ObservableObject, AVCaptureFileOutputRecordingDelegate {
    enum Phase: Equatable {
        case idle
        case countingDown(Int)
        case recording
        /// Finalized on disk, awaiting `save()` or `discard()`.
        case pendingSave(duration: TimeInterval)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var elapsed: TimeInterval = 0
    /// Increments on each successful save — a bare trigger for the "Saved!"
    /// confirmation (no rep number is stored or shown).
    @Published private(set) var saveTick = 0
    /// Bumped whenever capture fails to start — drives the error status. Without
    /// this signal the UI sat in `.recording` forever waiting for a delegate
    /// callback that was never coming.
    @Published private(set) var startFailures = 0

    var isRecording: Bool { phase == .recording }

    /// Called on the main thread with the saved movie URL once `save()` commits.
    var onSaved: ((URL) -> Void)?

    private let camera: CameraManager
    private var pendingFileURL: URL?
    private var startedAt: Date?
    private var topicText: String?
    private var pendingTitle = ""
    private var timer: Timer?
    /// Closes the async re-entry gap while the first-ever mic permission dialog
    /// is up (`phase` is still `.idle` until the user answers it).
    private var isStarting = false
    /// When set, `finalize` saves immediately instead of parking in `.pendingSave`.
    private var autoSaveOnFinalize = false

    init(camera: CameraManager) {
        self.camera = camera
        super.init()
    }

    // MARK: - Countdown → start

    /// 3-2-1 on the note, then records. Cancelled by `stopAndAutoSave()`.
    func beginCountdown(topicText: String?, title: String) {
        guard phase == .idle, !isStarting else { return }
        self.topicText = topicText
        self.pendingTitle = title
        phase = .countingDown(3)
        tickCountdown()
    }

    private func tickCountdown() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self, case .countingDown(let n) = self.phase else { return } // cancelled
            if n <= 1 {
                self.phase = .idle
                self.start()
            } else {
                self.phase = .countingDown(n - 1)
                self.tickCountdown()
            }
        }
    }

    private func start() {
        guard phase == .idle, !isStarting else { return }
        isStarting = true
        // Mic permission + recording outputs were already set up when practice
        // opened, so this changes no session config — Record is flash-free.
        LocalPaths.ensureExists()
        let url = LocalPaths.tmp.appendingPathComponent("rec-\(UUID().uuidString).mov")
        startedAt = Date()
        phase = .recording
        isStarting = false
        elapsed = 0
        startTimer()
        // Mirror read live so toggling Mirror after the note opened is honored.
        camera.startRecording(to: url, mirrored: camera.isMirrored, delegate: self) { [weak self] in
            self?.handleStartFailure()
        }
    }

    /// Capture never began (session not running / output rejected) — unwind so
    /// the UI returns to idle instead of hanging on a Stop that can't work.
    private func handleStartFailure() {
        stopTimer()
        isStarting = false
        startedAt = nil
        phase = .idle
        startFailures += 1
    }

    // MARK: - Stop / save / discard

    /// Finalizes the file and moves to `.pendingSave` — does NOT save anything yet.
    func stop() {
        guard phase == .recording else { return }
        stopTimer()
        camera.stopRecording()
    }

    /// Used when the note/camera closes: cancels a countdown, auto-saves an
    /// active recording once it finalizes, or saves a parked take — so closing
    /// mid-flow never orphans or loses anything.
    func stopAndAutoSave() {
        switch phase {
        case .countingDown:
            phase = .idle
        case .recording:
            autoSaveOnFinalize = true
            stop()
        case .pendingSave:
            save()
        case .idle:
            break
        }
    }

    /// Commits the pending take to disk. Uses the duration captured at finalize
    /// time — never recomputed here, so time spent deciding on the Save/Discard
    /// card doesn't inflate the sidecar.
    func save() {
        guard case .pendingSave(let duration) = phase,
              let fileURL = pendingFileURL, let started = startedAt else { return }
        do {
            let saved = try ClipWriter.commit(
                tmpMovURL: fileURL, title: pendingTitle,
                topicText: topicText, createdAt: started, duration: duration
            )
            reset()
            saveTick += 1
            onSaved?(saved)
        } catch {
            try? FileManager.default.removeItem(at: fileURL)
            reset()
        }
    }

    /// Throws the pending take away.
    func discard() {
        guard case .pendingSave = phase, let fileURL = pendingFileURL else { return }
        try? FileManager.default.removeItem(at: fileURL)
        reset()
    }

    private func reset() {
        pendingFileURL = nil
        startedAt = nil
        isStarting = false
        autoSaveOnFinalize = false
        phase = .idle
    }

    // MARK: - Timer

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let started = self.startedAt, self.phase == .recording else { return }
                self.elapsed = Date().timeIntervalSince(started)
                // No time cap — recording runs until the user presses Stop.
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - AVCaptureFileOutputRecordingDelegate (fires on a private queue)

    nonisolated func fileOutput(_ output: AVCaptureFileOutput,
                                didFinishRecordingTo outputFileURL: URL,
                                from connections: [AVCaptureConnection],
                                error: Error?) {
        // The output knows the exact recorded length — wall-clock from
        // `startedAt` overstates it by the ~0.7 s the session takes to spin up.
        let recorded = output.recordedDuration
        let recordedSeconds = (recorded.isValid && !recorded.isIndefinite) ? CMTimeGetSeconds(recorded) : nil
        Task { @MainActor in self.finalize(fileURL: outputFileURL, recordedSeconds: recordedSeconds, error: error) }
    }

    private func finalize(fileURL: URL, recordedSeconds: Double?, error: Error?) {
        stopTimer()
        camera.finishRecordingCleanup()
        guard error == nil, let started = startedAt else {
            try? FileManager.default.removeItem(at: fileURL)
            reset()
            return
        }
        pendingFileURL = fileURL
        phase = .pendingSave(duration: recordedSeconds ?? Date().timeIntervalSince(started))
        if autoSaveOnFinalize {
            autoSaveOnFinalize = false
            save()
        }
    }
}
