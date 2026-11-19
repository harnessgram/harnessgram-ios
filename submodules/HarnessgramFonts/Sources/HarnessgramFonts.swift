import Foundation
import UIKit
import CoreText
import HarnessgramSettings

/// Bundled OFL families (Resources/FONTS_PROVENANCE.md): the message text font (bubbles and the chat input field,
/// build 11) and the app font (the whole app through Display's `Font` helpers, build 22), at a chosen weight.
public enum HarnessgramFonts {
    public struct Fonts {
        public let regular: UIFont
        public let bold: UIFont
        public let italic: UIFont
        public let boldItalic: UIFont
    }

    struct Family: Equatable {
        let fileName: String
        let weightRange: ClosedRange<CGFloat>
        /// A variable font ('wght' axis); a static one is drawn at its single weight.
        let variable: Bool
    }

    /// Every family in the bundle.
    enum BundledFamily: CaseIterable {
        case assistant
        case heebo
        case rubik
        case frankRuhlLibre
        case secularOne

        var family: Family {
            switch self {
            case .assistant:
                return Family(fileName: "Assistant-Variable", weightRange: 200.0 ... 800.0, variable: true)
            case .heebo:
                return Family(fileName: "Heebo-Variable", weightRange: 100.0 ... 900.0, variable: true)
            case .rubik:
                return Family(fileName: "Rubik-Variable", weightRange: 300.0 ... 900.0, variable: true)
            case .frankRuhlLibre:
                return Family(fileName: "FrankRuhlLibre-Variable", weightRange: 300.0 ... 900.0, variable: true)
            case .secularOne:
                return Family(fileName: "SecularOne-Regular", weightRange: 400.0 ... 400.0, variable: false)
            }
        }
    }

    static func family(_ font: HarnessgramSettings.MessageFont) -> Family? {
        switch font {
        case .system:
            return nil
        case .assistant:
            return BundledFamily.assistant.family
        case .heebo:
            return BundledFamily.heebo.family
        case .rubik:
            return BundledFamily.rubik.family
        case .frankRuhlLibre:
            return BundledFamily.frankRuhlLibre.family
        case .secularOne:
            return BundledFamily.secularOne.family
        }
    }

    static func appFamily(_ font: HarnessgramSettings.AppFont) -> Family? {
        switch font {
        case .system:
            return nil
        case .assistant:
            return BundledFamily.assistant.family
        case .heebo:
            return BundledFamily.heebo.family
        case .rubik:
            return BundledFamily.rubik.family
        case .frankRuhlLibre:
            return BundledFamily.frankRuhlLibre.family
        case .secularOne:
            return BundledFamily.secularOne.family
        }
    }

    /// Bold inside a message stays three steps heavier than the chosen base (regular 400 -> 700).
    public static func boldWeight(for base: CGFloat) -> CGFloat {
        return min(900.0, base + 300.0)
    }

    /// The closest weight the family has.
    public static func resolvedWeight(_ weight: CGFloat, for font: HarnessgramSettings.MessageFont) -> CGFloat {
        return self.resolvedWeight(weight, in: self.family(font))
    }

    /// The closest weight the family has (Secular One: always 400).
    public static func resolvedAppWeight(_ weight: CGFloat, for font: HarnessgramSettings.AppFont) -> CGFloat {
        return self.resolvedWeight(weight, in: self.appFamily(font))
    }

    static func resolvedWeight(_ weight: CGFloat, in family: Family?) -> CGFloat {
        guard let family else {
            return min(max(weight, 100.0), 900.0)
        }
        return min(max(weight, family.weightRange.lowerBound), family.weightRange.upperBound)
    }

    private static let italicMatrix = CGAffineTransform(a: 1.0, b: 0.0, c: 0.2, d: 1.0, tx: 0.0, ty: 0.0)
    private static let weightAxis = NSNumber(value: 0x77676874) // 'wght'

    private final class BundleAnchor {
    }

    private static let lock = NSLock()
    private static var baseDescriptors: [String: CTFontDescriptor] = [:]
    private static var registrations: [String: Registration] = [:]

    /// How a bundled family came up for this process.
    public enum Registration: Equatable {
        case registered
        /// Not in the app bundle.
        case missing
        /// The system refused it (CTFontManager error code), or its file has no font.
        case failed(code: Int)

        public var isAvailable: Bool {
            return self == .registered
        }
    }

    /// Registers every bundled family for this process; the app calls it once at start. A family that fails
    /// is never used: its messages and the input field fall back to the system font, and `log` gets one line.
    /// Later calls return the first result without registering again.
    @discardableResult
    public static func registerBundledFonts(log: (String) -> Void = { _ in }) -> [HarnessgramSettings.MessageFont: Registration] {
        var result: [HarnessgramSettings.MessageFont: Registration] = [:]
        for font in HarnessgramSettings.MessageFont.allCases {
            guard let family = self.family(font) else {
                continue
            }
            self.lock.lock()
            let registration = self.registerLocked(family)
            self.lock.unlock()
            result[font] = registration
            if !registration.isAvailable {
                log("HarnessgramFonts: \(family.fileName) is unavailable (\(registration)); its messages use the system font")
            }
        }
        // Families only the app font offers (build 22).
        let messageFamilies = HarnessgramSettings.MessageFont.allCases.compactMap { self.family($0) }
        for bundled in BundledFamily.allCases where !messageFamilies.contains(bundled.family) {
            self.lock.lock()
            let registration = self.registerLocked(bundled.family)
            self.lock.unlock()
            if !registration.isAvailable {
                log("HarnessgramFonts: \(bundled.family.fileName) is unavailable (\(registration)); the app keeps the system font")
            }
        }
        return result
    }

    /// Registered for this process so UIKit can re-resolve the font by name (text input, copy). Once per family;
    /// "already registered" counts as registered.
    private static func registerLocked(_ family: Family) -> Registration {
        if let current = self.registrations[family.fileName] {
            return current
        }
        var registration = Registration.missing
        for bundle in [Bundle.main, Bundle(for: BundleAnchor.self)] {
            guard let url = bundle.url(forResource: family.fileName, withExtension: "ttf") else {
                continue
            }
            var error: Unmanaged<CFError>?
            if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
                let code = error.map { CFErrorGetCode($0.takeRetainedValue()) } ?? -1
                if code != CTFontManagerError.alreadyRegistered.rawValue {
                    registration = .failed(code: code)
                    break
                }
            }
            guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor], let descriptor = descriptors.first else {
                registration = .failed(code: -1)
                break
            }
            self.baseDescriptors[family.fileName] = descriptor
            registration = .registered
            break
        }
        self.registrations[family.fileName] = registration
        return registration
    }

    /// Test hook: marks a family as failed, as if the system had refused it.
    static func markUnavailableForTesting(_ font: HarnessgramSettings.MessageFont, code: Int) {
        self.markUnavailableForTesting(self.family(font), code: code)
    }

    static func markAppFontUnavailableForTesting(_ font: HarnessgramSettings.AppFont, code: Int) {
        self.markUnavailableForTesting(self.appFamily(font), code: code)
    }

    private static func markUnavailableForTesting(_ family: Family?, code: Int) {
        guard let family else {
            return
        }
        self.lock.lock()
        defer { self.lock.unlock() }
        self.registrations[family.fileName] = .failed(code: code)
        self.baseDescriptors[family.fileName] = nil
    }

    /// Test hook: forgets every registration result (the process registration itself stays).
    static func resetRegistrationsForTesting() {
        self.lock.lock()
        defer { self.lock.unlock() }
        self.registrations = [:]
        self.baseDescriptors = [:]
    }

    /// The bundled font's descriptor, or nil when the family is unavailable (the caller uses the system font).
    static func baseDescriptor(_ family: Family) -> CTFontDescriptor? {
        self.lock.lock()
        defer { self.lock.unlock() }
        guard self.registerLocked(family).isAvailable else {
            return nil
        }
        return self.baseDescriptors[family.fileName]
    }

    static func systemWeight(_ weight: CGFloat) -> UIFont.Weight {
        switch weight {
        case ..<250.0:
            return .ultraLight
        case ..<350.0:
            return .light
        case ..<450.0:
            return .regular
        case ..<550.0:
            return .medium
        case ..<650.0:
            return .semibold
        case ..<750.0:
            return .bold
        case ..<850.0:
            return .heavy
        default:
            return .black
        }
    }

    /// One font: `weight` is CSS-style; a family without that weight uses its closest; missing glyphs
    /// (emoji, other scripts) fall back to the system font.
    public static func font(_ font: HarnessgramSettings.MessageFont, weight: CGFloat, size: CGFloat, italic: Bool = false) -> UIFont {
        if let family = self.family(font), let bundled = self.bundledFont(family, weight: weight, size: size, italic: italic) {
            return bundled
        }
        let system = UIFont.systemFont(ofSize: size, weight: self.systemWeight(weight))
        if italic, let descriptor = system.fontDescriptor.withSymbolicTraits(.traitItalic) {
            return UIFont(descriptor: descriptor, size: size)
        }
        return system
    }

    /// A bundled family's font, or nil when the family is unavailable. A static family draws at its one weight; a
    /// glyph the family lacks falls back to the system font at the matching weight.
    static func bundledFont(_ family: Family, weight: CGFloat, size: CGFloat, italic: Bool) -> UIFont? {
        guard let base = self.baseDescriptor(family) else {
            return nil
        }
        let resolved = self.resolvedWeight(weight, in: family)
        var descriptor = family.variable ? CTFontDescriptorCreateCopyWithVariation(base, self.weightAxis as CFNumber, resolved) : base
        // The fallback follows the weight asked for, so a bold request on a one-weight family keeps bold emoji/Latin.
        let fallback = UIFont.systemFont(ofSize: size, weight: self.systemWeight(family.variable ? resolved : weight)).fontDescriptor as CTFontDescriptor
        descriptor = CTFontDescriptorCreateCopyWithAttributes(descriptor, [kCTFontCascadeListAttribute: [fallback]] as CFDictionary)
        var matrix = self.italicMatrix
        let ctFont = italic ? CTFontCreateWithFontDescriptor(descriptor, size, &matrix) : CTFontCreateWithFontDescriptor(descriptor, size, nil)
        return ctFont as UIFont
    }

    /// The app font (build 22) for one of Display's `Font` helpers, or nil for the system font: the system choice, or a
    /// family that failed to register (the app then keeps the system font, never a missing-glyph box).
    public static func appFont(_ font: HarnessgramSettings.AppFont, weight: CGFloat, size: CGFloat, italic: Bool = false) -> UIFont? {
        guard let family = self.appFamily(font) else {
            return nil
        }
        return self.bundledFont(family, weight: weight, size: size, italic: italic)
    }

    private static var launchedAppFontValue: HarnessgramSettings.AppFont = .system

    /// The app font this process launched with: the picker compares the owner's choice to it ("on the next launch").
    public static var launchedAppFont: HarnessgramSettings.AppFont {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.launchedAppFontValue
    }

    /// Launch (build 22): registers the bundled families and returns the app family for Display's `Font` helpers, or
    /// nil to keep the system font (the system choice, or a family that cannot be drawn). Read once per launch.
    public static func appFamilyForLaunch(settings: HarnessgramSettings = .shared, log: (String) -> Void = { _ in }) -> ((CGFloat, CGFloat, Bool) -> UIFont?)? {
        self.registerBundledFonts(log: log)
        var choice = settings.appFont
        if choice != .system && !self.isAvailable(choice) {
            log("HarnessgramFonts: the app font \(choice.rawValue) is unavailable; the app keeps the system font")
            choice = .system
        }
        self.lock.lock()
        self.launchedAppFontValue = choice
        self.lock.unlock()
        guard choice != .system else {
            return nil
        }
        return { weight, size, italic in
            return HarnessgramFonts.appFont(choice, weight: weight, size: size, italic: italic)
        }
    }

    /// Build 23: the family for Display's `Font` helpers when the owner picks a font while the app runs (the font page
    /// swaps it at once; the restart banner covers text that screens drew earlier). nil for the system font or a
    /// family that cannot be drawn. The launch font (`launchedAppFont`) is not changed.
    public static func liveAppFamily(_ font: HarnessgramSettings.AppFont) -> ((CGFloat, CGFloat, Bool) -> UIFont?)? {
        guard font != .system, self.isAvailable(font) else {
            return nil
        }
        return { weight, size, italic in
            return HarnessgramFonts.appFont(font, weight: weight, size: size, italic: italic)
        }
    }

    /// Whether the family can be drawn in this process (the system font always can).
    public static func isAvailable(_ font: HarnessgramSettings.AppFont) -> Bool {
        guard let family = self.appFamily(font) else {
            return true
        }
        return self.baseDescriptor(family) != nil
    }

    public static func fonts(_ font: HarnessgramSettings.MessageFont, weight: HarnessgramSettings.FontWeight, size: CGFloat) -> Fonts {
        let base = weight.value
        let bold = self.boldWeight(for: base)
        return Fonts(
            regular: self.font(font, weight: base, size: size),
            bold: self.font(font, weight: bold, size: size),
            italic: self.font(font, weight: base, size: size, italic: true),
            boldItalic: self.font(font, weight: bold, size: size, italic: true)
        )
    }

    /// Whether the owner changed anything from Telegram's own message text (system font, regular weight).
    public static func isCustomized(_ settings: HarnessgramSettings = .shared) -> Bool {
        return settings.messageFont != .system || settings.fontWeight != .regular
    }

    /// The chat input field's empty height for a typing size, when the Harnessgram reading choices change the
    /// input (a size step or another font): one line of the input font plus the field's vertical insets, never
    /// below Telegram's 31. Nil leaves Telegram's own table. For the system font this formula gives Telegram's
    /// measured heights (17pt 31, 19pt 33, 23pt 38, 26pt 42).
    public static func inputFieldMinHeight(size: CGFloat, verticalInsets: CGFloat, settings: HarnessgramSettings = .shared) -> CGFloat? {
        guard settings.textSizeSteps != 0 || self.isCustomized(settings) else {
            return nil
        }
        return self.fieldHeight(font: self.inputFont(size: size, settings: settings) ?? UIFont.systemFont(ofSize: size), verticalInsets: verticalInsets)
    }

    static func fieldHeight(font: UIFont, verticalInsets: CGFloat) -> CGFloat {
        return max(31.0, ceil(font.lineHeight + verticalInsets))
    }

    /// The chat input field's fonts for the current settings (bold is the input's semibold-relative bold).
    public static func inputFont(size: CGFloat, bold: Bool = false, italic: Bool = false, settings: HarnessgramSettings = .shared) -> UIFont? {
        guard self.isCustomized(settings) else {
            return nil
        }
        let base = settings.fontWeight.value
        return self.font(settings.messageFont, weight: bold ? self.boldWeight(for: base) : base, size: size, italic: italic)
    }
}
