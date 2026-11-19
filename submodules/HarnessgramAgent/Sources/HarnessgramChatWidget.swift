import Foundation

/// Telegram's chat-list home-screen widget in Harnessgram (build 18, owner decision 15.11): it may show only the
/// bridge's own chats, the agent forum groups (HarnessgramAgentGroups) and the bridge bot's private chat (by the
/// panel-pinned bot id, HarnessgramBridgeIdentity; nothing before the pin). The same rule filters what Edit Widget offers,
/// the defaults, and what a saved widget shows: a saved chat that is no longer allowed is dropped, never shown.
public enum HarnessgramChatWidget {
    /// A chat as the widget's Postbox sees it.
    public enum ChatKind: Equatable {
        case user(id: Int64, isBot: Bool)
        case channel(id: Int64, isForum: Bool)
        case other
    }

    /// How many chats the widget shows at most (Telegram's own limit for this widget).
    public static let limit = 8

    public static func isAllowed(_ kind: ChatKind, groups: HarnessgramAgentGroups, identity: HarnessgramBridgeIdentity) -> Bool {
        switch kind {
        case let .user(id, isBot):
            return isBot && identity.isBridge(userId: id)
        case let .channel(id, isForum):
            return HarnessgramAgentChat.isAgentChat(HarnessgramAgentChat.Kind(isBotPrivateChat: false, channelId: id, isForum: isForum), groups: groups)
        case .other:
            return false
        }
    }

    /// Saved or offered chats, in their order: only the allowed ones, each once, at most `limit`.
    public static func filter<Id: Hashable>(_ chats: [(Id, ChatKind)], groups: HarnessgramAgentGroups, identity: HarnessgramBridgeIdentity, limit: Int = HarnessgramChatWidget.limit) -> [Id] {
        var result: [Id] = []
        var seen = Set<Id>()
        for (id, kind) in chats where result.count < limit {
            guard !seen.contains(id) else {
                continue
            }
            seen.insert(id)
            if HarnessgramChatWidget.isAllowed(kind, groups: groups, identity: identity) {
                result.append(id)
            }
        }
        return result
    }
}
