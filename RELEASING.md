# Releasing SelfCam

SelfCam ships as a normal macOS `.app` packaged in a drag-to-install `.dmg`.

## Build a release

```bash
./scripts/release.sh
```

This builds the Release configuration and produces `dist/SelfCam-<version>.dmg`
(e.g. `dist/SelfCam-1.0.0.dmg`). The `dist/` folder is git-ignored.

To bump the version first, edit `CFBundleShortVersionString` in `SelfCam/Info.plist`
(and `MARKETING_VERSION` in the project to match). Increment `CFBundleVersion` for
each build you hand out.

## Install it (your own Mac)

Open the DMG and drag **SelfCam** onto **Applications**. Launch it from Applications —
since you built it locally there's no Gatekeeper warning. Grant camera access on first
run. Enable **Launch at Login** from the menu for daily use.

## Share it with friends (current: ad-hoc, not notarized)

Send them the `.dmg`. Because the app isn't notarized by Apple yet, the first launch is
blocked by Gatekeeper. They open it once like this:

1. Drag **SelfCam** to **Applications**.
2. **Right-click** the app → **Open** → **Open** in the dialog.
   (Or: System Settings → Privacy & Security → scroll down → **Open Anyway**.)
3. Grant camera access.

After that first time it opens normally. This manual step is fine for technical friends
but not for the general public — that needs notarization (below).

## Upgrade path: notarized distribution (no warnings for anyone)

When you're ready to share with the general public, do this once-per-release after
joining the **Apple Developer Program** ($99/yr) and creating a **Developer ID
Application** certificate. Hardened Runtime is already enabled in the project.

```bash
# 1. Sign with Developer ID (Hardened Runtime already on)
codesign --force --options runtime --sign "Developer ID Application: <Your Name> (<TEAMID>)" \
  build/Build/Products/Release/SelfCam.app

# 2. Repackage the DMG (re-run release.sh after signing, or sign the .dmg too)
# 3. Notarize and wait for Apple's scan
xcrun notarytool submit dist/SelfCam-<version>.dmg --keychain-profile "<profile>" --wait

# 4. Staple the ticket so it works offline
xcrun stapler staple dist/SelfCam-<version>.dmg
```

After this, anyone can download the DMG and open it with no warnings. Good places to
host it: a **GitHub Release**, and later a **Homebrew Cask** (`brew install --cask selfcam`).
