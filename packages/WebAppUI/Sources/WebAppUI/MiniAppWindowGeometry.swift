import CoreGraphics

struct MiniAppWindowGeometry {
    let frame: CGRect
    let minimumSize: CGSize

    init(parentFrame: CGRect, visibleFrame: CGRect?, largerWidth: Bool, largerHeight: Bool) {
        let standardSize = CGSize(width: 420, height: 714)
        let preferredSize = CGSize(width: largerWidth ? 512 : standardSize.width,
                                   height: largerHeight ? 782 : standardSize.height)
        let screen = visibleFrame.flatMap { $0.isEmpty ? nil : $0 }
        let size = CGSize(width: min(preferredSize.width, screen?.width ?? preferredSize.width),
                          height: min(preferredSize.height, screen?.height ?? preferredSize.height))
        minimumSize = CGSize(width: min(standardSize.width, size.width), height: min(standardSize.height, size.height))

        let center = CGPoint(x: parentFrame.midX - size.width / 2, y: parentFrame.midY - size.height / 2)
        let origin = screen.map {
            CGPoint(x: min(max(center.x, $0.minX), $0.maxX - size.width),
                    y: min(max(center.y, $0.minY), $0.maxY - size.height))
        } ?? center
        frame = CGRect(origin: origin, size: size)
    }
}
