import Foundation
import UIKit
import SwiftUI
import HarnessgramHouseCore

extension HouseColor {
    public var uiColor: UIColor {
        return UIColor(red: CGFloat((self.rgb >> 16) & 0xff) / 255.0, green: CGFloat((self.rgb >> 8) & 0xff) / 255.0, blue: CGFloat(self.rgb & 0xff) / 255.0, alpha: CGFloat(self.alpha))
    }

    public var color: Color {
        return Color(self.uiColor)
    }
}

/// The House tokens (tokens.json), written by hand: a test reads a copy of tokens.json and compares every value, so
/// drift fails the build. Colours are in HarnessgramHouseCore (`HouseColors`) so the presentation theme and the widgets
/// share one table. Values are in points.
public enum HouseTokens {
    public static func colors(darkAppearance: Bool) -> HousePalette {
        return HouseColors.palette(darkAppearance: darkAppearance)
    }

    public enum Space {
        public static let base: CGFloat = 4.0
        public static let xs: CGFloat = 4.0
        public static let sm: CGFloat = 8.0
        public static let md: CGFloat = 12.0
        public static let lg: CGFloat = 16.0
        public static let xl: CGFloat = 20.0
        public static let xxl: CGFloat = 24.0
        public static let xxxl: CGFloat = 32.0
        public static let gutterPhone: CGFloat = 16.0
        public static let gutterTablet: CGFloat = 24.0
        public static let cardPadding: CGFloat = 14.0
        public static let cardGap: CGFloat = 12.0
        public static let sectionGap: CGFloat = 24.0
        public static let radioBarInset: CGFloat = 12.0
        public static let minTapTarget: CGFloat = 44.0
        /// The radio bar floats this far above the tab bar (brand kit, "Spacing and layout").
        public static let radioBarAboveTabBar: CGFloat = 8.0
    }

    public enum Radius {
        public static let card: CGFloat = 20.0
        public static let roomArt: CGFloat = 16.0
        public static let button: CGFloat = 14.0
        public static let chip: CGFloat = 999.0
        public static let sheetTop: CGFloat = 28.0
        public static let radioBar: CGFloat = 22.0
        /// The knock sheet's arched top rises this much (a shallow arch).
        public static let knockArchRise: CGFloat = 24.0
        /// The window opening is 0.75 wide for 1 high.
        public static let windowAspect: CGFloat = 0.75
    }

    /// Durations in seconds. With Reduce Motion every movement becomes `reduceMotionFade`.
    public enum Motion {
        public static let reduceMotionFade: Double = 0.150
        public static let windowLightOn: Double = 0.400
        public static let windowLightOff: Double = 0.600
        public static let enterRoom: Double = 0.350
        public static let enterRoomDamping: Double = 0.85
        public static let knock: Double = 0.320
        public static let knockDamping: Double = 0.8
        public static let badgePulse: Double = 1.200
        public static let badgePulseCycles: Int = 3
        public static let radioWave: Double = 0.900
        public static let progressFill: Double = 0.500
    }
}
