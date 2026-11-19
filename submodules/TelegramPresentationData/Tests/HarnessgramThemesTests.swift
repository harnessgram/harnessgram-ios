import Foundation
import UIKit
import Display
import XCTest
import TelegramCore
import HarnessgramSettings
import HarnessgramHouseCore
import TelegramPresentationData

/// Build 22: the built-in Harnessgram themes ("לילה בקוקפיט", "שחר על המסלול", "שמיים פתוחים", "מכשירים").
final class HarnessgramThemesTests: XCTestCase {
    private func settings(theme: HarnessgramSettings.Theme, houseTheme: Bool) -> HarnessgramSettings {
        let defaults = UserDefaults(suiteName: "HarnessgramThemesTests." + UUID().uuidString)!
        let settings = HarnessgramSettings(defaults: defaults)
        settings.setHouseFeature(.theme, houseTheme)
        settings.theme = theme
        return settings
    }

    private func baseTheme(dark: Bool) -> PresentationTheme {
        return makeDefaultPresentationTheme(reference: dark ? .night : .day, serviceBackgroundColor: nil)
    }

    private func luminance(_ color: UIColor) -> Double {
        var r: CGFloat = 0.0, g: CGFloat = 0.0, b: CGFloat = 0.0, a: CGFloat = 0.0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        func channel(_ c: CGFloat) -> Double {
            let v = Double(c)
            return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)
    }

    private func ratio(_ a: UIColor, _ b: UIColor) -> Double {
        let la = self.luminance(a)
        let lb = self.luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    func testNoneLeavesTheTelegramThemeAndTheHouseColoursAlone() {
        for dark in [false, true] {
            let base = self.baseTheme(dark: dark)
            XCTAssertTrue(harnessgramHouseResolvedTheme(base, settings: self.settings(theme: .none, houseTheme: false)) === base)
        }
    }

    func testAThemeWinsOverTheHouseColoursAndFollowsItsOwnAppearance() {
        for palette in HarnessgramThemePalettes.all {
            for dark in [false, true] {
                for house in [false, true] {
                    let theme = harnessgramHouseResolvedTheme(self.baseTheme(dark: dark), settings: self.settings(theme: palette.theme, houseTheme: house))
                    XCTAssertEqual(theme.overallDarkAppearance, palette.dark, "\(palette.theme) on a \(dark ? "dark" : "light") base")
                    XCTAssertEqual(theme.list.blocksBackgroundColor.rgb, palette.palette.bg.rgb, "\(palette.theme)")
                    XCTAssertEqual(theme.chatList.backgroundColor.rgb, palette.palette.bg.rgb)
                    XCTAssertEqual(theme.list.itemAccentColor.rgb, palette.palette.olive.rgb)
                    XCTAssertEqual(theme.chat.defaultWallpaper, .color(palette.palette.bg.rgb))
                    XCTAssertEqual(theme.chat.message.outgoing.bubble.withoutWallpaper.fill.map(\.rgb), [palette.palette.olive.rgb])
                    XCTAssertEqual(theme.chat.message.incoming.bubble.withoutWallpaper.fill.map(\.rgb), [palette.palette.surface.rgb])
                }
            }
        }
    }

    func testTheSameChoiceGivesTheSameThemeObject() {
        let settings = self.settings(theme: .openSky, houseTheme: false)
        let first = harnessgramHouseResolvedTheme(self.baseTheme(dark: false), settings: settings)
        let second = harnessgramHouseResolvedTheme(self.baseTheme(dark: true), settings: settings)
        XCTAssertTrue(first === second, "built once, so the presentation data does not churn")
    }

    /// The finished themes' text keeps WCAG AA on its main backgrounds and in both bubbles.
    func testTextKeepsAAOnTheMainBackgroundsAndBubbles() {
        for palette in HarnessgramThemePalettes.all {
            let theme = makeHarnessgramThemePresentationTheme(palette)
            let pairs: [(String, UIColor, UIColor)] = [
                ("list text", theme.list.itemPrimaryTextColor, theme.list.itemBlocksBackgroundColor),
                ("list secondary", theme.list.itemSecondaryTextColor, theme.list.itemBlocksBackgroundColor),
                ("list accent", theme.list.itemAccentColor, theme.list.itemBlocksBackgroundColor),
                ("section header", theme.list.sectionHeaderTextColor, theme.list.blocksBackgroundColor),
                ("footer", theme.list.freeTextColor, theme.list.blocksBackgroundColor),
                ("chat title", theme.chatList.titleColor, theme.chatList.itemBackgroundColor),
                ("chat preview", theme.chatList.messageTextColor, theme.chatList.itemBackgroundColor),
                ("chat date", theme.chatList.dateTextColor, theme.chatList.itemBackgroundColor),
                ("unread badge", theme.chatList.unreadBadgeActiveTextColor, theme.chatList.unreadBadgeActiveBackgroundColor),
                ("their bubble", theme.chat.message.incoming.primaryTextColor, theme.chat.message.incoming.bubble.withoutWallpaper.fill[0]),
                ("their link", theme.chat.message.incoming.linkTextColor, theme.chat.message.incoming.bubble.withoutWallpaper.fill[0]),
                ("your bubble", theme.chat.message.outgoing.primaryTextColor, theme.chat.message.outgoing.bubble.withoutWallpaper.fill[0]),
                ("navigation title", theme.rootController.navigationBar.primaryTextColor, theme.rootController.navigationBar.opaqueBackgroundColor),
                ("navigation button", theme.rootController.navigationBar.buttonColor, theme.rootController.navigationBar.opaqueBackgroundColor),
                ("input text", theme.chat.inputPanel.inputTextColor, theme.chat.inputPanel.inputBackgroundColor),
                ("action sheet", theme.actionSheet.primaryTextColor, theme.actionSheet.opaqueItemBackgroundColor),
            ]
            for (role, text, background) in pairs {
                let value = self.ratio(text, background)
                XCTAssertGreaterThanOrEqual(value, 4.5, "\(palette.theme.rawValue): \(role) = \(value)")
            }
        }
    }
}
