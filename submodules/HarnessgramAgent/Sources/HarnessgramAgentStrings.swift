import Foundation

/// The agent features' copy, one place (a small t()-style layer). Hebrew only for now, right to left.
public enum HarnessgramAgentStrings {
    public enum Key: String, CaseIterable {
        case ribbonContinue
        case ribbonStatus
        case ribbonSummary
        case ribbonStop
        case ribbonContinueAccessibility
        case ribbonStatusAccessibility
        case ribbonSummaryAccessibility
        case ribbonStopAccessibility
        case ribbonStopConfirmText
        case ribbonStopConfirm
        case ribbonStopCancel
        case confirmSensitiveReason
        case confirmSensitiveReasonNamed
        case confirmWidgetRequestReason
        case radioReplaceTitle
        case radioReplaceText
        case radioReplace
        case radioKeep
    }

    /// The ribbon reads right to left: its first action sits at the right edge.
    public static let isRightToLeft = true

    public static func string(_ key: Key) -> String {
        switch key {
        case .ribbonContinue:
            return "המשך"
        case .ribbonStatus:
            return "מצב"
        case .ribbonSummary:
            return "סיכום"
        case .ribbonStop:
            return "עצור"
        case .ribbonContinueAccessibility:
            return "המשך את הסשן"
        case .ribbonStatusAccessibility:
            return "מצב הסשן"
        case .ribbonSummaryAccessibility:
            return "בקש סיכום קצר"
        case .ribbonStopAccessibility:
            return "עצור את הסשן"
        case .ribbonStopConfirmText:
            return "לעצור את הסשן עכשיו?"
        case .ribbonStopConfirm:
            return "עצור"
        case .ribbonStopCancel:
            return "ביטול"
        case .confirmSensitiveReason:
            return "אישור פעולה רגישה"
        case .confirmSensitiveReasonNamed:
            return "אישור פעולה רגישה: {action}"
        case .confirmWidgetRequestReason:
            return "אישור פעולה מכרטיס של הגשר"
        case .radioReplaceTitle:
            return "להחליף את קישור השידורים?"
        case .radioReplaceText:
            // Dynamic values are isolated from the surrounding Hebrew below.
            return "הקישור החדש מגיע מהכתובת:\n{host}"
        case .radioReplace:
            return "החלף"
        case .radioKeep:
            return "השאר"
        }
    }

    /// `{name}` placeholders replaced by `values`.
    public static func string(_ key: Key, _ values: [String: String]) -> String {
        var text = HarnessgramAgentStrings.string(key)
        for (name, value) in values {
            text = text.replacingOccurrences(of: "{" + name + "}", with: "\u{2068}" + value + "\u{2069}")
        }
        return text
    }
}
