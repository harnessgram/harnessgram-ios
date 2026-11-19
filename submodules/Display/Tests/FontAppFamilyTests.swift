import XCTest
import UIKit
@testable import Display

/// Harnessgram build 22: the app-wide family behind Font's plain helpers.
final class FontAppFamilyTests: XCTestCase {
    private var requests: [(CGFloat, CGFloat, Bool)] = []

    override func tearDown() {
        Font.setAppFamily(nil)
        super.tearDown()
    }

    /// A stand-in family: Georgia (every iOS and macOS install has it), so the routing is visible by family name.
    private func installGeorgia() {
        Font.setAppFamily({ [weak self] weight, size, italic in
            self?.requests.append((weight, size, italic))
            return UIFont(name: weight >= 600.0 ? "Georgia-Bold" : "Georgia", size: size)
        })
    }

    private func family(_ font: UIFont) -> String {
        return font.familyName
    }

    func testWithoutAFamilyEveryHelperIsTheSystemFont() {
        Font.setAppFamily(nil)
        XCTAssertFalse(Font.hasAppFamily)
        let system = UIFont.systemFont(ofSize: 17.0).familyName
        for font in [Font.regular(17.0), Font.medium(17.0), Font.semibold(17.0), Font.bold(17.0), Font.light(17.0), Font.with(size: 17.0, weight: .heavy)] {
            XCTAssertEqual(self.family(font), system)
        }
    }

    func testThePlainHelpersFollowTheFamily() {
        self.installGeorgia()
        XCTAssertTrue(Font.hasAppFamily)
        XCTAssertEqual(self.family(Font.regular(17.0)), "Georgia")
        XCTAssertEqual(self.family(Font.medium(15.0)), "Georgia")
        XCTAssertEqual(self.family(Font.semibold(17.0)), "Georgia")
        XCTAssertEqual(self.family(Font.bold(20.0)), "Georgia")
        XCTAssertEqual(self.family(Font.light(13.0)), "Georgia")
        XCTAssertEqual(self.family(Font.heavy(13.0)), "Georgia")
        XCTAssertEqual(self.family(Font.italic(13.0)), "Georgia")
        XCTAssertEqual(self.family(Font.with(size: 16.0, weight: .semibold)), "Georgia")
        XCTAssertEqual(Font.bold(20.0).pointSize, 20.0, accuracy: 0.01)
        // Weights reach the family as CSS weights.
        XCTAssertTrue(self.requests.contains { $0.0 == 700.0 && $0.1 == 20.0 && !$0.2 })
        XCTAssertTrue(self.requests.contains { $0.0 == 400.0 && $0.1 == 13.0 && $0.2 }, "italic")
    }

    func testSpecialDesignsAndNumberFeaturesKeepTheSystemFonts() {
        self.installGeorgia()
        XCTAssertNotEqual(self.family(Font.with(size: 17.0, design: .round, weight: .semibold)), "Georgia")
        XCTAssertNotEqual(self.family(Font.with(size: 17.0, weight: .regular, traits: [.monospacedNumbers])), "Georgia")
        XCTAssertNotEqual(self.family(Font.with(size: 17.0, weight: .regular, width: .condensed)), "Georgia")
        XCTAssertEqual(self.family(Font.monospace(17.0)), "Menlo")
    }

    func testCameraFontsUseSystemSizeAndWeight() {
        self.installGeorgia()
        let weights: [(Font.Weight, UIFont.Weight)] = [(.regular, .regular), (.semibold, .semibold)]
        let sizes: [CGFloat] = [13.0, 14.0, 15.0, 17.0, 21.0, 23.0]
        for size in sizes {
            for (weight, systemWeight) in weights {
                XCTAssertEqual(Font.with(size: size, design: .camera, weight: weight), UIFont.systemFont(ofSize: size, weight: systemWeight))
            }
        }
        XCTAssertTrue(self.requests.isEmpty)
    }

    func testCameraNumberFontsUseSystemMonospacedDigits() {
        self.installGeorgia()
        let weights: [(Font.Weight, UIFont.Weight)] = [(.regular, .regular), (.semibold, .semibold)]
        for (weight, systemWeight) in weights {
            XCTAssertEqual(Font.with(size: 15.0, design: .camera, weight: weight, traits: .monospacedNumbers), UIFont.monospacedDigitSystemFont(ofSize: 15.0, weight: systemWeight))
        }
        XCTAssertTrue(self.requests.isEmpty)
    }

    func testFontsAreCachedAndAChangeForgetsTheCache() {
        self.installGeorgia()
        _ = Font.regular(17.0)
        _ = Font.regular(17.0)
        XCTAssertEqual(self.requests.filter { $0.0 == 400.0 && $0.1 == 17.0 && !$0.2 }.count, 1, "the second request is served from the cache")
        Font.setAppFamily(nil)
        XCTAssertEqual(self.family(Font.regular(17.0)), UIFont.systemFont(ofSize: 17.0).familyName)
    }

    func testAFamilyThatHasNoFontForARequestFallsBackToTheSystemFont() {
        Font.setAppFamily({ _, _, _ in nil })
        XCTAssertEqual(self.family(Font.semibold(17.0)), UIFont.systemFont(ofSize: 17.0, weight: .semibold).familyName)
    }
}
