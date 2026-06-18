# SelfCam

A native macOS **menu-bar camera-check utility** — a personal clone of Hand Mirror.
Click the menu-bar icon, see yourself, fix your hair before the call. Built with
Swift + SwiftUI + AppKit + AVFoundation. No dependencies, no build tooling beyond Xcode.

<!-- TODO: add a screenshot or short GIF of the app here, e.g.:
![SelfCam](docs/screenshot.png)
-->

## Features

- **Menu-bar mirror** — left-click the icon, the camera window emerges from the menu bar
  (it powers the camera on only while open; closing it turns the camera off).
- **Drag to detach** — drag the window anywhere and it becomes a floating, always-on-top
  window. Hover for a ✕ to close.
- **5 fixed 16:9 sizes** (clamped to your screen), and **shape masks**: rounded, circle, square.
- **Zoom 1×–3×** (software: scales the preview and centre-crops snaps).
- **Camera picker + mirror toggle** (works with built-in, external, and Continuity Camera).
- **Snaps** — capture a still, mark it up with a marker, and save to `~/Pictures/SelfCam`
  (location configurable). A popover shows the 5 most recent.
- **Notch trigger** — on notched MacBooks, click the notch to toggle the window.
- **Custom menu-bar icon**, and **Launch at Login**.

Everything except the live window lives in the **right-click menu** or the **Settings** window.

## Install

Download the latest `SelfCam-<version>.dmg` from the
[Releases page](https://github.com/saishmalunde8/SelfCam/releases), open it, and drag
**SelfCam** onto **Applications**. Launch it from Applications and allow camera access when
prompted. There's no Dock icon — it lives in the menu bar; **Quit** is in the right-click menu.

> **First launch:** SelfCam isn't notarized by Apple yet, so macOS shows a warning the first
> time. To open it: **right-click the app → Open → Open**, or go to **System Settings →
> Privacy & Security** and click **Open Anyway**. Only needed once.

## Build from source

Open `SelfCam.xcodeproj` in Xcode 16 and press **⌘R**. The app has no Dock icon — it lives
in the menu bar. **Quit** is in the right-click menu.

**First time:** Select the SelfCam target → Signing & Capabilities → set **Team** to your
Apple ID ("Personal Team"), then run and allow camera access when prompted.

**Headless build:**
```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project SelfCam.xcodeproj -scheme SelfCam \
  -configuration Debug -destination "platform=macOS" build
```

## Architecture

Single-window menu-bar agent. `AppDelegate` builds the object graph at launch; `AppController`
(`@MainActor`) is the coordinator and settings source of truth, owning `CameraManager` (the
reference-counted `AVCaptureSession`), `SnapStore` (on-disk snaps), the `NSPanel`-based camera
window, the notch catcher, and the Settings / Snaps-gallery controllers.

New `.swift` files added to `SelfCam/` are compiled automatically (Xcode file-system-synchronized
group) — no project edits needed.

## Requirements

macOS 14+, Xcode 16+. Not sandboxed (Hardened Runtime + camera entitlement).
