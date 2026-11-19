import Foundation

/// The Home screen's copy and the words the models speak, one place (a small t()-style layer, ready for i18next
/// later). Plain, warm Hebrew, no technical words (brand kit, "Voice"). Hebrew only for now, right to left.
public enum HouseHomeStrings {
    public enum Key: String, CaseIterable {
        case greetingMorning
        case greetingNoon
        case greetingEvening
        case roomWorking
        case roomQuiet
        case roomWaitingOne
        case roomWaitingMany
        case doorwayTitle
        case doorwayEmpty
        case newRoom
        case unnamedRoom
    }

    public static let isRightToLeft = true

    public static func string(_ key: Key) -> String {
        switch key {
        case .greetingMorning:
            return "בוקר טוב"
        case .greetingNoon:
            return "צהריים טובים"
        case .greetingEvening:
            return "ערב טוב"
        case .roomWorking:
            return "בעבודה"
        case .roomQuiet:
            return "שקט"
        case .roomWaitingOne:
            return "מחכה לך"
        case .roomWaitingMany:
            return "מחכים לך"
        case .doorwayTitle:
            return "מחכה לך"
        case .doorwayEmpty:
            return "הכול טופל"
        case .newRoom:
            return "חדר חדש"
        case .unnamedRoom:
            return "חדר"
        }
    }

    /// `{name}` placeholders replaced by `values`.
    public static func string(_ key: Key, _ values: [String: String]) -> String {
        var text = HouseHomeStrings.string(key)
        for (name, value) in values {
            text = text.replacingOccurrences(of: "{" + name + "}", with: value)
        }
        return text
    }
}
