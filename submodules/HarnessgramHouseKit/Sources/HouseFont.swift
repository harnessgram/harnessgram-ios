import Foundation
import UIKit
import SwiftUI
import CoreText
import HarnessgramFonts
import HarnessgramSettings

/// The House type scale (brand kit, "Typography"). All four families ship with the app (HarnessgramFonts).
public enum HouseTextStyle: String, CaseIterable, Sendable {
    case display
    case title1
    case title2
    case title3
    case headline
    case body
    case reading
    case callout
    case button
    case caption
    case badge
}

public enum HouseFontFamily: String, Sendable {
    /// Frank Ruhl Libre, the serif.
    case display
    /// Assistant.
    case body
    /// Heebo.
    case ui
    /// Rubik, with tabular figures.
    case numeric

    var messageFont: HarnessgramSettings.MessageFont {
        switch self {
        case .display:
            return .frankRuhlLibre
        case .body:
            return .assistant
        case .ui:
            return .heebo
        case .numeric:
            return .rubik
        }
    }

    public var familyName: String {
        switch self {
        case .display:
            return "Frank Ruhl Libre"
        case .body:
            return "Assistant"
        case .ui:
            return "Heebo"
        case .numeric:
            return "Rubik"
        }
    }
}

public struct HouseFontSpec: Equatable, Sendable {
    public let family: HouseFontFamily
    public let size: CGFloat
    public let weight: CGFloat
    public let lineHeight: CGFloat
    /// Times and counts keep every digit the same width.
    public let tabularFigures: Bool
}

public enum HouseFont {
    public static func spec(_ style: HouseTextStyle) -> HouseFontSpec {
        switch style {
        case .display:
            return HouseFontSpec(family: .display, size: 34.0, weight: 700.0, lineHeight: 40.0, tabularFigures: false)
        case .title1:
            return HouseFontSpec(family: .display, size: 28.0, weight: 700.0, lineHeight: 34.0, tabularFigures: false)
        case .title2:
            return HouseFontSpec(family: .display, size: 22.0, weight: 700.0, lineHeight: 28.0, tabularFigures: false)
        case .title3:
            return HouseFontSpec(family: .display, size: 20.0, weight: 500.0, lineHeight: 26.0, tabularFigures: false)
        case .headline:
            return HouseFontSpec(family: .body, size: 17.0, weight: 700.0, lineHeight: 24.0, tabularFigures: false)
        case .body:
            return HouseFontSpec(family: .body, size: 17.0, weight: 400.0, lineHeight: 26.0, tabularFigures: false)
        case .reading:
            return HouseFontSpec(family: .body, size: 18.0, weight: 400.0, lineHeight: 30.0, tabularFigures: false)
        case .callout:
            return HouseFontSpec(family: .body, size: 15.0, weight: 600.0, lineHeight: 22.0, tabularFigures: false)
        case .button:
            return HouseFontSpec(family: .ui, size: 17.0, weight: 600.0, lineHeight: 22.0, tabularFigures: false)
        case .caption:
            return HouseFontSpec(family: .numeric, size: 13.0, weight: 500.0, lineHeight: 18.0, tabularFigures: true)
        case .badge:
            return HouseFontSpec(family: .numeric, size: 15.0, weight: 700.0, lineHeight: 18.0, tabularFigures: true)
        }
    }

    /// The system text style each House style scales with (Dynamic Type): display to largeTitle, title1..3 to
    /// title1..3, headline to headline, body and reading to body, callout to callout, button to body, caption and
    /// badge to caption1.
    public static func textStyle(_ style: HouseTextStyle) -> UIFont.TextStyle {
        switch style {
        case .display:
            return .largeTitle
        case .title1:
            return .title1
        case .title2:
            return .title2
        case .title3:
            return .title3
        case .headline:
            return .headline
        case .body, .reading, .button:
            return .body
        case .callout:
            return .callout
        case .caption, .badge:
            return .caption1
        }
    }

    /// The font at the design's size, before Dynamic Type.
    public static func baseFont(_ style: HouseTextStyle) -> UIFont {
        let spec = HouseFont.spec(style)
        let font = HarnessgramFonts.font(spec.family.messageFont, weight: spec.weight, size: spec.size)
        guard spec.tabularFigures else {
            return font
        }
        let features: [[UIFontDescriptor.FeatureKey: Int]] = [[
            .type: kNumberSpacingType,
            .selector: kMonospacedNumbersSelector,
        ]]
        return UIFont(descriptor: font.fontDescriptor.addingAttributes([.featureSettings: features]), size: spec.size)
    }

    /// The scaled font through `UIFontMetrics`: it follows the user's text size (and Larger Accessibility Sizes) for the
    /// given traits, the current ones when nil.
    public static func font(_ style: HouseTextStyle, compatibleWith traits: UITraitCollection? = nil) -> UIFont {
        return UIFontMetrics(forTextStyle: HouseFont.textStyle(style)).scaledFont(for: HouseFont.baseFont(style), compatibleWith: traits)
    }

    /// The design's line height scaled the same way, so a line never gets tighter than the design when the text grows.
    public static func lineHeight(_ style: HouseTextStyle, compatibleWith traits: UITraitCollection? = nil) -> CGFloat {
        return UIFontMetrics(forTextStyle: HouseFont.textStyle(style)).scaledValue(for: HouseFont.spec(style).lineHeight, compatibleWith: traits)
    }

    /// SwiftUI's Dynamic Type size as the UIKit category the metrics work with.
    public static func contentSizeCategory(_ size: DynamicTypeSize) -> UIContentSizeCategory {
        switch size {
        case .xSmall:
            return .extraSmall
        case .small:
            return .small
        case .medium:
            return .medium
        case .large:
            return .large
        case .xLarge:
            return .extraLarge
        case .xxLarge:
            return .extraExtraLarge
        case .xxxLarge:
            return .extraExtraExtraLarge
        case .accessibility1:
            return .accessibilityMedium
        case .accessibility2:
            return .accessibilityLarge
        case .accessibility3:
            return .accessibilityExtraLarge
        case .accessibility4:
            return .accessibilityExtraExtraLarge
        case .accessibility5:
            return .accessibilityExtraExtraExtraLarge
        @unknown default:
            return .large
        }
    }
}

private struct HouseFontModifier: ViewModifier {
    let style: HouseTextStyle
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func body(content: Content) -> some View {
        let traits = UITraitCollection(preferredContentSizeCategory: HouseFont.contentSizeCategory(self.dynamicTypeSize))
        let font = HouseFont.font(self.style, compatibleWith: traits)
        let lineHeight = HouseFont.lineHeight(self.style, compatibleWith: traits)
        return content
            .font(Font(font as CTFont))
            .lineSpacing(max(0.0, lineHeight - font.lineHeight))
    }
}

extension View {
    /// The House type style, scaled with Dynamic Type; the line height follows the design.
    public func houseFont(_ style: HouseTextStyle) -> some View {
        return self.modifier(HouseFontModifier(style: style))
    }
}
