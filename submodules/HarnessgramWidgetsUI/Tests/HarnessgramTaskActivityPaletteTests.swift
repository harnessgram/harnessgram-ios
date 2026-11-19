import XCTest
@testable import HarnessgramWidgetsUI

/// The fixed colours must keep WCAG AA where they are drawn together, including the Dynamic Island's black surface.
final class HarnessgramTaskActivityPaletteTests: XCTestCase {
    func testContrastFormulaMatchesWcagReferencePoints() {
        let black = HarnessgramRGB(hex: 0x000000)
        let white = HarnessgramRGB(hex: 0xFFFFFF)
        XCTAssertEqual(HarnessgramRGB.contrastRatio(black, white), 21.0, accuracy: 0.01)
        XCTAssertEqual(HarnessgramRGB.contrastRatio(white, white), 1.0, accuracy: 0.0001)
        // #777777 on white is the classic "just under AA" grey (4.48).
        XCTAssertEqual(HarnessgramRGB.contrastRatio(HarnessgramRGB(hex: 0x777777), white), 4.48, accuracy: 0.01)
    }

    func testEveryTextColourKeepsAAOnTheCardAndTheIsland() {
        for (name, palette) in [("standard", HarnessgramTaskActivityPalette.standard), ("reducedLuminance", HarnessgramTaskActivityPalette.reducedLuminance)] {
            for (role, color) in palette.textColors {
                let onCard = HarnessgramRGB.contrastRatio(color, palette.background)
                XCTAssertGreaterThanOrEqual(onCard, 4.5, "\(name).\(role) on the card: \(onCard)")
                let onIsland = HarnessgramRGB.contrastRatio(color, HarnessgramTaskActivityPalette.islandBackground)
                XCTAssertGreaterThanOrEqual(onIsland, 4.5, "\(name).\(role) on the island: \(onIsland)")
            }
        }
    }

    func testTheCardIsDarkAndTheTextIsLight() {
        // The regression itself: a light card (or light text on light) must never come back.
        for palette in [HarnessgramTaskActivityPalette.standard, HarnessgramTaskActivityPalette.reducedLuminance] {
            XCTAssertLessThan(palette.background.relativeLuminance, 0.05)
            XCTAssertGreaterThan(palette.primaryText.relativeLuminance, 0.6)
            XCTAssertGreaterThan(palette.secondaryText.relativeLuminance, 0.3)
        }
    }

    func testFillsStandOutFromTheTrack() {
        // Non-text UI (bar, ring, step dots) needs 3:1 against what it sits next to (WCAG 1.4.11).
        for palette in [HarnessgramTaskActivityPalette.standard, HarnessgramTaskActivityPalette.reducedLuminance] {
            XCTAssertGreaterThanOrEqual(HarnessgramRGB.contrastRatio(palette.accent, palette.track), 3.0)
            XCTAssertGreaterThanOrEqual(HarnessgramRGB.contrastRatio(palette.approve, palette.track), 3.0)
            XCTAssertGreaterThan(HarnessgramRGB.contrastRatio(palette.track, palette.background), 1.3)
        }
    }

    func testLockScreenInstrumentsKeepContrastOnTheirOwnFills() {
        for reduced in [false, true] {
            let colors = HarnessgramTaskActivityColors.lockScreen(luminanceReduced: reduced)
            let palette = colors.instruments
            XCTAssertEqual(palette, reduced ? .reducedLuminance : .standard)
            XCTAssertGreaterThanOrEqual(HarnessgramRGB.contrastRatio(palette.primaryText, palette.background), 4.5)
            for fill in [palette.accent, palette.approve] {
                let tail = fill.over(palette.track, alpha: palette.fillTailOpacity)
                XCTAssertGreaterThanOrEqual(HarnessgramRGB.contrastRatio(tail, palette.track), 3.0)
            }
        }
    }

    /// Build 22 (CarPlay): the small family sits on the system tile, light or dark, so its text colours must keep AA on
    /// both ends of each tile range (light: systemGray5 and white; dark: systemGray5 dark and black).
    func testSmallFamilyTextKeepsAAInLightAndDark() {
        for dark in [false, true] {
            let palette = HarnessgramTaskActivityPalette.small(dark: dark)
            for background in [palette.background, HarnessgramTaskActivityPalette.smallAlternateBackground(dark: dark)] {
                for (role, color) in palette.textColors {
                    let ratio = HarnessgramRGB.contrastRatio(color, background)
                    XCTAssertGreaterThanOrEqual(ratio, 4.5, "small \(dark ? "dark" : "light").\(role): \(ratio)")
                }
                XCTAssertGreaterThanOrEqual(HarnessgramRGB.contrastRatio(palette.accent, palette.track), 3.0)
            }
        }
        // Light tile, dark text; dark tile, light text.
        XCTAssertLessThan(HarnessgramTaskActivityPalette.smallLight.primaryText.relativeLuminance, 0.05)
        XCTAssertGreaterThan(HarnessgramTaskActivityPalette.smallDark.primaryText.relativeLuminance, 0.6)
    }

    func testPaletteFollowsAlwaysOn() {
        XCTAssertEqual(HarnessgramTaskActivityPalette.palette(luminanceReduced: false), .standard)
        XCTAssertEqual(HarnessgramTaskActivityPalette.palette(luminanceReduced: true), .reducedLuminance)
    }

    /// Build 31: the day card (light appearance): dark text on a light card, every text colour and the "waits" glow
    /// at AA, fills 3:1 on the track; Always-On stays the dimmed night card; the night card is unchanged.
    func testTheDayCardFollowsTheLightAppearance() {
        XCTAssertEqual(HarnessgramTaskActivityPalette.palette(luminanceReduced: false, dark: false), .standardLight)
        XCTAssertEqual(HarnessgramTaskActivityPalette.palette(luminanceReduced: false, dark: true), .standard)
        XCTAssertEqual(HarnessgramTaskActivityPalette.palette(luminanceReduced: true, dark: false), .reducedLuminance)
        let day = HarnessgramTaskActivityPalette.standardLight
        XCTAssertGreaterThan(day.background.relativeLuminance, 0.8)
        XCTAssertLessThan(day.primaryText.relativeLuminance, 0.05)
        for background in [day.background, day.sky] {
            for (role, color) in day.textColors + [("glow", day.glow)] {
                let ratio = HarnessgramRGB.contrastRatio(color, background)
                XCTAssertGreaterThanOrEqual(ratio, 4.5, "day \(role): \(ratio)")
            }
        }
        // The gradient's weakest stop is the fill at the palette's tail opacity over the opaque track.
        for fill in [day.accent, day.approve] {
            XCTAssertGreaterThanOrEqual(HarnessgramRGB.contrastRatio(fill.over(day.track, alpha: day.fillTailOpacity), day.track), 3.0)
            XCTAssertGreaterThanOrEqual(HarnessgramRGB.contrastRatio(fill, day.track), 3.0)
        }
        XCTAssertGreaterThan(HarnessgramRGB.contrastRatio(day.track, day.background), 1.3)
        // Every light palette fades its fill less, so the whole fill keeps 3:1 on its track; the night ones keep their fade.
        for light in [HarnessgramTaskActivityPalette.standardLight, .smallLight] {
            for fill in [light.accent, light.approve] {
                XCTAssertGreaterThanOrEqual(HarnessgramRGB.contrastRatio(fill.over(light.track, alpha: light.fillTailOpacity), light.track), 3.0)
            }
        }
        XCTAssertEqual(HarnessgramTaskActivityPalette.standard.fillTailOpacity, 0.55)
        // The night card's decoration keeps its build 30 numbers.
        XCTAssertEqual(HarnessgramTaskActivityPalette.standard.sky, HarnessgramTaskActivityPalette.skyTop)
        XCTAssertEqual(HarnessgramTaskActivityPalette.standard.glow, HarnessgramTaskActivityPalette.horizonGlow)
        XCTAssertEqual(HarnessgramTaskActivityPalette.standard.edge, HarnessgramTaskActivityPalette.glassEdge)
    }

    func testTranslucentBlend() {
        let blended = HarnessgramRGB(hex: 0xFFFFFF).over(HarnessgramRGB(hex: 0x000000), alpha: 0.5)
        XCTAssertEqual(blended.red, 0.5, accuracy: 0.0001)
    }

    /// Build 31: the waiting widget's colours in the light and the dark appearance (white and the dark widget
    /// background): text at AA, the approve fill (never text: the button and the agents' dots) at AA under its white label.
    func testWidgetColoursKeepAAInLightAndDark() {
        let white = HarnessgramRGB(hex: 0xFFFFFF)
        let darkBackground = HarnessgramRGB(hex: 0x1C1C1E)
        for (name, tone) in [("accent", HarnessgramWidgetPalette.Tones.accent), ("decline", HarnessgramWidgetPalette.Tones.decline), ("sensitive", HarnessgramWidgetPalette.Tones.sensitive), ("radioOn", HarnessgramWidgetPalette.Tones.radioOn)] {
            let light = HarnessgramRGB.contrastRatio(HarnessgramRGB(hex: tone.light), white)
            let dark = HarnessgramRGB.contrastRatio(HarnessgramRGB(hex: tone.dark), darkBackground)
            XCTAssertGreaterThanOrEqual(light, 4.5, "light \(name): \(light)")
            XCTAssertGreaterThanOrEqual(dark, 4.5, "dark \(name): \(dark)")
        }
        let approve = HarnessgramWidgetPalette.Tones.approve
        XCTAssertGreaterThanOrEqual(HarnessgramRGB.contrastRatio(white, HarnessgramRGB(hex: approve.light)), 4.5)
        XCTAssertGreaterThanOrEqual(HarnessgramRGB.contrastRatio(white, HarnessgramRGB(hex: approve.dark)), 4.5)
    }
}
