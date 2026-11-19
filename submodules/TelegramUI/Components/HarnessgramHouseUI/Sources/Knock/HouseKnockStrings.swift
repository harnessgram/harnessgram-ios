import Foundation

/// The knock sheet's and the waiting list's copy, one place (a small t()-style layer, ready for i18next later).
/// Plain, warm Hebrew, no technical words (brand kit, "Voice"). Hebrew only for now, right to left.
enum HouseKnockStrings {
    enum Key: String {
        case knockTitle
        case approve
        case approveFaceIDHint
        case later
        case openRoom
        case choose
        case seeFirst
        case needsFaceID
        case roomQuestionFallback
        case waitingTitle
        case waitingEmptyTitle
        case waitingEmptyBody
        case waitingFooter
        case sending
        case sendFailed
        case answerSent
        case decisionGone
        case notConfirmed
        case waitingWindow
        case waitingRowHint
    }

    static let isRightToLeft = true

    /// The accessibility language of every House sheet and list: VoiceOver reads Hebrew even when the phone is set to English.
    static let speechLanguage = "he-IL"

    private static let hebrew: [Key: String] = [
        .knockTitle: "איתות קשר",
        .approve: "אישור",
        .approveFaceIDHint: "אישור, דורש זיהוי פנים",
        .later: "אחר כך",
        .openRoom: "לפתוח את החדר",
        .choose: "לבחור",
        .seeFirst: "לראות קודם",
        .needsFaceID: "נדרש זיהוי פנים",
        .roomQuestionFallback: "יש שאלה שמחכה לך בחדר",
        .waitingTitle: "מעגל ההמתנה",
        .waitingEmptyTitle: "השמיים נקיים",
        .waitingEmptyBody: "כשמשהו יחכה לך, הוא יופיע כאן",
        .waitingFooter: "אחרי אלה המסלול פנוי",
        .sending: "שולח",
        .sendFailed: "לא הצלחתי לשלוח. אפשר לנסות שוב",
        .answerSent: "נשלח",
        .decisionGone: "ההחלטה כבר נסגרה",
        .notConfirmed: "לא אושר",
        .waitingWindow: "מחכה",
        .waitingRowHint: "פותח את החדר",
    ]

    static func t(_ key: Key) -> String {
        return hebrew[key] ?? key.rawValue
    }

    /// "{agent} מאותת לך" when the bridge names the agent; the plain title otherwise.
    static func title(agentName: String?) -> String {
        if let agentName, !agentName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return agentName + " מאותת לך"
        }
        return t(.knockTitle)
    }
}
