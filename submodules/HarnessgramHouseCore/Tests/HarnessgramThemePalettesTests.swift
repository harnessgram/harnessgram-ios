import XCTest
import HarnessgramSettings
@testable import HarnessgramHouseCore

/// Build 22: the built-in Harnessgram themes keep WCAG AA for every text they draw.
final class HarnessgramThemePalettesTests: XCTestCase {
    func testEveryThemeHasAPaletteAndNoneHasNone() {
        XCTAssertNil(HarnessgramThemePalettes.palette(.none))
        for theme in HarnessgramSettings.Theme.allCases where theme != .none {
            XCTAssertEqual(HarnessgramThemePalettes.palette(theme)?.theme, theme)
        }
        XCTAssertEqual(HarnessgramThemePalettes.all.map(\.theme), HarnessgramSettings.Theme.allCases.filter { $0 != .none })
        XCTAssertGreaterThanOrEqual(HarnessgramThemePalettes.all.count, 3)
    }

    func testTheThemesHaveTheirCharacter() {
        XCTAssertTrue(HarnessgramThemePalettes.cockpitNight.dark)
        XCTAssertTrue(HarnessgramThemePalettes.instruments.dark)
        XCTAssertFalse(HarnessgramThemePalettes.runwayDawn.dark)
        XCTAssertFalse(HarnessgramThemePalettes.openSky.dark)
        for theme in HarnessgramThemePalettes.all {
            let page = theme.palette.bg.relativeLuminance
            XCTAssertEqual(page < 0.2, theme.dark, "\(theme.theme): a dark theme has a dark page, a light theme a light one")
        }
    }

    func testTheContrastFormulaMatchesWcag() {
        XCTAssertEqual(HouseColor.contrastRatio(HouseColor(0x000000), HouseColor(0xFFFFFF)), 21.0, accuracy: 0.01)
        XCTAssertEqual(HouseColor.contrastRatio(HouseColor(0x777777), HouseColor(0xFFFFFF)), 4.48, accuracy: 0.01)
    }

    func testEveryTextPairKeepsAA() {
        for theme in HarnessgramThemePalettes.all {
            XCTAssertGreaterThanOrEqual(theme.textPairs.count, 19)
            for (role, text, background) in theme.textPairs {
                let ratio = HouseColor.contrastRatio(text, background)
                XCTAssertGreaterThanOrEqual(ratio, 4.5, "\(theme.theme.rawValue): \(role) = \(ratio)")
            }
        }
    }
}
