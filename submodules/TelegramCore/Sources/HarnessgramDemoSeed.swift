import Foundation
import Postbox
import SwiftSignalKit

/// Simulator-only demo mode for the screenshot gate (build 20): a logged-in app with no network and no real account.
/// `--harnessgram-demo` (TelegramUI AppDelegate) opens a fresh data folder; this writes a loopback proxy (every
/// connection is refused on the machine itself, the method of Tests/ComposerHarness), an authorised account state for
/// a made-up user, and made-up chats: a synthetic bridge bot and example project groups. Nothing is read
/// from or sent to Telegram.
public enum HarnessgramDemoSeed {
    public static let accountPeerId = PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(990000001))
    static let bridgeBotId = PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(990000002))

    /// Synthetic sequential IDs for the demo chat list; never real group identities.
    static let groups: [(id: Int64, title: String, line: String)] = [
        (900000001, "גשר", "הסוכן סיים את בדיקות הבנייה. מחכה לאישור שלך."),
        (900000002, "פרויקט לדוגמה", "התדריך של מחר מוכן לצפייה."),
        (900000003, "תוכן לדוגמה", "שלוש בקשות חדשות מחכות בתור."),
        (900000004, "חנות לדוגמה", "ההזמנות של היום נשלחו."),
    ]

    /// The loopback proxy, the account record (current) and its authorised state with the made-up chats.
    public static func seed(accountManager: AccountManager<TelegramAccountManagerTypes>, rootPath: String, networkArguments: NetworkInitializationArguments, encryptionParameters: ValueBoxEncryptionParameters, auxiliaryMethods: AccountAuxiliaryMethods) -> Signal<Bool, NoError> {
        let loopback = ProxyServerSettings(host: "127.0.0.1", port: 1, connection: .socks5(username: nil, password: nil))
        let recordId = generateAccountRecordId()
        let prepare = accountManager.transaction { transaction -> Void in
            let _ = updateProxySettingsInteractively(transaction: transaction) { _ in
                return ProxySettings(enabled: true, servers: [loopback], activeServer: loopback, useForCalls: false)
            }
            transaction.updateRecord(recordId, { _ in
                return AccountRecord(id: recordId, attributes: [.environment(AccountEnvironmentAttribute(environment: .production)), .sortOrder(AccountSortOrderAttribute(order: 1))], temporarySessionId: nil)
            })
            transaction.setCurrentId(recordId)
            transaction.removeAuth()
        }
        func open() -> Signal<AccountResult, NoError> {
            return accountWithId(accountManager: accountManager, networkArguments: networkArguments, id: recordId, encryptionParameters: encryptionParameters, supplementary: true, isSupportUser: false, rootPath: rootPath, beginWithTestingEnvironment: false, backupData: nil, auxiliaryMethods: auxiliaryMethods, shouldKeepAutoConnection: false)
        }
        return prepare
        |> mapToSignal { _ -> Signal<AccountResult, NoError> in
            return open()
        }
        |> take(1)
        |> mapToSignal { first -> Signal<Bool, NoError> in
            guard case let .unauthorized(unauthorized) = first else {
                return .single(false)
            }
            return unauthorized.postbox.transaction { transaction -> Bool in
                transaction.setState(AuthorizedAccountState(isTestingEnvironment: false, masterDatacenterId: 2, peerId: HarnessgramDemoSeed.accountPeerId, state: nil, invalidatedChannels: []))
                HarnessgramDemoSeed.addChats(transaction: transaction)
                return true
            }
        }
    }

    static func user(id: PeerId, firstName: String, username: String?, isBot: Bool) -> TelegramUser {
        return TelegramUser(id: id, accessHash: nil, firstName: firstName, lastName: nil, username: username, phone: nil, photo: [], botInfo: isBot ? BotUserInfo(flags: [], inlinePlaceholder: nil) : nil, restrictionInfo: nil, flags: [], emojiStatus: nil, usernames: [], storiesHidden: nil, nameColor: nil, backgroundEmojiId: nil, profileColor: nil, profileBackgroundEmojiId: nil, subscriberCount: nil, verificationIconFileId: nil)
    }

    static func channel(id: Int64, title: String) -> TelegramChannel {
        return TelegramChannel(id: PeerId(namespace: Namespaces.Peer.CloudChannel, id: PeerId.Id._internalFromInt64Value(id)), accessHash: nil, title: title, username: nil, photo: [], creationDate: 0, version: 0, participationStatus: .member, info: .group(TelegramChannelGroupInfo(flags: [])), flags: [], restrictionInfo: nil, adminRights: nil, bannedRights: nil, defaultBannedRights: nil, usernames: [], storiesHidden: nil, nameColor: nil, backgroundEmojiId: nil, profileColor: nil, profileBackgroundEmojiId: nil, emojiStatus: nil, approximateBoostLevel: nil, subscriptionUntilDate: nil, verificationIconFileId: nil, sendPaidMessageStars: nil, linkedMonoforumId: nil)
    }

    static func addChats(transaction: Transaction) {
        let me = HarnessgramDemoSeed.user(id: HarnessgramDemoSeed.accountPeerId, firstName: "Harnessgram", username: nil, isBot: false)
        let bot = HarnessgramDemoSeed.user(id: HarnessgramDemoSeed.bridgeBotId, firstName: "גשר", username: "ExampleBridgeBot", isBot: true)
        var peers: [Peer] = [me, bot]
        let now = Int32(Date().timeIntervalSince1970)
        var messages: [StoreMessage] = []
        func line(_ peerId: PeerId, _ id: Int32, _ author: PeerId, _ text: String, _ age: Int32) {
            messages.append(StoreMessage(id: MessageId(peerId: peerId, namespace: Namespaces.Message.Cloud, id: id), customStableId: nil, globallyUniqueId: nil, groupingKey: nil, threadId: nil, timestamp: now - age, flags: [.Incoming], tags: [], globalTags: [], localTags: [], forwardInfo: nil, authorId: author, text: text, attributes: [], media: []))
        }
        line(bot.id, 1, bot.id, "יש שאלה שמחכה לך: למזג את תיקון ההתחברות?", 60)
        for (index, group) in HarnessgramDemoSeed.groups.enumerated() {
            let channel = HarnessgramDemoSeed.channel(id: group.id, title: group.title)
            peers.append(channel)
            line(channel.id, 1, bot.id, group.line, Int32(300 * (index + 1)))
        }
        updatePeersCustom(transaction: transaction, peers: peers, update: { _, updated in updated })
        for peer in peers where peer.id != HarnessgramDemoSeed.accountPeerId {
            transaction.updatePeerChatListInclusion(peer.id, inclusion: .ifHasMessagesOrOneOf(groupId: .root, pinningIndex: nil, minTimestamp: nil))
        }
        let _ = transaction.addMessages(messages, location: .UpperHistoryBlock)
        // The chat list is complete as written: no hole that would wait for Telegram to fill it.
        for groupId in [PeerGroupId.root, PeerGroupId.group(1)] {
            for hole in transaction.allChatListHoles(groupId: groupId) {
                transaction.replaceChatListHole(groupId: groupId, index: hole.index, hole: nil)
            }
        }
    }
}
