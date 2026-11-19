import Foundation

/// "מה חדש" (coordinator, build 18 fix): once, on the first launch of each new build, a short sheet of what changed
/// and where to find it. The lines are kept here per build number; a build without lines shows nothing.
public enum HarnessgramWhatsNew {
    public static let title = "עדכוני נתיב"
    public static let button = "הבנתי"

    /// Build number -> 1 to 5 plain Hebrew lines.
    public static let lines: [String: [String]] = [
        "19": [
            "צבעי הבית, מסך הרדיו, הדפיקה בדלת ורשימת ההמתנה פועלים עכשיו מההתחלה.",
            "אפשר לכבות כל אחד מהם בהגדרות, בתוך \u{2068}HarnessGram\u{2069}, בחלק \"תצוגה מקדימה: הבית\".",
            "מסך הרדיו החדש נפתח מכפתור הרדיו, ובזמן ההאזנה פס הנגינה למעלה מראה מה מתנגן.",
            "חיבור הווידג׳טים לגשר אומר עכשיו מה בדיוק לא עבד, אם משהו לא עבד.",
        ],
        "34": [
            "לשונית הקוקפיט נפתחת עכשיו בקוקפיט החדש של האפליקציה: מה מחכה לך, החלטות וכפתור לקוקפיט המלא.",
            "בכל החלטה רואים את כל ההקשר, תמונות וקישורים. אפשר לכתוב לסוכן תגובה במילים שלך, והיא לא מאשרת דבר.",
            "אפשר לשאול את \u{2068}Siri\u{2069}: \"מה מחכה לי ב־\u{2068}HarnessGram\u{2069}\". עובד גם ברכב, בלי פרטים רגישים.",
            "סינון: מדיה עם ספוילר נשארת מוסתרת, והצטרפות לערוץ או לקבוצה חדשים מחכה לאישור הוועדה.",
            "הווידג׳טים מתעדכנים כמה דקות אחרי הודעה מהגשר.",
        ],
        "21": [
            "הסינון: אפשר רק להדליק כללים; כיבוי רק דרך הוועדה.",
        ],
        "23": [
            "לשונית קוקפיט ליד הצ׳אטים: אישורי המראה, לוח טיסה, שידורי הקוקפיט וכפתור לקוקפיט המלא. מספר אדום מראה מה מחכה לך.",
            "הרדיו נקרא עכשיו שידורי הקוקפיט, עם המגדל בשקיעה במסך הנעילה.",
            "גופן אחד לכל האפליקציה, גם להודעות. אם צריך פתיחה מחדש, יש כפתור שעושה את זה.",
            "בהגדרות, בתוך \u{2068}HarnessGram\u{2069}, לכל שורה יש סמל, הסבר ותצוגה קטנה.",
            "ערכות הנושא קריאות בכל מקום, גם בשורות לחוצות ובתאריכים בצ׳אט.",
        ],
        "22": [
            "גופן האפליקציה: גופן עברי לבחירה לכל האפליקציה, בהגדרות, בתוך \u{2068}HarnessGram\u{2069}, בחלק \"מראה\". הגופן מתחלף בפתיחה הבאה.",
            "ערכת נושא: ארבע ערכות צבעים בהשראת תא הטייס, באותו חלק. הבחירה חלה מיד, ו\"ללא\" מחזיר את ערכת הנושא של טלגרם.",
            "כרטיסי המשימות במסך הנעילה קריאים עכשיו גם על רקע בהיר.",
            "בלוח של \u{2068}CarPlay\u{2069} כרטיס המשימה בהיר, ומראה את שם המשימה, השלב והאחוז.",
        ],
    ]

    static let seenKey = "HarnessgramSettings.whatsNew.seenBuild"

    /// The lines to show for `build`, or nil when there are none or they were shown already.
    public static func pending(build: String?, seen: String?) -> [String]? {
        guard let build, build != seen, let lines = HarnessgramWhatsNew.lines[build], !lines.isEmpty else {
            return nil
        }
        return lines
    }

    /// The lines for this app's build, once: the build is marked as seen as soon as they are handed out.
    public static func takePending(defaults: UserDefaults = HarnessgramSettings.appGroupDefaults(), bundle: Bundle = .main) -> [String]? {
        let build = HarnessgramWhatsNew.demoBuild() ?? (bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String)
        guard let lines = HarnessgramWhatsNew.pending(build: build, seen: defaults.string(forKey: HarnessgramWhatsNew.seenKey)) else {
            return nil
        }
        defaults.set(build, forKey: HarnessgramWhatsNew.seenKey)
        return lines
    }

    /// Screenshots: the simulator build is always build 1, so HARNESSGRAM_DEMO_BUILD names the build to show.
    static func demoBuild() -> String? {
        #if targetEnvironment(simulator)
        return ProcessInfo.processInfo.environment["HARNESSGRAM_DEMO_BUILD"]
        #else
        return nil
        #endif
    }
}
