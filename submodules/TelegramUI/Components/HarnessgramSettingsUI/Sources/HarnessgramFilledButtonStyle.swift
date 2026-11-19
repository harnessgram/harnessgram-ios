import Foundation
import SwiftUI

/// The house filled button's colours as plain sRGB hex numbers, so the contrast rule is unit tested without SwiftUI.
/// Every fill keeps a white label at WCAG AA (4.5:1) or better: normal, pressed and disabled.
public enum HarnessgramFilledButtonPalette {
    public enum Role: CaseIterable {
        /// The main action: deep runway mint (the house mint, darkened until white text passes AA).
        case primary
        /// A warning action (restart the app): deep amber.
        case warning
    }

    /// The label and the icon, in every state.
    public static let label: UInt32 = 0xFFFFFF
    public static let primaryFill: UInt32 = 0x0B6E57
    public static let primaryPressedFill: UInt32 = 0x08594A
    public static let warningFill: UInt32 = 0xA84300
    public static let warningPressedFill: UInt32 = 0x8A3700
    /// Disabled (and busy): a dimmed slate fill; the label stays white and readable.
    public static let disabledFill: UInt32 = 0x4A5A63

    public static func fill(_ role: Role, pressed: Bool, enabled: Bool) -> UInt32 {
        guard enabled else {
            return HarnessgramFilledButtonPalette.disabledFill
        }
        switch role {
        case .primary:
            return pressed ? HarnessgramFilledButtonPalette.primaryPressedFill : HarnessgramFilledButtonPalette.primaryFill
        case .warning:
            return pressed ? HarnessgramFilledButtonPalette.warningPressedFill : HarnessgramFilledButtonPalette.warningFill
        }
    }

    /// Every fill the button can show, for the contrast rule.
    public static var allFills: [UInt32] {
        var out: [UInt32] = [HarnessgramFilledButtonPalette.disabledFill]
        for role in Role.allCases {
            out.append(HarnessgramFilledButtonPalette.fill(role, pressed: false, enabled: true))
            out.append(HarnessgramFilledButtonPalette.fill(role, pressed: true, enabled: true))
        }
        return out
    }
}

extension Color {
    /// An opaque sRGB colour from 0xRRGGBB.
    init(harnessgramHex hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xff) / 255.0, green: Double((hex >> 8) & 0xff) / 255.0, blue: Double(hex & 0xff) / 255.0, opacity: 1.0)
    }
}

/// The one filled button of the Harnessgram screens. It draws its own fill and paints the label and icon white, so a
/// List or Form row cannot tint them with the theme's accent (the build 23 report: a light-blue label and a blue
/// airplane on the system bordered-prominent blue fill). Disabled is a dimmed fill with the same white label; `busy` adds a
/// spinner before the label (for "opening..." states). The system bordered-prominent style is not used in the Harnessgram UI
/// modules; a source check (`NoBorderedProminentTest`) keeps it that way.
public struct HarnessgramFilledButtonStyle: ButtonStyle {
    public var role: HarnessgramFilledButtonPalette.Role
    public var busy: Bool

    public init(role: HarnessgramFilledButtonPalette.Role = .primary, busy: Bool = false) {
        self.role = role
        self.busy = busy
    }

    public func makeBody(configuration: Configuration) -> some View {
        HarnessgramFilledButtonBody(configuration: configuration, role: self.role, busy: self.busy)
    }
}

private struct HarnessgramFilledButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let role: HarnessgramFilledButtonPalette.Role
    let busy: Bool
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.harnessgramMinimumTapHeight) private var minimumTapHeight

    var body: some View {
        let label = Color(harnessgramHex: HarnessgramFilledButtonPalette.label)
        let fill = Color(harnessgramHex: HarnessgramFilledButtonPalette.fill(self.role, pressed: self.configuration.isPressed, enabled: self.isEnabled && !self.busy))
        let shape = RoundedRectangle(cornerRadius: 12.0, style: .continuous)
        HStack(spacing: 8.0) {
            if self.busy {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(label)
                    .accessibilityHidden(true)
            }
            self.configuration.label
        }
        .foregroundColor(label)
        .tint(label)
        .padding(.horizontal, 14.0)
        .padding(.vertical, 8.0)
        .frame(minHeight: max(40.0, self.minimumTapHeight))
        .background(shape.fill(fill))
        .contentShape(shape)
    }
}

extension ButtonStyle where Self == HarnessgramFilledButtonStyle {
    /// The house filled button (primary role).
    public static var harnessgramFilled: HarnessgramFilledButtonStyle {
        return HarnessgramFilledButtonStyle()
    }

    public static func harnessgramFilled(role: HarnessgramFilledButtonPalette.Role = .primary, busy: Bool = false) -> HarnessgramFilledButtonStyle {
        return HarnessgramFilledButtonStyle(role: role, busy: busy)
    }
}

private struct HarnessgramMinimumTapHeightKey: EnvironmentKey {
    static let defaultValue: CGFloat = 40.0
}

extension EnvironmentValues {
    /// The smallest height of the house buttons below this point (40 by default; the phone tower asks for 44, the
    /// recommended touch target). The decision rows also make their bordered buttons large from 44 on.
    public var harnessgramMinimumTapHeight: CGFloat {
        get { self[HarnessgramMinimumTapHeightKey.self] }
        set { self[HarnessgramMinimumTapHeightKey.self] = newValue }
    }
}
