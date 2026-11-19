import XCTest
import UIKit
import CoreText
import HarnessgramSettings
@testable import HarnessgramFonts

final class HarnessgramFontsTests: XCTestCase {
    private let hebrew = "בראשית ברא אלקים את השמים ואת הארץ"
    private let families: [HarnessgramSettings.MessageFont: String] = [.assistant: "Assistant", .heebo: "Heebo", .rubik: "Rubik", .frankRuhlLibre: "Frank Ruhl Libre"]

    private func family(of font: UIFont) -> String {
        return CTFontCopyFamilyName(font as CTFont) as String
    }

    /// The font's 'wght' value. CoreText leaves an axis at its default out of the variation, so a missing
    /// entry means the axis default.
    private func weightAxisValue(_ font: UIFont) -> CGFloat? {
        let tag = NSNumber(value: 0x77676874)
        if let variation = CTFontCopyVariation(font as CTFont) as? [NSNumber: NSNumber], let value = variation[tag] {
            return CGFloat(value.doubleValue)
        }
        guard let axes = CTFontCopyVariationAxes(font as CTFont) as? [[String: Any]] else {
            return nil
        }
        for axis in axes where (axis[kCTFontVariationAxisIdentifierKey as String] as? NSNumber) == tag {
            return (axis[kCTFontVariationAxisDefaultValueKey as String] as? NSNumber).map { CGFloat($0.doubleValue) }
        }
        return nil
    }

    func testEveryBundledFontIsInTheBundle() {
        for font in HarnessgramSettings.MessageFont.allCases where font != .system {
            XCTAssertNotNil(HarnessgramFonts.baseDescriptor(HarnessgramFonts.family(font)!), "\(font)")
        }
    }

    func testEveryFontAndWeightResolvesToTheClosestAvailableWeight() {
        for font in HarnessgramSettings.MessageFont.allCases {
            for weight in HarnessgramSettings.FontWeight.allCases {
                let fonts = HarnessgramFonts.fonts(font, weight: weight, size: 17.0)
                for value in [fonts.regular, fonts.bold, fonts.italic, fonts.boldItalic] {
                    XCTAssertEqual(value.pointSize, 17.0, accuracy: 0.01)
                    if let expected = self.families[font] {
                        XCTAssertEqual(self.family(of: value), expected, "\(font) \(weight)")
                    }
                }
                if self.families[font] != nil {
                    let regular = self.weightAxisValue(fonts.regular)
                    let bold = self.weightAxisValue(fonts.bold)
                    XCTAssertEqual(regular, HarnessgramFonts.resolvedWeight(weight.value, for: font), "\(font) \(weight)")
                    // Bold inside a message stays heavier than the chosen base.
                    XCTAssertGreaterThan(bold ?? 0.0, regular ?? 0.0, "\(font) \(weight)")
                }
            }
        }
        // A weight a family lacks takes its closest: Rubik starts at 300, Assistant ends at 800.
        XCTAssertEqual(HarnessgramFonts.resolvedWeight(100.0, for: .rubik), 300.0)
        XCTAssertEqual(HarnessgramFonts.resolvedWeight(900.0, for: .assistant), 800.0)
        XCTAssertEqual(HarnessgramFonts.boldWeight(for: 600.0), 900.0)
        XCTAssertEqual(HarnessgramFonts.boldWeight(for: 400.0), 700.0)
    }

    func testSystemWeightsFollowTheChoice() {
        let light = HarnessgramFonts.font(.system, weight: 300.0, size: 17.0)
        let semibold = HarnessgramFonts.font(.system, weight: 600.0, size: 17.0)
        XCTAssertEqual(light.familyName, UIFont.systemFont(ofSize: 17.0).familyName)
        let lightWidth = ("שלום עולם" as NSString).size(withAttributes: [.font: light]).width
        let semiboldWidth = ("שלום עולם" as NSString).size(withAttributes: [.font: semibold]).width
        XCTAssertNotEqual(lightWidth, semiboldWidth)
    }

    func testMissingGlyphsFallBackToTheSystemFont() {
        for (font, name) in self.families {
            let value = HarnessgramFonts.font(font, weight: 400.0, size: 17.0) as CTFont
            let hebrew = CTFontCreateForString(value, self.hebrew as CFString, CFRange(location: 0, length: 4))
            XCTAssertEqual(CTFontCopyFamilyName(hebrew) as String, name)
            let emoji = "😀" as CFString
            let fallback = CTFontCreateForString(value, emoji, CFRange(location: 0, length: CFStringGetLength(emoji)))
            XCTAssertNotEqual(CTFontCopyFamilyName(fallback) as String, name, "\(font) has no emoji; another font draws it")
            var glyphs = [CGGlyph](repeating: 0, count: 2)
            var characters = Array("😀".utf16)
            XCTAssertTrue(CTFontGetGlyphsForCharacters(fallback, &characters, &glyphs, characters.count))
        }
    }

    /// Snapshot-style check: Hebrew is drawn with each chosen font (its own glyphs, not a fallback), right to left.
    func testHebrewRendersWithEachFont() {
        var widths: [String: CGFloat] = [:]
        for font in HarnessgramSettings.MessageFont.allCases {
            let value = HarnessgramFonts.font(font, weight: 400.0, size: 20.0)
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: self.hebrew, attributes: [.font: value]))
            let runs = CTLineGetGlyphRuns(line) as! [CTRun]
            XCTAssertFalse(runs.isEmpty)
            for run in runs {
                XCTAssertTrue(CTRunGetStatus(run).contains(.rightToLeft), "\(font)")
                let attributes = CTRunGetAttributes(run) as NSDictionary
                let runFont = attributes[kCTFontAttributeName as String] as! CTFont
                if let expected = self.families[font] {
                    XCTAssertEqual(CTFontCopyFamilyName(runFont) as String, expected, "\(font)")
                }
            }
            let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
            let size = CGSize(width: ceil(width) + 4.0, height: 32.0)
            XCTAssertGreaterThan(self.darkPixelCount(drawing: self.hebrew, font: value, size: size), 200, "\(font) drew nothing")
            widths[font.rawValue] = width
        }
        // Each family draws the same text differently.
        XCTAssertEqual(Set(widths.values.map { Int($0.rounded()) }).count, widths.count, "\(widths)")
    }

    func testTheInputFieldKeepsTelegramsFontUntilSomethingIsChosen() {
        let suite = "HarnessgramFontsTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = HarnessgramSettings(defaults: defaults)
        XCTAssertNil(HarnessgramFonts.inputFont(size: 17.0, settings: settings))
        settings.messageFont = .heebo
        XCTAssertEqual(HarnessgramFonts.inputFont(size: 17.0, settings: settings).map { self.family(of: $0) }, "Heebo")
        settings.messageFont = .system
        settings.fontWeight = .medium
        XCTAssertNotNil(HarnessgramFonts.inputFont(size: 17.0, settings: settings))
    }

    func testEveryBundledFamilyRegistersAtStart() {
        var lines: [String] = []
        let result = HarnessgramFonts.registerBundledFonts(log: { lines.append($0) })
        XCTAssertEqual(result.count, HarnessgramSettings.MessageFont.allCases.count - 1)
        for (font, registration) in result {
            XCTAssertEqual(registration, .registered, "\(font)")
        }
        XCTAssertEqual(lines, [], "nothing to report when every family registers")
        XCTAssertEqual(HarnessgramFonts.registerBundledFonts(), result, "a second call keeps the first result")
    }

    func testAFamilyThatFailsToRegisterFallsBackToTheSystemFontWithALogLine() {
        HarnessgramFonts.markUnavailableForTesting(.rubik, code: 104)
        defer { HarnessgramFonts.resetRegistrationsForTesting() }
        var lines: [String] = []
        let result = HarnessgramFonts.registerBundledFonts(log: { lines.append($0) })
        XCTAssertEqual(result[.rubik], .failed(code: 104))
        XCTAssertEqual(lines.count, 1)
        XCTAssertTrue(lines.first?.contains("Rubik-Variable") == true, "\(lines)")
        let font = HarnessgramFonts.font(.rubik, weight: 400.0, size: 17.0)
        XCTAssertEqual(self.family(of: font), self.family(of: UIFont.systemFont(ofSize: 17.0)))
        XCTAssertEqual(self.family(of: HarnessgramFonts.font(.heebo, weight: 400.0, size: 17.0)), "Heebo", "other families are not affected")
    }

    /// The input field's measured height for the system font is Telegram's own table, so a size step on top
    /// of Text Size gets the height the field will settle at.
    func testInputFieldHeightMatchesTelegramsMeasuredTable() {
        let table: [(CGFloat, CGFloat)] = [(14.0, 31.0), (15.0, 31.0), (16.0, 31.0), (17.0, 31.0), (19.0, 33.0), (23.0, 38.0), (26.0, 42.0)]
        for (size, height) in table {
            XCTAssertEqual(HarnessgramFonts.fieldHeight(font: UIFont.systemFont(ofSize: size), verticalInsets: 10.0), height, "\(size)")
        }
    }

    func testInputFieldHeightIsTelegramsUntilAReadingChoiceChangesTheInput() {
        let suite = "HarnessgramFontsTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = HarnessgramSettings(defaults: defaults)
        XCTAssertNil(HarnessgramFonts.inputFieldMinHeight(size: 17.0, verticalInsets: 10.0, settings: settings))
        settings.textSizeSteps = 4
        XCTAssertEqual(settings.messageFontSize(base: 17.0), 21.0)
        XCTAssertEqual(HarnessgramFonts.inputFieldMinHeight(size: 21.0, verticalInsets: 10.0, settings: settings), HarnessgramFonts.fieldHeight(font: UIFont.systemFont(ofSize: 21.0), verticalInsets: 10.0))
        settings.textSizeSteps = 0
        settings.messageFont = .frankRuhlLibre
        let height = HarnessgramFonts.inputFieldMinHeight(size: 17.0, verticalInsets: 10.0, settings: settings)
        XCTAssertNotNil(height)
        XCTAssertGreaterThanOrEqual(height ?? 0.0, 31.0)
    }

    /// Draws the text black on white into an 8-bit RGBA bitmap (a known layout, unlike the simulator's
    /// wide-colour renderer) and counts the dark pixels.
    private func darkPixelCount(drawing text: String, font: UIFont, size: CGSize) -> Int {
        let width = Int(size.width), height = Int(size.height), bytesPerRow = width * 4
        var bytes = [UInt8](repeating: 0, count: bytesPerRow * height)
        let drawn: Bool = bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                return false
            }
            context.setFillColor(UIColor.white.cgColor)
            context.fill(CGRect(origin: .zero, size: size))
            context.translateBy(x: 0.0, y: size.height)
            context.scaleBy(x: 1.0, y: -1.0)
            UIGraphicsPushContext(context)
            (text as NSString).draw(at: CGPoint(x: 2.0, y: 2.0), withAttributes: [.font: font, .foregroundColor: UIColor.black])
            UIGraphicsPopContext()
            return true
        }
        guard drawn else {
            return 0
        }
        var count = 0
        for offset in stride(from: 0, to: bytes.count, by: 4) where bytes[offset] < 128 && bytes[offset + 1] < 128 && bytes[offset + 2] < 128 {
            count += 1
        }
        return count
    }
}
