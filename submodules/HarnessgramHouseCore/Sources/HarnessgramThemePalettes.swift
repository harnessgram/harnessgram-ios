import Foundation
import HarnessgramSettings

/// The built-in Harnessgram themes' colours (build 22), as House palettes: the presentation theme maps the same roles
/// as the House colours (page, card, ink, accent = `olive`, count badge = `amberDeep`), so one recolour serves both.
/// Plain values so the tests hold every text pair to WCAG AA without the app.
public struct HarnessgramThemePalette: Equatable, Sendable {
    public let theme: HarnessgramSettings.Theme
    /// Built on Telegram's Night (true) or Day (false).
    public let dark: Bool
    public let palette: HousePalette

    /// The text pairs the theme draws: (role, text, background). Every one must keep 4.5:1.
    public var textPairs: [(String, HouseColor, HouseColor)] {
        let p = self.palette
        var pairs: [(String, HouseColor, HouseColor)] = []
        for (name, background) in [("page", p.bg), ("card", p.surface), ("raised", p.surfaceRaised)] {
            pairs.append(("ink on \(name)", p.ink, background))
            pairs.append(("ink2 on \(name)", p.ink2, background))
            pairs.append(("ink3 on \(name)", p.ink3, background))
            pairs.append(("accent on \(name)", p.olive, background))
            pairs.append(("error on \(name)", p.statusError, background))
        }
        pairs.append(("text in your bubble", p.onOlive, p.olive))
        pairs.append(("text in a highlighted bubble of yours", p.onOlive, p.oliveDeep))
        pairs.append(("text in their bubble", p.ink, p.surface))
        pairs.append(("count badge", p.onAmberDeep, p.amberDeep))
        return pairs
    }
}

public enum HarnessgramThemePalettes {
    public static let cockpitNight = HarnessgramThemePalette(theme: .cockpitNight, dark: true, palette: HousePalette(
        bg: HouseColor(0x0B1424),
        surface: HouseColor(0x13203A),
        surfaceRaised: HouseColor(0x1A2A48),
        border: HouseColor(0x25365A),
        borderStrong: HouseColor(0x3A4E78),
        ink: HouseColor(0xEEF2FA),
        ink2: HouseColor(0xC3CDE0),
        ink3: HouseColor(0x9AA7C0),
        cedar: HouseColor(0x8A5A36),
        cedarDeep: HouseColor(0x5E3B22),
        brass: HouseColor(0xC9A257),
        amber: HouseColor(0xF5B544),
        amberGlow: HouseColor(0xFFD27A),
        amberDeep: HouseColor(0xF0A93A),
        olive: HouseColor(0xF5B544),
        oliveDeep: HouseColor(0xE09E2E),
        onOlive: HouseColor(0x0B1424),
        statusWorking: HouseColor(0x6CCB8A),
        statusIdle: HouseColor(0x4A5878),
        statusWaiting: HouseColor(0xF5B544),
        statusError: HouseColor(0xFF8A7A),
        scrim: HouseColor(0x000000, alpha: 0.6),
        onAmberDeep: HouseColor(0x0B1424)
    ))

    public static let runwayDawn = HarnessgramThemePalette(theme: .runwayDawn, dark: false, palette: HousePalette(
        bg: HouseColor(0xFFF6EC),
        surface: HouseColor(0xFFFDF8),
        surfaceRaised: HouseColor(0xFFFFFF),
        border: HouseColor(0xF1DEC8),
        borderStrong: HouseColor(0xE0C3A0),
        ink: HouseColor(0x2B1D12),
        ink2: HouseColor(0x5C4433),
        ink3: HouseColor(0x765A44),
        cedar: HouseColor(0x7A4E2D),
        cedarDeep: HouseColor(0x56361F),
        brass: HouseColor(0xB08A3E),
        amber: HouseColor(0xF59E0B),
        amberGlow: HouseColor(0xFCD34D),
        amberDeep: HouseColor(0xB93C0B),
        olive: HouseColor(0xB93C0B),
        oliveDeep: HouseColor(0x9A3209),
        onOlive: HouseColor(0xFFFFFF),
        statusWorking: HouseColor(0x2F855A),
        statusIdle: HouseColor(0xC9B8A6),
        statusWaiting: HouseColor(0xF59E0B),
        statusError: HouseColor(0xB42318),
        scrim: HouseColor(0x2B1D12, alpha: 0.45),
        onAmberDeep: HouseColor(0xFFFFFF)
    ))

    public static let openSky = HarnessgramThemePalette(theme: .openSky, dark: false, palette: HousePalette(
        bg: HouseColor(0xF2F8FD),
        surface: HouseColor(0xFFFFFF),
        surfaceRaised: HouseColor(0xFFFFFF),
        border: HouseColor(0xD6E6F3),
        borderStrong: HouseColor(0xB5CFE6),
        ink: HouseColor(0x0F2235),
        ink2: HouseColor(0x36506A),
        ink3: HouseColor(0x4F6680),
        cedar: HouseColor(0x7A4E2D),
        cedarDeep: HouseColor(0x56361F),
        brass: HouseColor(0xB08A3E),
        amber: HouseColor(0xF5B544),
        amberGlow: HouseColor(0xFFD27A),
        amberDeep: HouseColor(0x0A65AE),
        olive: HouseColor(0x0A65AE),
        oliveDeep: HouseColor(0x08528D),
        onOlive: HouseColor(0xFFFFFF),
        statusWorking: HouseColor(0x2F855A),
        statusIdle: HouseColor(0xB5C4D3),
        statusWaiting: HouseColor(0xE9A23B),
        statusError: HouseColor(0xC0362C),
        scrim: HouseColor(0x0F2235, alpha: 0.45),
        onAmberDeep: HouseColor(0xFFFFFF)
    ))

    public static let instruments = HarnessgramThemePalette(theme: .instruments, dark: true, palette: HousePalette(
        bg: HouseColor(0x070D0A),
        surface: HouseColor(0x0F1914),
        surfaceRaised: HouseColor(0x15231C),
        border: HouseColor(0x1F3329),
        borderStrong: HouseColor(0x2F4A3C),
        ink: HouseColor(0xE6F5EC),
        ink2: HouseColor(0xB5CFC0),
        ink3: HouseColor(0x8AA798),
        cedar: HouseColor(0x8A5A36),
        cedarDeep: HouseColor(0x5E3B22),
        brass: HouseColor(0xC9A257),
        amber: HouseColor(0xF2B24C),
        amberGlow: HouseColor(0xFFD27A),
        amberDeep: HouseColor(0x4ADE80),
        olive: HouseColor(0x4ADE80),
        oliveDeep: HouseColor(0x34C76A),
        onOlive: HouseColor(0x04210F),
        statusWorking: HouseColor(0x4ADE80),
        statusIdle: HouseColor(0x3A5446),
        statusWaiting: HouseColor(0xF2B24C),
        statusError: HouseColor(0xFF8A7A),
        scrim: HouseColor(0x000000, alpha: 0.6),
        onAmberDeep: HouseColor(0x04210F)
    ))

    /// Every built-in theme, in the picker's order.
    public static let all: [HarnessgramThemePalette] = [cockpitNight, runwayDawn, openSky, instruments]

    /// The palette for a theme; nil for `none` (the owner's Telegram theme).
    public static func palette(_ theme: HarnessgramSettings.Theme) -> HarnessgramThemePalette? {
        switch theme {
        case .none:
            return nil
        case .cockpitNight:
            return cockpitNight
        case .runwayDawn:
            return runwayDawn
        case .openSky:
            return openSky
        case .instruments:
            return instruments
        }
    }
}

extension HouseColor {
    /// WCAG 2.x relative luminance (alpha ignored: every theme colour that carries text is opaque).
    public var relativeLuminance: Double {
        func linear(_ value: UInt32) -> Double {
            let channel = Double(value & 0xff) / 255.0
            return channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(self.rgb >> 16) + 0.7152 * linear(self.rgb >> 8) + 0.0722 * linear(self.rgb)
    }

    /// WCAG 2.x contrast ratio (1...21).
    public static func contrastRatio(_ a: HouseColor, _ b: HouseColor) -> Double {
        let la = a.relativeLuminance
        let lb = b.relativeLuminance
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }
}
