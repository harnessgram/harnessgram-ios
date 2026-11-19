import Foundation

/// The native Cockpit's copy: one table per screen, Hebrew shown, English beside it for review and a later language
/// switch. Numbers, percents and times go through `NativeCockpitFormat` (Intl formatters for the Hebrew locale).
enum NativeCockpitStrings {
    struct Entry: Equatable {
        let he: String
        let en: String
    }

    enum Key: String, CaseIterable {
        // Home
        case homeTitle
        case tabTitle
        case sessionsHeader
        case sessionsWorking
        case sessionsWaiting
        case sessionsIdle
        case decisionsHeader
        case decisionsRow
        case decisionsNone
        case waitingTotal
        case quotaHeader
        case quotaNone
        case quotaWeekly
        case quotaResets
        case quotaBanked
        case radioHeader
        case radioOn
        case radioOff
        case radioDisabled
        case radioUnknown
        case fullCockpitHeader
        case fullCockpit
        case fullCockpitFooter
        case updated
        case loading
        case disconnectedTitle
        case disconnectedDetail
        case pausedDetail
        case connect
        case connecting
        case unavailableTitle
        case retry
        case busyRetryIn
        // Decisions
        case decisionsTitle
        case decisionsFresh
        case decisionsOld
        case decisionsEmpty
        case decisionsAnswerOff
        case decisionTitle
        case decisionQuestion
        case decisionDetail
        case decisionContext
        case commentHeader
        case commentFooter
        case commentPlaceholder
        case commentSend
        case commentSending
        case commentSent
        case commentRefused
        case commentUncertain
        case commentFaceIDReason
        case commentEarlier
        case siriTip
        case decisionImages
        case decisionLinks
        case decisionImageUnavailable
        case decisionTopic
        case decisionAsked
        case decisionNeedsFaceID
        case decisionRoutine
        case decisionPermission
        case decisionPermissionFooter
        case decisionDeclineOnly
        case decisionNote
        case decisionNotePlaceholder
        case decisionNoteFooter
        case decisionAnswerHeader
        case decisionOpenTopic
        case decisionOpenFull
        case faceIDReason
        case sending
        // Results
        case resultHeader
        case resultSent
        case resultDelivered
        case resultInFlight
        case resultQueued
        case resultCancelled
        case resultUnknown
        case resultRetrying
        case resultClosed
        case resultClosedChoice
        case resultNotConfirmed
        case resultCancelledLocally
        case resultLoginExpired
        case resultBusy
        case resultNotAllowed
        case resultFailed
        case answerUncertain
        case answeredYes
        case answeredNo
        // Settings
        case settingNativeCockpit
        case settingNativeCockpitDetail
        case settingNativeDecisions
        case settingNativeDecisionsDetail
    }

    static let table: [Key: Entry] = [
        .homeTitle: Entry(he: "קוקפיט", en: "Cockpit"),
        .tabTitle: Entry(he: "קוקפיט", en: "Cockpit"),
        .sessionsHeader: Entry(he: "סוכנים", en: "Agents"),
        .sessionsWorking: Entry(he: "עובדים עכשיו", en: "Working now"),
        .sessionsWaiting: Entry(he: "מחכים לך", en: "Waiting for you"),
        .sessionsIdle: Entry(he: "פנויים", en: "Idle"),
        .decisionsHeader: Entry(he: "החלטות", en: "Decisions"),
        .decisionsRow: Entry(he: "החלטות שמחכות לך", en: "Decisions waiting for you"),
        .decisionsNone: Entry(he: "אין", en: "None"),
        .waitingTotal: Entry(he: "כל מה שמחכה לך", en: "Everything waiting for you"),
        .quotaHeader: Entry(he: "מכסה שבועית", en: "Weekly quota"),
        .quotaNone: Entry(he: "אין עדיין מדידה של המכסה", en: "No quota reading yet"),
        .quotaWeekly: Entry(he: "נוצל השבוע", en: "Used this week"),
        .quotaResets: Entry(he: "מתאפס", en: "Resets"),
        .quotaBanked: Entry(he: "איפוסים שמורים", en: "Banked resets"),
        .radioHeader: Entry(he: "רדיו", en: "Radio"),
        .radioOn: Entry(he: "משדר", en: "On air"),
        .radioOff: Entry(he: "כבוי", en: "Off"),
        .radioDisabled: Entry(he: "לא מוגדר בגשר", en: "Not set up on the bridge"),
        .radioUnknown: Entry(he: "לא ידוע", en: "Unknown"),
        .fullCockpitHeader: Entry(he: "עוד בקוקפיט", en: "More in the Cockpit"),
        .fullCockpit: Entry(he: "פתיחת הקוקפיט המלא", en: "Open the full Cockpit"),
        .fullCockpitFooter: Entry(he: "פרויקטים, משימות, תזכורות, הגדרות הגשר וכל השאר נמצאים בקוקפיט המלא.", en: "Projects, tasks, reminders, bridge settings and everything else are in the full Cockpit."),
        .updated: Entry(he: "עודכן", en: "Updated"),
        .loading: Entry(he: "טוען מהגשר…", en: "Loading from the bridge…"),
        .disconnectedTitle: Entry(he: "הקוקפיט לא מחובר", en: "The Cockpit is not connected"),
        .disconnectedDetail: Entry(he: "חיבור אחד לגשר, עם זיהוי פנים, מביא לכאן את מצב הסוכנים וההחלטות. זה אותו חיבור של הווידג׳טים.", en: "One connection to the bridge, with Face ID, brings the agents and decisions here. It is the widgets' connection."),
        .pausedDetail: Entry(he: "החיבור הושהה כי נכנס חשבון נוסף, הוחלף חשבון או שהייתה התנתקות. אפשר לחבר מחדש.", en: "The connection is paused after another login, an account switch or a logout. You can connect again."),
        .connect: Entry(he: "חיבור לגשר", en: "Connect to the bridge"),
        .connecting: Entry(he: "מתחבר…", en: "Connecting…"),
        .unavailableTitle: Entry(he: "הגשר לא עונה", en: "The bridge is not answering"),
        .retry: Entry(he: "לנסות שוב", en: "Try again"),
        .busyRetryIn: Entry(he: "הגשר ביקש להמתין. ניסיון נוסף בעוד", en: "The bridge asked to wait. Next try in"),
        .decisionsTitle: Entry(he: "החלטות", en: "Decisions"),
        .decisionsFresh: Entry(he: "מחכות לך", en: "Waiting for you"),
        .decisionsOld: Entry(he: "ישנות", en: "Old"),
        .decisionsEmpty: Entry(he: "אין החלטות שמחכות לך", en: "No decisions are waiting for you"),
        .decisionsAnswerOff: Entry(he: "המענה מכאן כבוי בהגדרות. אפשר לענות בקוקפיט המלא.", en: "Answering here is off in Settings. You can answer in the full Cockpit."),
        .decisionTitle: Entry(he: "החלטה", en: "Decision"),
        .decisionQuestion: Entry(he: "השאלה", en: "Question"),
        .decisionDetail: Entry(he: "פרטים", en: "Details"),
        .decisionContext: Entry(he: "הקשר מלא", en: "Full context"),
        .commentHeader: Entry(he: "תגובה במילים שלך", en: "Your own words"),
        .commentFooter: Entry(he: "התגובה נשלחת לסוכן ולא מאשרת שום דבר. ההחלטה נשארת פתוחה.", en: "The comment goes to the agent and approves nothing. The decision stays open."),
        .commentPlaceholder: Entry(he: "מה לכתוב לסוכן?", en: "What should the agent hear?"),
        .commentSend: Entry(he: "שליחת תגובה", en: "Send comment"),
        .commentSending: Entry(he: "שולח…", en: "Sending…"),
        .commentSent: Entry(he: "התגובה נשלחה. לא אושר דבר.", en: "Comment sent. Nothing was approved."),
        .commentRefused: Entry(he: "הגשר לא קיבל את התגובה להחלטה הזאת.", en: "The bridge did not take a comment on this decision."),
        .commentUncertain: Entry(he: "לא ברור אם התגובה הגיעה. אפשר לבדוק ברשימת התגובות אחרי רענון.", en: "Not sure the comment arrived. Check the comments after a refresh."),
        .commentFaceIDReason: Entry(he: "שליחת תגובה לסוכן", en: "Send a comment to the agent"),
        .commentEarlier: Entry(he: "תגובות קודמות שלך", en: "Your earlier comments"),
        .siriTip: Entry(he: "אפשר גם לשאול את \u{2068}Siri\u{2069}: \"מה מחכה לי ב־\u{2068}HarnessGram\u{2069}\".", en: "You can also ask Siri: \"What waits for me in HarnessGram\"."),
        .decisionImages: Entry(he: "תמונות", en: "Pictures"),
        .decisionLinks: Entry(he: "קישורים", en: "Links"),
        .decisionImageUnavailable: Entry(he: "התמונה לא זמינה כרגע", en: "Picture not available right now"),
        .decisionTopic: Entry(he: "נושא", en: "Topic"),
        .decisionAsked: Entry(he: "נשאלה", en: "Asked"),
        .decisionNeedsFaceID: Entry(he: "רגישה: התשובה דורשת זיהוי פנים", en: "Sensitive: answering needs Face ID"),
        .decisionRoutine: Entry(he: "שגרתית", en: "Routine"),
        .decisionPermission: Entry(he: "בקשת הרשאה במסוף", en: "Terminal permission request"),
        .decisionPermissionFooter: Entry(he: "בקשת הרשאה נענית רק בקוקפיט המלא, שמציג אותה במלואה.", en: "A permission request is answered only in the full Cockpit, which shows it whole."),
        .decisionDeclineOnly: Entry(he: "אפשר רק לדחות", en: "Decline only"),
        .decisionNote: Entry(he: "הערה לסוכן", en: "Note for the agent"),
        .decisionNotePlaceholder: Entry(he: "הערה קצרה (לא חובה)", en: "A short note (optional)"),
        .decisionNoteFooter: Entry(he: "עד 300 תווים. ההערה נשלחת יחד עם התשובה.", en: "Up to 300 characters. The note goes with the answer."),
        .decisionAnswerHeader: Entry(he: "תשובה", en: "Answer"),
        .decisionOpenTopic: Entry(he: "פתיחת הנושא", en: "Open the topic"),
        .decisionOpenFull: Entry(he: "לענות בקוקפיט המלא", en: "Answer in the full Cockpit"),
        .faceIDReason: Entry(he: "אישור התשובה להחלטה", en: "Confirm the answer to the decision"),
        .sending: Entry(he: "שולח…", en: "Sending…"),
        .resultHeader: Entry(he: "מה קרה", en: "What happened"),
        .resultSent: Entry(he: "התשובה נקלטה בגשר", en: "The bridge took the answer"),
        .resultDelivered: Entry(he: "נמסרה לסוכן", en: "Delivered to the agent"),
        .resultInFlight: Entry(he: "בדרך לסוכן", en: "On its way to the agent"),
        .resultQueued: Entry(he: "בתור, הסוכן יקבל כשיתפנה", en: "Queued; the agent gets it when free"),
        .resultCancelled: Entry(he: "המסירה בוטלה", en: "Delivery cancelled"),
        .resultUnknown: Entry(he: "מצב המסירה לא ידוע עדיין", en: "Delivery state not known yet"),
        .resultRetrying: Entry(he: "הגשר מנסה להעיר את הסוכן שוב", en: "The bridge keeps trying to wake the agent"),
        .resultClosed: Entry(he: "ההחלטה כבר נסגרה. לא נשלח דבר.", en: "The decision was already closed. Nothing was sent."),
        .resultClosedChoice: Entry(he: "ההחלטה כבר נענתה:", en: "The decision was already answered:"),
        .resultNotConfirmed: Entry(he: "זיהוי הפנים בוטל או לא הצליח. לא נשלח דבר.", en: "Face ID was cancelled or failed. Nothing was sent."),
        .resultCancelledLocally: Entry(he: "שליחת התשובה בוטלה.", en: "Sending the answer was cancelled."),
        .resultLoginExpired: Entry(he: "הכניסה לגשר פגה. אפשר לנסות שוב, האפליקציה תתחבר מחדש.", en: "The bridge login expired. Try again and the app logs in again."),
        .resultBusy: Entry(he: "הגשר עמוס.", en: "The bridge is busy."),
        .resultNotAllowed: Entry(he: "את התשובה הזאת אפשר לשלוח רק בקוקפיט המלא.", en: "This answer can be sent only in the full Cockpit."),
        .resultFailed: Entry(he: "לא ברור אם התשובה התקבלה.", en: "The answer may have reached the bridge."),
        .answerUncertain: Entry(he: "ייתכן שהתשובה התקבלה. שליחה חוזרת חסומה זמנית.", en: "The answer may have reached the bridge. Resending is temporarily blocked."),
        .answeredYes: Entry(he: "כן", en: "Yes"),
        .answeredNo: Entry(he: "לא", en: "No"),
        .settingNativeCockpit: Entry(he: "קוקפיט מקומי", en: "Native Cockpit"),
        .settingNativeCockpitDetail: Entry(he: "לשונית הקוקפיט מוצגת במסכים של האפליקציה: מצב הסוכנים, ההחלטות, המכסה והרדיו. מתעדכנת רק כשהמסך פתוח. כבוי: הלשונית הקיימת.", en: "The Cockpit tab drawn by the app: agents, decisions, quota and radio. It updates only while on screen. Off: the current tab."),
        .settingNativeDecisions: Entry(he: "מענה להחלטות בקוקפיט המקומי", en: "Answer decisions in the native Cockpit"),
        .settingNativeDecisionsDetail: Entry(he: "כן ולא נשלחים לגשר מתוך האפליקציה. החלטה רגישה דורשת זיהוי פנים. כבוי: ההחלטות מוצגות בלבד.", en: "Yes and No go to the bridge from the app. A sensitive decision needs Face ID. Off: decisions are shown only."),
    ]

    /// The Hebrew text (the app's language).
    static func t(_ key: Key) -> String {
        return self.table[key]?.he ?? ""
    }

    static func english(_ key: Key) -> String {
        return self.table[key]?.en ?? ""
    }
}

/// Numbers, percents and times for the native Cockpit, through the Hebrew locale's formatters.
enum NativeCockpitFormat {
    static let locale = Locale(identifier: "he_IL")

    static func count(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    static func percent(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .percent
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: Double(value) / 100.0)) ?? "\(value)%"
    }

    /// "לפני 5 דקות" / "בעוד יומיים".
    static func relative(_ date: Date, now: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: now)
    }

    static func seconds(_ value: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        formatter.calendar = calendar
        formatter.unitsStyle = .full
        formatter.allowedUnits = value >= 60 ? [.minute] : [.second]
        return formatter.string(from: max(1.0, value.rounded(.up))) ?? "\(Int(value))"
    }
}

/// Which way a text field writes. An empty field takes the page's direction (right to left), so its Hebrew placeholder
/// sits on the right; once it holds text, the first strong letter decides.
enum NativeCockpitTextDirection: Equatable {
    case rightToLeft
    case leftToRight

    static func of(_ text: String) -> NativeCockpitTextDirection {
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x0590 ... 0x08FF, 0xFB1D ... 0xFDFF, 0xFE70 ... 0xFEFF:
                return .rightToLeft
            default:
                if scalar.properties.isAlphabetic {
                    return .leftToRight
                }
            }
        }
        return .rightToLeft
    }
}
