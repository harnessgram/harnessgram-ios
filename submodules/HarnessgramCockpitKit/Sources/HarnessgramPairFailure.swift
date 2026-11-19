import Foundation

/// Why connecting the widgets to the bridge failed, step by step (build 18 fix): each step of getting the Cockpit
/// login and reading the panel once has its own reason, so the owner sees what is actually wrong instead of
/// "the bridge did not answer".
public enum HarnessgramPairFailure: String, CaseIterable, Sendable {
    /// Telegram did not find the bridge bot by its username (or it is not a bot).
    case botNotFound
    /// The username now leads to another bot than the one pinned: it waits for the owner's confirmation.
    case botChanged
    /// The bot has no web app (no menu button web app and no Main App) for this account.
    case noWebApp
    /// The bot's web app is not an authorized HTTPS origin: the login is never sent there.
    case webAppElsewhere
    /// Telegram refused to open the bot's web app.
    case loginRefused
    /// Telegram opened it but the signed login was missing or malformed.
    case loginUnreadable
    /// Telegram did not answer in time.
    case timedOut
    /// The panel could not be reached (network, Tailscale or the panel itself).
    case panelUnreachable
    /// The panel answered but did not accept the login.
    case panelRefused
    /// The panel answered with something the app does not understand.
    case panelBadAnswer
    /// The panel asked the app to wait a little (busy or rate limited); the app tries again by itself.
    case panelBusy
    /// The app could not save the login on the phone.
    case storage

    /// The text for the owner (Hebrew, short, says what to do).
    public var text: String {
        switch self {
        case .botNotFound:
            return "לא הוגדר או לא נמצא בוט הגשר שלך. כדאי לבדוק את הגדרות החיבור ושהבוט פעיל."
        case .botChanged:
            return "בוט הגשר התחלף. צריך לאשר את הבוט החדש בהגדרות, ואז לחבר שוב."
        case .noWebApp:
            return "לבוט הגשר אין לוח בקרה פתוח לחשבון הזה. צריך להגדיר לו כפתור תפריט או אפליקציה ראשית."
        case .webAppElsewhere:
            return "כתובת הגשר במחשב שלך חסרה או אינה מאושרת בהגדרות החיבור. הכניסה לא נשלחה."
        case .loginRefused:
            return "טלגרם לא פתח את לוח הבקרה של הגשר. נסה שוב בעוד רגע."
        case .loginUnreadable:
            return "טלגרם פתח את לוח הבקרה בלי כניסה חתומה. נסה שוב בעוד רגע."
        case .timedOut:
            return "טלגרם לא ענה בזמן. כדאי לבדוק את החיבור ולנסות שוב."
        case .panelUnreachable:
            return "הגשר במחשב שלך לא זמין. כדאי לבדוק שהמחשב דולק ושהחיבור לרשת שלו פעיל."
        case .panelRefused:
            return "לוח הבקרה לא קיבל את הכניסה. כדאי לבדוק שהחשבון הזה הוא החשבון של בעל הגשר."
        case .panelBadAnswer:
            return "לוח הבקרה ענה תשובה לא צפויה. כדאי לעדכן את הגשר."
        case .panelBusy:
            return "הגשר עמוס כרגע. האפליקציה תנסה שוב בעוד רגע."
        case .storage:
            return "לא ניתן לשמור את החיבור בטלפון. נסה שוב אחרי פתיחת הנעילה."
        }
    }

    /// The panel's answer to the first read, as a failure (nil when it read fine).
    public static func fromPanel(status: Int?) -> HarnessgramPairFailure? {
        guard let status else {
            return .panelUnreachable
        }
        switch status {
        case 200:
            return nil
        case 401, 403:
            return .panelRefused
        case 404:
            return .panelBadAnswer
        case 500...599:
            return .panelUnreachable
        default:
            return .panelBadAnswer
        }
    }
}
