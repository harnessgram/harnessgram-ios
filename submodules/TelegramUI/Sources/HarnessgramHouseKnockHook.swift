import Foundation
import TelegramCore
import AccountContext
import HarnessgramSettings
import HarnessgramAgent
import HarnessgramHouseCore
import HarnessgramHouseUI

/// Harnessgram House (plan step 3): the in-app notification. ApplicationContext calls this just before it would show
/// Telegram's banner for new messages; true means the House took over (the knock sheet) and no banner is shown. Lane D owns
/// the body.
///
/// With `.knock` off, and for every message that is not the bridge bot's own question in its own agent chats, this
/// returns false and nothing changes. The rule is `HouseKnockRule`: the pinned bridge bot (by its user id, never its
/// username), not a forward, not sent through another bot, in the bot's private chat or an agent group's topic, and the
/// message carries inline buttons or a bridge widget. The sheet itself, the Cockpit lookup and the ledger of decisions
/// that already knocked are in HarnessgramHouseUI (`HouseKnockCenter`).
func harnessgramHouseKnockIntercept(context: AccountContext, messages: [EngineRawMessage]) -> Bool {
    guard HarnessgramSettings.shared.houseFeature(.knock), let message = messages.first else {
        return false
    }
    let author = message.author as? TelegramUser
    let isBot = author?.botInfo != nil
    let authorId = author.map { $0.id.id._internalGetInt64Value() }
    let peerId = message.id.peerId
    var isInAgentChat = false
    var chatTitle = ""
    var openRoomLink: String?
    if let author, isBot, peerId == author.id {
        // The bot's private chat with the owner.
        isInAgentChat = true
        chatTitle = author.firstName ?? author.addressName ?? ""
        if let username = author.addressName, !username.isEmpty {
            openRoomLink = "tg://resolve?domain=" + username
        }
    } else if let channel = message.peers[peerId] as? TelegramChannel {
        let kind = HarnessgramAgentChat.Kind(isBotPrivateChat: false, channelId: channel.id.id._internalGetInt64Value(), isForum: channel.flags.contains(.isForum))
        isInAgentChat = HarnessgramAgentChat.isAgentChat(kind, groups: HarnessgramAgentGroups.current())
        chatTitle = channel.title
        if let threadId = message.threadId {
            openRoomLink = "tg://privatepost?channel=\(channel.id.id._internalGetInt64Value())&thread=\(threadId)"
        }
    }
    let asksQuestion = message.media.contains(where: { $0 is TelegramMediaWidget }) || message.attributes.contains(where: { attribute in
        if let markup = attribute as? ReplyMarkupMessageAttribute {
            return markup.flags.contains(.inline) && !markup.rows.isEmpty
        }
        return false
    })
    let facts = HouseKnockRule.MessageFacts(
        authorIsPinnedBridgeBot: isBot && HarnessgramAgentChat.isBridgeBot(userId: authorId),
        isForward: message.forwardInfo != nil,
        isViaBot: message.attributes.contains(where: { $0 is InlineBotMessageAttribute }),
        isInAgentChat: isInAgentChat,
        asksQuestion: asksQuestion
    )
    guard HouseKnockRule.mayKnock(facts) else {
        return false
    }
    let key = "\(peerId.toInt64()):\(message.id.namespace):\(message.id.id)"
    HouseKnockCenter.shared.poke(context: context, message: HouseKnockMessage(key: key, text: message.text, chatTitle: chatTitle, openRoomLink: openRoomLink))
    return true
}
