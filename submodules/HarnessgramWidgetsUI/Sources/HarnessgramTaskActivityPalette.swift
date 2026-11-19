import Foundation

/// One sRGB colour, 0...1 per channel. Plain numbers so the contrast rules are testable without SwiftUI.
public struct HarnessgramRGB: Equatable {
    public let red: Double
    public let green: Double
    public let blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xff) / 255.0, green: Double((hex >> 8) & 0xff) / 255.0, blue: Double(hex & 0xff) / 255.0)
    }

    /// This colour drawn at `alpha` over `background` (what the eye sees for a translucent fill).
    public func over(_ background: HarnessgramRGB, alpha: Double) -> HarnessgramRGB {
        let a = min(1.0, max(0.0, alpha))
        return HarnessgramRGB(
            red: self.red * a + background.red * (1.0 - a),
            green: self.green * a + background.green * (1.0 - a),
            blue: self.blue * a + background.blue * (1.0 - a)
        )
    }

    /// WCAG 2.x relative luminance.
    public var relativeLuminance: Double {
        func linear(_ channel: Double) -> Double {
            return channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(self.red) + 0.7152 * linear(self.green) + 0.0722 * linear(self.blue)
    }

    /// WCAG 2.x contrast ratio between two opaque colours (1...21).
    public static func contrastRatio(_ a: HarnessgramRGB, _ b: HarnessgramRGB) -> Double {
        let la = a.relativeLuminance
        let lb = b.relativeLuminance
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }
}

/// The task Live Activity's fixed colours. The Lock Screen uses system colours for its surface and the text on it;
/// these palettes still supply paired colours for the progress bar and readout. The Dynamic Island uses the standard
/// palette on black and the small supplemental family has its own day and night palettes.
public struct HarnessgramTaskActivityPalette: Equatable {
    /// The card (lock screen banner); the Dynamic Island is black and every colour below also passes on black.
    public let background: HarnessgramRGB
    /// Title, step line, percent when finished.
    public let primaryText: HarnessgramRGB
    /// Topic, current step name.
    public let secondaryText: HarnessgramRGB
    /// The percent, the ring and the current step.
    public let accent: HarnessgramRGB
    /// Finished: ring, bar, done steps.
    public let approve: HarnessgramRGB
    /// The bar's and ring's unfilled track and the steps still ahead (drawn as an opaque colour).
    public let track: HarnessgramRGB
    /// The card's decoration: the sky at the top (above `background`), the glass edge, and the glow on the horizon,
    /// which is also the "waits for you" signal (so it keeps AA like the text).
    public var sky: HarnessgramRGB = HarnessgramRGB(hex: 0x14232D)
    public var edge: HarnessgramRGB = HarnessgramRGB(hex: 0x9FE8D6)
    public var glow: HarnessgramRGB = HarnessgramRGB(hex: 0xFF9E4A)
    /// Opacity of the progress fill's tail (its head is opaque). The night cards keep their soft fade; the light ones
    /// fade less, so the whole fill keeps 3:1 against the light track while the brand colours stay as they are.
    public var fillTailOpacity: Double = 0.55

    /// The normal instruments and Dynamic Island: white text, a mint instrument accent and a runway-green "landed".
    public static let standard = HarnessgramTaskActivityPalette(
        background: HarnessgramRGB(hex: 0x0C161E),
        primaryText: HarnessgramRGB(hex: 0xFFFFFF),
        secondaryText: HarnessgramRGB(hex: 0xB3C3CC),
        accent: HarnessgramRGB(hex: 0x5EEAC4),
        approve: HarnessgramRGB(hex: 0x8EE68A),
        track: HarnessgramRGB(hex: 0x22343F)
    )

    /// The original day card colours, kept as a matching light palette and contrast reference.
    public static let standardLight = HarnessgramTaskActivityPalette(
        background: HarnessgramRGB(hex: 0xF2F8FB),
        primaryText: HarnessgramRGB(hex: 0x0C1A24),
        secondaryText: HarnessgramRGB(hex: 0x3B5160),
        accent: HarnessgramRGB(hex: 0x076656),
        approve: HarnessgramRGB(hex: 0x1D6A28),
        track: HarnessgramRGB(hex: 0xC9DCE6),
        sky: HarnessgramRGB(hex: 0xD7ECF8),
        edge: HarnessgramRGB(hex: 0x2E8C78),
        glow: HarnessgramRGB(hex: 0x974008),
        fillTailOpacity: 0.85
    )

    /// Always-On instruments: dimmer fills with the same contrast requirements.
    public static let reducedLuminance = HarnessgramTaskActivityPalette(
        background: HarnessgramRGB(hex: 0x070D12),
        primaryText: HarnessgramRGB(hex: 0xE2E9EE),
        secondaryText: HarnessgramRGB(hex: 0x9FB0BA),
        accent: HarnessgramRGB(hex: 0x4CC9A8),
        approve: HarnessgramRGB(hex: 0x77C474),
        track: HarnessgramRGB(hex: 0x1E2D37)
    )

    /// The card's decoration (never text): the glass edge and the sunset glow on the horizon behind the altimeter.
    public static let glassEdge = HarnessgramRGB(hex: 0x9FE8D6)
    public static let horizonGlow = HarnessgramRGB(hex: 0xFF9E4A)
    /// The sky at the top of the card, above `background`.
    public static let skyTop = HarnessgramRGB(hex: 0x14232D)

    /// The Dynamic Island is always drawn on black.
    public static let islandBackground = HarnessgramRGB(hex: 0x000000)

    /// The fixed palette for a self-contained instrument. The default uses the dark instrument face even on a light
    /// system surface. Reduced luminance dims the instrument independently of its surroundings.
    public static func palette(luminanceReduced: Bool, dark: Bool = true) -> HarnessgramTaskActivityPalette {
        if luminanceReduced {
            return .reducedLuminance
        }
        return dark ? .standard : .standardLight
    }

    // MARK: The small supplemental family (CarPlay dashboard, Apple Watch Smart Stack)

    /// Small family, light appearance: the system's light material tile (like the CarPlay widgets around it), so
    /// dark text. `background` is the darkest light tile it is checked against (systemGray5); white is checked too.
    public static let smallLight = HarnessgramTaskActivityPalette(
        background: HarnessgramRGB(hex: 0xE5E5EA),
        primaryText: HarnessgramRGB(hex: 0x111318),
        secondaryText: HarnessgramRGB(hex: 0x484E5C),
        accent: HarnessgramRGB(hex: 0x0B6E57),
        approve: HarnessgramRGB(hex: 0x116B3A),
        track: HarnessgramRGB(hex: 0xBFC5D2),
        fillTailOpacity: 0.9
    )

    /// Small family, dark appearance: the system's dark tile. `background` is the lightest dark tile it is checked
    /// against (systemGray5 dark); black is checked too.
    public static let smallDark = HarnessgramTaskActivityPalette(
        background: HarnessgramRGB(hex: 0x2C2C2E),
        primaryText: HarnessgramRGB(hex: 0xFFFFFF),
        secondaryText: HarnessgramRGB(hex: 0xC3CAD6),
        accent: HarnessgramRGB(hex: 0x5EEAC4),
        approve: HarnessgramRGB(hex: 0x8EE68A),
        track: HarnessgramRGB(hex: 0x55596A)
    )

    /// The other end of each small-tile range: white behind the light tile, black behind the dark one.
    public static func smallAlternateBackground(dark: Bool) -> HarnessgramRGB {
        return dark ? HarnessgramRGB(hex: 0x000000) : HarnessgramRGB(hex: 0xFFFFFF)
    }

    public static func small(dark: Bool) -> HarnessgramTaskActivityPalette {
        return dark ? .smallDark : .smallLight
    }

    /// Every text colour with its role, for the contrast rule.
    public var textColors: [(String, HarnessgramRGB)] {
        return [
            ("primaryText", self.primaryText),
            ("secondaryText", self.secondaryText),
            ("accent", self.accent),
            ("approve", self.approve),
        ]
    }
}
