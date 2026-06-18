import SwiftUI
import Carbon.HIToolbox

/// Fixed window sizes (no free resizing — keeps the live feed crisp).
/// All 16:9 to match the MacBook camera, five steps from Small to Large.
enum WindowSize: String, CaseIterable {
    case small, smallMedium, medium, mediumLarge, large

    var dimensions: NSSize {
        switch self {
        case .small:       return NSSize(width: 384, height: 216)
        case .smallMedium: return NSSize(width: 480, height: 270)
        case .medium:      return NSSize(width: 608, height: 342)
        case .mediumLarge: return NSSize(width: 736, height: 414)
        case .large:       return NSSize(width: 960, height: 540)
        }
    }

    var label: String {
        switch self {
        case .small:       return "Small"
        case .smallMedium: return "Small–Medium"
        case .medium:      return "Medium"
        case .mediumLarge: return "Medium–Large"
        case .large:       return "Large"
        }
    }
}

/// Shape mask applied to the window.
enum MaskShape: String, CaseIterable {
    case rounded, circle, square

    var label: String {
        switch self {
        case .rounded: return "Rectangular"
        case .circle:  return "Circle"
        case .square:  return "Square"
        }
    }

    /// Horizontal inset from the rectangle edge to the edge of the inscribed shape.
    /// Used to nudge overlay buttons inward so they stay inside the visible area.
    func safeInset(for size: CGSize) -> CGFloat {
        switch self {
        case .rounded: return 0
        case .circle, .square: return max(0, (size.width - min(size.width, size.height)) / 2)
        }
    }

    var anyShape: AnyShape {
        switch self {
        case .rounded: return AnyShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        case .circle:  return AnyShape(Circle())
        case .square:  return AnyShape(CenteredSquare(cornerRadius: 14))
        }
    }
}

/// A real (centered) square cropped from a wider frame, with rounded corners —
/// so "Square" looks square on the 16:9 window instead of filling it as a rectangle.
struct CenteredSquare: Shape {
    var cornerRadius: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let square = CGRect(x: rect.midX - side / 2, y: rect.midY - side / 2,
                            width: side, height: side)
        return Path(roundedRect: square, cornerRadius: cornerRadius, style: .continuous)
    }
}

/// Menu-bar icon styles.
enum IconStyle: String, CaseIterable {
    case person, camera, video, eye, smiley

    var symbol: String {
        switch self {
        case .person: return "person.crop.square"
        case .camera: return "camera.fill"
        case .video:  return "video.fill"
        case .eye:    return "eye.fill"
        case .smiley: return "face.smiling.fill"
        }
    }

    var label: String {
        switch self {
        case .person: return "Person"
        case .camera: return "Camera"
        case .video:  return "Video"
        case .eye:    return "Eye"
        case .smiley: return "Smiley"
        }
    }
}

/// Curated global-hotkey choices for toggling the camera window. Low-conflict
/// combos plus "Off". `carbon` maps to the Carbon key code + modifier mask.
enum HotKeyPreset: String, CaseIterable {
    case optCmdM, ctrlCmdM, optCmdC, ctrlCmdC, ctrlOptCmdM, off

    var label: String {
        switch self {
        case .optCmdM:     return "⌥⌘M"
        case .ctrlCmdM:    return "⌃⌘M"
        case .optCmdC:     return "⌥⌘C"
        case .ctrlCmdC:    return "⌃⌘C"
        case .ctrlOptCmdM: return "⌃⌥⌘M"
        case .off:         return "Off"
        }
    }

    /// Carbon key code + modifier mask, or nil when disabled.
    var carbon: (keyCode: Int, modifiers: Int)? {
        switch self {
        case .optCmdM:     return (kVK_ANSI_M, cmdKey | optionKey)
        case .ctrlCmdM:    return (kVK_ANSI_M, cmdKey | controlKey)
        case .optCmdC:     return (kVK_ANSI_C, cmdKey | optionKey)
        case .ctrlCmdC:    return (kVK_ANSI_C, cmdKey | controlKey)
        case .ctrlOptCmdM: return (kVK_ANSI_M, cmdKey | optionKey | controlKey)
        case .off:         return nil
        }
    }
}
