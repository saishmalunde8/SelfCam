import SwiftUI

/// The Settings dialog — every control in one clean form.
struct SettingsView: View {
    @ObservedObject var app: AppController
    @ObservedObject var camera: CameraManager
    @ObservedObject var snaps: SnapStore

    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    var body: some View {
        Form {
            Section("Camera") {
                Picker("Source", selection: cameraBinding) {
                    if camera.devices.isEmpty {
                        Text("No cameras found").tag("")
                    }
                    ForEach(camera.devices, id: \.uniqueID) { device in
                        Text(device.localizedName).tag(device.uniqueID)
                    }
                }
                Toggle("Mirror", isOn: $camera.isMirrored)
            }

            Section("Window") {
                Picker("Size", selection: $app.windowSize) {
                    ForEach(WindowSize.allCases, id: \.self) { size in
                        Text(size.label).tag(size)
                    }
                }
                Picker("Shape", selection: $app.mask) {
                    ForEach(MaskShape.allCases, id: \.self) { shape in
                        Text(shape.label).tag(shape)
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Zoom")
                        Spacer()
                        Text(String(format: "%.1f×", app.zoom))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $app.zoom, in: 1...3, step: 0.1) {
                        Text("Zoom")
                    } minimumValueLabel: {
                        Text("1×").font(.caption2).foregroundStyle(.secondary)
                    } maximumValueLabel: {
                        Text("3×").font(.caption2).foregroundStyle(.secondary)
                    }
                    .labelsHidden()
                }
            }

            Section("Menu Bar") {
                Picker("Icon", selection: $app.iconStyle) {
                    ForEach(IconStyle.allCases, id: \.self) { style in
                        Label(style.label, systemImage: style.symbol).tag(style)
                    }
                }
                Toggle("Notch Trigger", isOn: $app.notchEnabled)
                    .disabled(!NotchCatcher.hasNotch)
                if !NotchCatcher.hasNotch {
                    Text("This Mac has no notch.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Picker("Shortcut", selection: $app.hotKeyPreset) {
                    ForEach(HotKeyPreset.allCases, id: \.self) { Text($0.label).tag($0) }
                }
            }

            Section("Snaps") {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Save Location")
                        Text(snaps.directory.path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    Button("Change…", action: chooseFolder)
                }
            }

            Section("General") {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        LaunchAtLogin.set(newValue)
                        launchAtLogin = LaunchAtLogin.isEnabled
                    }
            }
        }
        .formStyle(.grouped)
        .frame(width: 380, height: 460)
    }

    private var cameraBinding: Binding<String> {
        Binding(
            get: { camera.selectedDeviceID },
            set: { camera.select(deviceID: $0) }
        )
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = snaps.directory
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            snaps.setDirectory(url)
        }
    }
}
