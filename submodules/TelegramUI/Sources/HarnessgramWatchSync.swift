import Foundation
import SwiftSignalKit
import TelegramCore
import AccountContext
import HarnessgramWatchLink

/// HarnessGram watch phase 1: the iPhone tells the watch app which chats the filter approved (the newest of the main
/// chat list that the filter lists), and which of them are text only. Exactly one logged-in account, or the watch gets
/// a deny-all list. Nothing is approved here: the list only mirrors HarnessgramPolicyStore.
enum HarnessgramWatchSync {
    static func payload(accountPeerId: EnginePeer.Id, peers: [EnginePeer], now: Date) -> HarnessgramWatchAllowlistPayload {
        var allowed: [Int64] = []
        var textOnly: [Int64] = []
        for peer in peers {
            let kind: HarnessgramWatchChatId.Kind
            switch peer {
            case .user:
                kind = .user
            case .legacyGroup:
                kind = .basicGroup
            case .channel:
                kind = .channel
            case .secretChat, .community:
                // Secret chats live on one device; communities have no plain TDLib chat of their own.
                continue
            }
            guard HarnessgramPolicyStore.shared.isListedChat(peer, accountPeerId: accountPeerId, recordsRequest: false), let id = HarnessgramWatchChatId.tdlib(kind: kind, id: peer.id.id._internalGetInt64Value()) else {
                continue
            }
            allowed.append(id)
            if HarnessgramPolicyStore.shared.mediaLevel(forChat: peer, accountPeerId: accountPeerId) == .textOnly {
                textOnly.append(id)
            }
        }
        return HarnessgramWatchAllowlistPayload(accountUserId: accountPeerId.id._internalGetInt64Value(), allowedChatIds: allowed, textOnlyChatIds: textOnly, issuedAt: now)
    }

    /// The list for the current accounts, again whenever the chat list or the filter's approvals change.
    static func signal(sharedContext: SharedAccountContext) -> Signal<HarnessgramWatchAllowlistPayload, NoError> {
        return sharedContext.activeAccountContexts
        |> mapToSignal { value -> Signal<HarnessgramWatchAllowlistPayload, NoError> in
            guard value.accounts.count == 1, let context = value.primary else {
                return .single(.denyAll(issuedAt: Date()))
            }
            let accountPeerId = context.account.peerId
            return combineLatest(
                context.engine.messages.chatList(group: .root, count: HarnessgramWatchAllowlistPayload.maxChats),
                HarnessgramPolicyStore.shared.updates
            )
            |> map { chatList, _ -> HarnessgramWatchAllowlistPayload in
                let peers = chatList.items.reversed().compactMap { $0.renderedPeer.peer }
                return HarnessgramWatchSync.payload(accountPeerId: accountPeerId, peers: peers, now: Date())
            }
        }
        |> distinctUntilChanged(isEqual: { $0.sameChats(as: $1) })
    }
}
