import SwiftUI
import AppKit

/// Sticky-note practice panel: shows a table topic (always visible), cycles
/// prompts, records a take, and saves it into ~/Movies/SelfCam.
///
/// Palette is explicit (dark ink on warm paper) so every control reads clearly
/// on the yellow — `.borderedProminent` rendered white-on-light before. All
/// transient feedback (countdown ring, save check, status) renders INSIDE the
/// note's frame so the panel window never clips it.
struct NoteView: View {
    @ObservedObject var topics: TopicStore
    @ObservedObject var recording: RecordingManager
    @ObservedObject var camera: CameraManager

    @State private var statusText: String?
    @State private var statusIsError = false
    @State private var statusGeneration = 0
    @State private var lowDisk = false
    @State private var showSaveCheck = false   // just-saved → checkmark animation
    @State private var categoryMenuOpen = false

    // Palette
    private let paper     = Color(red: 0.99,  green: 0.94, blue: 0.73)
    private let paperEdge = Color(red: 0.87,  green: 0.79, blue: 0.52)
    private let ruleLine  = Color(red: 0.82,  green: 0.72, blue: 0.45)
    private let ink       = Color(red: 0.22,  green: 0.17, blue: 0.08)
    private let ochre     = Color(red: 0.60,  green: 0.43, blue: 0.06)  // category label
    private let terracotta = Color(red: 0.74, green: 0.33, blue: 0.22)
    private let olive     = Color(red: 0.28,  green: 0.47, blue: 0.28)
    private let cream     = Color(red: 0.99,  green: 0.97, blue: 0.90)

    private var inkSoft: Color { ink.opacity(0.55) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
                .zIndex(1)   // keep the category dropdown above the topic/controls below it
            topicArea
            Spacer(minLength: 2)
            if recording.isRecording { timerPill }
            statusZone
            controls
        }
        .padding(14)
        .frame(width: 220, height: 260)
        .background {
            ZStack {
                paper
                ruledPaper
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(paperEdge, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay { countdownOverlay }
        .overlay { saveOverlay }
        .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
        .padding(NotePanel.contentInset) // margin so the shadow isn't clipped
        .onAppear { topics.ensureCurrent() }
        .onChange(of: recording.saveTick) { _, _ in
            triggerSaveAnimation()
            SoundCue.playSave()
        }
        .onChange(of: recording.phase) { old, new in
            if new == .recording && old != .recording { SoundCue.playStart() }
        }
        .onChange(of: recording.startFailures) { _, count in
            guard count > 0 else { return }
            showStatus("Couldn't start recording", isError: true)
        }
    }

    // MARK: - Paper texture

    private var ruledPaper: some View {
        GeometryReader { geo in
            Path { p in
                let spacing: CGFloat = 22
                var y = spacing
                while y < geo.size.height {
                    p.move(to: CGPoint(x: 10, y: y))
                    p.addLine(to: CGPoint(x: geo.size.width - 10, y: y))
                    y += spacing
                }
            }
            .stroke(ruleLine.opacity(0.22), lineWidth: 0.5)
        }
    }

    // MARK: - Header (category picker + mic)

    private var header: some View {
        HStack {
            categoryPicker
            Spacer()
            micToggle
        }
    }

    /// A plain custom dropdown rather than SwiftUI's `Menu` — on macOS, `Menu`
    /// with `.menuStyle(.borderlessButton)` renders its label through native
    /// button chrome that ignores `foregroundStyle`/`tint` on custom label
    /// content, so the ochre color never actually showed. Plain buttons have no
    /// such override.
    private var categoryPicker: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeOut(duration: 0.15)) { categoryMenuOpen.toggle() }
            } label: {
                HStack(spacing: 3) {
                    Text(topics.categoryFilter?.label ?? "All categories")
                    Image(systemName: "chevron.down").font(.system(size: 7, weight: .bold))
                }
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(ochre)
            }
            .buttonStyle(.plain)
        }
        .overlay(alignment: .topLeading) {
            if categoryMenuOpen {
                categoryDropdown.offset(y: 20)
            }
        }
    }

    private var categoryDropdown: some View {
        VStack(alignment: .leading, spacing: 1) {
            categoryRow("All categories") { topics.categoryFilter = nil }
            ForEach(TopicCategory.allCases, id: \.self) { cat in
                categoryRow(cat.label) { topics.categoryFilter = cat }
            }
        }
        .padding(4)
        .frame(width: 130, alignment: .leading)
        .background(paper)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(paperEdge, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .shadow(color: .black.opacity(0.2), radius: 6, y: 2)
        .zIndex(10)
    }

    private func categoryRow(_ label: String, action: @escaping () -> Void) -> some View {
        Button {
            action()
            withAnimation(.easeOut(duration: 0.15)) { categoryMenuOpen = false }
        } label: {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(ink.opacity(0.75))
                .padding(.horizontal, 6).padding(.vertical, 3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
    }

    /// Tap behavior depends on the live system permission:
    /// - never asked → request it directly (a fresh click reliably triggers the
    ///   system prompt, unlike requesting as a side effect of opening the note)
    /// - authorized → plain on/off toggle
    /// - denied → open the Microphone settings pane (macOS won't re-prompt)
    private var micToggle: some View {
        Button {
            switch camera.micAuthStatus {
            case .authorized:
                camera.setMicEnabled(!camera.micEnabled)
            case .notDetermined:
                camera.requestMicrophoneAccess { _ in }
            case .denied, .restricted:
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                    NSWorkspace.shared.open(url)
                }
            @unknown default:
                break
            }
        } label: {
            Image(systemName: micIconName)
                .font(.system(size: 12))
                .foregroundStyle(micIconColor)
        }
        .buttonStyle(.plain)
        .help(micHelpText)
    }

    private var micIconName: String {
        switch camera.micAuthStatus {
        case .authorized: return camera.micEnabled ? "mic.fill" : "mic.slash.fill"
        case .denied, .restricted: return "mic.slash.fill"
        default: return "mic"
        }
    }

    private var micIconColor: Color {
        switch camera.micAuthStatus {
        case .authorized: return camera.micEnabled ? ink.opacity(0.7) : inkSoft
        case .denied, .restricted: return terracotta
        default: return ochre
        }
    }

    private var micHelpText: String {
        switch camera.micAuthStatus {
        case .authorized: return camera.micEnabled ? "Mic on — click to mute" : "Mic off — click to unmute"
        case .denied, .restricted: return "Microphone access denied — click to open Settings"
        default: return "Click to allow microphone access"
        }
    }

    private var micStatusMessage: String {
        switch camera.micAuthStatus {
        case .authorized: return "Mic off — no audio in this take"
        case .denied, .restricted: return "Mic access denied"
        default: return "Tap the mic icon to allow audio"
        }
    }

    // MARK: - Topic (always visible)

    private var topicArea: some View {
        ZStack(alignment: .topLeading) {
            Text(topics.current?.text ?? "No topics yet")
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(ink.opacity(dimTopic ? 0.35 : 0.9))
                .lineLimit(7)
                .minimumScaleFactor(0.65)
                .frame(maxWidth: .infinity, alignment: .leading)
                .id(topics.current?.id)            // new identity → reveal transition
                .transition(.opacity)
        }
        .animation(.easeInOut(duration: 0.22), value: topics.current?.id)
    }

    /// Topic dims while the countdown ring takes focus.
    private var dimTopic: Bool { isCountingDown }

    // MARK: - Timer pill (below topic, only while recording)

    private var timerPill: some View {
        HStack(spacing: 5) {
            Circle().fill(timerColor).frame(width: 7, height: 7)
            Text(formatElapsed(recording.elapsed))
                .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(timerColor)
            Text("recording")
                .font(.system(size: 10))
                .foregroundStyle(inkSoft)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Capsule().fill(timerColor.opacity(0.14)))
    }

    /// Toastmasters pacing: green under a minute, amber 60–90 s, red past 90 s.
    private var timerColor: Color {
        switch recording.elapsed {
        case ..<60: return Color(red: 0.2, green: 0.55, blue: 0.3)
        case 60..<90: return Color(red: 0.8, green: 0.55, blue: 0.1)
        default: return terracotta
        }
    }

    // MARK: - Status zone (errors / mic / low disk)

    private var statusZone: some View {
        Group {
            if let statusText {
                Text(statusText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(statusIsError ? terracotta : inkSoft)
            } else if lowDisk {
                Text("Low disk space — recording disabled")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(terracotta)
            } else if !camera.micEnabled {
                Text(micStatusMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(inkSoft)
            } else {
                Text(" ").font(.system(size: 11))
            }
        }
        .frame(height: 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Controls

    @ViewBuilder
    private var controls: some View {
        switch recording.phase {
        case .idle, .countingDown:
            VStack(spacing: 10) {
                HStack {
                    iconButton("chevron.left", enabled: topics.canGoBack) { topics.prev() }
                    Spacer()
                    iconButton("shuffle") { topics.shuffle() }
                    Spacer()
                    iconButton("chevron.right") { topics.next() }
                }
                filledButton("Record", "record.circle", fill: terracotta, fg: cream) { requestRecord() }
            }
            .disabled(isCountingDown || lowDisk)

        case .recording:
            filledButton("Stop", "stop.fill", fill: terracotta, fg: cream) { recording.stop() }

        case .pendingSave(let duration):
            VStack(spacing: 8) {
                Text("Take ready — \(formatElapsed(duration))")
                    .font(.system(size: 11))
                    .foregroundStyle(inkSoft)
                HStack(spacing: 8) {
                    ghostButton("Discard", "xmark") { recording.discard() }
                    filledButton("Save", "checkmark", fill: olive, fg: cream) { recording.save() }
                }
            }
        }
    }

    // MARK: - Button styles (explicit colors — visible on the yellow)

    private func filledButton(_ title: String, _ systemImage: String, fill: Color, fg: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(fg)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(Capsule().fill(fill))
        }
        .buttonStyle(.plain)
    }

    private func ghostButton(_ title: String, _ systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(ink.opacity(0.75))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(Capsule().stroke(ink.opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func iconButton(_ systemImage: String, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(enabled ? ink.opacity(0.7) : ink.opacity(0.22))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    // MARK: - Countdown ring (over the still-visible topic)

    @ViewBuilder
    private var countdownOverlay: some View {
        if case .countingDown(let n) = recording.phase {
            CountdownRing(number: n, totalSeconds: 3, ring: terracotta, ink: ink, track: ink.opacity(0.15))
        }
    }

    // MARK: - Save animation

    @ViewBuilder
    private var saveOverlay: some View {
        if showSaveCheck {
            VStack(spacing: 8) {
                ZStack {
                    Circle().fill(olive).frame(width: 54, height: 54)
                    Image(systemName: "checkmark")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(cream)
                }
                Text("Saved!")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ink.opacity(0.75))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(paper.opacity(0.82))
            .transition(.scale(scale: 0.4).combined(with: .opacity))
        }
    }

    private func triggerSaveAnimation() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) { showSaveCheck = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            withAnimation(.easeOut(duration: 0.3)) { showSaveCheck = false }
        }
    }

    private func showStatus(_ text: String, isError: Bool) {
        statusGeneration += 1
        let generation = statusGeneration
        withAnimation(.easeOut(duration: 0.15)) {
            statusText = text
            statusIsError = isError
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            guard generation == statusGeneration else { return }
            withAnimation(.easeOut(duration: 0.3)) { statusText = nil }
        }
    }

    // MARK: - Helpers

    private var isCountingDown: Bool {
        if case .countingDown = recording.phase { return true }
        return false
    }

    private func formatElapsed(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private func requestRecord() {
        lowDisk = !hasEnoughDiskSpace()
        guard !lowDisk else { return }
        recording.beginCountdown(topicText: topics.current?.text, title: noteTitle())
    }

    private func noteTitle() -> String {
        if let text = topics.current?.text {
            return "Table Topic — \(text)"
        }
        return "Table Topic"
    }

    /// Warns under 2 GB free on the recordings volume.
    private func hasEnoughDiskSpace() -> Bool {
        guard let values = try? LocalPaths.root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
              let available = values.volumeAvailableCapacityForImportantUsage
        else { return true }
        return available > 2_000_000_000
    }
}

/// A 3-2-1 ring that sweeps empty smoothly over the WHOLE countdown (one
/// continuous depletion across all counts), with the number updating in the
/// centre. It is updated-in-place as the count changes — no `.id`, so `onAppear`
/// fires once and the single sweep isn't restarted each second.
private struct CountdownRing: View {
    let number: Int
    let totalSeconds: Double
    let ring: Color
    let ink: Color
    let track: Color
    @State private var progress: CGFloat = 1

    var body: some View {
        ZStack {
            Circle().stroke(track, lineWidth: 4)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(ring, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(number)")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(ink.opacity(0.85))
        }
        .frame(width: 66, height: 66)
        .onAppear {
            progress = 1
            withAnimation(.linear(duration: totalSeconds)) { progress = 0 }
        }
    }
}
