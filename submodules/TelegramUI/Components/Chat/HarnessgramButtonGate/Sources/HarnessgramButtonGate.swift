import Foundation
import TelegramCore
import HarnessgramSettings
import HarnessgramAgent

/// Harnessgram: every bot button (inline buttons, the pinned-message button, the reply keyboard) passes
/// here before it acts. A sensitive one asks the owner for Face ID (or the passcode) first; on success the
/// same press is replayed once through `proceed`, on failure or cancel nothing is sent.
public enum HarnessgramButtonGate {
    public static func kind(of action: ReplyMarkupButtonAction) -> HarnessgramSensitiveAction.ButtonKind {
        switch action {
        case let .callback(_, data):
            return .callback(data: data.makeData())
        case .text:
            return .text
        case .urlAuth:
            return .urlAuth
        case .payment:
            return .payment
        case .openWebApp, .openWebView:
            return .webApp
        default:
            return .other
        }
    }

    /// True when the press may go ahead now. False when it waits for the owner's confirmation.
    public static func check(button: ReplyMarkupButton, message: EngineRawMessage?, proceed: @escaping () -> Void) -> Bool {
        guard HarnessgramSettings.shared.confirmSensitiveButtons else {
            return true
        }
        let kind = HarnessgramButtonGate.kind(of: button.action)
        let bot = HarnessgramButtonGate.bot(of: message)
        guard HarnessgramSensitiveAction.requiresConfirmation(kind: kind, buttonTitle: button.title, messageText: message?.text ?? "", fromBot: bot.isBot, botIsBridge: HarnessgramAgentChat.isBridgeBot(userId: bot.userId)) else {
            return true
        }
        let key = HarnessgramButtonGate.key(button: button, message: message)
        return HarnessgramOwnerConfirmation.shared.gate(key: key, reason: HarnessgramOwnerConfirmation.reason(buttonTitle: button.title), proceed: proceed)
    }

    /// The bot behind a message's buttons: its author, or the bot it was sent via (an inline bot's buttons sit
    /// on a message the owner's contact sent). A via-bot whose peer is unknown still counts as a bot, with no
    /// user id, so it gets the stricter rules of a bot outside the marker contract (a via-bot message is
    /// never the bridge's own).
    static func bot(of message: EngineRawMessage?) -> (isBot: Bool, userId: Int64?) {
        guard let message else {
            return (false, nil)
        }
        if let author = message.author as? TelegramUser, author.botInfo != nil {
            return (true, author.id.id._internalGetInt64Value())
        }
        if message.attributes.contains(where: { $0 is InlineBotMessageAttribute }) {
            // Sent via a bot by someone else: never the bridge's own message, so no marker exemption.
            return (true, nil)
        }
        return (false, nil)
    }

    /// One key per press: the message (or the reply keyboard), and the button's title and payload.
    static func key(button: ReplyMarkupButton, message: EngineRawMessage?) -> String {
        let messageId = message.flatMap { "\($0.id.peerId.toInt64()):\($0.id.namespace):\($0.id.id)" } ?? "keyboard"
        var payload = Data(button.title.utf8)
        switch button.action {
        case let .callback(_, data):
            payload.append(0)
            payload.append(data.makeData())
        case let .urlAuth(url, buttonId):
            payload.append(Data(("|auth|\(buttonId)|" + url).utf8))
        case let .openWebView(url, _):
            payload.append(Data(("|web|" + url).utf8))
        default:
            break
        }
        return HarnessgramOwnerConfirmation.key(messageId: messageId, callbackData: payload)
    }
}
