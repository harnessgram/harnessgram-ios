import Foundation
import UIKit
import Display
import XCTest
import TelegramCore
import HarnessgramSettings
import HarnessgramHouseCore
import TelegramPresentationData

final class HarnessgramHouseThemeTests: XCTestCase {
    private func settings(houseTheme: Bool) -> HarnessgramSettings {
        let suite = "HarnessgramHouseThemeTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        let settings = HarnessgramSettings(defaults: defaults)
        settings.setHouseFeature(.theme, houseTheme)
        return settings
    }

    // PresentationData needs PresentationStrings, which cannot be built in a test process (it asserts without the app
    // bundle's data), so the tests go through the theme functions `harnessgramHouseApply` is made of.
    private func baseTheme(dark: Bool) -> PresentationTheme {
        return makeDefaultPresentationTheme(reference: dark ? .night : .day, serviceBackgroundColor: nil)
    }

    private func rgb(_ color: UIColor) -> UInt32 {
        return color.rgb
    }

    func testWithTheSwitchOffTheThemeIsTheSameObject() {
        for dark in [false, true] {
            let base = self.baseTheme(dark: dark)
            XCTAssertTrue(harnessgramHouseResolvedTheme(base, settings: self.settings(houseTheme: false)) === base)
        }
    }

    /// Owner-first (build 18 fix): the House colours are on in the shipped settings until the owner turns them off.
    func testTheSwitchIsOnByDefaultInTheShippedSettings() {
        let suite = "HarnessgramHouseThemeTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let base = self.baseTheme(dark: false)
        XCTAssertFalse(harnessgramHouseResolvedTheme(base, settings: HarnessgramSettings(defaults: defaults)) === base)
    }

    private func assertCarriesTheTokens(_ theme: PresentationTheme, dark: Bool, file: StaticString = #filePath, line: UInt = #line) {
        let p = HouseColors.palette(darkAppearance: dark)
        XCTAssertEqual(theme.chat.defaultWallpaper, .color(p.bg.rgb), "chat page (the presentation data takes it as its wallpaper)", file: file, line: line)
        XCTAssertEqual(self.rgb(theme.list.plainBackgroundColor), p.bg.rgb, "list page", file: file, line: line)
        XCTAssertEqual(self.rgb(theme.list.blocksBackgroundColor), p.bg.rgb, "list blocks page", file: file, line: line)
        XCTAssertEqual(self.rgb(theme.list.itemBlocksBackgroundColor), p.surface.rgb, "list card", file: file, line: line)
        XCTAssertEqual(self.rgb(theme.list.itemPrimaryTextColor), p.ink.rgb, "list text", file: file, line: line)
        // Build 23 contrast audit: secondary and accent text are the tokens lifted just enough for 4.5:1 on a pressed row.
        let pressedCard = harnessgramMix(p.surface, p.ink, 0.07)
        XCTAssertEqual(self.rgb(theme.list.itemSecondaryTextColor), harnessgramReadable(p.ink3, on: pressedCard).rgb, file: file, line: line)
        XCTAssertEqual(self.rgb(theme.list.itemAccentColor), harnessgramReadable(p.olive, on: pressedCard).rgb, "list accent", file: file, line: line)
        XCTAssertEqual(self.rgb(theme.list.itemBlocksSeparatorColor), p.border.rgb, file: file, line: line)
        XCTAssertEqual(self.rgb(theme.list.itemDestructiveColor), harnessgramReadable(p.statusError, on: pressedCard).rgb, file: file, line: line)

        XCTAssertEqual(self.rgb(theme.rootController.tabBar.selectedIconColor), p.olive.rgb, "tab", file: file, line: line)
        XCTAssertEqual(self.rgb(theme.rootController.tabBar.iconColor), p.ink3.rgb, file: file, line: line)
        XCTAssertEqual(self.rgb(theme.rootController.tabBar.badgeBackgroundColor), p.amberDeep.rgb, "count badge", file: file, line: line)
        XCTAssertEqual(self.rgb(theme.rootController.tabBar.badgeTextColor), p.onAmberDeep.rgb, file: file, line: line)
        XCTAssertEqual(self.rgb(theme.rootController.navigationBar.buttonColor), p.olive.rgb, "navigation", file: file, line: line)
        XCTAssertEqual(self.rgb(theme.rootController.navigationBar.primaryTextColor), p.ink.rgb, file: file, line: line)
        XCTAssertEqual(self.rgb(theme.rootController.navigationBar.opaqueBackgroundColor), p.bg.rgb, file: file, line: line)

        XCTAssertEqual(self.rgb(theme.chatList.backgroundColor), p.bg.rgb, "chat list", file: file, line: line)
        XCTAssertEqual(self.rgb(theme.chatList.titleColor), p.ink.rgb, file: file, line: line)
        XCTAssertEqual(self.rgb(theme.chatList.unreadBadgeActiveBackgroundColor), p.amberDeep.rgb, file: file, line: line)

        XCTAssertEqual(theme.chat.defaultWallpaper, .color(p.bg.rgb), "chat page", file: file, line: line)
        XCTAssertEqual(theme.chat.message.outgoing.bubble.withoutWallpaper.fill.map { self.rgb($0) }, [p.olive.rgb], "own bubble", file: file, line: line)
        XCTAssertEqual(theme.chat.message.outgoing.bubble.withWallpaper.fill.map { self.rgb($0) }, [p.olive.rgb], file: file, line: line)
        XCTAssertEqual(self.rgb(theme.chat.message.outgoing.primaryTextColor), p.onOlive.rgb, file: file, line: line)
        XCTAssertEqual(theme.chat.message.incoming.bubble.withoutWallpaper.fill.map { self.rgb($0) }, [p.surface.rgb], "their bubble", file: file, line: line)
        XCTAssertEqual(self.rgb(theme.chat.message.incoming.primaryTextColor), p.ink.rgb, file: file, line: line)
        XCTAssertEqual(self.rgb(theme.chat.inputPanel.actionControlFillColor), p.olive.rgb, "input panel", file: file, line: line)
        XCTAssertEqual(self.rgb(theme.chat.inputPanel.inputBackgroundColor), p.surface.rgb, file: file, line: line)

        XCTAssertEqual(self.rgb(theme.actionSheet.standardActionTextColor), harnessgramReadable(p.olive, on: harnessgramMix(p.surfaceRaised, p.ink, 0.07)).rgb, "action sheet", file: file, line: line)
        XCTAssertEqual(self.rgb(theme.inAppNotification.fillColor), p.surfaceRaised.rgb, "banner", file: file, line: line)
    }

    func testTheStoneThemeCarriesTheLightTokens() {
        let base = self.baseTheme(dark: false)
        let theme = harnessgramHouseResolvedTheme(base, settings: self.settings(houseTheme: true))
        XCTAssertFalse(theme === base)
        XCTAssertFalse(theme.overallDarkAppearance)
        self.assertCarriesTheTokens(theme, dark: false)
    }

    func testTheNightThemeCarriesTheDarkTokens() {
        let base = self.baseTheme(dark: true)
        let theme = harnessgramHouseResolvedTheme(base, settings: self.settings(houseTheme: true))
        XCTAssertTrue(theme.overallDarkAppearance)
        self.assertCarriesTheTokens(theme, dark: true)
    }

    func testTheThemeKeepsWhatTheUpstreamSwitchesAndCachesAreKeyedOn() {
        for dark in [false, true] {
            let base = self.baseTheme(dark: dark)
            let theme = harnessgramHouseResolvedTheme(base, settings: self.settings(houseTheme: true))
            XCTAssertEqual(theme.index, base.index)
            XCTAssertEqual(theme.referenceTheme, base.referenceTheme)
            XCTAssertEqual(theme.name, base.name)
            XCTAssertEqual(theme.overallDarkAppearance, base.overallDarkAppearance)
            // Only the House parts are recoloured: everything else is the base's own object.
            XCTAssertTrue(theme.intro === base.intro)
            XCTAssertTrue(theme.passcode === base.passcode)
            XCTAssertTrue(theme.chart === base.chart)
        }
    }

    func testSwitchingOffGivesTheBaseBackAtOnce() {
        let settings = self.settings(houseTheme: true)
        let base = self.baseTheme(dark: false)
        XCTAssertFalse(harnessgramHouseResolvedTheme(base, settings: settings) === base)
        settings.setHouseFeature(.theme, false)
        XCTAssertTrue(harnessgramHouseResolvedTheme(base, settings: settings) === base)
    }

    /// Text on the House surfaces keeps WCAG AA (tokens.json: ink 13.6, ink2 6.8, ink3 4.9, white on amberDeep 5.1).
    func testTextKeepsContrastOnItsSurface() {
        func luminance(_ rgb: UInt32) -> Double {
            func channel(_ value: UInt32) -> Double {
                let c = Double(value) / 255.0
                return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * channel((rgb >> 16) & 0xff) + 0.7152 * channel((rgb >> 8) & 0xff) + 0.0722 * channel(rgb & 0xff)
        }
        func ratio(_ a: UInt32, _ b: UInt32) -> Double {
            let l1 = luminance(a)
            let l2 = luminance(b)
            return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
        }
        for dark in [false, true] {
            let p = HouseColors.palette(darkAppearance: dark)
            XCTAssertGreaterThanOrEqual(ratio(p.ink.rgb, p.bg.rgb), 4.5)
            XCTAssertGreaterThanOrEqual(ratio(p.ink2.rgb, p.bg.rgb), 4.5)
            XCTAssertGreaterThanOrEqual(ratio(p.ink3.rgb, p.bg.rgb), 4.5)
            XCTAssertGreaterThanOrEqual(ratio(p.ink3.rgb, p.surface.rgb), 4.5)
            XCTAssertGreaterThanOrEqual(ratio(p.onOlive.rgb, p.olive.rgb), 4.5)
            XCTAssertGreaterThanOrEqual(ratio(p.olive.rgb, p.surface.rgb), 4.5)
            XCTAssertGreaterThanOrEqual(ratio(p.onAmberDeep.rgb, p.amberDeep.rgb), 4.5)
        }
    }
}
