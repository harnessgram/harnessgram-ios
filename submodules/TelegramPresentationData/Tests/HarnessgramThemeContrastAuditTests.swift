import XCTest
import UIKit
import HarnessgramSettings
import HarnessgramHouseCore
@testable import TelegramPresentationData

/// Build 23 (owner: "the themes are not contrasting enough in all states"): a complete contrast audit over every colour
/// pair a Harnessgram theme sets or changes, read from the PresentationTheme objects the theme code produces, so a
/// later colour change cannot slip past. WCAG 2.x: 4.5 for body text and small labels; 3.0 for icons, large titles,
/// non-text controls and placeholders. A colour with alpha is composited over what it sits on (bars and menus over the
/// page, the chat's date pill over the chat wallpaper). On a failure the message lists every failing role and ratio.
///
/// Variants: each built-in theme has one appearance (its `dark`); the House colours have a light and a dark one, both
/// audited. Telegram derives no increased-contrast variant for these themes (iOS "Increase Contrast" does not change a
/// PresentationTheme), so there is none to audit. Plain hairline separators carry no meaning and are not held to 3.0.
final class HarnessgramThemeContrastAuditTests: XCTestCase {
    private struct Pair {
        let role: String
        let foreground: UIColor
        let background: UIColor
        let minimum: Double
    }

    private static let text = 4.5
    private static let nonText = 3.0

    private func rgba(_ color: UIColor) -> (Double, Double, Double, Double) {
        var r: CGFloat = 0.0, g: CGFloat = 0.0, b: CGFloat = 0.0, a: CGFloat = 0.0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Double(r), Double(g), Double(b), Double(a))
    }

    /// `top` drawn over `bottom` (both made opaque first; `bottom` over `page` when it has alpha).
    private func over(_ top: UIColor, _ bottom: UIColor) -> UIColor {
        let t = self.rgba(top), b = self.rgba(bottom)
        let a = t.3
        return UIColor(red: CGFloat(t.0 * a + b.0 * (1.0 - a)), green: CGFloat(t.1 * a + b.1 * (1.0 - a)), blue: CGFloat(t.2 * a + b.2 * (1.0 - a)), alpha: 1.0)
    }

    private func luminance(_ color: UIColor) -> Double {
        let c = self.rgba(color)
        func channel(_ v: Double) -> Double {
            return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(c.0) + 0.7152 * channel(c.1) + 0.0722 * channel(c.2)
    }

    private func ratio(_ a: UIColor, _ b: UIColor) -> Double {
        let la = self.luminance(a), lb = self.luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /// Every pair the theme draws, backgrounds made opaque over the page.
    private func pairs(_ theme: PresentationTheme) -> [Pair] {
        let page = self.over(theme.list.blocksBackgroundColor, .white)
        let solid: (UIColor) -> UIColor = { self.over($0, page) }
        var pairs: [Pair] = []
        func add(_ role: String, _ foreground: UIColor, _ background: UIColor, _ minimum: Double) {
            let bg = solid(background)
            pairs.append(Pair(role: role, foreground: self.over(foreground, bg), background: bg, minimum: minimum))
        }

        // Chat list: every row background (plain, pinned, highlighted, selected).
        let chatList = theme.chatList
        let rowBackgrounds: [(String, UIColor)] = [("row", chatList.itemBackgroundColor), ("pinned row", chatList.pinnedItemBackgroundColor), ("pressed row", chatList.itemHighlightedBackgroundColor), ("pressed pinned row", chatList.pinnedItemHighlightedBackgroundColor), ("selected row", chatList.itemSelectedBackgroundColor)]
        for (name, background) in rowBackgrounds {
            add("chat list title on \(name)", chatList.titleColor, background, Self.text)
            add("chat list author on \(name)", chatList.authorNameColor, background, Self.text)
            add("chat list preview on \(name)", chatList.messageTextColor, background, Self.text)
            add("chat list date on \(name)", chatList.dateTextColor, background, Self.text)
            add("chat list read check on \(name)", chatList.checkmarkColor, background, Self.nonText)
            add("chat list mute icon on \(name)", chatList.muteIconColor, background, Self.nonText)
            add("chat list pin icon on \(name)", chatList.pinnedBadgeColor, background, Self.nonText)
        }
        add("chat list unread badge", chatList.unreadBadgeActiveTextColor, chatList.unreadBadgeActiveBackgroundColor, Self.text)
        add("chat list muted unread badge", chatList.unreadBadgeInactiveTextColor, chatList.unreadBadgeInactiveBackgroundColor, Self.text)
        add("chat list section header", chatList.sectionHeaderTextColor, chatList.sectionHeaderFillColor, Self.text)
        add("chat list verified mark", chatList.verifiedIconForegroundColor, chatList.verifiedIconFillColor, Self.nonText)

        // Navigation bar and tab bar.
        let nav = theme.rootController.navigationBar
        let navBackground = solid(nav.blurredBackgroundColor)
        for (name, background) in [("bar", nav.opaqueBackgroundColor), ("translucent bar", navBackground)] {
            add("navigation title on \(name)", nav.primaryTextColor, background, Self.text)
            add("navigation subtitle on \(name)", nav.secondaryTextColor, background, Self.text)
            add("navigation button on \(name)", nav.buttonColor, background, Self.text)
            add("navigation accent on \(name)", nav.accentTextColor, background, Self.text)
            add("navigation control on \(name)", nav.controlColor, background, Self.nonText)
        }
        add("navigation badge", nav.badgeTextColor, nav.badgeBackgroundColor, Self.text)
        add("segmented control text", nav.segmentedTextColor, nav.segmentedForegroundColor, Self.text)
        let tab = theme.rootController.tabBar
        let tabBackground = solid(tab.backgroundColor)
        add("tab label", tab.textColor, tabBackground, Self.text)
        add("selected tab label", tab.selectedTextColor, tabBackground, Self.text)
        add("tab icon", tab.iconColor, tabBackground, Self.nonText)
        add("selected tab icon", tab.selectedIconColor, tabBackground, Self.nonText)
        add("tab badge", tab.badgeTextColor, tab.badgeBackgroundColor, Self.text)

        // Search field.
        let search = theme.rootController.navigationSearchBar
        let searchFill = self.over(search.inputFillColor, solid(search.backgroundColor))
        add("search text", search.inputTextColor, searchFill, Self.text)
        add("search placeholder", search.inputPlaceholderTextColor, searchFill, Self.nonText)
        add("search icon", search.inputIconColor, searchFill, Self.nonText)
        add("search cancel", search.accentColor, search.backgroundColor, Self.text)

        // Chat: both bubbles, plain and pressed.
        let message = theme.chat.message
        let incoming = message.incoming, outgoing = message.outgoing
        let incomingFills = [("their bubble", incoming.bubble.withoutWallpaper.fill[0]), ("their pressed bubble", incoming.bubble.withoutWallpaper.highlightedFill)]
        let outgoingFills = [("your bubble", outgoing.bubble.withoutWallpaper.fill[0]), ("your pressed bubble", outgoing.bubble.withoutWallpaper.highlightedFill)]
        for (colors, fills) in [(incoming, incomingFills), (outgoing, outgoingFills)] {
            for (name, fill) in fills {
                add("text in \(name)", colors.primaryTextColor, fill, Self.text)
                add("time in \(name)", colors.secondaryTextColor, fill, Self.text)
                add("link in \(name)", colors.linkTextColor, fill, Self.text)
                add("reply and quote header in \(name)", colors.accentTextColor, fill, Self.text)
                add("file title in \(name)", colors.fileTitleColor, fill, Self.text)
                add("file details in \(name)", colors.fileDescriptionColor, fill, Self.text)
                add("media control in \(name)", colors.mediaActiveControlColor, fill, Self.nonText)
            }
        }
        add("read checks in your bubble", message.outgoingCheckColor, outgoing.bubble.withoutWallpaper.fill[0], Self.nonText)
        let wallpaper: UIColor
        if case let .color(rgb) = theme.chat.defaultWallpaper {
            wallpaper = UIColor(red: CGFloat((rgb >> 16) & 0xff) / 255.0, green: CGFloat((rgb >> 8) & 0xff) / 255.0, blue: CGFloat(rgb & 0xff) / 255.0, alpha: 1.0)
        } else {
            wallpaper = page
        }
        let service = theme.chat.serviceMessage.components.withDefaultWallpaper
        let serviceFill = self.over(service.fill, wallpaper)
        add("date pill and service message", service.primaryText, serviceFill, Self.text)
        add("info link", message.infoLinkTextColor, wallpaper, Self.text)

        // Input bar.
        let input = theme.chat.inputPanel
        let panel = solid(input.panelBackgroundColorNoWallpaper)
        add("input text", input.inputTextColor, input.inputBackgroundColor, Self.text)
        add("input placeholder", input.inputPlaceholderColor, input.inputBackgroundColor, Self.nonText)
        add("input icons", input.panelControlColor, panel, Self.nonText)
        add("input accent icon", input.panelControlAccentColor, panel, Self.nonText)
        add("send button", input.actionControlForegroundColor, input.actionControlFillColor, Self.nonText)
        add("input panel text", input.primaryTextColor, panel, Self.text)
        add("input panel secondary", input.secondaryTextColor, panel, Self.text)

        // Settings lists.
        let list = theme.list
        for (name, background) in [("row", list.itemBlocksBackgroundColor), ("pressed row", list.itemHighlightedBackgroundColor), ("plain row", list.plainBackgroundColor)] {
            add("list text on \(name)", list.itemPrimaryTextColor, background, Self.text)
            add("list secondary on \(name)", list.itemSecondaryTextColor, background, Self.text)
            add("list accent on \(name)", list.itemAccentColor, background, Self.text)
            add("list destructive on \(name)", list.itemDestructiveColor, background, Self.text)
            add("disclosure arrow on \(name)", list.disclosureArrowColor, background, Self.nonText)
        }
        add("list placeholder", list.itemPlaceholderTextColor, list.itemBlocksBackgroundColor, Self.nonText)
        add("section header", list.sectionHeaderTextColor, list.blocksBackgroundColor, Self.text)
        add("footer", list.freeTextColor, list.blocksBackgroundColor, Self.text)
        add("footer error", list.freeTextErrorColor, list.blocksBackgroundColor, Self.text)
        add("switch on", list.itemSwitchColors.positiveColor, list.itemBlocksBackgroundColor, Self.nonText)
        add("check mark on the accent", list.itemCheckColors.foregroundColor, list.itemCheckColors.fillColor, Self.nonText)
        add("text on an accent button", list.itemCheckColors.foregroundColor, list.itemAccentColor, Self.text)

        // Sheets and context menus, plain and pressed.
        let sheet = theme.actionSheet
        for (name, background) in [("sheet", sheet.opaqueItemBackgroundColor), ("pressed sheet item", sheet.opaqueItemHighlightedBackgroundColor), ("translucent sheet", sheet.itemBackgroundColor), ("pressed translucent sheet item", sheet.itemHighlightedBackgroundColor)] {
            add("sheet text on \(name)", sheet.primaryTextColor, background, Self.text)
            add("sheet secondary on \(name)", sheet.secondaryTextColor, background, Self.text)
            add("sheet action on \(name)", sheet.standardActionTextColor, background, Self.text)
            add("sheet destructive on \(name)", sheet.destructiveActionTextColor, background, Self.text)
        }
        add("sheet field text", sheet.inputTextColor, sheet.inputBackgroundColor, Self.text)
        add("sheet field placeholder", sheet.inputPlaceholderColor, sheet.inputBackgroundColor, Self.nonText)
        let menu = theme.contextMenu
        let menuBackground = solid(menu.backgroundColor)
        for (name, background) in [("menu", menuBackground), ("pressed menu item", self.over(menu.itemHighlightedBackgroundColor, menuBackground))] {
            add("menu text on \(name)", menu.primaryColor, background, Self.text)
            add("menu secondary on \(name)", menu.secondaryColor, background, Self.text)
            add("menu destructive on \(name)", menu.destructiveColor, background, Self.text)
        }
        add("in-app banner", theme.inAppNotification.primaryTextColor, theme.inAppNotification.fillColor, Self.text)
        return pairs
    }

    /// Every theme the Harnessgram code produces: the four built-in themes and the House colours on day and night.
    private func themes() -> [(String, PresentationTheme)] {
        var result: [(String, PresentationTheme)] = HarnessgramThemePalettes.all.map { ($0.theme.rawValue, makeHarnessgramThemePresentationTheme($0)) }
        for dark in [false, true] {
            let base = makeDefaultPresentationTheme(reference: dark ? .night : .day, serviceBackgroundColor: nil)
            result.append((dark ? "house night" : "house stone", makeHousePresentationTheme(base: base)))
        }
        return result
    }

    func testEveryThemePassesContrastOnEverySurface() {
        var failures: [String] = []
        var checked = 0
        for (name, theme) in self.themes() {
            for pair in self.pairs(theme) {
                checked += 1
                let value = self.ratio(pair.foreground, pair.background)
                if value < pair.minimum {
                    failures.append("\(name): \(pair.role) = \(String(format: "%.2f", value)) (needs \(pair.minimum))")
                }
            }
        }
        XCTAssertGreaterThan(checked, 600, "the audit covers every surface of every theme")
        XCTAssertTrue(failures.isEmpty, "\(failures.count) pairs below WCAG:\n" + failures.joined(separator: "\n"))
    }
}
