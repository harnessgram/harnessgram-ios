import Foundation
import HarnessgramSettings

/// The Harnessgram screens' copy, one place per screen (a small t()-style layer). Hebrew only for now.
enum HarnessgramStrings {
    enum Key: String {
        case settingsTitle
        case sectionAgents
        case agentQuickActions
        case agentQuickActionsFooter
        case topicStatusDots
        case topicStatusDotsFooter
        case confirmSensitiveButtons
        case confirmSensitiveButtonsFooter
        case confirmSensitiveOffReason
        case bridgeTitle
        case bridgeUnknown
        case bridgePinned
        case bridgeChangedTitle
        case bridgeChangedDetail
        case bridgeChangedConfirm
        case bridgeChangedReason
        case cockpitPausedTitle
        case cockpitPausedDetail
        case cockpitPausedOneAccount
        case cockpitRepair
        case widgetsPairTitle
        case widgetsPairDetail
        case widgetsConnected
        case widgetsPair
        case widgetsPairing
        case widgetsDisconnect
        case pairBridgeUnavailable
        case sectionConnection
        case homeRelay
        case homeRelayFooter
        case sectionRecording
        case recordWithBuiltInMic
        case recordWithBuiltInMicFooter
        case sectionMedia
        case autoDownload
        case autoDownloadFooter
        case perChatFooter
        case sectionReading
        case sectionAppearance
        case justifiedText
        case justifiedTextFooter
        case lineSpacing
        case lineSpacingNormal
        case lineSpacingComfortable
        case messageFont
        case fontSystem
        case fontAssistant
        case fontHeebo
        case fontRubik
        case fontFrankRuhlLibre
        case fontWeight
        case weightLight
        case weightRegular
        case weightMedium
        case weightSemibold
        case textSize
        case textSizeDefault
        case bubbleWidth
        case bubbleNormal
        case bubbleWide
        case readingFooter
        case readingPreview
        case sectionRadio
        case radioRow
        case filterFooter
        case mediaLevelTitle
        case mediaLevelTextOnly
        case mediaLevelPhotos
        case mediaLevelDocuments
        case mediaLevelAll
        case mediaLevelDefault
        case mediaLevelFooter
        case mediaLevelNotApproved
        case radioTitle
        case radioStation
        case radioPlay
        case radioPause
        case radioStopped
        case radioConnecting
        case radioPlaying
        case radioPaused
        case radioFailed
        case radioResumeOffer
        case radioLinkSection
        case radioLinkPlaceholder
        case radioLinkSave
        case radioLinkForget
        case radioLinkSaved
        case radioLinkInvalid
        case radioLinkMissing
        case radioLinkFooter
        case fontRow
        case fontRowDetail
        case separateMessageFont
        case separateMessageFontDetail
        case messageFontDetail
        case fontWeightDetail
        case textSizeDetail
        case bubbleWidthDetail
        case lineSpacingDetail
        case radioRowDetail
        case additionsRowDetail
    }

    private static let hebrew: [Key: String] = [
        .settingsTitle: "HarnessGram",
        .sectionAgents: "סוכנים",
        .agentQuickActions: "כפתורי סוכן מעל שדה הכתיבה",
        .agentQuickActionsFooter: "שורת המשך, מצב, סיכום ועצור מעל שדה הכתיבה בנושאי הסוכנים. כבוי: השורה לא מופיעה.",
        .topicStatusDots: "נקודות מצב ליד הנושאים",
        .topicStatusDotsFooter: "נקודה ליד כל נושא של סוכן: כחול עובד, כתום מחכה לך, ירוק נחת. כבוי: בלי נקודות.",
        .confirmSensitiveButtons: "זיהוי פנים לכפתורים רגישים",
        .confirmSensitiveButtonsFooter: "כפתור רגיש של בוט (כסף, מחיקה, פרסום, חשבונות) מבקש קודם זיהוי פנים. כיבוי דורש זיהוי פנים.",
        .confirmSensitiveOffReason: "כיבוי האישור לכפתורים רגישים",
        .bridgeTitle: "בוט הגשר",
        .bridgeUnknown: "עוד לא זוהה. הוא יזוהה ברגע שהווידג׳טים יתחברו לגשר (למטה, בשורה \"חיבור הווידג׳טים לגשר\").",
        .bridgePinned: "מזוהה לפי מספר הבוט הקבוע:",
        .bridgeChangedTitle: "בוט הגשר השתנה",
        .bridgeChangedDetail: "שם הבוט מוביל עכשיו לבוט אחר. עד שתאשר, אין לו הרשאות של הגשר. מספר קודם ומספר חדש:",
        .bridgeChangedConfirm: "אישור הבוט החדש",
        .bridgeChangedReason: "אישור בוט גשר חדש",
        .cockpitPausedTitle: "הווידג׳טים מושהים",
        .cockpitPausedDetail: "נכנס חשבון נוסף, הוחלף חשבון או שהייתה התנתקות, ולכן הכול נמחק. אפשר לחבר מחדש לחשבון הזה.",
        .cockpitPausedOneAccount: "הווידג׳טים עובדים רק כשמחובר חשבון טלגרם אחד. אחרי שיישאר חשבון אחד אפשר לחבר מחדש.",
        .cockpitRepair: "חיבור מחדש לגשר",
        .widgetsPairTitle: "חיבור הווידג׳טים לגשר",
        .widgetsPairDetail: "הווידג׳טים במסך הבית ובמסך הנעילה מראים מה מחכה לך. הקשה אחת מחברת אותם, עם זיהוי פנים.",
        .widgetsConnected: "מחוברים לגשר. ההחלטות והסוכנים מופיעים בווידג׳טים.",
        .widgetsPair: "חיבור",
        .widgetsPairing: "מתחבר…",
        .widgetsDisconnect: "ניתוק",
        .pairBridgeUnavailable: "הגשר לא ענה. נסה שוב בעוד רגע.",
        .sectionConnection: "חיבורים",
        .homeRelay: "חיבור דרך הממסר במחשב שלך",
        .homeRelayFooter: "כשהרשת חוסמת את טלגרם, החיבור עובר דרך הממסר במחשב שלך. כבוי: תמיד ישירות. שיחות לא עוברות דרכו.",
        .sectionRecording: "הקלטה",
        .recordWithBuiltInMic: "הקלטה במיקרופון של האייפון",
        .recordWithBuiltInMicFooter: "ברכב או עם אוזניות, הודעה קולית נקלטת במיקרופון של האייפון. כבוי: במיקרופון של הרכב.",
        .sectionMedia: "מדיה",
        .autoDownload: "הורדה אוטומטית בצ׳אטים מאושרים",
        .autoDownloadFooter: "צ׳אט מאושר מוריד מדיה לפי הרמה שלו (בוחרים בדף המידע של הצ׳אט). כבוי: תמונות בלבד.",
        .perChatFooter: "את רמת המדיה של כל צ׳אט בוחרים בדף המידע של הצ׳אט.",
        .sectionReading: "קריאה",
        .sectionAppearance: "מראה",
        .justifiedText: "יישור לשני הצדדים",
        .justifiedTextFooter: "הודעות של ארבע שורות ומעלה מיושרות לשני הצדדים, כמו בספר. כבוי: יישור רגיל.",
        .lineSpacing: "ריווח שורות",
        .lineSpacingNormal: "רגיל",
        .lineSpacingComfortable: "נוח",
        .messageFont: "גופן ההודעות",
        .fontSystem: "גופן המערכת",
        .fontAssistant: "\u{2068}Assistant\u{2069}",
        .fontHeebo: "\u{2068}Heebo\u{2069}",
        .fontRubik: "\u{2068}Rubik\u{2069}",
        .fontFrankRuhlLibre: "\u{2068}Frank Ruhl Libre\u{2069} (לטקסטים תורניים)",
        .fontWeight: "עובי הגופן",
        .weightLight: "דק",
        .weightRegular: "רגיל",
        .weightMedium: "בינוני",
        .weightSemibold: "עבה",
        .textSize: "גודל הטקסט",
        .textSizeDefault: "כמו בטלגרם",
        .bubbleWidth: "רוחב הבועות",
        .bubbleNormal: "רגיל",
        .bubbleWide: "רחב",
        .readingFooter: "הגופן, העובי והגודל חלים על ההודעות ועל שדה הכתיבה בלבד. השינוי נראה בצ׳אט שנפתח מחדש. רוחב רחב חל רק על בועות טקסט בצ׳אטים עם סוכנים ובוטים, ומשאיר פחות שורות קצרות בתשובות ארוכות.",
        .readingPreview: "בראשית ברא אלקים את השמים ואת הארץ. זו דוגמה לטקסט בהודעה.",
        .sectionRadio: "שידורי הקוקפיט",
        .radioRow: "שידורי הקוקפיט",
        .filterFooter: "המתגים כאן נוגעים לנוחות בלבד. אישור צ׳אטים, אתרים, חבילות מדבקות ובוטים נשאר ברשימה המאושרת ובבקשת אישור.",
        .mediaLevelTitle: "רמת מדיה",
        .mediaLevelTextOnly: "טקסט בלבד",
        .mediaLevelPhotos: "תמונות",
        .mediaLevelDocuments: "תמונות ומסמכים",
        .mediaLevelAll: "הכול",
        .mediaLevelDefault: "ברירת מחדל",
        .mediaLevelFooter: "הרמה חלה על הצ׳אט הזה בחשבון הזה בלבד. סרטונים מועברים נשארים לפי המקור שלהם.",
        .mediaLevelNotApproved: "הצ׳אט הזה לא אושר, ולכן הוא מציג תמונות בלבד. אפשר לבקש אישור מתוך הצ׳אט.",
        .radioTitle: "שידורי הקוקפיט",
        .radioStation: "שידורי הקוקפיט",
        .radioPlay: "הפעלה",
        .radioPause: "השהיה",
        .radioStopped: "כבוי",
        .radioConnecting: "מתחבר…",
        .radioPlaying: "משדר",
        .radioPaused: "מושהה",
        .radioFailed: "אין קשר עם השידורים. ננסה שוב בעוד רגע.",
        .radioResumeOffer: "השידורים הושהו בזמן השיחה. הקשה תמשיך אותם מהשידור החי.",
        .radioLinkSection: "קישור האזנה",
        .radioLinkPlaceholder: "הדבקת קישור האזנה",
        .radioLinkSave: "שמירה",
        .radioLinkForget: "מחיקת הקישור",
        .radioLinkSaved: "הקישור שמור במכשיר",
        .radioLinkInvalid: "זה לא קישור האזנה מאובטח מהגשר שלך.",
        .radioLinkMissing: "עדיין אין קישור האזנה מהגשר במחשב שלך.",
        .fontRow: "גופן",
        .fontRowDetail: "גופן אחד לכל האפליקציה, גם להודעות ולשדה הכתיבה. הבועה למטה מראה איך זה ייראה.",
        .separateMessageFont: "גופן שונה להודעות",
        .separateMessageFontDetail: "פועל: ההודעות ושדה הכתיבה בגופן משלהן. כבוי: הן בגופן של האפליקציה.",
        .messageFontDetail: "הגופן של ההודעות ושל שדה הכתיבה בלבד.",
        .fontWeightDetail: "כמה עבות האותיות בהודעות. דק לקריאה רכה, עבה לקריאה בשמש.",
        .textSizeDetail: "מוסיף או מקטין צעדים מעל גודל הטקסט של טלגרם, בהודעות בלבד.",
        .bubbleWidthDetail: "רחב: בועות הטקסט בצ׳אטים עם סוכנים ובוטים רחבות יותר, עם פחות שורות קצרות.",
        .lineSpacingDetail: "נוח: יותר אוויר בין השורות בהודעות ארוכות.",
        .radioRowDetail: "השידור החי של הצוות. הקשה פותחת את מסך השידורים.",
        .additionsRowDetail: "כל תוספת על טלגרם במקום אחד, עם הסבר, תצוגה ומתג.",
        .radioLinkFooter: "את הקישור מקבלים מכפתור ההאזנה בגשר במחשב שלך. הוא נשמר רק במכשיר הזה.",
    ]

    static func t(_ key: Key) -> String {
        if key == .homeRelayFooter, HarnessgramHomeRelay.host == nil { return HarnessgramHomeRelay.missingConfigurationMessage }
        return hebrew[key] ?? key.rawValue
    }
}
