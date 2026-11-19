import Foundation
import Postbox
import SwiftSignalKit
import HarnessgramSettings

/// Device-local Phase 1 state. Accounts never share grandfathering or requests.
public final class HarnessgramPolicyStore {
    public enum AccountPrivacyConsent: String, Equatable {
        case unknown
        case granted
        case declined
    }

    public struct PendingRequest: Codable, Equatable {
        /// Namespaced peer id, or "invite:<sha256>" when Telegram withholds the peer id.
        public let id: String
        public let title: String
        public let time: TimeInterval
    }

    enum JoinTarget {
        case chat(id: EnginePeer.Id, peer: EnginePeer?)
        case invite(hash: String, title: String)
    }

    enum JoinApproval: Equatable {
        case allowed
        case committeeApprovalRequired(requestRecorded: Bool)
    }

    private struct AccountState: Codable {
        var grandfatheredIds: Set<Int64>?
        var serverSnapshotPending = true
        var requests: [PendingRequest] = []
        /// Private chats (users, secret chats) present on this filter's first run; nil = not captured.
        var grandfatheredPrivateIds: Set<Int64>?
        /// Per-chat media levels set later (namespaced peer id -> MediaLevel raw value).
        var mediaLevels: [String: String]?
        /// Groups, channels and communities the owner created on this device, approved at creation by the new
        /// chat's id (owner, 2026-11-17). Never from the creator flag: ownership can be transferred to him.
        var createdIds: Set<Int64>?

        /// Every group, channel and community id this account approves locally (approved.json comes on top).
        var approvedGroupIds: Set<Int64> {
            return (self.grandfatheredIds ?? []).union(self.createdIds ?? [])
        }
    }

    /// Device-wide, unlike chats: rendering and fetch gates often run without an account.
    /// nil grandfathered means the installed-pack snapshot has not completed yet.
    private struct StickerState: Codable {
        var grandfathered: HarnessgramPolicy.ApprovedStickerPacks?
        var systemIds: Set<Int64> = []
    }

    private struct BundledLinks: Decodable {
        var linkPreviewDomains: [String]?
    }

    private struct BundledMediaLevels: Decodable {
        var mediaLevels: [String: String]?
    }

    private struct BundledStickerPacks: Decodable {
        var stickerPackIds: [String]?
        var stickerPackShortNames: [String]?
    }

    public static let shared = HarnessgramPolicyStore(defaults: HarnessgramPolicyStore.sharedDefaults())

    /// The app and its extensions (notifications, share, intents) read one state: the app group's
    /// defaults. Without the group, extensions see no snapshot and every gate fails closed.
    static func sharedDefaults() -> UserDefaults {
        guard let base = HarnessgramPolicyStore.baseAppBundleId(), let suite = UserDefaults(suiteName: "group." + base) else {
            return .standard
        }
        if Bundle.main.bundleURL.pathExtension != "appex" {
            // Builds up to 4 kept the state in the app's own defaults; move it once, never overwrite.
            for (key, value) in UserDefaults.standard.dictionaryRepresentation() where key.hasPrefix("Harnessgram.") {
                if suite.object(forKey: key) == nil {
                    suite.set(value, forKey: key)
                }
            }
        }
        return suite
    }

    private static func baseAppBundleId() -> String? {
        guard let id = Bundle.main.bundleIdentifier else {
            return nil
        }
        if Bundle.main.bundleURL.pathExtension == "appex", let dot = id.range(of: ".", options: .backwards) {
            return String(id[..<dot.lowerBound])
        }
        return id
    }

    /// approved.json ships in the app bundle; an extension finds it two levels up (App.app/PlugIns/X.appex).
    private static func bundledApprovedData() -> Data? {
        var bundles = [Bundle.main]
        if Bundle.main.bundleURL.pathExtension == "appex", let app = Bundle(url: Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent()) {
            bundles.append(app)
        }
        for bundle in bundles {
            // Bazel flattens ordinary application resources. Also accept a folder reference.
            if let url = bundle.url(forResource: "approved", withExtension: "json", subdirectory: "Harnessgram") ?? bundle.url(forResource: "approved", withExtension: "json"), let data = try? Data(contentsOf: url) {
                return data
            }
        }
        return nil
    }

    private static let stickerKey = "Harnessgram.stickerPacks.v1"

    private let defaults: UserDefaults
    /// The filter's switches, read from the same defaults as the rest of this store (build 19).
    let filter: HarnessgramFilterSettings
    private let approved: HarnessgramPolicy.ApprovedChats
    private let bundledStickerPacks: HarnessgramPolicy.ApprovedStickerPacks
    /// Domains whose link previews may show (approved.json "linkPreviewDomains"); empty shows none.
    public let linkPreviewDomains: [String]
    /// Per-chat media levels shipped in approved.json "mediaLevels" (namespaced peer id -> level).
    private let bundledMediaLevels: [String: HarnessgramPolicy.MediaLevel]
    private var stickerStateValue: StickerState?
    private var effectiveStickerPacks: HarnessgramPolicy.ApprovedStickerPacks?
    // In memory: every topic Info is built or decoded before its icon is rendered or fetched.
    private var topicIconFileIds = Set<Int64>()
    // In memory: standard reactions are decoded or received before any of their files render.
    private var systemFileIds = Set<Int64>()
    // Pickers check thousands of files per update; decisions per file stay valid until approvals change.
    private var stickerDecisions: [MediaId: Bool] = [:]
    private let lock = NSLock()
    private var approvedUsernamePeerIds: [Int64: Set<Int64>] = [:]
    private var contactIds: [Int64: Set<Int64>] = [:]
    // Device-wide, like stickers: profile photos are drawn without an account at hand.
    private var allContactIds = Set<Int64>()
    private var accountPeerIds = Set<Int64>()
    private var notedStrangers = Set<String>()
    private var accountStates: [String: AccountState] = [:]
    private var photoBotIds: Set<Int64>?
    private var webPreviewMedia: [MediaId: Bool] = [:]
    // Accounts whose local contact list has been read at least once this run.
    private var contactsLoaded = Set<Int64>()
    private let revision = ValuePromise<Int>(0, ignoreRepeated: true)
    private var revisionValue = 0
    private let accountPrivacyConsentChanges = ValuePipe<AccountRecordId>()

    public var updates: Signal<Int, NoError> {
        return self.revision.get()
    }

    private func accountPrivacyConsentKey(_ accountId: AccountRecordId) -> String {
        return "Harnessgram.accountPrivacyConsent.v1.\(accountId.int64)"
    }

    /// Each local sign-in has its own record. No older filter setting implies consent.
    public func accountPrivacyConsent(accountId: AccountRecordId) -> AccountPrivacyConsent {
        return self.defaults.string(forKey: self.accountPrivacyConsentKey(accountId)).flatMap(AccountPrivacyConsent.init(rawValue:)) ?? .unknown
    }

    /// Called on the main thread, where the privacy bootstrap also starts its requests.
    public func setAccountPrivacyConsent(_ consent: AccountPrivacyConsent, accountId: AccountRecordId) {
        precondition(Thread.isMainThread)
        guard consent != self.accountPrivacyConsent(accountId: accountId) else {
            return
        }
        self.defaults.set(consent.rawValue, forKey: self.accountPrivacyConsentKey(accountId))
        self.accountPrivacyConsentChanges.putNext(accountId)
    }

    func accountPrivacyConsentUpdates(accountId: AccountRecordId) -> Signal<AccountPrivacyConsent, NoError> {
        return Signal { subscriber in
            let disposable = self.accountPrivacyConsentChanges.signal().start(next: { changedAccountId in
                if changedAccountId == accountId {
                    subscriber.putNext(self.accountPrivacyConsent(accountId: accountId))
                }
            })
            subscriber.putNext(self.accountPrivacyConsent(accountId: accountId))
            return disposable
        }
        |> runOn(.mainQueue())
    }

    public init(defaults: UserDefaults = .standard, approved: HarnessgramPolicy.ApprovedChats? = nil, stickerPacks: HarnessgramPolicy.ApprovedStickerPacks? = nil, linkPreviewDomains: [String]? = nil, mediaLevels: [String: HarnessgramPolicy.MediaLevel]? = nil, filter: HarnessgramFilterSettings? = nil) {
        self.defaults = defaults
        self.filter = filter ?? HarnessgramFilterSettings(defaults: defaults)
        var bundleData: Data?
        if approved == nil || stickerPacks == nil || linkPreviewDomains == nil || mediaLevels == nil {
            bundleData = HarnessgramPolicyStore.bundledApprovedData()
        }
        if let approved {
            self.approved = approved
        } else {
            self.approved = bundleData.flatMap { try? JSONDecoder().decode(HarnessgramPolicy.ApprovedChats.self, from: $0) } ?? HarnessgramPolicy.ApprovedChats()
        }
        if let stickerPacks {
            self.bundledStickerPacks = stickerPacks
        } else {
            // Same file; missing keys or malformed data approve no packs.
            let bundled = bundleData.flatMap { try? JSONDecoder().decode(BundledStickerPacks.self, from: $0) }
            self.bundledStickerPacks = HarnessgramPolicy.ApprovedStickerPacks(ids: Set((bundled?.stickerPackIds ?? []).compactMap { Int64($0) }), shortNames: bundled?.stickerPackShortNames ?? [])
        }
        // Unknown level names are ignored, so a typo never loosens a chat (it keeps the default).
        if let mediaLevels {
            self.bundledMediaLevels = mediaLevels
        } else {
            let levels = bundleData.flatMap { try? JSONDecoder().decode(BundledMediaLevels.self, from: $0) }?.mediaLevels ?? [:]
            self.bundledMediaLevels = levels.compactMapValues(HarnessgramPolicy.MediaLevel.init(rawValue:))
        }
        if let linkPreviewDomains {
            self.linkPreviewDomains = linkPreviewDomains
        } else {
            // Missing key or malformed data approves no domains.
            self.linkPreviewDomains = bundleData.flatMap { try? JSONDecoder().decode(BundledLinks.self, from: $0) }?.linkPreviewDomains ?? []
        }
    }

    private func key(_ accountPeerId: EnginePeer.Id) -> String {
        return "Harnessgram.approvals.v1.\(accountPeerId.toInt64())"
    }

    /// Decoded once per account and kept in memory; every chat row reads it under the lock.
    private func state(_ accountPeerId: EnginePeer.Id) -> AccountState {
        let key = self.key(accountPeerId)
        if let value = self.accountStates[key] {
            return value
        }
        var value = AccountState()
        if let data = self.defaults.data(forKey: key) {
            // Corruption must never reopen the first-launch grandfathering window.
            value = (try? JSONDecoder().decode(AccountState.self, from: data)) ?? AccountState(grandfatheredIds: [], serverSnapshotPending: false, grandfatheredPrivateIds: [])
        }
        self.accountStates[key] = value
        return value
    }

    private func save(_ state: AccountState, accountPeerId: EnginePeer.Id) -> Bool {
        guard let data = try? JSONEncoder().encode(state) else {
            return false
        }
        self.defaults.set(data, forKey: self.key(accountPeerId))
        self.accountStates[self.key(accountPeerId)] = state
        return true
    }

    /// Call once from the account's first startup transaction, before sync starts.
    /// Includes archived local dialogs; merely cached peers and peeks are excluded.
    func captureMembership(transaction: Transaction, accountPeerId: EnginePeer.Id) {
        let peers = transaction.chatListGetAllPeerIds().compactMap(transaction.getPeer).map(EnginePeer.init)
        self.captureMembership(peers: peers, accountPeerId: accountPeerId)
    }

    func captureMembership(peers: [EnginePeer], accountPeerId: EnginePeer.Id) {
        self.lock.lock()
        defer { self.lock.unlock() }
        var state = self.state(accountPeerId)
        self.approvedUsernamePeerIds[accountPeerId.toInt64()] = Set(peers.filter {
            HarnessgramPolicy.isApprovedGroup($0, approved: self.approved, grandfatheredIds: [])
        }.map { $0.id.toInt64() })
        var changed = false
        if state.grandfatheredIds == nil {
            state.grandfatheredIds = HarnessgramPolicy.grandfatheredIds(existing: nil, peers: peers)
            changed = true
        }
        if state.grandfatheredPrivateIds == nil {
            // Also runs once on accounts that already had the group snapshot before slice 10.
            state.grandfatheredPrivateIds = HarnessgramPolicy.grandfatheredPrivateIds(peers: peers)
            changed = true
        }
        if changed {
            let _ = self.save(state, accountPeerId: accountPeerId)
        }
    }

    func needsServerSnapshot(accountPeerId: EnginePeer.Id) -> Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.state(accountPeerId).serverSnapshotPending
    }

    /// Completes the initial server sweep once, including dialogs not cached at login.
    /// Later launches and later membership updates can never extend this set.
    func completeInitialMembership(peers: [EnginePeer], accountPeerId: EnginePeer.Id) {
        self.lock.lock()
        var state = self.state(accountPeerId)
        guard state.serverSnapshotPending else {
            self.lock.unlock()
            return
        }
        state.grandfatheredIds = (state.grandfatheredIds ?? []).union(HarnessgramPolicy.grandfatheredIds(existing: nil, peers: peers))
        state.serverSnapshotPending = false
        let saved = self.save(state, accountPeerId: accountPeerId)
        self.revisionValue += 1
        let revision = self.revisionValue
        self.lock.unlock()
        if saved {
            self.revision.set(revision)
        }
    }

    public func isApprovedGroup(_ peer: EnginePeer, accountPeerId: EnginePeer.Id) -> Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.checkGroup(peer, accountPeerId: accountPeerId)
    }

    private func checkGroup(_ peer: EnginePeer, accountPeerId: EnginePeer.Id) -> Bool {
        if !self.filter.isOn(.approvedChats) {
            // Build 19: the approved-chats rule is off: every group and channel shows, as in Telegram.
            return true
        }
        let allowed = HarnessgramPolicy.isApprovedGroup(peer, approved: self.approved, grandfatheredIds: self.state(accountPeerId).approvedGroupIds)
        if allowed {
            self.approvedUsernamePeerIds[accountPeerId.toInt64(), default: []].insert(peer.id.toInt64())
        } else {
            self.approvedUsernamePeerIds[accountPeerId.toInt64()]?.remove(peer.id.toInt64())
        }
        return allowed
    }

    /// Last-resort synchronous gate for constructors that only carry an id.
    /// Username matches are learned only from peers independently checked above.
    public func isApprovedChatId(_ peerId: EnginePeer.Id, accountPeerId: EnginePeer.Id) -> Bool {
        if peerId.namespace == Namespaces.Peer.CloudUser || peerId.namespace == Namespaces.Peer.SecretChat || !self.filter.isOn(.approvedChats) {
            return true
        }
        self.lock.lock()
        defer { self.lock.unlock() }
        let id = peerId.toInt64()
        return self.approved.peerIds.contains(String(id)) || self.state(accountPeerId).approvedGroupIds.contains(id) || (self.approvedUsernamePeerIds[accountPeerId.toInt64()]?.contains(id) ?? false)
    }

    public func isApprovedPeer(_ peer: EnginePeer, accountPeerId: EnginePeer.Id, hasChat: Bool, isContact: Bool) -> Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        if HarnessgramPolicy.isGroupOrChannel(peer) {
            return self.checkGroup(peer, accountPeerId: accountPeerId)
        }
        return self.checkPrivate(peer, accountPeerId: accountPeerId, hasChat: hasChat, isContact: isContact || self.isContactLocked(peer, accountPeerId: accountPeerId))
    }

    private func checkPrivate(_ peer: EnginePeer, accountPeerId: EnginePeer.Id, hasChat: Bool, isContact: Bool) -> Bool {
        if !self.filter.isOn(.contactsOnly) {
            // Build 19: the contacts-only rule is off: every private chat shows, as in Telegram.
            return true
        }
        let state = self.state(accountPeerId)
        // A missing snapshot (not captured yet, or an extension without the app group) grandfathers nothing.
        return HarnessgramPolicy.isApprovedPeer(peer, accountPeerId: accountPeerId, hasChat: hasChat, isContact: isContact, approved: self.approved, grandfatheredIds: state.approvedGroupIds, grandfatheredPrivateIds: state.grandfatheredPrivateIds ?? [])
    }

    private func isContactLocked(_ peer: EnginePeer, accountPeerId: EnginePeer.Id) -> Bool {
        let peerId: EnginePeer.Id
        if case let .secretChat(chat) = peer {
            peerId = chat.regularPeerId
        } else {
            peerId = peer.id
        }
        return self.contactIds[accountPeerId.toInt64()]?.contains(peerId.toInt64()) ?? false
    }

    /// Kept current from the account's local contact list (see harnessgramTrackContacts).
    public func updateContacts(accountPeerId: EnginePeer.Id, peerIds: Set<EnginePeer.Id>) {
        let ids = Set(peerIds.map { $0.toInt64() })
        self.lock.lock()
        self.contactsLoaded.insert(accountPeerId.toInt64())
        guard self.contactIds[accountPeerId.toInt64()] != ids else {
            self.lock.unlock()
            return
        }
        self.contactIds[accountPeerId.toInt64()] = ids
        self.allContactIds = self.contactIds.values.reduce(into: Set<Int64>()) { $0.formUnion($1) }
        self.accountPeerIds.insert(accountPeerId.toInt64())
        self.revisionValue += 1
        let revision = self.revisionValue
        self.lock.unlock()
        self.revision.set(revision)
    }

    /// Synchronous: a user's photo shows for the device's accounts and their contacts only.
    public func showsProfilePhoto(_ peerId: EnginePeer.Id) -> Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        return HarnessgramPolicy.showsProfilePhoto(ofUser: peerId.toInt64(), contacts: self.allContactIds, accountPeerIds: self.accountPeerIds, approvedBots: self.photoBots())
    }

    private static let photoBotsKey = "Harnessgram.photoBots.v1"

    private func photoBots() -> Set<Int64> {
        if let value = self.photoBotIds {
            return value
        }
        // Shared with the extensions through the app group, so notifications follow the same rule.
        let value = Set((self.defaults.array(forKey: HarnessgramPolicyStore.photoBotsKey) as? [NSNumber] ?? []).map(\.int64Value))
        self.photoBotIds = value
        return value
    }

    /// A bot whose photo may show: it has a chat with the account, or it posts in an approved group
    /// or channel. Only bot users are recorded.
    public func noteApprovedBot(_ peer: EnginePeer) {
        guard case let .user(user) = peer, user.botInfo != nil else {
            return
        }
        self.lock.lock()
        defer { self.lock.unlock() }
        var bots = self.photoBots()
        guard bots.insert(peer.id.toInt64()).inserted else {
            return
        }
        self.photoBotIds = bots
        self.defaults.set(bots.map { NSNumber(value: $0) }, forKey: HarnessgramPolicyStore.photoBotsKey)
    }

    /// Message rendering: a bot author in an approved group or channel. The chat must pass the allow list.
    public func noteMessageAuthor(_ author: EnginePeer?, chat: EnginePeer?, accountPeerId: EnginePeer.Id) {
        guard let author, case let .user(user) = author, user.botInfo != nil, let chat, HarnessgramPolicy.isGroupOrChannel(chat) else {
            return
        }
        if self.isApprovedGroup(chat, accountPeerId: accountPeerId) {
            self.noteApprovedBot(author)
        }
    }

    /// Registered before any profile photo of the account itself is drawn.
    public func noteAccount(_ accountPeerId: EnginePeer.Id) {
        self.lock.lock()
        defer { self.lock.unlock() }
        self.accountPeerIds.insert(accountPeerId.toInt64())
    }

    /// Chat list gate for every chat kind. A hidden private chat from a stranger is recorded once
    /// in the local request list instead of being shown.
    /// Search results pass recordsRequest: false (a found person is not a message request). Nothing
    /// is recorded before the contact list has loaded, so a contact never becomes a request at startup.
    public func isListedChat(_ peer: EnginePeer, accountPeerId: EnginePeer.Id, recordsRequest: Bool = true) -> Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        if HarnessgramPolicy.isGroupOrChannel(peer) {
            return self.checkGroup(peer, accountPeerId: accountPeerId)
        }
        let allowed = self.checkPrivate(peer, accountPeerId: accountPeerId, hasChat: true, isContact: self.isContactLocked(peer, accountPeerId: accountPeerId))
        if allowed, recordsRequest, case let .user(user) = peer, user.botInfo != nil, !self.photoBots().contains(peer.id.toInt64()) {
            // A bot in the chat list: its photo may show (noteApprovedBot, inlined under the lock).
            var bots = self.photoBots()
            bots.insert(peer.id.toInt64())
            self.photoBotIds = bots
            self.defaults.set(bots.map { NSNumber(value: $0) }, forKey: HarnessgramPolicyStore.photoBotsKey)
        }
        if !allowed, recordsRequest, self.contactsLoaded.contains(accountPeerId.toInt64()) {
            let id = "user:\(peer.id.toInt64())"
            let key = "\(accountPeerId.toInt64()):" + id
            if !self.notedStrangers.contains(key) {
                self.notedStrangers.insert(key)
                let _ = self.recordRequest(accountPeerId: accountPeerId, id: id, title: "Message from " + peer.debugDisplayTitle, time: Date().timeIntervalSince1970)
            }
        }
        return allowed
    }

    private struct StrangerArchiveUnavailable: Codable {
        var time: TimeInterval
        var appVersion: String
    }

    private func strangerArchiveKey(_ accountPeerId: EnginePeer.Id) -> String {
        return "Harnessgram.strangerArchiveUnavailable.v2.\(accountPeerId.toInt64())"
    }

    static var appVersion: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "")(\(info?["CFBundleVersion"] as? String ?? ""))"
    }

    /// A refusal is remembered for 7 days and only for the same app version, so a passing network
    /// problem or a server change is retried.
    func isStrangerArchiveUnavailable(accountPeerId: EnginePeer.Id, now: TimeInterval = Date().timeIntervalSince1970, appVersion: String = HarnessgramPolicyStore.appVersion) -> Bool {
        guard let data = self.defaults.data(forKey: self.strangerArchiveKey(accountPeerId)), let value = try? JSONDecoder().decode(StrangerArchiveUnavailable.self, from: data) else {
            return false
        }
        return value.appVersion == appVersion && now >= value.time && now - value.time < 7 * 24 * 60 * 60
    }

    func markStrangerArchiveUnavailable(accountPeerId: EnginePeer.Id, now: TimeInterval = Date().timeIntervalSince1970, appVersion: String = HarnessgramPolicyStore.appVersion) {
        if let data = try? JSONEncoder().encode(StrangerArchiveUnavailable(time: now, appVersion: appVersion)) {
            self.defaults.set(data, forKey: self.strangerArchiveKey(accountPeerId))
        }
    }

    /// Notification extension gate. The extension reads the chat's peer and contact flag from its
    /// own postbox; an unknown peer is never allowed.
    public func allowsNotification(from peer: EnginePeer?, isContact: Bool, accountPeerId: EnginePeer.Id) -> Bool {
        guard let peer else {
            return false
        }
        self.lock.lock()
        defer { self.lock.unlock() }
        if HarnessgramPolicy.isGroupOrChannel(peer) {
            return self.checkGroup(peer, accountPeerId: accountPeerId)
        }
        return self.checkPrivate(peer, accountPeerId: accountPeerId, hasChat: true, isContact: isContact || self.isContactLocked(peer, accountPeerId: accountPeerId))
    }

    /// The owner created this group, channel or community on this device: approve it by its new id before
    /// the server's updates reach the chat list. Only creation calls this (ChannelCreation, CreateGroup,
    /// Communities); a chat transferred to him, an invite link or a join keeps the usual rules.
    /// Users and secret chats are refused.
    @discardableResult public func noteCreatedChat(_ peerId: EnginePeer.Id, accountPeerId: EnginePeer.Id) -> Bool {
        guard HarnessgramPolicy.isCreatableChatId(peerId) else {
            return false
        }
        self.lock.lock()
        var state = self.state(accountPeerId)
        var created = state.createdIds ?? []
        guard created.insert(peerId.toInt64()).inserted else {
            self.lock.unlock()
            return true
        }
        state.createdIds = created
        let saved = self.save(state, accountPeerId: accountPeerId)
        self.revisionValue += 1
        let revision = self.revisionValue
        self.lock.unlock()
        self.revision.set(revision)
        return saved
    }

    /// A basic group became a supergroup (Telegram gives it a new channel id). The supergroup is approved only when
    /// the basic group was: created here or in the first-run snapshot. Never from approved.json names or anything else.
    @discardableResult public func noteMigratedChat(from: EnginePeer.Id, to: EnginePeer.Id, accountPeerId: EnginePeer.Id) -> Bool {
        guard from.namespace == Namespaces.Peer.CloudGroup, to.namespace == Namespaces.Peer.CloudChannel else {
            return false
        }
        let fromId = from.toInt64()
        let toId = to.toInt64()
        self.lock.lock()
        var state = self.state(accountPeerId)
        var changed = false
        if var created = state.createdIds, created.contains(fromId), created.insert(toId).inserted {
            state.createdIds = created
            changed = true
        }
        if var grandfathered = state.grandfatheredIds, grandfathered.contains(fromId), grandfathered.insert(toId).inserted {
            state.grandfatheredIds = grandfathered
            changed = true
        }
        guard changed else {
            let approved = state.approvedGroupIds.contains(toId)
            self.lock.unlock()
            return approved
        }
        let saved = self.save(state, accountPeerId: accountPeerId)
        self.revisionValue += 1
        let revision = self.revisionValue
        self.lock.unlock()
        self.revision.set(revision)
        return saved
    }

    /// Replays persisted migrations on chat-list refresh, including groups no longer in the visible list.
    /// Approval notifications run after the Postbox transaction, just like the live-update fast path.
    public func replayChatListMigrations(postbox: Postbox, accountPeerId: EnginePeer.Id) -> Signal<Void, NoError> {
        return postbox.transaction { transaction -> [TelegramGroup] in
            return self.migrationReplayPeerIds(accountPeerId: accountPeerId).compactMap { transaction.getPeer($0) as? TelegramGroup }
        }
        |> map { groups -> Void in
            self.replayMigratedChats(groups: groups, accountPeerId: accountPeerId)
        }
    }

    func migrationReplayPeerIds(accountPeerId: EnginePeer.Id) -> [EnginePeer.Id] {
        self.lock.lock()
        let ids = self.state(accountPeerId).approvedGroupIds
        self.lock.unlock()
        return ids.map(EnginePeer.Id.init).filter { $0.namespace == Namespaces.Peer.CloudGroup }
    }

    func replayMigratedChats(groups: [TelegramGroup], accountPeerId: EnginePeer.Id) {
        let approvedIds = Set(self.migrationReplayPeerIds(accountPeerId: accountPeerId))
        for group in groups {
            if approvedIds.contains(group.id), let migration = group.migrationReference {
                self.noteMigratedChat(from: group.id, to: migration.peerId, accountPeerId: accountPeerId)
            }
        }
    }

    /// Records a request only; it never grants local approval or changes the snapshot.
    @discardableResult public func requestApproval(accountPeerId: EnginePeer.Id, id: String, title: String, time: TimeInterval = Date().timeIntervalSince1970) -> Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.recordRequest(accountPeerId: accountPeerId, id: id, title: title, time: time)
    }

    /// Save an explicit user request from the restricted link prompt using the engine's queue format.
    public func requestJoinApproval(accountPeerId: EnginePeer.Id, id: String, name: String) -> Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.recordJoinRequest(accountPeerId: accountPeerId, id: id, name: name)
    }

    /// Run before an RPC which can join a chat. Only a resolved, approved peer can pass the filter.
    /// An opaque invitation can be requested, but a title or a hash is never proof of approval.
    func evaluateJoin(_ target: JoinTarget, accountPeerId: EnginePeer.Id?) -> JoinApproval {
        guard let accountPeerId, accountPeerId.namespace == Namespaces.Peer.CloudUser, accountPeerId.id._internalGetInt64Value() > 0 else {
            return .committeeApprovalRequired(requestRecorded: false)
        }
        guard self.filter.isOn(.approvedChats) else {
            return .allowed
        }
        self.lock.lock()
        defer { self.lock.unlock() }
        let requestId: String
        let name: String?
        switch target {
        case let .chat(id, peer):
            guard HarnessgramPolicy.isCreatableChatId(id), id.id._internalGetInt64Value() > 0 else {
                return .committeeApprovalRequired(requestRecorded: false)
            }
            requestId = String(id.toInt64())
            if let peer, peer.id == id {
                if HarnessgramPolicy.isApprovedGroup(peer, approved: self.approved, grandfatheredIds: self.state(accountPeerId).approvedGroupIds) {
                    return .allowed
                }
                name = peer.debugDisplayTitle
            } else {
                // Not cached (e.g. inside a folder link): approved by id only when the id is on a list (approved.json,
                // this account's grandfathered/created chats, or its approved usernames); otherwise it waits.
                let raw = id.toInt64()
                if self.approved.peerIds.contains(String(raw)) || self.state(accountPeerId).approvedGroupIds.contains(raw) || (self.approvedUsernamePeerIds[accountPeerId.toInt64()]?.contains(raw) ?? false) {
                    return .allowed
                }
                name = nil
            }
        case let .invite(hash, title):
            requestId = HarnessgramPolicy.inviteRequestId(hash)
            name = title
        }
        let recorded = self.recordJoinRequest(accountPeerId: accountPeerId, id: requestId, name: name)
        return .committeeApprovalRequired(requestRecorded: recorded)
    }

    private func recordJoinRequest(accountPeerId: EnginePeer.Id, id: String, name: String?) -> Bool {
        return self.recordRequest(accountPeerId: accountPeerId, id: id, title: "Join " + (name ?? id), time: Date().timeIntervalSince1970, updateTitle: name != nil)
    }

    private func recordRequest(accountPeerId: EnginePeer.Id, id: String, title: String, time: TimeInterval, updateTitle: Bool = false) -> Bool {
        var state = self.state(accountPeerId)
        if let index = state.requests.firstIndex(where: { $0.id == id }) {
            let request = state.requests[index]
            guard updateTitle, request.title != title else {
                return true
            }
            state.requests[index] = PendingRequest(id: id, title: title, time: request.time)
        } else {
            state.requests.append(PendingRequest(id: id, title: title, time: time))
        }
        return self.save(state, accountPeerId: accountPeerId)
    }

    // MARK: Media level per chat

    /// Whether a chat (as a peer) is approved for the given account.
    private func isApprovedChatLocked(_ peer: EnginePeer, accountPeerId: EnginePeer.Id) -> Bool {
        if HarnessgramPolicy.isGroupOrChannel(peer) {
            return self.checkGroup(peer, accountPeerId: accountPeerId)
        }
        return self.checkPrivate(peer, accountPeerId: accountPeerId, hasChat: true, isContact: self.isContactLocked(peer, accountPeerId: accountPeerId))
    }

    /// Id-only approval for references that carry no peer object. Bots without a recorded chat fail
    /// closed (their peer is needed to decide).
    private func isApprovedChatIdLocked(_ peerId: EnginePeer.Id, accountPeerId: EnginePeer.Id) -> Bool {
        let id = peerId.toInt64()
        let state = self.state(accountPeerId)
        if self.approved.peerIds.contains(String(id)) {
            return true
        }
        switch peerId.namespace {
        case Namespaces.Peer.CloudUser:
            return id == accountPeerId.toInt64() || peerId.id._internalGetInt64Value() == HarnessgramPolicy.telegramServiceUserId || (self.contactIds[accountPeerId.toInt64()]?.contains(id) ?? false) || (state.grandfatheredPrivateIds?.contains(id) ?? false) || self.photoBots().contains(id)
        case Namespaces.Peer.SecretChat:
            return false
        default:
            return state.approvedGroupIds.contains(id) || (self.approvedUsernamePeerIds[accountPeerId.toInt64()]?.contains(id) ?? false)
        }
    }

    private func configuredLevelLocked(_ peerId: EnginePeer.Id, accountPeerId: EnginePeer.Id) -> HarnessgramPolicy.MediaLevel {
        let key = String(peerId.toInt64())
        let bundled = self.bundledMediaLevels[key] ?? HarnessgramPolicy.approvedChatMedia
        if let raw = self.state(accountPeerId).mediaLevels?[key], let level = HarnessgramPolicy.MediaLevel(rawValue: raw) {
            // A level chosen on the device may tighten, never widen, what approved.json ships.
            return HarnessgramPolicy.strictest(level, bundled)
        }
        return bundled
    }

    /// The viewing account's level for a chat. Without a known viewer, the strictest level across this
    /// device's accounts applies, so one account's approval or looser setting never reaches another.
    /// Secret chats always keep the fallback, whatever their approval.
    private func levelLocked(chat: EnginePeer?, chatId: EnginePeer.Id, accountPeerId: EnginePeer.Id?) -> HarnessgramPolicy.MediaLevel {
        if !self.filter.isOn(.mediaFilter) {
            // Build 19: the media rule is off: everything shows, as in Telegram.
            return .all
        }
        if chatId.namespace == Namespaces.Peer.SecretChat {
            return HarnessgramPolicy.media
        }
        let accounts = accountPeerId.map { [$0] } ?? self.accountPeerIds.map(EnginePeer.Id.init)
        if accounts.isEmpty {
            return HarnessgramPolicy.media
        }
        var level = HarnessgramPolicy.MediaLevel.all
        for account in accounts {
            let approved: Bool
            if let chat {
                approved = self.isApprovedChatLocked(chat, accountPeerId: account)
            } else {
                approved = self.isApprovedChatIdLocked(chatId, accountPeerId: account)
            }
            level = HarnessgramPolicy.strictest(level, approved ? self.configuredLevelLocked(chatId, accountPeerId: account) : HarnessgramPolicy.media)
        }
        return level
    }

    /// The media level of a chat: its own setting (default all) when approved, otherwise the fallback.
    public func mediaLevel(forChat peer: EnginePeer, accountPeerId: EnginePeer.Id? = nil) -> HarnessgramPolicy.MediaLevel {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.levelLocked(chat: peer, chatId: peer.id, accountPeerId: accountPeerId)
    }

    public func mediaLevel(forChatId peerId: EnginePeer.Id, accountPeerId: EnginePeer.Id? = nil) -> HarnessgramPolicy.MediaLevel {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.levelLocked(chat: nil, chatId: peerId, accountPeerId: accountPeerId)
    }

    /// A message's level is its chat's level; a forward is also held to its source's level, and a
    /// source that is unknown or unapproved keeps the fallback (forwarded media stays filtered).
    public func mediaLevel(for message: EngineMessage, accountPeerId: EnginePeer.Id? = nil) -> HarnessgramPolicy.MediaLevel {
        let raw = message._asMessage()
        self.lock.lock()
        defer { self.lock.unlock() }
        var level = self.levelLocked(chat: raw.peers[raw.id.peerId].map(EnginePeer.init), chatId: raw.id.peerId, accountPeerId: accountPeerId)
        if let forwardInfo = raw.forwardInfo {
            if let source = forwardInfo.source ?? forwardInfo.author {
                level = HarnessgramPolicy.strictest(level, self.levelLocked(chat: EnginePeer(source), chatId: source.id, accountPeerId: accountPeerId))
            } else {
                level = HarnessgramPolicy.strictest(level, HarnessgramPolicy.media)
            }
        }
        return level
    }

    /// The same rule for a message known only by reference (reply previews, fetches): the reference
    /// records whether the message is a forward and its source; unknown means the fallback.
    public func mediaLevel(for reference: MessageReference, accountPeerId: EnginePeer.Id? = nil) -> HarnessgramPolicy.MediaLevel {
        guard let messageId = reference.id, let isForward = reference.harnessgramIsForward else {
            return HarnessgramPolicy.media
        }
        self.lock.lock()
        defer { self.lock.unlock() }
        var level = self.levelLocked(chat: nil, chatId: messageId.peerId, accountPeerId: accountPeerId)
        if isForward {
            if let source = reference.harnessgramForwardSourceId {
                level = HarnessgramPolicy.strictest(level, self.levelLocked(chat: nil, chatId: EnginePeer.Id(source), accountPeerId: accountPeerId))
            } else {
                level = HarnessgramPolicy.strictest(level, HarnessgramPolicy.media)
            }
        }
        return level
    }

    /// The chat info page's choice: the chat's own level for this account, or nil when the chat is not
    /// approved for it (or is a secret chat), so no choice is offered. Reading never approves anything.
    public func configurableMediaLevel(forChat peerId: EnginePeer.Id, accountPeerId: EnginePeer.Id) -> HarnessgramPolicy.MediaLevel? {
        if peerId.namespace == Namespaces.Peer.SecretChat {
            return nil
        }
        self.lock.lock()
        defer { self.lock.unlock() }
        guard self.isApprovedChatIdLocked(peerId, accountPeerId: accountPeerId) else {
            return nil
        }
        return self.configuredLevelLocked(peerId, accountPeerId: accountPeerId)
    }

    /// Tightens or loosens one approved chat; nil returns it to the default. Never approves a chat.
    @discardableResult public func setMediaLevel(_ level: HarnessgramPolicy.MediaLevel?, forChat peerId: EnginePeer.Id, accountPeerId: EnginePeer.Id) -> Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        var state = self.state(accountPeerId)
        var levels = state.mediaLevels ?? [:]
        levels[String(peerId.toInt64())] = level?.rawValue
        state.mediaLevels = levels
        return self.save(state, accountPeerId: accountPeerId)
    }

    // MARK: Links

    /// Every preview is built or decoded before its media can be fetched, also when the fetch only
    /// names the message. Media of an unapproved preview never loads, whatever reference asks for it.
    public func noteWebPreview(_ webpage: TelegramMediaWebpage) {
        guard case let .Loaded(content) = webpage.content else {
            return
        }
        var ids: [MediaId] = []
        if let id = content.image?.imageId {
            ids.append(id)
        }
        if let id = content.file?.fileId {
            ids.append(id)
        }
        if ids.isEmpty {
            return
        }
        let approved = self.isApprovedLinkPreview(webpage)
        self.lock.lock()
        defer { self.lock.unlock() }
        for id in ids {
            // Once unapproved anywhere, it stays unapproved.
            self.webPreviewMedia[id] = (self.webPreviewMedia[id] ?? true) && approved
        }
    }

    public func isUnapprovedWebPreviewMedia(_ id: MediaId) -> Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.webPreviewMedia[id] == false
    }

    public func isApprovedLinkPreview(_ webpage: TelegramMediaWebpage) -> Bool {
        if !self.filter.isOn(.linkPreviews) {
            return true
        }
        return HarnessgramPolicy.isApprovedLinkPreview(webpage, domains: self.linkPreviewDomains)
    }

    public func isApprovedLinkPreviewUrl(_ url: String) -> Bool {
        if !self.filter.isOn(.linkPreviews) {
            return true
        }
        return HarnessgramPolicy.isApprovedLinkDomain(url, domains: self.linkPreviewDomains)
    }

    // MARK: Sticker packs

    private func stickerState() -> StickerState {
        if let value = self.stickerStateValue {
            return value
        }
        var value = StickerState()
        if let data = self.defaults.data(forKey: HarnessgramPolicyStore.stickerKey) {
            // Corruption must never reopen the first-run grandfathering window.
            value = (try? JSONDecoder().decode(StickerState.self, from: data)) ?? StickerState(grandfathered: HarnessgramPolicy.ApprovedStickerPacks(), systemIds: [])
        }
        self.stickerStateValue = value
        return value
    }

    private func saveStickerState(_ state: StickerState) -> Bool {
        guard let data = try? JSONEncoder().encode(state) else {
            return false
        }
        self.defaults.set(data, forKey: HarnessgramPolicyStore.stickerKey)
        self.stickerStateValue = state
        self.effectiveStickerPacks = nil
        self.stickerDecisions.removeAll()
        return true
    }

    private func approvedStickerPacks() -> HarnessgramPolicy.ApprovedStickerPacks {
        if let value = self.effectiveStickerPacks {
            return value
        }
        let state = self.stickerState()
        var value = self.bundledStickerPacks.union(state.grandfathered ?? HarnessgramPolicy.ApprovedStickerPacks())
        value.ids.formUnion(state.systemIds)
        self.effectiveStickerPacks = value
        return value
    }

    /// Synchronous and in-memory: safe for rendering and fetch gates.
    public func isApprovedStickerPack(_ reference: StickerPackReference?) -> Bool {
        if !self.filter.isOn(.stickerPacks) {
            return true
        }
        self.lock.lock()
        defer { self.lock.unlock() }
        return HarnessgramPolicy.isApprovedStickerPack(reference, approved: self.approvedStickerPacks())
    }

    public func isApprovedSticker(_ file: TelegramMediaFile) -> Bool {
        if !self.filter.isOn(.stickerPacks) {
            return true
        }
        self.lock.lock()
        defer { self.lock.unlock() }
        return HarnessgramPolicy.isApprovedSticker(file, approved: self.approvedStickerPacks(), topicIconFileIds: self.topicIconFileIds, systemFileIds: self.systemFileIds)
    }

    /// Same decision for picker items, parsed once per file until an approval changes.
    public func isApprovedSticker(_ file: TelegramMediaFile.Accessor) -> Bool {
        if !self.filter.isOn(.stickerPacks) {
            return true
        }
        let fileId = file.fileId
        self.lock.lock()
        defer { self.lock.unlock() }
        if let value = self.stickerDecisions[fileId] {
            return value
        }
        let value = HarnessgramPolicy.isApprovedSticker(file._parse(), approved: self.approvedStickerPacks(), topicIconFileIds: self.topicIconFileIds, systemFileIds: self.systemFileIds)
        self.stickerDecisions[fileId] = value
        return value
    }

    /// Picker item decision. No file means a Unicode emoji or an action icon, always shown.
    /// Collectible gifts are paid gift art outside any approved pack and are never shown.
    public func pickerShowsItem(file: TelegramMediaFile.Accessor?, isGift: Bool) -> Bool {
        if isGift && self.filter.isOn(.stickerPacks) {
            return false
        }
        guard let file else {
            return true
        }
        return self.isApprovedSticker(file)
    }

    public func pickerShowsPackGroup(_ id: ItemCollectionId) -> Bool {
        return HarnessgramPolicy.pickerShowsPackGroup(id, packs: { self.isApprovedStickerPack($0) })
    }

    /// Telegram's standard reaction files (static icon and animations). Custom emoji reactions
    /// are not registered here; they are decided by their pack.
    public func noteSystemFiles(_ fileIds: [Int64]) {
        self.lock.lock()
        defer { self.lock.unlock() }
        let count = self.systemFileIds.count
        self.systemFileIds.formUnion(fileIds.filter { $0 != 0 })
        if self.systemFileIds.count != count {
            self.stickerDecisions.removeAll()
        }
    }

    /// The files of a Telegram system pack (HarnessgramPolicy.isSystemDefaultStickerPack), as loaded for that
    /// system reference from the account's cache or from Telegram. Their sticker attribute names the pack by an
    /// id that may not be learned yet, so each file is approved by its own id (big animated emoji and their
    /// tap effects). Any other reference is ignored.
    public func noteSystemStickerPackFiles(reference: StickerPackReference, fileIds: [MediaId]) {
        guard HarnessgramPolicy.isSystemDefaultStickerPack(reference) else {
            return
        }
        self.noteSystemFiles(fileIds.filter { $0.namespace == Namespaces.Media.CloudFile }.map(\.id))
    }

    public func noteTopicIcon(fileId: Int64?) {
        guard let fileId, fileId != 0 else {
            return
        }
        self.lock.lock()
        defer { self.lock.unlock() }
        if self.topicIconFileIds.insert(fileId).inserted {
            self.stickerDecisions.removeAll()
        }
    }

    public func isApprovedStickerPackInfo(id: Int64, shortName: String) -> Bool {
        return self.isApprovedStickerPack(.id(id: id, accessHash: 0)) || self.isApprovedStickerPack(.name(shortName))
    }

    func needsStickerSnapshot() -> Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.stickerState().grandfathered == nil
    }

    /// Grandfathers the packs installed when the filter first runs. Later installs never extend it.
    func completeStickerSnapshot(_ packs: HarnessgramPolicy.ApprovedStickerPacks) {
        self.lock.lock()
        var state = self.stickerState()
        guard state.grandfathered == nil else {
            self.lock.unlock()
            return
        }
        state.grandfathered = packs
        let saved = self.saveStickerState(state)
        self.revisionValue += 1
        let revision = self.revisionValue
        self.lock.unlock()
        if saved {
            self.revision.set(revision)
        }
    }

    /// The concrete id of a system default pack (HarnessgramPolicy.isSystemDefaultStickerPack), as
    /// answered by Telegram for that system reference. Message stickers name packs by id, never by the system reference.
    func learnSystemStickerPack(reference: StickerPackReference, id: Int64) {
        guard HarnessgramPolicy.isSystemDefaultStickerPack(reference) else {
            return
        }
        self.lock.lock()
        defer { self.lock.unlock() }
        var state = self.stickerState()
        guard !state.systemIds.contains(id) else {
            return
        }
        state.systemIds.insert(id)
        let _ = self.saveStickerState(state)
    }

    /// TODO(Phase 2): deliver these to the owner's Harnessgram bridge and track acknowledgement.
    /// "Request sent" in Phase 1 means saved here, not delivered over the network.
    public func pendingRequests(accountPeerId: EnginePeer.Id) -> [PendingRequest] {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.state(accountPeerId).requests
    }
}
