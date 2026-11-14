import Cocoa
import TGUIKit

enum StickerPackArtworkClipping {
    static func tile(for artwork: CALayer, fittedSize: CGSize?) -> SimpleLayer {
        let tile = SimpleLayer(frame: artwork.frame)
        artwork.frame = tile.bounds

        if let fittedSize, fittedSize.width > 0, fittedSize.height > 0 {
            let scale = artwork.contentsScale
            let rect = CGRect(
                x: floorToScreenPixels(scale, (artwork.bounds.width - fittedSize.width) / 2),
                y: floorToScreenPixels(scale, (artwork.bounds.height - fittedSize.height) / 2),
                width: fittedSize.width,
                height: fittedSize.height
            )
            let radius = min(5, fittedSize.width / 2, fittedSize.height / 2)
            let mask = SimpleShapeLayer()
            mask.frame = artwork.bounds
            mask.contentsScale = scale
            mask.fillColor = NSColor.black.cgColor
            mask.path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
            artwork.mask = mask
            artwork.isOpaque = false
        }

        tile.addSublayer(artwork)
        return tile
    }
}
