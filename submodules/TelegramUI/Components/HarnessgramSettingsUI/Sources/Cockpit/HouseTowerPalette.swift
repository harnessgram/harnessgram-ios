import Foundation
import UIKit
import SwiftUI

/// The Cockpit tower's colours, one place for both appearances (owner, build 31: "everything should support light
/// mode too"). Dark is the tower at night, exactly as before (the lock screen pack's flight deck colours); light is the
/// day sky with dark text. Every text colour keeps WCAG AA (4.5:1) on the page and on the cards in both
/// (HouseTowerPaletteTests). The views never name a colour of their own (TowerPaletteOnlyTest).
enum HouseTowerPalette {
    /// One colour as plain sRGB numbers per appearance, so the contrast rule is tested without SwiftUI.
    struct Tone: Equatable {
        let light: UInt32
        let dark: UInt32

        var color: Color {
            return Color(uiColor: self.uiColor)
        }

        /// Resolves with the view's appearance (the screen's interface style, set from the Telegram theme).
        var uiColor: UIColor {
            let light = self.light
            let dark = self.dark
            return UIColor { traits in
                return HouseTowerPalette.Tone.uiColor(traits.userInterfaceStyle == .dark ? dark : light)
            }
        }

        static func uiColor(_ hex: UInt32) -> UIColor {
            return UIColor(red: CGFloat((hex >> 16) & 0xff) / 255.0, green: CGFloat((hex >> 8) & 0xff) / 255.0, blue: CGFloat(hex & 0xff) / 255.0, alpha: 1.0)
        }
    }

    enum Tones {
        /// The page (and the lower half of each card).
        static let background = Tone(light: 0xF2F8FB, dark: 0x0C161E)
        /// The sky at the top of the page and of each card.
        static let skyTop = Tone(light: 0xD7ECF8, dark: 0x14232D)
        static let primaryText = Tone(light: 0x0C1A24, dark: 0xFFFFFF)
        static let secondaryText = Tone(light: 0x3B5160, dark: 0xB3C3CC)
        /// The instrument mint (text, icons, bars, the selected card's edge).
        static let accent = Tone(light: 0x076656, dark: 0x5EEAC4)
        /// Landed.
        static let approve = Tone(light: 0x1D6A28, dark: 0x8EE68A)
        /// The unfilled part of bars and dials.
        static let track = Tone(light: 0xC9DCE6, dark: 0x22343F)
        /// The cards' hairline edge.
        static let glassEdge = Tone(light: 0x2E8C78, dark: 0x9FE8D6)
        /// The glow on the horizon (sunset at night, sun at day); also the "waits for you" signal, so it is text-safe.
        static let horizonGlow = Tone(light: 0x974008, dark: 0xFF9E4A)
        /// The tower's steel, top and foot of its gradient.
        static let towerSteelTop = Tone(light: 0xB8C9D4, dark: 0x3A4E5C)
        static let towerSteelBottom = Tone(light: 0x7C95A5, dark: 0x1B2A35)
        /// The cab's window band: lit amber at night, the sky's reflection by day.
        static let cabWindow = Tone(light: 0x7FC0E8, dark: 0xFFD08A)
        /// The runway's edge lights (and the altimeter's warm marks): readable on the day sky too.
        static let runwayLight = Tone(light: 0xA2650C, dark: 0xFFD08A)
        static let runwayAmber = Tone(light: 0x9C5F0A, dark: 0xE0A43A)

        /// Every text colour with the backgrounds it is drawn on, for the contrast rule.
        static let textColors: [(String, Tone)] = [("primaryText", primaryText), ("secondaryText", secondaryText), ("accent", accent), ("approve", approve), ("horizonGlow", horizonGlow)]
        static let textBackgrounds: [(String, Tone)] = [("background", background), ("skyTop", skyTop)]
    }

    static let background = Tones.background.color
    /// The same page colour for UIKit (behind the phone tower, under the status bar and the tab bar); dynamic.
    static let backgroundUIColor = Tones.background.uiColor
    static let skyTop = Tones.skyTop.color
    static let primaryText = Tones.primaryText.color
    static let secondaryText = Tones.secondaryText.color
    static let accent = Tones.accent.color
    static let approve = Tones.approve.color
    static let track = Tones.track.color
    static let glassEdge = Tones.glassEdge.color
    static let horizonGlow = Tones.horizonGlow.color
    static let towerSteelTop = Tones.towerSteelTop.color
    static let towerSteelBottom = Tones.towerSteelBottom.color
    static let cabWindow = Tones.cabWindow.color
    static let runwayLight = Tones.runwayLight.color
    static let runwayAmber = Tones.runwayAmber.color
}
