import Foundation

/// One colour: 0xRRGGBB and an alpha.
public struct HouseColor: Equatable, Sendable {
    public let rgb: UInt32
    public let alpha: Double

    public init(_ rgb: UInt32, alpha: Double = 1.0) {
        self.rgb = rgb
        self.alpha = alpha
    }
}

/// The House colours (brand kit and tokens.json, "color.light" and "color.dark"), as plain values so the app's
/// presentation theme, the widgets and the tests all read one table. HarnessgramHouseKit wraps them in UIColor and
/// SwiftUI Color; a test holds this table equal to tokens.json.
public struct HousePalette: Equatable, Sendable {
    public let bg: HouseColor
    public let surface: HouseColor
    public let surfaceRaised: HouseColor
    public let border: HouseColor
    public let borderStrong: HouseColor
    public let ink: HouseColor
    public let ink2: HouseColor
    public let ink3: HouseColor
    public let cedar: HouseColor
    public let cedarDeep: HouseColor
    public let brass: HouseColor
    public let amber: HouseColor
    public let amberGlow: HouseColor
    public let amberDeep: HouseColor
    public let olive: HouseColor
    public let oliveDeep: HouseColor
    public let onOlive: HouseColor
    public let statusWorking: HouseColor
    public let statusIdle: HouseColor
    public let statusWaiting: HouseColor
    public let statusError: HouseColor
    public let scrim: HouseColor
    /// Text on the count badge (tokens.json: white on the stone theme, #14110E at night).
    public let onAmberDeep: HouseColor
}

public enum HouseColors {
    public static let light = HousePalette(
        bg: HouseColor(0xF4EDE2),
        surface: HouseColor(0xFBF7F0),
        surfaceRaised: HouseColor(0xFFFDF9),
        border: HouseColor(0xE3D6C2),
        borderStrong: HouseColor(0xCDBA9C),
        ink: HouseColor(0x2A2118),
        ink2: HouseColor(0x5E4F3E),
        ink3: HouseColor(0x74644F),
        cedar: HouseColor(0x7A4E2D),
        cedarDeep: HouseColor(0x56361F),
        brass: HouseColor(0xB08A3E),
        amber: HouseColor(0xE9A23B),
        amberGlow: HouseColor(0xF6C76A),
        amberDeep: HouseColor(0xA85A1A),
        olive: HouseColor(0x55683A),
        oliveDeep: HouseColor(0x3F4F2A),
        onOlive: HouseColor(0xFBF7F0),
        statusWorking: HouseColor(0x5FA83A),
        statusIdle: HouseColor(0xB9AE9C),
        statusWaiting: HouseColor(0xE9A23B),
        statusError: HouseColor(0xB5452F),
        scrim: HouseColor(0x2A2118, alpha: 0.45),
        onAmberDeep: HouseColor(0xFFFFFF)
    )

    public static let dark = HousePalette(
        bg: HouseColor(0x14110E),
        surface: HouseColor(0x1F1A15),
        surfaceRaised: HouseColor(0x28221B),
        border: HouseColor(0x3A3128),
        borderStrong: HouseColor(0x56493B),
        ink: HouseColor(0xF3EADB),
        ink2: HouseColor(0xC7B8A2),
        ink3: HouseColor(0x968670),
        cedar: HouseColor(0x8A5A36),
        cedarDeep: HouseColor(0x5E3B22),
        brass: HouseColor(0xC9A257),
        amber: HouseColor(0xF2B24C),
        amberGlow: HouseColor(0xFFD27A),
        amberDeep: HouseColor(0xD07A2A),
        olive: HouseColor(0x8FA866),
        oliveDeep: HouseColor(0x768D50),
        onOlive: HouseColor(0x14110E),
        statusWorking: HouseColor(0x7CC653),
        statusIdle: HouseColor(0x6E6355),
        statusWaiting: HouseColor(0xF2B24C),
        statusError: HouseColor(0xD9654B),
        scrim: HouseColor(0x000000, alpha: 0.6),
        onAmberDeep: HouseColor(0x14110E)
    )

    public static func palette(darkAppearance: Bool) -> HousePalette {
        return darkAppearance ? HouseColors.dark : HouseColors.light
    }

    /// Lock screen, Live Activity, Dynamic Island and CarPlay: dark glass whatever the theme (tokens.json "liveSurfaces").
    public enum LiveSurfaces {
        public static let glass = HouseColor(0x1F1A15, alpha: 0.78)
        public static let progress = HouseColor(0xF2B24C)
        public static let done = HouseColor(0x8FA866)
        public static let track = HouseColor(0xF3EADB, alpha: 0.18)
        public static let text = HouseColor(0xF3EADB)
    }
}
