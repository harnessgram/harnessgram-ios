import Foundation
import CoreGraphics

/// The radio's artwork for the lock screen, Control Center and the Dynamic Island: the same mark as the bridge's
/// listen page (see docs/harnessgram-local-config.md): a navy rounded square, a white centre dot and two white
/// arcs above it. Drawn in code, so no image file and no network.
public enum HarnessgramRadioArtwork {
    /// Build 23: the bundled artwork, the control tower at sunset, bundled in the House asset catalog (HarnessgramHouseKit
    /// Resources). The app's Now Playing and the radio screen use it; the drawn mark below stays the fallback.
    public static let bundledImageName = "House/Radio/radio-tower"

    /// Navy #1F3A5F and the page's light #F2F6FB.
    public static let backgroundRGB: (CGFloat, CGFloat, CGFloat) = (0x1F / 255.0, 0x3A / 255.0, 0x5F / 255.0)
    public static let foregroundRGB: (CGFloat, CGFloat, CGFloat) = (0xF2 / 255.0, 0xF6 / 255.0, 0xFB / 255.0)

    /// A square image `pixels` wide (nil only when the system cannot make a bitmap).
    public static func image(pixels: Int) -> CGImage? {
        let side = max(16, pixels)
        guard let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }
        // The page's 512-unit drawing, scaled; CoreGraphics' y axis points up, so the arcs open downwards in
        // page terms and are drawn above the dot by flipping the context first.
        let scale = CGFloat(side) / 512.0
        context.translateBy(x: 0.0, y: CGFloat(side))
        context.scaleBy(x: scale, y: -scale)

        let background = self.backgroundRGB, foreground = self.foregroundRGB
        context.setFillColor(red: background.0, green: background.1, blue: background.2, alpha: 1.0)
        context.addPath(CGPath(roundedRect: CGRect(x: 0.0, y: 0.0, width: 512.0, height: 512.0), cornerWidth: 96.0, cornerHeight: 96.0, transform: nil))
        context.fillPath()

        context.setFillColor(red: foreground.0, green: foreground.1, blue: foreground.2, alpha: 1.0)
        context.fillEllipse(in: CGRect(x: 256.0 - 64.0, y: 256.0 - 64.0, width: 128.0, height: 128.0))

        context.setStrokeColor(red: foreground.0, green: foreground.1, blue: foreground.2, alpha: 1.0)
        context.setLineWidth(28.0)
        context.setLineCap(.round)
        for radius in [126.0, 170.0] as [CGFloat] {
            // SVG "a r r 0 0 1": the upper half circle from the left point to the right point.
            context.addArc(center: CGPoint(x: 256.0, y: 256.0), radius: radius, startAngle: .pi, endAngle: 0.0, clockwise: false)
            context.strokePath()
        }
        return context.makeImage()
    }
}
