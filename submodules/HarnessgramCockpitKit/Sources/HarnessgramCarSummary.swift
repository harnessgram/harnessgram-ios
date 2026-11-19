import Foundation

/// Spoken Hebrew summary of the Cockpit snapshot for Siri while driving.
public enum HarnessgramCarSummary {
    private static let maxLength = 300
    private static let maxDecisions = 3
    private static let staleThresholdSeconds: TimeInterval = 30 * 60

    private static let unpairedMessage = "צריך לפתוח את האפליקציה כדי לחבר את הגשר."
    private static let sensitiveMessage = "החלטה רגישה שמחכה לאישור בטלפון."
    private static let hebrewCountsThreeToTen = [
        "שלושה",
        "ארבעה",
        "חמישה",
        "שישה",
        "שבעה",
        "שמונה",
        "תשעה",
        "עשרה",
    ]

    private static let bidiScalars: Set<UInt32> = [
        0x200E, 0x200F,
        0x202A, 0x202B, 0x202C, 0x202D, 0x202E,
        0x2066, 0x2067, 0x2068, 0x2069,
    ]

    public static func spokenSummary(snapshot: HarnessgramCockpitSnapshot?, paired: Bool, now: Date) -> String {
        guard paired, let snapshot else {
            return unpairedMessage
        }

        let openCount = max(0, snapshot.waitingCount)
        let header = countSentence(openCount)
        let decisionLines: [String]
        if openCount > 0 {
            decisionLines = Array(orderedDecisions(snapshot.decisions).compactMap(decisionSentence).prefix(maxDecisions))
        } else {
            decisionLines = []
        }

        let stale = staleSentence(updatedAt: snapshot.updatedAt, now: now)
        return joinWithinLimit(countSentence: header, decisions: decisionLines, staleSentence: stale)
    }

    private static func countSentence(_ count: Int) -> String {
        switch count {
        case ...0:
            return "אין משהו שמחכה לך."
        case 1:
            return "דבר אחד מחכה לך."
        case 2:
            return "שני דברים מחכים לך."
        case 3...10:
            return "\(hebrewCountsThreeToTen[count - 3]) דברים מחכים לך."
        default:
            return "\(count) דברים מחכים לך."
        }
    }

    private static func orderedDecisions(_ decisions: [HarnessgramCockpitSnapshot.Decision]) -> [HarnessgramCockpitSnapshot.Decision] {
        return decisions.enumerated().sorted { lhs, rhs in
            switch (lhs.element.askedAt, rhs.element.askedAt) {
            case let (l?, r?) where l != r:
                return l > r
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                return lhs.offset < rhs.offset
            }
        }.map { $0.element }
    }

    private static func decisionSentence(_ decision: HarnessgramCockpitSnapshot.Decision) -> String? {
        if decision.sensitive {
            return sensitiveMessage
        }
        let cleaned = cleanTitle(decision.title)
        guard !cleaned.isEmpty else {
            return nil
        }
        if let last = cleaned.last, last == "." || last == "?" || last == "!" {
            return cleaned
        }
        return cleaned + "."
    }

    private static func cleanTitle(_ title: String) -> String {
        let withoutBidi = String(String.UnicodeScalarView(title.unicodeScalars.filter { !bidiScalars.contains($0.value) }))
        let withoutCode = withoutBidi
            .replacingOccurrences(of: "(?s)```.*?```", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "`[^`]*`", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "`", with: "")
        let withoutURLs = withoutCode
            .replacingOccurrences(of: "(?i)(?:[a-z][a-z0-9+.-]*://|\\bwww\\.)\\S+", with: " ", options: .regularExpression)
        let withoutEmoji = withoutURLs
            .map { isEmojiCharacter($0) ? " " : String($0) }
            .joined()
        return withoutEmoji
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    private static func isEmojiCharacter(_ character: Character) -> Bool {
        for scalar in character.unicodeScalars {
            if scalar.properties.isEmojiPresentation {
                return true
            }
            switch scalar.value {
            case 0xFE0F,
                 0x20E3,
                 0x1F1E6...0x1F1FF,
                 0x1F300...0x1FAFF,
                 0x2600...0x27BF:
                return true
            default:
                continue
            }
        }
        return false
    }

    private static func staleSentence(updatedAt: Date, now: Date) -> String? {
        let elapsed = now.timeIntervalSince(updatedAt)
        guard elapsed > staleThresholdSeconds else {
            return nil
        }
        let minutes = Int(elapsed / 60)
        if minutes < 60 {
            return "המידע מלפני \(minutes) דקות."
        }
        let hours = minutes / 60
        if hours == 1 {
            return "המידע מלפני שעה."
        }
        return "המידע מלפני \(hours) שעות."
    }

    private static func joinWithinLimit(countSentence: String, decisions: [String], staleSentence: String?) -> String {
        let suffix = staleSentence.map { [$0] } ?? []
        var kept: [String] = []
        for decision in decisions {
            let candidate = ([countSentence] + kept + [decision] + suffix).joined(separator: " ")
            if candidate.count <= maxLength {
                kept.append(decision)
            } else {
                break
            }
        }
        let withSuffix = ([countSentence] + kept + suffix).joined(separator: " ")
        if withSuffix.count <= maxLength {
            return withSuffix
        }
        let withoutSuffix = ([countSentence] + kept).joined(separator: " ")
        if withoutSuffix.count <= maxLength {
            return withoutSuffix
        }
        return String(countSentence.prefix(maxLength))
    }
}
