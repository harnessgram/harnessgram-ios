import Foundation
import Postbox
import HarnessgramAgent

/// Harnessgram (build 18): Telegram's chat-list widget shows the bridge's chats only (HarnessgramChatWidget). These
/// helpers map Postbox peers for that rule, for the intents extension (Edit Widget, defaults) and the widget extension
/// (what a saved widget shows).
public func harnessgramChatWidgetKind(_ peer: Peer) -> HarnessgramChatWidget.ChatKind {
    if let user = peer as? TelegramUser {
        return .user(id: user.id.id._internalGetInt64Value(), isBot: user.botInfo != nil)
    }
    if let channel = peer as? TelegramChannel {
        return .channel(id: channel.id.id._internalGetInt64Value(), isForum: channel.flags.contains(.isForum))
    }
    return .other
}

/// The allowed peers among `peers`, in order, each once, at most `limit`.
public func harnessgramChatWidgetAllowedPeers(_ peers: [Peer], limit: Int = HarnessgramChatWidget.limit, groups: HarnessgramAgentGroups = HarnessgramAgentGroups.current(), identity: HarnessgramBridgeIdentity = .shared) -> [Peer] {
    let usable = peers.filter { !($0 is TelegramSecretChat) && !$0.isDeleted }
    let byId = Dictionary(usable.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    let ids = HarnessgramChatWidget.filter(usable.map { ($0.id, harnessgramChatWidgetKind($0)) }, groups: groups, identity: identity, limit: limit)
    return ids.compactMap { byId[$0] }
}
