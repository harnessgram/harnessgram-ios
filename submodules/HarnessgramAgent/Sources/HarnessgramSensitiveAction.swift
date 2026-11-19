import Foundation

/// Decides whether pressing a bot's button needs the owner's Face ID (or passcode) first.
///
/// The bridge integration contract (docs/harnessgram-local-config.md) treats these areas as sensitive: money, deletion, publication, app stores, production, accounts and credentials.
/// Over-matching only costs one Face ID. A refusal ("No", "Cancel", "לא", "ביטול") passes only when its
/// callback data is a plain refusal too and the card is not marked sensitive.
public enum HarnessgramSensitiveAction {
    /// The bridge marks a card about a sensitive action with this icon (see docs/harnessgram-local-config.md).
    public static let sensitiveCardMarker = "\u{1F512}"

    // MARK: Marker contract (build 13; the bridge, by its pinned user id since build 14)
    //
    // A bot that follows the contract marks every button that performs a sensitive action, so the app never
    // has to guess from wording:
    // - an inline callback button: its callback data starts with the ASCII bytes "hg!" (for example
    //   "hg!deploy:42"); the bot strips the prefix when it reads the callback;
    // - a button without callback data (reply keyboard, inline text, web app): its title starts with "🔐"
    //   (U+1F510), shown as is, so the owner sees the lock too.
    // A marked button always asks for Face ID or the passcode, whatever its title (a marked "No" asks too).
    // Unmarked buttons still pass through the word rules below, so a forgotten marker over-asks rather than
    // under-asks only where the wording shows it.

    /// Callback data prefix of a marked button.
    public static let callbackMarker: [UInt8] = Array("hg!".utf8)
    /// Title prefix of a marked button without callback data.
    public static let titleMarker = "\u{1F510}"
    /// Bots that follow the marker contract (lower-cased usernames without "@"): the Harnessgram bridge.
    public static var markerBotUsernames: Set<String> {
        return HarnessgramAgentChat.bridgeBotUsernames
    }

    /// The button carries the contract's marker.
    public static func isMarked(kind: ButtonKind, buttonTitle: String?) -> Bool {
        if let buttonTitle, buttonTitle.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix(HarnessgramSensitiveAction.titleMarker) {
            return true
        }
        if case let .callback(data) = kind {
            return data.starts(with: HarnessgramSensitiveAction.callbackMarker)
        }
        return false
    }

    /// What the button does when pressed.
    public enum ButtonKind: Equatable {
        /// Sends its callback data to the bot.
        case callback(data: Data)
        /// Sends its own title as a message (reply keyboard or inline text button).
        case text
        /// Logs in to a website with the Telegram account.
        case urlAuth
        /// Opens a payment.
        case payment
        /// Opens a bot's web app or web view, which can act for the owner.
        case webApp
        /// Anything else (links, location, contacts, ...): not gated here.
        case other
    }

    /// - Parameters:
    ///   - kind: what the button does.
    ///   - buttonTitle: the pressed button's text, when known.
    ///   - messageText: the text of the message that carries the button ("" for a reply keyboard).
    ///   - fromBot: the message was sent by a bot (the bridge is one).
    ///   - botIsBridge: the bot behind the buttons is the pinned bridge bot (HarnessgramBridgeIdentity).
    ///     Any other bot (outside the marker contract) gets one more rule: any callback button under a message that names
    ///     money, deletion or publication asks (an opaque "action:42" titled "Continue" cannot slip through).
    public static func requiresConfirmation(kind: ButtonKind, buttonTitle: String?, messageText: String, fromBot: Bool, botIsBridge: Bool = false) -> Bool {
        if HarnessgramSensitiveAction.isMarked(kind: kind, buttonTitle: buttonTitle) {
            return true
        }
        switch kind {
        case .urlAuth, .payment, .webApp:
            // A website login, a payment or a web app acting for the owner: always confirmed.
            return true
        case .text:
            // The text is sent as the owner's own words: a sensitive one asks, and so does a yes under a
            // question about a sensitive action or a card marked sensitive.
            if HarnessgramSensitiveAction.namesSensitiveAction(buttonTitle ?? "") {
                return true
            }
            if HarnessgramSensitiveAction.isApproval(title: buttonTitle, dataWords: "") {
                return messageText.contains(HarnessgramSensitiveAction.sensitiveCardMarker) || HarnessgramSensitiveAction.namesSensitiveAction(messageText)
            }
            return false
        case .other:
            return false
        case let .callback(data):
            guard fromBot else {
                return false
            }
            let dataWords = HarnessgramSensitiveAction.splitIdentifiers(String(decoding: data, as: UTF8.self))
            let sensitiveData = HarnessgramSensitiveAction.namesSensitiveAction(dataWords)
            let markedCard = messageText.contains(HarnessgramSensitiveAction.sensitiveCardMarker)
            if let buttonTitle, HarnessgramSensitiveAction.isRefusal(buttonTitle), HarnessgramSensitiveAction.isPlainRefusalData(dataWords), !sensitiveData, !markedCard {
                return false
            }
            if sensitiveData || markedCard {
                return true
            }
            if !botIsBridge, HarnessgramSensitiveAction.namesMoneyDeletionOrPublication(messageText) {
                // A bot that does not mark its buttons: under a message about money, deletion or publication
                // every button but a plain refusal asks, whatever its title or data say.
                return true
            }
            if let buttonTitle, HarnessgramSensitiveAction.namesSensitiveAction(buttonTitle) {
                return true
            }
            // A yes approves the action its question names (the bridge's "✅ כן", say:yes).
            if HarnessgramSensitiveAction.isApproval(title: buttonTitle, dataWords: dataWords), HarnessgramSensitiveAction.namesSensitiveAction(messageText) {
                return true
            }
            return false
        }
    }

    /// The button says yes: its title starts with ✅/✔ or a yes word, or its data carries yes/approve/confirm.
    public static func isApproval(title: String?, dataWords: String) -> Bool {
        if let title {
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            if let first = trimmed.unicodeScalars.first, first.value == 0x2705 || first.value == 0x2714 || first.value == 0x2611 {
                return true
            }
            if let firstWord = HarnessgramSensitiveAction.bareWords(trimmed).split(separator: " ").first, HarnessgramSensitiveAction.approvalWords.contains(String(firstWord)) {
                return true
            }
        }
        let words = HarnessgramSensitiveAction.bareWords(dataWords).split(separator: " ").map(String.init)
        return words.contains(where: { HarnessgramSensitiveAction.approvalDataWords.contains($0) })
    }

    /// Callback data that only says no or back ("say:no", "close:no", "more:back"), with nothing else that acts.
    static func isPlainRefusalData(_ dataWords: String) -> Bool {
        let words = HarnessgramSensitiveAction.bareWords(dataWords).split(separator: " ").map(String.init)
        return words.contains(where: { HarnessgramSensitiveAction.refusalDataWords.contains($0) }) && !words.contains(where: { HarnessgramSensitiveAction.approvalDataWords.contains($0) })
    }

    private static let approvalWords: Set<String> = ["yes", "approve", "approved", "confirm", "ok", "okay", "כן", "אישור", "אשר", "מאשר", "מאשרת", "אישרתי", "בטח"]
    private static let approvalDataWords: Set<String> = ["yes", "approve", "approved", "confirm", "confirmed", "ok", "accept", "allow", "grant"]
    private static let refusalDataWords: Set<String> = ["no", "cancel", "back", "dismiss", "close", "skip", "later", "deny", "reject", "decline", "never", "abort"]

    /// The text names a sensitive action (English or Hebrew).
    public static func namesSensitiveAction(_ text: String) -> Bool {
        let range = NSRange(text.startIndex..., in: text)
        for expression in HarnessgramSensitiveAction.expressions {
            if expression.firstMatch(in: text, options: [], range: range) != nil {
                return true
            }
        }
        return false
    }

    /// The text names money, a deletion or a publication (the subset of `namesSensitiveAction` that makes
    /// every button of an unmarked bot's message ask).
    public static func namesMoneyDeletionOrPublication(_ text: String) -> Bool {
        let range = NSRange(text.startIndex..., in: text)
        for expression in HarnessgramSensitiveAction.harmExpressions {
            if expression.firstMatch(in: text, options: [], range: range) != nil {
                return true
            }
        }
        return false
    }

    private static let harmEnglishPattern = "\\b(?:pay|pays|paid|payment|payments|purchas\\w*|buy\\w*|billing|charge[sd]?|invoice\\w*|subscri\\w+|refund\\w*|money|price\\w*|credit ?cards?|"
        + "delet\\w*|remov\\w*|drop (?:table|database|schema)|wipe\\w*|erase\\w*|destroy\\w*|truncat\\w*|purge\\w*|"
        + "publish\\w*|public(?:ly)?|announce\\w*|broadcast\\w*)\\b"

    private static let harmHebrewWords = [
        "תשלום", "תשלומים", "לשלם", "כסף", "כספים", "מחיר", "מחירים", "רכישה", "רכישת", "לרכוש", "קנייה", "קניה", "לקנות", "חיוב", "לחייב", "מנוי", "החזר",
        "מחיקה", "מחיקת", "למחוק", "מחק", "מחקו", "נמחק", "תמחק", "הסרה", "הסרת", "להסיר", "הסר", "הסירו",
        "פרסום", "פרסומים", "לפרסם", "פרסם", "פרסמו", "תפרסם", "ציבורי", "ציבורית", "הפצה", "להפיץ",
    ]

    private static let harmExpressions: [NSRegularExpression] = {
        var result: [NSRegularExpression] = []
        if let english = try? NSRegularExpression(pattern: HarnessgramSensitiveAction.harmEnglishPattern, options: [.caseInsensitive]) {
            result.append(english)
        }
        let hebrew = "(?<!\\p{L})[\u{05D5}\u{05D4}\u{05D1}\u{05DC}\u{05DE}\u{05E9}\u{05DB}]{0,3}(?:" + HarnessgramSensitiveAction.harmHebrewWords.joined(separator: "|") + ")(?!\\p{L})"
        if let hebrewExpression = try? NSRegularExpression(pattern: hebrew, options: []) {
            result.append(hebrewExpression)
        }
        if let amounts = try? NSRegularExpression(pattern: "\u{20AA}|\\$\\s?\\d", options: []) {
            result.append(amounts)
        }
        return result
    }()

    /// The whole button says no: refusing or going back never needs confirmation.
    public static func isRefusal(_ title: String) -> Bool {
        return HarnessgramSensitiveAction.refusals.contains(HarnessgramSensitiveAction.bareWords(title))
    }

    /// Callback data packs words ("deploy_prod", "rm:delete", "confirmDelete", "doPublish2"); spaced out at
    /// separators, lower-to-upper case changes and letter-digit changes, word rules apply.
    static func splitIdentifiers(_ value: String) -> String {
        var result = ""
        var previous: Unicode.Scalar?
        for scalar in value.unicodeScalars {
            let isDigit = (0x30...0x39).contains(scalar.value)
            let isLetter = scalar.properties.isAlphabetic
            if isLetter || isDigit || scalar == "$" || scalar == "\u{20AA}" {
                if let previous {
                    let previousDigit = (0x30...0x39).contains(previous.value)
                    let previousLetter = previous.properties.isAlphabetic
                    let caseChange = previous.properties.isLowercase && scalar.properties.isUppercase
                    let kindChange = (previousDigit && isLetter) || (previousLetter && isDigit)
                    if caseChange || kindChange {
                        result.append(" ")
                    }
                }
                result.unicodeScalars.append(scalar)
                previous = scalar
            } else {
                result.append(" ")
                previous = nil
            }
        }
        return result
    }

    /// Letters, digits and single spaces only, lower-cased: "❌ לא" -> "לא", "« Back" -> "back".
    static func bareWords(_ value: String) -> String {
        var result = ""
        var pendingSpace = false
        for scalar in value.unicodeScalars {
            if scalar.properties.isAlphabetic || (0x30...0x39).contains(scalar.value) {
                if pendingSpace && !result.isEmpty {
                    result.append(" ")
                }
                pendingSpace = false
                result.unicodeScalars.append(scalar)
            } else if scalar.properties.isWhitespace || scalar == "-" {
                pendingSpace = true
            }
        }
        return result.lowercased()
    }

    private static let refusals: Set<String> = [
        "no", "nope", "cancel", "back", "go back", "dismiss", "close", "skip", "not now", "later", "deny", "reject", "decline", "never mind", "keep", "stop",
        "לא", "לא תודה", "ביטול", "בטל", "חזרה", "חזור", "סגור", "סגירה", "דלג", "לא עכשיו", "אחר כך", "אחרכך", "דחה", "דחייה", "סרב", "עצור", "השאר",
    ]

    private static let englishPattern = "\\b(?:pay|pays|paid|payment|payments|purchas\\w*|buy\\w*|billing|charge[sd]?|invoice\\w*|subscri\\w+|refund\\w*|money|price\\w*|credit ?cards?|"
        + "prod|production|promot\\w+|go[- ]?live|release\\w*|deploy\\w*|roll ?out\\w*|canary|"
        + "delet\\w*|remov\\w*|drop (?:table|database|schema)|wipe\\w*|erase\\w*|destroy\\w*|truncat\\w*|purge\\w*|force[- ]?push\\w*|reset --hard|rm -r\\w*|"
        + "publish\\w*|public(?:ly)?|announce\\w*|broadcast\\w*|send (?:an? )?(?:e-?mails?|messages?|sms)|whatsapp|"
        + "app ?store|testflight|play (?:store|console)|store submission|submit for review|app review|"
        + "login|log ?in|sign[- ]?in|password\\w*|passwd|credential\\w*|secret\\w*|api[- ]?keys?|tokens?|oauth|2fa|accounts?)\\b"

    /// Hebrew words with up to three one-letter prefixes (ו ה ב ל מ ש כ), whole words only: "מחק" is a
    /// deletion, "מחקר" (research) is not.
    private static let hebrewWords = [
        // money
        "תשלום", "תשלומים", "לשלם", "כסף", "כספים", "מחיר", "מחירים", "רכישה", "רכישת", "לרכוש", "קנייה", "קניה", "לקנות", "חיוב", "לחייב", "מנוי", "החזר",
        // deletion
        "מחיקה", "מחיקת", "למחוק", "מחק", "מחקו", "נמחק", "תמחק", "הסרה", "הסרת", "להסיר", "הסר", "הסירו",
        // publication
        "פרסום", "פרסומים", "לפרסם", "פרסם", "פרסמו", "תפרסם", "ציבורי", "ציבורית", "הפצה", "להפיץ",
        // production and stores
        "פרודקשן", "ייצור", "לאוויר", "פריסה", "לפרוס", "שחרור", "חנות", "אפסטור", "טסטפלייט",
        // accounts and credentials
        "סיסמה", "סיסמא", "סיסמאות", "חשבון", "חשבונות", "הרשאה", "הרשאות", "התחברות", "להתחבר", "טוקן",
    ]

    private static let expressions: [NSRegularExpression] = {
        var result: [NSRegularExpression] = []
        if let english = try? NSRegularExpression(pattern: HarnessgramSensitiveAction.englishPattern, options: [.caseInsensitive]) {
            result.append(english)
        }
        let hebrew = "(?<!\\p{L})[\u{05D5}\u{05D4}\u{05D1}\u{05DC}\u{05DE}\u{05E9}\u{05DB}]{0,3}(?:" + HarnessgramSensitiveAction.hebrewWords.joined(separator: "|") + ")(?!\\p{L})"
        if let hebrewExpression = try? NSRegularExpression(pattern: hebrew, options: []) {
            result.append(hebrewExpression)
        }
        // Amounts: a shekel sign anywhere, or a dollar sign before a number.
        if let amounts = try? NSRegularExpression(pattern: "\u{20AA}|\\$\\s?\\d", options: []) {
            result.append(amounts)
        }
        return result
    }()
}
