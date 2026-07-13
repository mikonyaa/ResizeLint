import CoreGraphics

enum AdaptiveLayout {
    static func columns(for width: CGFloat) -> Int {
        switch width {
        case ..<560: 2
        case ..<880: 3
        default: 4
        }
    }

    static func contentWidth(containerWidth: CGFloat, horizontalInsets: CGFloat) -> CGFloat {
        max(0, containerWidth - horizontalInsets * 2)
    }
}
