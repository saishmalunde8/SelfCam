# SelfCam

A native macOS **menu-bar camera-check utility** — a personal clone of Hand Mirror.
Click the menu-bar icon, see yourself, fix your hair before the call. Built with
Swift + SwiftUI + AppKit + AVFoundation. No dependencies, no build tooling beyond Xcode.

## Features

- **Menu-bar mirror** — left-click the icon, the camera window emerges from the menu bar
  (it powers the camera on only while open; closing it turns the camera off).
- **Drag to detach** — drag the window anywhere and it becomes a floating, always-on-top
  window. Hover for a ✕ to close; hover while attached for a ⚙︎ to open Settings.
- **5 fixed 16:9 sizes** (clamped to your screen), and **shape masks**: rounded, circle, square.
- **Zoom 1×–3×** (software: scales the preview and centre-crops snaps).
- **Camera picker + mirror toggle** (works with built-in, external, and Continuity Camera).
- **Snaps** — capture a still, mark it up with a marker, and copy/save. Snaps auto-save to
  `~/Pictures/SelfCam` (location configurable). A menu popover shows the 5 most recent.
- **Notch trigger** — on notched MacBooks, click the notch to toggle the window.
- **Custom menu-bar icon**, and **Launch at Login**.

Everything except the live window lives in the **right-click menu** or the **Settings** window.

## Open & run

Open `SelfCam.xcodeproj` in Xcode and press **⌘R**. The app has **no Dock icon** — it lives in
the menu bar (it's an `LSUIElement`/`.accessory` agent). **Quit** is in the right-click menu.

First time only:
1. Select the **SelfCam** target → **Signing & Capabilities** → set **Team** to your Apple ID
   ("Personal Team"). Required once so the camera permission sticks across rebuilds.
2. Press **⌘R**, click the menu-bar icon, and **Allow** camera access when prompted.

Headless build (for CI / verification):

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project SelfCam.xcodeproj -scheme SelfCam -configuration Debug \
  -destination "platform=macOS" build
```

The `DEVELOPER_DIR` override is needed if `xcode-select` points at CommandLineTools.

If the feed stays black after granting permission, reset the camera privacy entry:

```bash
tccutil reset Camera com.saish.selfcam
```

## Architecture

Single-window menu-bar agent. `AppDelegate` builds the object graph at launch; `AppController`
(`@MainActor`) is the coordinator and settings source of truth, owning `CameraManager` (the
reference-counted `AVCaptureSession`), `SnapStore` (on-disk snaps), the `NSPanel`-based camera
window, the notch catcher, and the Settings / Snaps-gallery controllers.

New `.swift` files added to `SelfCam/` are compiled automatically (Xcode file-system-synchronized
group) — no project edits needed.

See **CLAUDE.md** for the detailed architecture, build notes, and the invariants to preserve.

## Requirements

macOS 14+, Xcode 16+. Not sandboxed (Hardened Runtime + camera entitlement). Bundle id
`com.saish.selfcam`.
