import SwiftUI

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
        case .rounded: return "Rounded"
        case .circle:  return "Circle"
        case .square:  return "Square"
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
