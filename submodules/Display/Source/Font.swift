import Foundation
import UIKit

public struct Font {
    public enum Design {
        case regular
        case serif
        case monospace
        case round
        case camera
        
        var key: String {
            switch self {
            case .regular:
                return "regular"
            case .serif:
                return "serif"
            case .monospace:
                return "monospace"
            case .round:
                return "round"
            case .camera:
                return "camera"
            }
        }
    }
    
    public struct Traits: OptionSet {
        public var rawValue: Int32
        
        public init(rawValue: Int32) {
            self.rawValue = rawValue
        }
        
        public init() {
            self.rawValue = 0
        }
        
        public static let italic = Traits(rawValue: 1 << 0)
        public static let monospacedNumbers = Traits(rawValue: 1 << 1)
        public static let alternateDollarSign = Traits(rawValue: 1 << 2)
    }
    
    public enum Width {
        case standard
        case condensed
        case compressed
        case expanded
        
        @available(iOS 16.0, *)
        var width: UIFont.Width {
            switch self {
            case .standard:
                return .standard
            case .condensed:
                return .condensed
            case .compressed:
                return .compressed
            case .expanded:
                return .expanded
            }
        }
        
        var key: String {
            switch self {
            case .standard:
                return "standard"
            case .condensed:
                return "condensed"
            case .compressed:
                return "compressed"
            case .expanded:
                return "expanded"
            }
        }
    }
    
    public enum Weight {
        case regular
        case thin
        case light
        case medium
        case semibold
        case bold
        case heavy
        
        var isBold: Bool {
            switch self {
                case .medium, .semibold, .bold, .heavy:
                    return true
                default:
                    return false
            }
        }
        
        var weight: UIFont.Weight {
            switch self {
                case .thin:
                    return .thin
                case .light:
                    return .light
                case .medium:
                    return .medium
                case .semibold:
                    return .semibold
                case .bold:
                    return .bold
                case .heavy:
                    return .heavy
                default:
                    return .regular
            }
        }
        
        /// CSS-style weight (100–900), for the Harnessgram app family.
        public var cssWeight: CGFloat {
            switch self {
            case .thin:
                return 200.0
            case .light:
                return 300.0
            case .regular:
                return 400.0
            case .medium:
                return 500.0
            case .semibold:
                return 600.0
            case .bold:
                return 700.0
            case .heavy:
                return 800.0
            }
        }
        
        var key: String {
            switch self {
            case .regular:
                return "regular"
            case .thin:
                return "thin"
            case .light:
                return "light"
            case .medium:
                return "medium"
            case .semibold:
                return "semibold"
            case .bold:
                return "bold"
            case .heavy:
                return "heavy"
            }
        }
    }
    
    private final class Cache {
        private var lock: pthread_rwlock_t
        private var fonts: [String: UIFont] = [:]
        
        init() {
            self.lock = pthread_rwlock_t()
            let status = pthread_rwlock_init(&self.lock, nil)
            assert(status == 0)
        }
        
        func get(_ key: String) -> UIFont? {
            let font: UIFont?
            pthread_rwlock_rdlock(&self.lock)
            font = self.fonts[key]
            pthread_rwlock_unlock(&self.lock)
            return font
        }
        
        func set(_ font: UIFont, key: String) {
            pthread_rwlock_wrlock(&self.lock)
            self.fonts[key] = font
            pthread_rwlock_unlock(&self.lock)
        }
        
        private var appFamily: AppFamilyProvider?
        
        func appFamilyProvider() -> AppFamilyProvider? {
            pthread_rwlock_rdlock(&self.lock)
            let provider = self.appFamily
            pthread_rwlock_unlock(&self.lock)
            return provider
        }
        
        /// Replaces the provider and forgets every cached font, so no font of the previous family is handed out again.
        func setAppFamily(_ provider: AppFamilyProvider?) {
            pthread_rwlock_wrlock(&self.lock)
            self.appFamily = provider
            self.fonts.removeAll()
            pthread_rwlock_unlock(&self.lock)
        }
    }

    private static let cache = Cache()
    
    /// Harnessgram (build 22): the app-wide font family. Given a CSS-style weight, a size and whether the font is
    /// italic, returns the font to use, or nil to keep the system font for that request.
    public typealias AppFamilyProvider = (_ weight: CGFloat, _ size: CGFloat, _ italic: Bool) -> UIFont?
    
    /// Harnessgram (build 22): routes the plain helpers (`regular`, `medium`, `semibold`, `bold`, `heavy`, `light`,
    /// the italics, and `with(...)` for the regular design at standard width without number or dollar-sign features)
    /// through `provider`; nil restores the system font. The app sets it once at launch, before any UI is laid out: many
    /// screens keep the fonts they made in long-lived constants, so a change mid-run would mix two families. The round,
    /// serif, monospace and camera designs and the monospaced-digit requests always keep their system fonts.
    public static func setAppFamily(_ provider: AppFamilyProvider?) {
        self.cache.setAppFamily(provider)
    }
    
    /// Whether an app family is installed.
    public static var hasAppFamily: Bool {
        return self.cache.appFamilyProvider() != nil
    }
    
    private static func appFamilyFont(_ weight: Weight, size: CGFloat, italic: Bool) -> UIFont? {
        guard let provider = self.cache.appFamilyProvider() else {
            return nil
        }
        let key = "app_\(size)_\(weight.key)_\(italic)"
        if let cachedFont = self.cache.get(key) {
            return cachedFont
        }
        guard let font = provider(weight.cssWeight, size, italic) else {
            return nil
        }
        self.cache.set(font, key: key)
        return font
    }
    
    public static func with(size: CGFloat, design: Design = .regular, weight: Weight = .regular, width: Width = .standard, traits: Traits = []) -> UIFont {
        if design == .regular && width == .standard && traits.subtracting(.italic).isEmpty, let font = self.appFamilyFont(weight, size: size, italic: traits.contains(.italic)) {
            return font
        }
        let key = "\(size)_\(design.key)_\(weight.key)_\(width.key)_\(traits.rawValue)"
        
        if let cachedFont = self.cache.get(key) {
            return cachedFont
        }
        if #available(iOS 13.0, *), design != .camera {
            let descriptor: UIFontDescriptor
            if #available(iOS 14.0, *) {
                descriptor = UIFont.systemFont(ofSize: size).fontDescriptor
            } else {
                descriptor = UIFont.systemFont(ofSize: size, weight: weight.weight).fontDescriptor
            }

            var symbolicTraits = descriptor.symbolicTraits
            if traits.contains(.italic) {
                symbolicTraits.insert(.traitItalic)
            }
            var updatedDescriptor: UIFontDescriptor? = descriptor.withSymbolicTraits(symbolicTraits)
            var featureSettings: [[String: Any]] = []
            if traits.contains(.monospacedNumbers) {
                featureSettings.append([
                    UIFontDescriptor.FeatureKey.type.rawValue: kNumberSpacingType,
                    UIFontDescriptor.FeatureKey.selector.rawValue: kMonospacedNumbersSelector
                ])
            }
            if traits.contains(.alternateDollarSign) {
                featureSettings.append([
                    kCTFontOpenTypeFeatureTag as String: "cv09",
                    kCTFontOpenTypeFeatureValue as String: 1
                ])
            }
            if !featureSettings.isEmpty {
                updatedDescriptor = updatedDescriptor?.addingAttributes([
                    UIFontDescriptor.AttributeName.featureSettings: featureSettings
                ])
            }
            switch design {
                case .serif:
                    updatedDescriptor = updatedDescriptor?.withDesign(.serif)
                case .monospace:
                    updatedDescriptor = updatedDescriptor?.withDesign(.monospaced)
                case .round:
                    updatedDescriptor = updatedDescriptor?.withDesign(.rounded)
                default:
                    updatedDescriptor = updatedDescriptor?.withDesign(.default)
            }
            if #available(iOS 14.0, *) {
                if weight != .regular {
                    updatedDescriptor = updatedDescriptor?.addingAttributes([
                        UIFontDescriptor.AttributeName.traits: [UIFontDescriptor.TraitKey.weight: weight.weight]
                    ])
                }
            }
            if #available(iOS 16.0, *) {
                if width != .standard {
                    updatedDescriptor = updatedDescriptor?.addingAttributes([
                        UIFontDescriptor.AttributeName.traits: [UIFontDescriptor.TraitKey.width: width.width]
                    ])
                }
            }
            
            let font: UIFont
            if let updatedDescriptor = updatedDescriptor {
                font = UIFont(descriptor: updatedDescriptor, size: size)
            } else {
                font = UIFont(descriptor: descriptor, size: size)
            }
            
            self.cache.set(font, key: key)
            
            return font
        } else {
            let font: UIFont
            switch design {
                case .regular, .round:
                    if traits.contains(.italic) {
                        if let descriptor = UIFont.systemFont(ofSize: size, weight: weight.weight).fontDescriptor.withSymbolicTraits([.traitItalic]) {
                            font = UIFont(descriptor: descriptor, size: size)
                        } else {
                            font = UIFont.italicSystemFont(ofSize: size)
                        }
                    } else {
                        return UIFont.systemFont(ofSize: size, weight: weight.weight)
                    }
                case .serif:
                    if weight.isBold && traits.contains(.italic) {
                        font = UIFont(name: "Georgia-BoldItalic", size: size - 1.0) ?? UIFont.systemFont(ofSize: size)
                    } else if weight.isBold {
                        font = UIFont(name: "Georgia-Bold", size: size - 1.0) ?? UIFont.systemFont(ofSize: size)
                    } else if traits.contains(.italic) {
                        font = UIFont(name: "Georgia-Italic", size: size - 1.0) ?? UIFont.systemFont(ofSize: size)
                    } else {
                        font = UIFont(name: "Georgia", size: size - 1.0) ?? UIFont.systemFont(ofSize: size)
                    }
                case .monospace:
                    if weight.isBold && traits.contains(.italic) {
                        font = UIFont(name: "Menlo-BoldItalic", size: size - 1.0) ?? UIFont.systemFont(ofSize: size)
                    } else if weight.isBold {
                        font = UIFont(name: "Menlo-Bold", size: size - 1.0) ?? UIFont.systemFont(ofSize: size)
                    } else if traits.contains(.italic) {
                        font = UIFont(name: "Menlo-Italic", size: size - 1.0) ?? UIFont.systemFont(ofSize: size)
                    } else {
                        font = UIFont(name: "Menlo", size: size - 1.0) ?? UIFont.systemFont(ofSize: size)
                    }
                case .camera:
                    if traits.contains(.monospacedNumbers) {
                        font = UIFont.monospacedDigitSystemFont(ofSize: size, weight: weight.weight)
                    } else {
                        font = UIFont.systemFont(ofSize: size, weight: weight.weight)
                    }
            }
            
            self.cache.set(font, key: key)
            
            return font
        }
    }
    
    public static func regular(_ size: CGFloat) -> UIFont {
        if let font = self.appFamilyFont(.regular, size: size, italic: false) {
            return font
        }
        return UIFont.systemFont(ofSize: size)
    }
    
    public static func medium(_ size: CGFloat) -> UIFont {
        if let font = self.appFamilyFont(.medium, size: size, italic: false) {
            return font
        }
        return UIFont.systemFont(ofSize: size, weight: UIFont.Weight.medium)
    }
    
    public static func semibold(_ size: CGFloat) -> UIFont {
        if let font = self.appFamilyFont(.semibold, size: size, italic: false) {
            return font
        }
        return UIFont.systemFont(ofSize: size, weight: UIFont.Weight.semibold)
    }
    
    public static func bold(_ size: CGFloat) -> UIFont {
        if let font = self.appFamilyFont(.bold, size: size, italic: false) {
            return font
        }
        if #available(iOS 8.2, *) {
            return UIFont.boldSystemFont(ofSize: size)
        } else {
            return CTFontCreateWithName("HelveticaNeue-Bold" as CFString, size, nil)
        }
    }
    
    public static func heavy(_ size: CGFloat) -> UIFont {
        return self.with(size: size, design: .regular, weight: .heavy, traits: [])
    }
    
    public static func light(_ size: CGFloat) -> UIFont {
        if let font = self.appFamilyFont(.light, size: size, italic: false) {
            return font
        }
        return UIFont.systemFont(ofSize: size, weight: UIFont.Weight.light)
    }
    
    public static func semiboldItalic(_ size: CGFloat) -> UIFont {
        if let font = self.appFamilyFont(.semibold, size: size, italic: true) {
            return font
        }
        if let descriptor = UIFont.systemFont(ofSize: size).fontDescriptor.withSymbolicTraits([.traitBold, .traitItalic]) {
            return UIFont(descriptor: descriptor, size: size)
        } else {
            return UIFont.italicSystemFont(ofSize: size)
        }
    }
    
    public static func mediumItalic(_ size: CGFloat) -> UIFont {
        if let font = self.appFamilyFont(.medium, size: size, italic: true) {
            return font
        }
        if let descriptor = UIFont.systemFont(ofSize: size, weight: .medium).fontDescriptor.withSymbolicTraits([.traitItalic]) {
            return UIFont(descriptor: descriptor, size: size)
        } else {
            return UIFont.italicSystemFont(ofSize: size)
        }
    }
    
    public static func monospace(_ size: CGFloat) -> UIFont {
        return UIFont(name: "Menlo-Regular", size: size - 1.0) ?? UIFont.systemFont(ofSize: size)
    }
    
    public static func semiboldMonospace(_ size: CGFloat) -> UIFont {
        return UIFont(name: "Menlo-Bold", size: size - 1.0) ?? UIFont.systemFont(ofSize: size)
    }
    
    public static func italicMonospace(_ size: CGFloat) -> UIFont {
        return UIFont(name: "Menlo-Italic", size: size - 1.0) ?? UIFont.systemFont(ofSize: size)
    }
    
    public static func semiboldItalicMonospace(_ size: CGFloat) -> UIFont {
        return UIFont(name: "Menlo-BoldItalic", size: size - 1.0) ?? UIFont.systemFont(ofSize: size)
    }
    
    public static func italic(_ size: CGFloat) -> UIFont {
        if let font = self.appFamilyFont(.regular, size: size, italic: true) {
            return font
        }
        return UIFont.italicSystemFont(ofSize: size)
    }
}

public extension NSAttributedString {
    convenience init(string: String, font: UIFont? = nil, textColor: UIColor = UIColor.black, paragraphAlignment: NSTextAlignment? = nil) {
        var attributes: [NSAttributedString.Key: AnyObject] = [:]
        if let font = font {
            attributes[NSAttributedString.Key.font] = font
        }
        attributes[NSAttributedString.Key.foregroundColor] = textColor
        if let paragraphAlignment = paragraphAlignment {
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = paragraphAlignment
            attributes[NSAttributedString.Key.paragraphStyle] = paragraphStyle
        }
        self.init(string: string, attributes: attributes)
    }
}
