import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import HarnessgramSettings
import HarnessgramHouseCore

// The House colours (Harnessgram "The House", step 1). Recolour at the presentation-data choke point: no new
// built-in theme type (that enum is stored as an Int32 and about 14 files switch over it). The House theme is the
// theme Telegram already resolved (day or night, sunset auto-night included) with its colours replaced by the stone
// or night palette, rebuilt through the public `PresentationTheme` initialiser. It keeps `name`, `index` and
// `referenceTheme` from the base, so every switch and cache keyed on them still works, and with the switch off
// `harnessgramHouseApply` returns its input untouched.

private extension HouseColor {
    var ui: UIColor {
        return UIColor(rgb: self.rgb, alpha: CGFloat(self.alpha))
    }
}

/// `a` blended toward `b` by `t` (0 ... 1), opaque.
public func harnessgramMix(_ a: HouseColor, _ b: HouseColor, _ t: Double) -> HouseColor {
    func channel(_ shift: UInt32) -> UInt32 {
        let x = Double((a.rgb >> shift) & 0xff), y = Double((b.rgb >> shift) & 0xff)
        return UInt32(max(0.0, min(255.0, (x + (y - x) * t).rounded())))
    }
    return HouseColor((channel(16) << 16) | (channel(8) << 8) | channel(0))
}

/// Build 23 contrast audit: `text` moved toward white (on a dark surface) or black (on a light one), keeping its hue,
/// just until it reaches `minimum` against `surface` (the same colour when it already does).
public func harnessgramReadable(_ text: HouseColor, on surface: HouseColor, minimum: Double = 4.5) -> HouseColor {
    if HouseColor.contrastRatio(text, surface) >= minimum {
        return text
    }
    let target = surface.relativeLuminance < 0.18 ? HouseColor(0xFFFFFF) : HouseColor(0x000000)
    var step = 0.04
    while step <= 1.0 {
        let candidate = harnessgramMix(text, target, step)
        if HouseColor.contrastRatio(candidate, surface) >= minimum {
            return candidate
        }
        step += 0.04
    }
    return target
}

/// The House theme built on `base`: stone when the base is light, night when it is dark.
public func makeHousePresentationTheme(base: PresentationTheme) -> PresentationTheme {
    return makeHarnessgramPalettePresentationTheme(base: base, palette: HouseColors.palette(darkAppearance: base.overallDarkAppearance))
}

/// `base` recoloured with a House-shaped palette (the House colours, or a built-in Harnessgram theme): pages, cards,
/// ink, the accent (`olive`), your bubbles (`olive` with `onOlive` text), their bubbles (`surface` with `ink`), the
/// count badge (`amberDeep` with `onAmberDeep`) and the chat page (`bg`).
public func makeHarnessgramPalettePresentationTheme(base: PresentationTheme, palette p: HousePalette) -> PresentationTheme {
    // Build 23 contrast audit (HarnessgramThemeContrastAuditTests): a pressed or selected surface is its own colour
    // nudged toward the ink (subtle, as Telegram's own), never the border colour, so secondary text keeps 4.5:1 on it;
    // secondary and warning text on sheets and menus is lifted just enough for 4.5:1.
    let pressedPage = harnessgramMix(p.bg, p.ink, 0.07)
    let pressedCard = harnessgramMix(p.surface, p.ink, 0.07)
    let pressedRaised = harnessgramMix(p.surfaceRaised, p.ink, 0.07)
    let sheetSecondary = harnessgramReadable(harnessgramReadable(p.ink3, on: pressedRaised), on: p.surfaceRaised)
    let sheetDestructive = harnessgramReadable(p.statusError, on: pressedRaised)
    let listDestructive = harnessgramReadable(p.statusError, on: pressedCard)
    let listAccent = harnessgramReadable(p.olive, on: pressedCard)
    let rowSecondary = harnessgramReadable(p.ink3, on: pressedCard)
    let pageSecondary = harnessgramReadable(harnessgramReadable(p.ink3, on: pressedPage), on: pressedCard)

    // Navigation bar and tab bar. The bars keep the translucency the base gave them (their alpha).
    func translucent(_ color: HouseColor, like old: UIColor) -> UIColor {
        var alpha: CGFloat = 1.0
        old.getRed(nil, green: nil, blue: nil, alpha: &alpha)
        return color.ui.withAlphaComponent(alpha)
    }
    let tabBar = base.rootController.tabBar.withUpdated(
        backgroundColor: translucent(p.bg, like: base.rootController.tabBar.backgroundColor),
        separatorColor: p.border.ui,
        iconColor: p.ink3.ui,
        selectedIconColor: p.olive.ui,
        textColor: p.ink3.ui,
        selectedTextColor: p.olive.ui,
        badgeBackgroundColor: p.amberDeep.ui,
        badgeStrokeColor: p.bg.ui,
        badgeTextColor: p.onAmberDeep.ui
    )
    let navigationBar = base.rootController.navigationBar.withUpdated(
        buttonColor: p.olive.ui,
        disabledButtonColor: p.ink3.ui.withAlphaComponent(0.6),
        primaryTextColor: p.ink.ui,
        secondaryTextColor: p.ink3.ui,
        controlColor: p.ink2.ui,
        accentTextColor: p.olive.ui,
        blurredBackgroundColor: translucent(p.bg, like: base.rootController.navigationBar.blurredBackgroundColor),
        opaqueBackgroundColor: p.bg.ui,
        separatorColor: p.border.ui,
        badgeBackgroundColor: p.amberDeep.ui,
        badgeStrokeColor: p.bg.ui,
        badgeTextColor: p.onAmberDeep.ui,
        segmentedBackgroundColor: p.border.ui,
        segmentedForegroundColor: p.surfaceRaised.ui,
        segmentedTextColor: p.ink.ui,
        segmentedDividerColor: p.borderStrong.ui
    )
    let searchBar = base.rootController.navigationSearchBar.withUpdated(
        backgroundColor: p.bg.ui,
        accentColor: p.olive.ui,
        inputFillColor: p.border.ui,
        inputTextColor: p.ink.ui,
        inputPlaceholderTextColor: p.ink3.ui,
        inputIconColor: p.ink3.ui,
        inputClearButtonColor: p.ink3.ui,
        separatorColor: p.border.ui
    )
    let rootController = base.rootController.withUpdated(tabBar: tabBar, navigationBar: navigationBar, navigationSearchBar: searchBar)

    // Lists (Settings and every other ItemListController screen).
    let list = base.list.withUpdated(
        blocksBackgroundColor: p.bg.ui,
        modalBlocksBackgroundColor: p.bg.ui,
        plainBackgroundColor: p.bg.ui,
        modalPlainBackgroundColor: p.surfaceRaised.ui,
        itemPrimaryTextColor: p.ink.ui,
        itemSecondaryTextColor: rowSecondary.ui,
        itemDisabledTextColor: p.ink3.ui.withAlphaComponent(0.6),
        itemAccentColor: listAccent.ui,
        itemHighlightedColor: p.olive.ui.withAlphaComponent(0.15),
        itemDestructiveColor: listDestructive.ui,
        itemPlaceholderTextColor: p.ink3.ui,
        itemBlocksBackgroundColor: p.surface.ui,
        itemModalBlocksBackgroundColor: p.surface.ui,
        itemHighlightedBackgroundColor: pressedCard.ui,
        itemBlocksSeparatorColor: p.border.ui,
        itemPlainSeparatorColor: p.border.ui,
        disclosureArrowColor: p.ink3.ui,
        sectionHeaderTextColor: p.ink2.ui,
        freeTextColor: p.ink2.ui,
        freeTextErrorColor: p.statusError.ui,
        freeTextSuccessColor: p.statusWorking.ui,
        freeMonoIconColor: p.ink3.ui,
        itemSwitchColors: base.list.itemSwitchColors.withUpdated(frameColor: p.borderStrong.ui, positiveColor: p.olive.ui, negativeColor: p.statusError.ui),
        itemCheckColors: base.list.itemCheckColors.withUpdated(fillColor: p.olive.ui, strokeColor: p.borderStrong.ui, foregroundColor: p.onOlive.ui),
        controlSecondaryColor: p.ink3.ui.withAlphaComponent(0.5),
        mediaPlaceholderColor: p.border.ui,
        inputClearButtonColor: p.ink3.ui
    )

    // The chat list (Chats tab).
    let chatList = base.chatList.withUpdated(
        backgroundColor: p.bg.ui,
        itemSeparatorColor: p.border.ui,
        itemBackgroundColor: p.bg.ui,
        pinnedItemBackgroundColor: p.surface.ui,
        itemHighlightedBackgroundColor: pressedPage.ui,
        pinnedItemHighlightedBackgroundColor: pressedCard.ui,
        itemSelectedBackgroundColor: pressedPage.ui,
        titleColor: p.ink.ui,
        dateTextColor: pageSecondary.ui,
        authorNameColor: p.ink.ui,
        messageTextColor: pageSecondary.ui,
        messageHighlightedTextColor: p.ink2.ui,
        checkmarkColor: p.olive.ui,
        pendingIndicatorColor: p.ink3.ui,
        muteIconColor: pageSecondary.ui,
        unreadBadgeActiveBackgroundColor: p.amberDeep.ui,
        unreadBadgeActiveTextColor: p.onAmberDeep.ui,
        unreadBadgeInactiveBackgroundColor: p.statusIdle.ui,
        unreadBadgeInactiveTextColor: p.ink.ui,
        reactionBadgeActiveBackgroundColor: p.amberDeep.ui,
        pinnedBadgeColor: pageSecondary.ui,
        pinnedSearchBarColor: p.border.ui,
        regularSearchBarColor: p.border.ui,
        sectionHeaderFillColor: p.surface.ui,
        sectionHeaderTextColor: p.ink2.ui,
        verifiedIconFillColor: p.olive.ui,
        verifiedIconForegroundColor: p.onOlive.ui,
        onlineDotColor: p.statusWorking.ui,
        storyUnseenColors: PresentationThemeGradientColors(topColor: p.amber.ui, bottomColor: p.amberDeep.ui),
        storyUnseenPrivateColors: PresentationThemeGradientColors(topColor: p.olive.ui, bottomColor: p.oliveDeep.ui),
        storySeenColors: PresentationThemeGradientColors(topColor: p.borderStrong.ui, bottomColor: p.borderStrong.ui)
    )

    // Messages: your side in olive, theirs on the card colour with a hairline.
    func bubble(_ colors: PresentationThemeBubbleColor, fill: HouseColor, highlighted: HouseColor, stroke: UIColor) -> PresentationThemeBubbleColor {
        func components(_ value: PresentationThemeBubbleColorComponents) -> PresentationThemeBubbleColorComponents {
            return value.withUpdated(fill: [fill.ui], highlightedFill: highlighted.ui, stroke: stroke)
        }
        return colors.withUpdated(withWallpaper: components(colors.withWallpaper), withoutWallpaper: components(colors.withoutWallpaper))
    }
    let incoming = base.chat.message.incoming.withUpdated(
        bubble: bubble(base.chat.message.incoming.bubble, fill: p.surface, highlighted: pressedCard, stroke: p.border.ui),
        primaryTextColor: p.ink.ui,
        secondaryTextColor: rowSecondary.ui,
        linkTextColor: listAccent.ui,
        linkHighlightColor: p.olive.ui.withAlphaComponent(0.2),
        accentTextColor: listAccent.ui,
        accentControlColor: p.olive.ui,
        mediaActiveControlColor: p.olive.ui,
        mediaInactiveControlColor: p.olive.ui.withAlphaComponent(0.4),
        pendingActivityColor: rowSecondary.ui,
        fileTitleColor: listAccent.ui,
        fileDescriptionColor: rowSecondary.ui,
        fileDurationColor: rowSecondary.ui,
        textSelectionColor: p.olive.ui.withAlphaComponent(0.2),
        textSelectionKnobColor: p.olive.ui
    )
    let outgoing = base.chat.message.outgoing.withUpdated(
        bubble: bubble(base.chat.message.outgoing.bubble, fill: p.olive, highlighted: p.oliveDeep, stroke: .clear),
        primaryTextColor: p.onOlive.ui,
        // Times and file details in your bubble: 0.9 (was 0.7) keeps 4.5:1 on the accent and on its pressed shade.
        secondaryTextColor: p.onOlive.ui.withAlphaComponent(0.9),
        linkTextColor: p.onOlive.ui,
        linkHighlightColor: p.onOlive.ui.withAlphaComponent(0.25),
        accentTextColor: p.onOlive.ui,
        accentControlColor: p.onOlive.ui,
        mediaActiveControlColor: p.onOlive.ui,
        mediaInactiveControlColor: p.onOlive.ui.withAlphaComponent(0.4),
        pendingActivityColor: p.onOlive.ui.withAlphaComponent(0.9),
        fileTitleColor: p.onOlive.ui,
        fileDescriptionColor: p.onOlive.ui.withAlphaComponent(0.9),
        fileDurationColor: p.onOlive.ui.withAlphaComponent(0.9),
        textSelectionColor: p.onOlive.ui.withAlphaComponent(0.25),
        textSelectionKnobColor: p.onOlive.ui
    )
    let message = base.chat.message.withUpdated(
        incoming: incoming,
        outgoing: outgoing,
        infoLinkTextColor: p.olive.ui,
        outgoingCheckColor: p.onOlive.ui
    )

    let inputPanel = base.chat.inputPanel.withUpdated(
        panelBackgroundColor: p.surface.ui.withAlphaComponent(0.94),
        panelBackgroundColorNoWallpaper: p.bg.ui,
        panelSeparatorColor: p.border.ui,
        panelControlAccentColor: p.olive.ui,
        panelControlColor: p.ink3.ui,
        panelControlDisabledColor: p.ink3.ui.withAlphaComponent(0.5),
        panelControlDestructiveColor: p.statusError.ui,
        inputBackgroundColor: p.surface.ui,
        inputStrokeColor: p.border.ui,
        inputPlaceholderColor: p.ink3.ui,
        inputTextColor: p.ink.ui,
        inputControlColor: p.ink3.ui,
        actionControlFillColor: p.olive.ui,
        actionControlForegroundColor: p.onOlive.ui,
        primaryTextColor: p.ink.ui,
        secondaryTextColor: p.ink3.ui,
        mediaRecordingDotColor: p.statusError.ui
    )

    // The date pills and service lines: on a light page Telegram's translucent pill is too pale for its white text, so
    // the pill takes the theme's own secondary ink, dark enough for 4.5:1. A dark page keeps Telegram's pill.
    var serviceMessage = base.chat.serviceMessage
    if !base.overallDarkAppearance {
        let pill = harnessgramReadable(p.ink3, on: HouseColor(0xFFFFFF)).ui
        let components = serviceMessage.components.withDefaultWallpaper.withUpdated(fill: pill, primaryText: .white, dateFillStatic: pill, dateFillFloating: pill.withAlphaComponent(0.9))
        serviceMessage = PresentationThemeServiceMessage(components: serviceMessage.components.withUpdated(withDefaultWallpaper: components), unreadBarFillColor: serviceMessage.unreadBarFillColor, unreadBarStrokeColor: serviceMessage.unreadBarStrokeColor, unreadBarTextColor: serviceMessage.unreadBarTextColor, dateTextColor: serviceMessage.dateTextColor)
    }

    let chat = base.chat.withUpdated(defaultWallpaper: .color(p.bg.rgb), message: message, serviceMessage: serviceMessage, inputPanel: inputPanel)

    // Sheets, menus and the in-app notification banner.
    let actionSheet = base.actionSheet.withUpdated(
        opaqueItemBackgroundColor: p.surfaceRaised.ui,
        itemBackgroundColor: p.surfaceRaised.ui.withAlphaComponent(0.92),
        opaqueItemHighlightedBackgroundColor: pressedRaised.ui,
        itemHighlightedBackgroundColor: pressedRaised.ui.withAlphaComponent(0.92),
        opaqueItemSeparatorColor: p.border.ui,
        standardActionTextColor: harnessgramReadable(p.olive, on: pressedRaised).ui,
        destructiveActionTextColor: sheetDestructive.ui,
        disabledActionTextColor: p.ink3.ui.withAlphaComponent(0.6),
        primaryTextColor: p.ink.ui,
        secondaryTextColor: sheetSecondary.ui,
        controlAccentColor: p.olive.ui,
        inputBackgroundColor: p.border.ui,
        inputBorderColor: p.borderStrong.ui,
        inputPlaceholderColor: p.ink3.ui,
        inputTextColor: p.ink.ui,
        inputClearButtonColor: p.ink3.ui,
        checkContentColor: p.onOlive.ui
    )
    let contextMenu = base.contextMenu.withUpdated(
        backgroundColor: p.surfaceRaised.ui.withAlphaComponent(0.92),
        itemSeparatorColor: p.border.ui,
        sectionSeparatorColor: p.border.ui.withAlphaComponent(0.8),
        itemBackgroundColor: .clear,
        itemHighlightedBackgroundColor: pressedRaised.ui.withAlphaComponent(0.92),
        primaryColor: p.ink.ui,
        secondaryColor: sheetSecondary.ui,
        destructiveColor: sheetDestructive.ui
    )
    let inAppNotification = base.inAppNotification.withUpdated(fillColor: p.surfaceRaised.ui, primaryTextColor: p.ink.ui)

    return PresentationTheme(
        name: base.name,
        index: base.index,
        referenceTheme: base.referenceTheme,
        overallDarkAppearance: base.overallDarkAppearance,
        intro: base.intro,
        passcode: base.passcode,
        rootController: rootController,
        list: list,
        chatList: chatList,
        chat: chat,
        actionSheet: actionSheet,
        contextMenu: contextMenu,
        inAppNotification: inAppNotification,
        chart: base.chart,
        preview: base.preview
    )
}

// Built-in Harnessgram themes (build 22): "לילה בקוקפיט", "שחר על המסלול", "שמיים פתוחים", "מכשירים". Each is Telegram's
// Night or Day with the theme's accent and your-bubble colour (`customizePresentationTheme`, as the accent-colour
// picker does), then recoloured with its palette like the House colours. Telegram's own theme settings are never
// written, so "ללא" returns exactly to the owner's Telegram theme.

private let harnessgramThemeCacheLock = NSLock()
private var harnessgramThemeCache: [HarnessgramSettings.Theme: PresentationTheme] = [:]

/// The presentation theme of a built-in Harnessgram theme. Built once per theme and kept, so the presentation data
/// sees the same object while the choice stands.
public func makeHarnessgramThemePresentationTheme(_ theme: HarnessgramThemePalette) -> PresentationTheme {
    harnessgramThemeCacheLock.lock()
    if let cached = harnessgramThemeCache[theme.theme] {
        harnessgramThemeCacheLock.unlock()
        return cached
    }
    harnessgramThemeCacheLock.unlock()
    let p = theme.palette
    let base = makeDefaultPresentationTheme(reference: theme.dark ? .night : .day, serviceBackgroundColor: nil)
    let tinted = customizePresentationTheme(base, editing: true, accentColor: p.olive.ui, outgoingAccentColor: nil, backgroundColors: [], bubbleColors: [p.olive.rgb], animateBubbleColors: false, wallpaper: .color(p.bg.rgb))
    let result = makeHarnessgramPalettePresentationTheme(base: tinted, palette: p)
    harnessgramThemeCacheLock.lock()
    harnessgramThemeCache[theme.theme] = result
    harnessgramThemeCacheLock.unlock()
    return result
}

/// The theme the app should use: the chosen built-in Harnessgram theme (it wins over the House colours); otherwise
/// `base`'s House version while the House theme switch is on, `base` itself (the same object) while it is off.
public func harnessgramHouseResolvedTheme(_ base: PresentationTheme, settings: HarnessgramSettings = .shared) -> PresentationTheme {
    if let theme = HarnessgramThemePalettes.palette(settings.theme) {
        return makeHarnessgramThemePresentationTheme(theme)
    }
    guard settings.houseFeature(.theme) else {
        return base
    }
    return makeHousePresentationTheme(base: base)
}

/// The presentation data with the House theme and its page as the chat wallpaper (a wallpaper saved per theme
/// index would otherwise show Telegram's blue gradient); the same object when the House theme switch is off.
public func harnessgramHouseApply(_ presentationData: PresentationData, settings: HarnessgramSettings = .shared) -> PresentationData {
    let theme = harnessgramHouseResolvedTheme(presentationData.theme, settings: settings)
    if theme === presentationData.theme {
        return presentationData
    }
    return presentationData.withUpdated(theme: theme).withUpdated(chatWallpaper: theme.chat.defaultWallpaper)
}

/// The system appearance signal, re-emitted whenever the House theme switch or the Harnessgram theme changes, so the
/// presentation data is rebuilt at once (no restart).
public func harnessgramHouseRefreshing(_ style: Signal<WindowUserInterfaceStyle, NoError>) -> Signal<WindowUserInterfaceStyle, NoError> {
    return combineLatest(style, harnessgramHouseThemeSwitch())
    |> map { style, _ -> WindowUserInterfaceStyle in
        return style
    }
}

/// What the resolved theme depends on: the House switch and the chosen Harnessgram theme. Build 23: also the fonts and
/// the message text settings, so a font picked while the app runs rebuilds the presentation data at once (the screens
/// redraw with the family Display's `Font` helpers now hand out; HarnessgramSettingApply says what waits for a restart).
func harnessgramThemeSwitchKey(_ settings: HarnessgramSettings) -> String {
    return "\(settings.houseFeature(.theme))/\(settings.theme.rawValue)/\(settings.appFont.rawValue)/\(settings.messageFont.rawValue)/\(settings.fontWeight.rawValue)/\(settings.textSizeSteps)/\(settings.lineSpacing.rawValue)/\(settings.bubbleWidth.rawValue)/\(settings.justifiedText)"
}

private func harnessgramHouseThemeSwitch() -> Signal<String, NoError> {
    return Signal { subscriber in
        subscriber.putNext(harnessgramThemeSwitchKey(HarnessgramSettings.shared))
        let observer = NotificationCenter.default.addObserver(forName: HarnessgramSettings.didChangeNotification, object: nil, queue: .main, using: { _ in
            subscriber.putNext(harnessgramThemeSwitchKey(HarnessgramSettings.shared))
        })
        return ActionDisposable {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    |> distinctUntilChanged
}
