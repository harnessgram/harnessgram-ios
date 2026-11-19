import Foundation

/// The widgets' and the Live Activity's copy. English names inside a Hebrew line are wrapped in
/// bidi isolates (U+2068 ... U+2069).
public enum HarnessgramWidgetStrings {
    public static let isRightToLeft = true

    /// Today follows the preferred languages, with Hebrew as the fallback.
    public enum Today {
        case hebrew
        case english

        @available(iOS 16.0, *)
        public init(preferredLanguages: [String] = Locale.preferredLanguages) {
            let preferred = Bundle.preferredLocalizations(from: ["he", "en"], forPreferences: preferredLanguages)
            // Bundle can return English as a fallback even when it is absent from the preferences.
            let prefersEnglish = preferred.first == "en" && preferredLanguages.contains {
                Locale(identifier: $0).language.languageCode?.identifier == "en"
            }
            self = prefersEnglish ? .english : .hebrew
        }

        public var isRightToLeft: Bool { self == .hebrew }
        public var title: String { self == .hebrew ? "היום" : "Today" }
        public var galleryName: String { self == .hebrew ? "הרנסגרם: היום" : "HarnessGram: Today" }
        public var galleryDescription: String {
            return self == .hebrew ? "המשימות שהושלמו היום ואלה שמחכות לך" : "Tasks completed today and tasks waiting for you"
        }
        public var empty: String { self == .hebrew ? "אין משימות להיום" : "No tasks today" }
        public var nothingWaiting: String { self == .hebrew ? "אין משימות שמחכות לך" : "No tasks waiting for you" }

        public func progress(done: Int, total: Int) -> String {
            return self == .hebrew ? "הושלמו היום \(done) מתוך \(total)" : "\(done) of \(total) done today"
        }

        public func age(minutes: Int) -> String {
            let minutes = max(0, minutes)
            if minutes < 60 {
                return self == .hebrew ? "\(minutes) דק׳" : "\(minutes) min"
            }
            if minutes < 48 * 60 {
                let hours = minutes / 60
                return self == .hebrew ? "\(hours) ש׳" : "\(hours) h"
            }
            let days = min(minutes / (24 * 60), 99)
            return self == .hebrew ? "\(days) ימים" : "\(days) d"
        }
    }

    public static let waitingTitle = "אישורי המראה"
    public static let waitingGalleryName = "הרנסגרם: אישורי המראה"
    public static let waitingGalleryDescription = "אישורי המראה שמחכים לך, הסוכנים שבאוויר והשידורים"
    public static let activityGalleryName = "הרנסגרם: לוח טיסה"
    public static let nothingWaiting = "אין אישורים ממתינים"
    public static let agentsTitle = "סוכנים באוויר"
    public static let noAgents = "אין סוכנים באוויר"
    public static let unnamedAgent = "סוכן"
    public static let radio = "שידורים"
    public static let radioOn = "השידורים פועלים"
    public static let radioOff = "השידורים כבויים"
    public static let approve = "אשר"
    public static let decline = "דחה"
    public static let openToAnswer = "פתח לאישור"
    /// Accessibility label of the lock on a sensitive line.
    public static let needsFaceID = "צריך אישור ב\u{2068}Face ID\u{2069}"
    public static let openAppToRefresh = "פתח את האפליקציה לרענון"
    /// Not paired with the bridge yet (no Cockpit login for this account): a pairing step, not just a refresh.
    public static let needsPairing = "צריך לחבר את הווידג׳ט לגשר"
    /// The unpaired widget's second line: what the owner actually does (a tap on it opens the app and connects).
    public static let openAppToPair = "הקשה כאן מחברת אותו"
    /// Face ID prompt line when the owner connects the widgets.
    public static let repairReason = "חיבור הווידג׳טים לגשר"
    // In-app results of connecting (build 18).
    public static let pairConnected = "הווידג׳טים מחוברים לגשר"
    public static let pairNeedsOneAccount = "הווידג׳טים עובדים רק כשמחובר חשבון טלגרם אחד. אפשר לחבר אחרי שיישאר חשבון אחד."
    public static let pairBridgeUnavailable = "הגשר לא ענה. נסה שוב בעוד רגע."
    public static let pairNotConfirmed = "החיבור בוטל"
    /// Both lines, each on its own line.
    public static let needsPairingFull = needsPairing + "\n" + openAppToPair

    /// The empty widget's text: the pairing step when unpaired, otherwise a refresh.
    /// The shared store was busy: nothing of any account is shown, and the widget asks again within a minute.
    public static let temporarilyUnavailable = "לא זמין כרגע. מתעדכן בעוד רגע"

    public static func emptyText(needsPairing: Bool, oneLine: Bool, unavailable: Bool = false) -> String {
        if unavailable {
            return HarnessgramWidgetStrings.temporarilyUnavailable
        }
        if needsPairing {
            return oneLine ? HarnessgramWidgetStrings.needsPairing : HarnessgramWidgetStrings.needsPairingFull
        }
        return HarnessgramWidgetStrings.openAppToRefresh
    }
    public static let answerNotSent = "התשובה לא נשלחה. פתח את האפליקציה"
    public static let answerIntentTitle = "תשובה להחלטה"

    // In-app confirmation of a widget answer.
    public static let confirmTitle = "תשובה להחלטה"
    public static let confirmFaceIDReason = "אישור החלטה רגישה"
    public static let decisionGone = "ההחלטה כבר נסגרה או שאינה ממתינה עוד"
    public static let cockpitUnavailable = "אין קשר עם המגדל כרגע. נסה שוב בעוד רגע"
    public static let answerSent = "התשובה נשלחה"
    public static let cancel = "ביטול"

    public static func waitingCount(_ count: Int) -> String {
        switch count {
        case 0:
            return nothingWaiting
        case 1:
            return "אישור המראה אחד ממתין"
        default:
            return "\(count) אישורי המראה ממתינים"
        }
    }

    public static func agentsCount(_ count: Int) -> String {
        switch count {
        case 0:
            return noAgents
        case 1:
            return "סוכן אחד עובד"
        default:
            return "\(count) סוכנים עובדים"
        }
    }

    /// "שלב 2 מתוך 5" (the step being worked on, 1-based).
    public static func stepOf(_ current: Int, _ total: Int) -> String {
        return "שלב \(current) מתוך \(total)"
    }

    /// "שלב 2/5": the watch-size step count.
    public static func stepShort(_ current: Int, _ total: Int) -> String {
        return "שלב \(current)/\(total)"
    }

    public static let allStepsDone = "נחת בשלום"

    public static func moreTasks(_ count: Int) -> String {
        return "+\(count) משימות נוספות"
    }

    public static func percent(_ value: Int) -> String {
        return "\(value)%"
    }

    // Lock screen pack (flight deck).
    /// The brand beside the tower glyph: a short English name, on its own (never inside a Hebrew line).
    public static let brandName = "HarnessGram"
    public static let activeTask = "משימה פעילה"
    public static let taskLanded = "הושלמה"
    /// iOS marked the activity stale: no update for a while.
    public static let taskNoSignal = "אין עדכון"
    /// The overflow summary's badge.
    public static let moreTasksBadge = "עוד משימות"
    public static let openCockpit = "פתח את הקוקפיט לכל המשימות"
    public static let nextDecisionPrefix = "הבא: "
    public static let radarTitle = "מכ״ם"

    /// "הבא: <title>".
    public static func next(_ title: String) -> String {
        return nextDecisionPrefix + title
    }

    /// "עוד 4 משימות באוויר" (the summary card under the shown tasks).
    public static func moreTasksInAir(_ count: Int) -> String {
        return count == 1 ? "עוד משימה אחת באוויר" : "עוד \(count) משימות באוויר"
    }

    /// The overflow summary's first row: "2 decisions wait for you" / "1 decision waits for you".
    public static func decisionsWaiting(_ count: Int) -> String {
        return count == 1 ? "החלטה אחת מחכה לך" : "\(count) החלטות מחכות לך"
    }

    /// The overflow summary's badge when something waits: "Waiting for you".
    public static let summaryWaitingBadge = "מחכה לך"
    /// The overflow summary's footer beside "+K": "more tasks in the Cockpit".
    public static let summaryMoreInCockpit = "עוד בקוקפיט"

    /// "3 משימות באוויר".
    public static func tasksInAir(_ count: Int) -> String {
        switch count {
        case ...0:
            return "אין משימות באוויר"
        case 1:
            return "משימה אחת באוויר"
        default:
            return "\(count) משימות באוויר"
        }
    }

    /// "1 מחכה לך" / "3 מחכים לך".
    public static func waitingForYou(_ count: Int) -> String {
        switch count {
        case ...0:
            return "אין ממתינים"
        case 1:
            return "1 מחכה לך"
        default:
            return "\(count) מחכים לך"
        }
    }

    /// The radar's two short labels.
    public static func radarRunning(_ count: Int) -> String {
        return "\(max(0, count)) פעילים"
    }

    public static func radarWaiting(_ count: Int) -> String {
        return "\(max(0, count)) מחכים"
    }

    /// "+2 נוספים" after the next decision.
    public static func moreWaiting(_ count: Int) -> String {
        return count == 1 ? "+1 נוסף" : "+\(count) נוספים"
    }

    /// "עכשיו" / "לפני 4 דק׳" / "לפני 2 שע׳" / "לפני 3 ימים".
    public static func askedAgo(_ seconds: TimeInterval) -> String {
        let minutes = Int(max(0, seconds.isFinite ? seconds : 0) / 60)
        if minutes < 1 {
            return "עכשיו"
        } else if minutes < 60 {
            return "לפני \(minutes) דק׳"
        } else if minutes < 24 * 60 {
            return "לפני \(minutes / 60) שע׳"
        } else {
            let days = minutes / (24 * 60)
            return days == 1 ? "לפני יום" : "לפני \(days) ימים"
        }
    }

    /// The altimeter's spoken value.
    public static func altitude(_ label: String) -> String {
        return "גובה \(label) רגל"
    }

    /// "עודכן לפני 5 דק׳" / "עודכן עכשיו".
    public static func updated(_ seconds: TimeInterval) -> String {
        let minutes = Int(max(0, seconds) / 60)
        if minutes < 1 {
            return "עודכן עכשיו"
        } else if minutes < 60 {
            return "עודכן לפני \(minutes) דק׳"
        } else {
            return "עודכן לפני \(minutes / 60) שע׳"
        }
    }
}
