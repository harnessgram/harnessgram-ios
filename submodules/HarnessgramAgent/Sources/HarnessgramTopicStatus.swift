import Foundation

/// A session topic's state, read from the icon the bridge puts in front of the topic name.
///
/// The bridge integration contract (docs/harnessgram-local-config.md) names a topic `icon + " " + name`, with
/// "⚙️" busy, "❓" waiting for the owner and "✅" done, and no icon for any other state. A title
/// without one of these leading icons has no state: no dot.
public enum HarnessgramTopicStatus: String, CaseIterable, Sendable {
    case working
    case waitingForYou
    case done

    /// The dot's colour (0xRRGGBB), the same in light and dark themes: blue busy, orange waiting, green done.
    public var rgb: UInt32 {
        switch self {
        case .working:
            return 0x0A84FF
        case .waitingForYou:
            return 0xFF9F0A
        case .done:
            return 0x30D158
        }
    }

    /// The House palette's dot colours (0xRRGGBB): the working green, the waiting amber and, for done, the olive of
    /// the primary buttons, in the stone theme and in the night theme. HarnessgramHouseCore's tests hold these equal
    /// to tokens.json's statusWorking, statusWaiting and olive.
    public func rgb(house: Bool, darkAppearance: Bool) -> UInt32 {
        guard house else {
            return self.rgb
        }
        switch self {
        case .working:
            return darkAppearance ? 0x7CC653 : 0x5FA83A
        case .waitingForYou:
            return darkAppearance ? 0xF2B24C : 0xE9A23B
        case .done:
            return darkAppearance ? 0x8FA866 : 0x55683A
        }
    }

    /// The icon scalar the bridge uses for this state (its emoji variation selector is optional).
    var iconScalar: Unicode.Scalar {
        switch self {
        case .working:
            return "\u{2699}"
        case .waitingForYou:
            return "\u{2753}"
        case .done:
            return "\u{2705}"
        }
    }

    /// The state a topic title announces, or nil. Leading spaces and bidi marks are skipped; the icon must
    /// be followed by the end of the title or a space ("✅x" is someone's own name, not a state).
    public static func from(title: String) -> HarnessgramTopicStatus? {
        var scalars = title.unicodeScalars[...]
        while let first = scalars.first, first.properties.isWhitespace || HarnessgramTopicStatus.bidiMarks.contains(first.value) {
            scalars = scalars.dropFirst()
        }
        guard let icon = scalars.first, let status = HarnessgramTopicStatus.allCases.first(where: { $0.iconScalar == icon }) else {
            return nil
        }
        scalars = scalars.dropFirst()
        if scalars.first?.value == 0xFE0F {
            scalars = scalars.dropFirst()
        }
        if let next = scalars.first, !next.properties.isWhitespace {
            return nil
        }
        return status
    }

    /// LRM, RLM, ALM, LRE...RLO, LRI...PDI.
    private static let bidiMarks: Set<UInt32> = [0x200E, 0x200F, 0x061C, 0x202A, 0x202B, 0x202C, 0x202D, 0x202E, 0x2066, 0x2067, 0x2068, 0x2069]

    /// The dot drawn in front of the title, with a thin space after it.
    public static let dotText = "\u{25CF}\u{2009}"
}
