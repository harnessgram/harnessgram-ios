import XCTest
import UIKit
import HarnessgramSettings
@testable import HarnessgramFonts

/// Hebrew with emoji in every reading font, drawn by UIKit as a message bubble would: emoji must come out in
/// colour (the cascade to the system font reaches Apple Color Emoji) and the Hebrew must draw. When the folder
/// `/private/tmp/harnessgram-font-snapshots` exists (create it to opt in), each rendering is saved there as
/// a PNG for a visual check; otherwise nothing is written.
final class HarnessgramFontsSnapshotTests: XCTestCase {
    private static let snapshotDirectory = URL(fileURLWithPath: "/private/tmp/harnessgram-font-snapshots", isDirectory: true)
    private let sample = "שלום 👋 הבנייה הסתיימה ✅\nבודקים עברית עם אימוג׳י 🙂🚗📻 וגם מודגש\nבראשית ברא אלקים את השמים ואת הארץ 🌍"

    func testHebrewWithEmojiInEveryFont() throws {
        let size = CGSize(width: 360.0, height: 150.0)
        for font in HarnessgramSettings.MessageFont.allCases {
            for weight in [HarnessgramSettings.FontWeight.regular, .semibold] {
                let fonts = HarnessgramFonts.fonts(font, weight: weight, size: 17.0)
                let image = self.render(fonts: fonts, size: size)
                let (colour, dark) = self.pixelCounts(image)
                XCTAssertGreaterThan(colour, 200, "\(font) \(weight): emoji must draw in colour")
                XCTAssertGreaterThan(dark, 800, "\(font) \(weight): the Hebrew must draw")
                var isDirectory: ObjCBool = false
                if FileManager.default.fileExists(atPath: HarnessgramFontsSnapshotTests.snapshotDirectory.path, isDirectory: &isDirectory), isDirectory.boolValue, let data = image.pngData() {
                    try data.write(to: HarnessgramFontsSnapshotTests.snapshotDirectory.appendingPathComponent("\(font.rawValue)-\(weight.rawValue).png"))
                }
            }
        }
    }

    private func render(fonts: HarnessgramFonts.Fonts, size: CGSize) -> UIImage {
        let paragraph = NSMutableParagraphStyle()
        paragraph.baseWritingDirection = .rightToLeft
        paragraph.alignment = .right
        paragraph.lineSpacing = 2.0
        let text = NSMutableAttributedString(string: self.sample, attributes: [.font: fonts.regular, .foregroundColor: UIColor.black, .paragraphStyle: paragraph])
        let bold = (self.sample as NSString).range(of: "מודגש")
        if bold.location != NSNotFound {
            text.addAttribute(.font, value: fonts.bold, range: bold)
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2.0
        format.preferredRange = .standard
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            text.draw(in: CGRect(x: 10.0, y: 8.0, width: size.width - 20.0, height: size.height - 16.0))
        }
    }

    /// Colourful pixels (emoji) and dark grey-to-black pixels (letters), read through an 8-bit RGBA bitmap.
    private func pixelCounts(_ image: UIImage) -> (colour: Int, dark: Int) {
        guard let cgImage = image.cgImage else {
            return (0, 0)
        }
        let width = cgImage.width, height = cgImage.height, bytesPerRow = width * 4
        var bytes = [UInt8](repeating: 0, count: bytesPerRow * height)
        let drawn: Bool = bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                return false
            }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else {
            return (0, 0)
        }
        var colour = 0
        var dark = 0
        for offset in stride(from: 0, to: bytes.count, by: 4) {
            let r = Int(bytes[offset]), g = Int(bytes[offset + 1]), b = Int(bytes[offset + 2])
            if max(r, g, b) - min(r, g, b) > 60 {
                colour += 1
            } else if r < 100 && g < 100 && b < 100 {
                dark += 1
            }
        }
        return (colour, dark)
    }
}
