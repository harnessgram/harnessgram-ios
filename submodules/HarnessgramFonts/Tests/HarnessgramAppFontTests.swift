import XCTest
import UIKit
import CoreText
import HarnessgramSettings
@testable import HarnessgramFonts

/// Build 22: the app font ("גופן האפליקציה") behind Display's `Font` helpers.
final class HarnessgramAppFontTests: XCTestCase {
    private let expectedFamily: [HarnessgramSettings.AppFont: String] = [
        .heebo: "Heebo",
        .assistant: "Assistant",
        .rubik: "Rubik",
        .frankRuhlLibre: "Frank Ruhl Libre",
        .secularOne: "Secular One",
    ]

    private func family(of font: UIFont) -> String {
        return CTFontCopyFamilyName(font as CTFont) as String
    }

    private func withSettings(_ body: (HarnessgramSettings, UserDefaults) -> Void) {
        let suite = "HarnessgramAppFontTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        body(HarnessgramSettings(defaults: defaults), defaults)
    }

    override func tearDown() {
        HarnessgramFonts.resetRegistrationsForTesting()
        super.tearDown()
    }

    func testEveryAppFontResolvesToItsFamilyAtEveryWeight() {
        HarnessgramFonts.registerBundledFonts()
        for font in HarnessgramSettings.AppFont.allCases {
            for weight: CGFloat in [200.0, 300.0, 400.0, 500.0, 600.0, 700.0, 800.0] {
                for italic in [false, true] {
                    let resolved = HarnessgramFonts.appFont(font, weight: weight, size: 17.0, italic: italic)
                    guard let expected = self.expectedFamily[font] else {
                        XCTAssertNil(resolved, "the system choice leaves Display's own fonts")
                        continue
                    }
                    guard let resolved else {
                        XCTFail("\(font) \(weight)")
                        continue
                    }
                    XCTAssertEqual(self.family(of: resolved), expected, "\(font) \(weight) \(italic)")
                    XCTAssertEqual(resolved.pointSize, 17.0, accuracy: 0.01)
                }
            }
        }
    }

    func testAMissingWeightTakesTheNearestOne() {
        // Secular One has only 400: every request draws at 400, never a synthesized weight.
        for weight: CGFloat in [100.0, 400.0, 700.0, 900.0] {
            XCTAssertEqual(HarnessgramFonts.resolvedAppWeight(weight, for: .secularOne), 400.0)
        }
        XCTAssertEqual(HarnessgramFonts.resolvedAppWeight(100.0, for: .rubik), 300.0)
        XCTAssertEqual(HarnessgramFonts.resolvedAppWeight(900.0, for: .assistant), 800.0)
        XCTAssertEqual(HarnessgramFonts.resolvedAppWeight(700.0, for: .heebo), 700.0)
        HarnessgramFonts.registerBundledFonts()
        let bold = HarnessgramFonts.appFont(.secularOne, weight: 700.0, size: 17.0)
        XCTAssertEqual(bold.map { self.family(of: $0) }, "Secular One")
    }

    func testMissingGlyphsFallBackToTheSystemFontNeverABox() {
        HarnessgramFonts.registerBundledFonts()
        for font in HarnessgramSettings.AppFont.allCases where font != .system {
            guard let resolved = HarnessgramFonts.appFont(font, weight: 600.0, size: 17.0) else {
                XCTFail("\(font)")
                continue
            }
            // Hebrew and digits come from the family itself.
            let hebrew = Array("שלום 123".utf16)
            var glyphs = [CGGlyph](repeating: 0, count: hebrew.count)
            XCTAssertTrue(CTFontGetGlyphsForCharacters(resolved as CTFont, hebrew, &glyphs, hebrew.count), "\(font)")
            // An emoji and Thai are in none of the families: the cascade list hands them to a font that has them.
            for text in ["😀", "สวัสดี"] {
                let fallback = CTFontCreateForString(resolved as CTFont, text as CFString, CFRange(location: 0, length: (text as NSString).length))
                let units = Array(text.utf16)
                var fallbackGlyphs = [CGGlyph](repeating: 0, count: units.count)
                XCTAssertTrue(CTFontGetGlyphsForCharacters(fallback, units, &fallbackGlyphs, units.count), "\(font) \(text)")
                XCTAssertNotEqual(CTFontCopyFamilyName(fallback) as String, self.expectedFamily[font], "\(font) \(text)")
            }
        }
    }

    func testTheChoicePersistsAndTheSystemFontIsTheDefault() {
        self.withSettings { settings, defaults in
            XCTAssertEqual(settings.appFont, .system)
            settings.appFont = .frankRuhlLibre
            XCTAssertEqual(HarnessgramSettings(defaults: defaults).appFont, .frankRuhlLibre)
            settings.appFont = .system
            XCTAssertNil(defaults.object(forKey: HarnessgramSettings.Key.appFont.rawValue), "the default is never stored")
            defaults.set("comic-sans", forKey: HarnessgramSettings.Key.appFont.rawValue)
            XCTAssertEqual(settings.appFont, .system, "an unknown stored value falls back to the system font")
        }
    }

    func testLaunchInstallsTheChosenFamilyOnly() {
        self.withSettings { settings, _ in
            XCTAssertNil(HarnessgramFonts.appFamilyForLaunch(settings: settings), "the system font installs nothing")
            XCTAssertEqual(HarnessgramFonts.launchedAppFont, .system)

            settings.appFont = .rubik
            let provider = HarnessgramFonts.appFamilyForLaunch(settings: settings)
            XCTAssertNotNil(provider)
            XCTAssertEqual(HarnessgramFonts.launchedAppFont, .rubik)
            XCTAssertEqual(provider?(700.0, 15.0, false).map { self.family(of: $0) }, "Rubik")

            // A family that cannot be drawn keeps the system font, with a log line, and the picker sees "system".
            HarnessgramFonts.markAppFontUnavailableForTesting(.rubik, code: 104)
            var lines: [String] = []
            XCTAssertNil(HarnessgramFonts.appFamilyForLaunch(settings: settings, log: { lines.append($0) }))
            XCTAssertEqual(HarnessgramFonts.launchedAppFont, .system)
            XCTAssertTrue(lines.contains { $0.contains("rubik") }, "\(lines)")
            XCTAssertFalse(HarnessgramFonts.isAvailable(.rubik))
            XCTAssertTrue(HarnessgramFonts.isAvailable(.system))
        }
    }

    func testSecularOneIsBundledAsAStaticFont() {
        XCTAssertNotNil(HarnessgramFonts.baseDescriptor(HarnessgramFonts.BundledFamily.secularOne.family))
        XCTAssertFalse(HarnessgramFonts.BundledFamily.secularOne.family.variable)
    }
}
