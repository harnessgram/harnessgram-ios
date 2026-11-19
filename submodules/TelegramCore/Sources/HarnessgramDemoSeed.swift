import Foundation
import Postbox
import SwiftSignalKit

/// A made-up account and chat fixtures shared by the offline sample and the simulator screenshot gate.
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
    private static let offlineGroups: [(id: Int64, title: String, line: String)] = [
        (900000001, "פינת הקריאה", "האיור לפינת הקריאה מוכן. בסקיצה יש מדף ספרים, גלובוס ומטוס קטן."),
        (900000002, "גלריית הכיתה", "חדר הקריאה הדמיוני מוכן לגלריית הציורים. ההחלטה על פתיחת הגלריה מחכה."),
        (900000003, "אתר החנות", "עמוד המוצרים החדש מוכן לבדיקה. נשארו שני תיקונים קטנים."),
        (900000004, "מסלול הלמידה", "שלב 3 מתוך 5 הושלם. השלב הבא: חידון קצר."),
        (900000005, "תדריך הבוקר", "התדריך של מחר נכתב ומחכה להקראה."),
        (900000006, "לוח המשימות", "4 מתוך 7 משימות הושלמו היום."),
        (900000007, "רדיו הצוות", "שידור הערב מוכן: סיכום של שלושה פרויקטים."),
    ]

    public struct OfflineChat: Sendable {
        public let title: String
        public let message: String
    }

    /// Opens the sample account's own Postbox directly. No AccountManager, network arguments, MTProto session,
    /// proxy, or auth key are needed to read and write this local account.
    public static func openOfflineAccount(directory: URL) -> Signal<[OfflineChat]?, NoError> {
        // The database contains shipped fixtures only. Never borrow the device's real-account key or salt.
        let encryption = ValueBoxEncryptionParameters(forceEncryptionIfNoSet: false, key: .init(data: Data(count: 32))!, salt: .init(data: Data(count: 16))!)
        return openPostbox(
            basePath: directory.appendingPathComponent("account/postbox", isDirectory: true).path,
            seedConfiguration: telegramPostboxSeedConfiguration,
            encryptionParameters: encryption,
            timestampForAbsoluteTimeBasedOperations: Int32(Date().timeIntervalSince1970),
            isMainProcess: true,
            isTemporary: false,
            isReadOnly: false,
            useCopy: false,
            useCaches: false,
            removeDatabaseOnError: false
        )
        |> mapToSignal { result -> Signal<[OfflineChat]?, NoError> in
            switch result {
            case .upgrading:
                return .complete()
            case .error:
                return .single(nil)
            case let .postbox(postbox):
                return postbox.transaction { transaction -> [OfflineChat]? in
                    if transaction.getState() == nil {
                        transaction.setState(AuthorizedAccountState(isTestingEnvironment: false, masterDatacenterId: 2, peerId: accountPeerId, state: nil, invalidatedChannels: []))
                        addChats(transaction: transaction, offline: true)
                    }
                    guard let state = transaction.getState() as? AuthorizedAccountState, state.peerId == accountPeerId else {
                        return nil
                    }
                    let peers = [bridgeBotId] + offlineGroups.map { channel(id: $0.id, title: $0.title).id }
                    return peers.compactMap { peerId in
                        let peer = transaction.getPeer(peerId)
                        guard let title = (peer as? TelegramUser)?.firstName ?? (peer as? TelegramChannel)?.title,
                              let message = transaction.getMessage(MessageId(peerId: peerId, namespace: Namespaces.Message.Cloud, id: 1)) else {
                            return nil
                        }
                        return OfflineChat(title: title, message: message.text)
                    }
                }
            }
        }
        |> mapToSignal { chats in
            return Signal<[OfflineChat]?, NoError> { subscriber in
                // Let the open or transaction unwind on the Postbox queue before callers can erase the directory.
                // Two hops: the first lets the open/transaction unwind, the second runs after any close it scheduled.
                Postbox.sharedQueue.justDispatch {
                    Postbox.sharedQueue.justDispatch {
                        subscriber.putNext(chats)
                        subscriber.putCompletion()
                    }
                }
                return EmptyDisposable
            }
        }
        |> take(1)
    }

    #if targetEnvironment(simulator)
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
    #endif

    static func user(id: PeerId, firstName: String, username: String?, isBot: Bool) -> TelegramUser {
        return TelegramUser(id: id, accessHash: nil, firstName: firstName, lastName: nil, username: username, phone: nil, photo: [], botInfo: isBot ? BotUserInfo(flags: [], inlinePlaceholder: nil) : nil, restrictionInfo: nil, flags: [], emojiStatus: nil, usernames: [], storiesHidden: nil, nameColor: nil, backgroundEmojiId: nil, profileColor: nil, profileBackgroundEmojiId: nil, subscriberCount: nil, verificationIconFileId: nil)
    }

    static func channel(id: Int64, title: String) -> TelegramChannel {
        return TelegramChannel(id: PeerId(namespace: Namespaces.Peer.CloudChannel, id: PeerId.Id._internalFromInt64Value(id)), accessHash: nil, title: title, username: nil, photo: [], creationDate: 0, version: 0, participationStatus: .member, info: .group(TelegramChannelGroupInfo(flags: [])), flags: [], restrictionInfo: nil, adminRights: nil, bannedRights: nil, defaultBannedRights: nil, usernames: [], storiesHidden: nil, nameColor: nil, backgroundEmojiId: nil, profileColor: nil, profileBackgroundEmojiId: nil, emojiStatus: nil, approximateBoostLevel: nil, subscriptionUntilDate: nil, verificationIconFileId: nil, sendPaidMessageStars: nil, linkedMonoforumId: nil)
    }

    static func addChats(transaction: Transaction, offline: Bool = false) {
        let me = HarnessgramDemoSeed.user(id: HarnessgramDemoSeed.accountPeerId, firstName: "Harnessgram", username: nil, isBot: false)
        let bot = HarnessgramDemoSeed.user(id: HarnessgramDemoSeed.bridgeBotId, firstName: "גשר", username: "ExampleBridgeBot", isBot: true)
        var peers: [Peer] = [me, bot]
        let now = Int32(Date().timeIntervalSince1970)
        var messages: [StoreMessage] = []
        func line(_ peerId: PeerId, _ id: Int32, _ author: PeerId, _ text: String, _ age: Int32) {
            messages.append(StoreMessage(id: MessageId(peerId: peerId, namespace: Namespaces.Message.Cloud, id: id), customStableId: nil, globallyUniqueId: nil, groupingKey: nil, threadId: nil, timestamp: now - age, flags: [.Incoming], tags: [], globalTags: [], localTags: [], forwardInfo: nil, authorId: author, text: text, attributes: [], media: []))
        }
        line(bot.id, 1, bot.id, offline ? "האיור לפינת הקריאה מחכה לבחירה." : "יש שאלה שמחכה לך: למזג את תיקון ההתחברות?", 60)
        for (index, group) in (offline ? HarnessgramDemoSeed.offlineGroups : HarnessgramDemoSeed.groups).enumerated() {
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
