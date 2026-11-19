import Foundation
import HarnessgramSettings

/// The filter page's and the additions page's copy (Hebrew, one plain line each). Build 19.
enum HarnessgramFilterStrings {
    static let filterTitle = "הסינון"
    static let filterIntro = "כל כלל בסינון מוסבר כאן. אפשר להדליק כללים; כיבוי כלל אפשרי רק דרך הוועדה."
    static let committeeOnly = "כיבוי כללי הסינון אפשרי רק דרך הוועדה."
    static let locked = "נעול על ידי הוועדה"
    static let lockedExplanation = "הסינון נעול על ידי הוועדה. אפשר לשנות אותו רק במסמך חדש מהוועדה."
    static let offWarningTitle = "לכבות את הכלל?"
    static let offConfirm = "כיבוי"
    static let cancel = "ביטול"
    static let offReason = "כיבוי כלל בסינון"
    static let additionsTitle = "מה \u{2068}HarnessGram\u{2069} מוסיף"
    static let additionsIntro = "כל מה שהאפליקציה מוסיפה על טלגרם, עם הסבר קצר ומתג או קישור."
    static let rulesOn = "כללים פועלים"
    static let filterRowDetail = "כל כלל בסינון, עם הסבר ומתג."

    static func title(_ rule: HarnessgramFilterRule) -> String {
        switch rule {
        case .approvedChats: return "רק קבוצות, ערוצים וקהילות מאושרים"
        case .contactsOnly: return "צ׳אטים פרטיים רק עם אנשי קשר"
        case .mediaFilter: return "סינון מדיה"
        case .mediaSpoilers: return "הסתרת מדיה שסומנה כספוילר"
        case .sensitiveContent: return "הסתרת תוכן רגיש"
        case .stickerPacks: return "מדבקות רק מחבילות מאושרות"
        case .linkPreviews: return "תצוגה מקדימה רק לאתרים מאושרים"
        case .linksOutside: return "קישורים נפתחים בספארי"
        case .search: return "בלי חיפוש כללי"
        case .stories: return "בלי סטוריז"
        case .adMedia: return "פרסומות בטקסט בלבד"
        case .otherBotWidgets: return "כרטיסים רק מהגשר"
        }
    }

    static func explanation(_ rule: HarnessgramFilterRule) -> String {
        switch rule {
        case .approvedChats: return "צ׳אטים שלא אושרו מוסתרים. ניסיון להצטרף לקבוצה, לערוץ או לקהילה כאלה נשמר כבקשת אישור לוועדה. אפשר לפתוח צ׳אטים משלך."
        case .contactsOnly: return "הודעה ממי שאינו איש קשר מחכה ברשימת הבקשות."
        case .mediaFilter: return "כל צ׳אט מציג מדיה לפי הרמה שלו. צ׳אט שלא אושר מציג תמונות בלבד."
        case .mediaSpoilers: return "תמונות וסרטונים שסומנו כספוילר מוסתרים גם בצ׳אטים מאושרים. לחיצה לא תחשוף אותם. הכלל אינו חל על מדיה ששלחת בעצמך או שנמצאת במכשיר."
        case .sensitiveContent: return "תוכן שסומן כרגיש מוסתר תמיד, גם אם בטלגרם מותר."
        case .stickerPacks: return "מדבקות ואימוג׳י מחבילות שלא אושרו מוסתרים."
        case .linkPreviews: return "קישור לאתר שלא אושר מופיע בלי תצוגה מקדימה."
        case .linksOutside: return "אין דפדפן בתוך האפליקציה, תצוגה מהירה או נגנים משובצים."
        case .search: return "אין חיפוש בכל טלגרם, חיפוש גיפים או חיפוש מדבקות ברשת."
        case .stories: return "סטוריז לא מוצגים ולא נטענים."
        case .adMedia: return "הודעות ממומנות מוצגות בלי תמונות וסרטונים."
        case .otherBotWidgets: return "כרטיסים אינטראקטיביים של בוטים אחרים מוסתרים."
        }
    }

    /// What turning the rule off lets in (the short warning before Face ID).
    static func offWarning(_ rule: HarnessgramFilterRule) -> String {
        switch rule {
        case .approvedChats: return "יוצגו גם קבוצות, ערוצים וקהילות שלא אושרו, ואפשר יהיה להצטרף אליהם כשהיעד מזוהה."
        case .contactsOnly: return "כל מי שכותב לך יופיע ברשימת הצ׳אטים."
        case .mediaFilter: return "תמונות, סרטונים וקבצים יוצגו בכל הצ׳אטים."
        case .mediaSpoilers: return "לחיצה תוכל לחשוף מדיה שסומנה כספוילר אם היא מותרת לפי שאר הכללים."
        case .sensitiveContent: return "תוכן רגיש יוצג לפי ההגדרה של טלגרם."
        case .stickerPacks: return "כל המדבקות והאימוג׳י יוצגו."
        case .linkPreviews: return "תצוגה מקדימה תופיע לכל אתר."
        case .linksOutside: return "קישורים ייפתחו גם בתוך האפליקציה."
        case .search: return "החיפוש יראה תוצאות מכל טלגרם."
        case .stories: return "סטוריז יוצגו."
        case .adMedia: return "פרסומות יוצגו עם תמונות וסרטונים."
        case .otherBotWidgets: return "כרטיסים של כל בוט יוצגו."
        }
    }
}
