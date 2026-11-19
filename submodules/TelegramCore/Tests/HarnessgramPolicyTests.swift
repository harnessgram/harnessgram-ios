import XCTest
import Postbox
import HarnessgramSettings
import HarnessgramAgent
import Emoji
import TelegramApi
@testable import TelegramCore

final class HarnessgramPolicyTests: XCTestCase {
    private let accountPeerId = EnginePeer.Id(namespace: Namespaces.Peer.CloudUser, id: EnginePeer.Id.Id._internalFromInt64Value(1))

    private func channel(_ status: TelegramChannelParticipationStatus, isBroadcast: Bool, username: String? = nil, restrictionInfo: PeerAccessRestrictionInfo? = nil) -> EnginePeer {
        let info: TelegramChannelInfo = isBroadcast ? .broadcast(TelegramChannelBroadcastInfo(flags: [])) : .group(TelegramChannelGroupInfo(flags: []))
        return .channel(TelegramChannel(id: EnginePeer.Id(namespace: Namespaces.Peer.CloudChannel, id: EnginePeer.Id.Id._internalFromInt64Value(2)), accessHash: nil, title: "Channel", username: username, photo: [], creationDate: 0, version: 0, participationStatus: status, info: info, flags: [], restrictionInfo: restrictionInfo, adminRights: nil, bannedRights: nil, defaultBannedRights: nil, usernames: [], storiesHidden: nil, nameColor: nil, backgroundEmojiId: nil, profileColor: nil, profileBackgroundEmojiId: nil, emojiStatus: nil, approximateBoostLevel: nil, subscriptionUntilDate: nil, verificationIconFileId: nil, sendPaidMessageStars: nil, linkedMonoforumId: nil))
    }

    func testCachedPublicPeersDoNotBecomeApprovedThroughHistoryOrContacts() {
        for isBroadcast in [false, true] {
            for status: TelegramChannelParticipationStatus in [.left, .kicked] {
                XCTAssertFalse(HarnessgramPolicy.isApprovedPeer(self.channel(status, isBroadcast: isBroadcast), accountPeerId: self.accountPeerId, hasChat: true, isContact: true))
            }
            let member = self.channel(.member, isBroadcast: isBroadcast)
            XCTAssertFalse(HarnessgramPolicy.isApprovedPeer(member, accountPeerId: self.accountPeerId, hasChat: true, isContact: true))
            XCTAssertTrue(HarnessgramPolicy.isApprovedPeer(member, accountPeerId: self.accountPeerId, hasChat: false, isContact: false, grandfatheredIds: [member.id.toInt64()]))
        }
    }

    func testBasicGroupMembershipAloneDoesNotGrantApproval() {
        for membership: TelegramGroupMembership in [.Member, .Left, .Removed] {
            let group = TelegramGroup(id: EnginePeer.Id(namespace: Namespaces.Peer.CloudGroup, id: EnginePeer.Id.Id._internalFromInt64Value(2)), title: "Group", photo: [], participantCount: 1, role: .member, membership: membership, flags: [], defaultBannedRights: nil, migrationReference: nil, creationDate: 0, version: 0)
            XCTAssertFalse(HarnessgramPolicy.isApprovedPeer(.legacyGroup(group), accountPeerId: self.accountPeerId, hasChat: true, isContact: true))
            XCTAssertTrue(HarnessgramPolicy.isApprovedPeer(.legacyGroup(group), accountPeerId: self.accountPeerId, hasChat: false, isContact: false, approved: .init(peerIds: [String(group.id.toInt64())])))
        }
    }

    func testResolvedUsernameAloneIsNotApprovalButExistingConversationsRemainAccessible() {
        let user = EnginePeer.user(TelegramUser(
            id: EnginePeer.Id(namespace: Namespaces.Peer.CloudUser, id: EnginePeer.Id.Id._internalFromInt64Value(2)),
            accessHash: nil, firstName: "User", lastName: nil, username: "user", phone: nil, photo: [],
            botInfo: nil, restrictionInfo: nil, flags: [], emojiStatus: nil, usernames: [],
            storiesHidden: nil, nameColor: nil, backgroundEmojiId: nil, profileColor: nil,
            profileBackgroundEmojiId: nil, subscriberCount: nil, verificationIconFileId: nil
        ))
        XCTAssertFalse(HarnessgramPolicy.isApprovedPeer(user, accountPeerId: self.accountPeerId, hasChat: false, isContact: false))
        // Slice 10: a chat with a stranger is not approval; a chat that existed on the first run is.
        XCTAssertFalse(HarnessgramPolicy.isApprovedPeer(user, accountPeerId: self.accountPeerId, hasChat: true, isContact: false))
        XCTAssertTrue(HarnessgramPolicy.isApprovedPeer(user, accountPeerId: self.accountPeerId, hasChat: true, isContact: false, grandfatheredPrivateIds: [user.id.toInt64()]))
        XCTAssertFalse(HarnessgramPolicy.isApprovedPeer(user, accountPeerId: self.accountPeerId, hasChat: false, isContact: false, grandfatheredPrivateIds: [user.id.toInt64()]))
        XCTAssertTrue(HarnessgramPolicy.isApprovedPeer(user, accountPeerId: self.accountPeerId, hasChat: false, isContact: true))
        XCTAssertTrue(HarnessgramPolicy.isApprovedPeer(user, accountPeerId: user.id, hasChat: false, isContact: false))
    }

    func testExplicitUsernameAndNamespacedIdApprovalAllowJoiningButMembershipDoesNot() {
        let peer = self.channel(.left, isBroadcast: true, username: "SafeChannel")
        XCTAssertTrue(HarnessgramPolicy.isApprovedGroup(peer, approved: .init(usernames: [" @SAFECHANNEL "]), grandfatheredIds: []))
        XCTAssertTrue(HarnessgramPolicy.isApprovedGroup(peer, approved: .init(peerIds: [String(peer.id.toInt64())]), grandfatheredIds: []))
        XCTAssertFalse(HarnessgramPolicy.isApprovedGroup(peer, approved: .init(usernames: ["other"]), grandfatheredIds: []))
        let sameNumberDifferentNamespace = EnginePeer.Id(namespace: Namespaces.Peer.CloudGroup, id: EnginePeer.Id.Id._internalFromInt64Value(2))
        XCTAssertFalse(HarnessgramPolicy.isApprovedGroup(peer, approved: .init(peerIds: [String(sameNumberDifferentNamespace.toInt64())]), grandfatheredIds: []))
    }

    func testOpaqueInviteRequestsDoNotStoreTheInviteToken() {
        let token = "example-private-invite"
        let id = HarnessgramPolicy.inviteRequestId(token)
        XCTAssertTrue(id.hasPrefix("invite:"))
        XCTAssertFalse(id.contains(token))
        XCTAssertEqual(id, HarnessgramPolicy.inviteRequestId(token))
        XCTAssertNotEqual(id, HarnessgramPolicy.inviteRequestId("different-invite"))
    }

    func testGrandfatheringCapturesOnlyMembersAndNeverExtendsAnExistingSnapshot() {
        let member = self.channel(.member, isBroadcast: true)
        let peek = self.channel(.left, isBroadcast: true)
        XCTAssertEqual(HarnessgramPolicy.grandfatheredIds(existing: nil, peers: [member]), [member.id.toInt64()])
        XCTAssertTrue(HarnessgramPolicy.grandfatheredIds(existing: nil, peers: [peek]).isEmpty)
        XCTAssertTrue(HarnessgramPolicy.grandfatheredIds(existing: [], peers: [member]).isEmpty)
        XCTAssertEqual(HarnessgramPolicy.grandfatheredIds(existing: [99], peers: [member]), [99])
    }

    private func withApprovalStore(_ body: (HarnessgramPolicyStore, UserDefaults) -> Void) {
        let suite = "HarnessgramPolicyTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        body(HarnessgramPolicyStore(defaults: defaults, approved: .init()), defaults)
    }

    func testStorePersistsOnceIncludingEmptySnapshotAndSeparatesAccounts() {
        self.withApprovalStore { store, defaults in
            let member = self.channel(.member, isBroadcast: true)
            store.captureMembership(peers: [member], accountPeerId: self.accountPeerId)
            XCTAssertTrue(store.isApprovedGroup(member, accountPeerId: self.accountPeerId))
            let restored = HarnessgramPolicyStore(defaults: defaults, approved: .init())
            restored.captureMembership(peers: [], accountPeerId: self.accountPeerId)
            XCTAssertTrue(restored.isApprovedGroup(member, accountPeerId: self.accountPeerId))
            let otherAccount = EnginePeer.Id(namespace: Namespaces.Peer.CloudUser, id: EnginePeer.Id.Id._internalFromInt64Value(9))
            restored.captureMembership(peers: [], accountPeerId: otherAccount)
            restored.captureMembership(peers: [member], accountPeerId: otherAccount)
            XCTAssertFalse(restored.isApprovedGroup(member, accountPeerId: otherAccount))
            XCTAssertFalse(restored.isApprovedChatId(member.id, accountPeerId: otherAccount))
        }
    }

    func testInitialServerSweepIncludesUncachedMembershipOnlyOnce() {
        self.withApprovalStore { store, defaults in
            let peer = self.channel(.member, isBroadcast: true)
            store.captureMembership(peers: [], accountPeerId: self.accountPeerId)
            XCTAssertTrue(store.needsServerSnapshot(accountPeerId: self.accountPeerId))
            store.completeInitialMembership(peers: [peer], accountPeerId: self.accountPeerId)
            let restored = HarnessgramPolicyStore(defaults: defaults, approved: .init())
            XCTAssertFalse(restored.needsServerSnapshot(accountPeerId: self.accountPeerId))
            XCTAssertTrue(restored.isApprovedGroup(peer, accountPeerId: self.accountPeerId))
            let otherAccount = EnginePeer.Id(namespace: Namespaces.Peer.CloudUser, id: EnginePeer.Id.Id._internalFromInt64Value(9))
            restored.captureMembership(peers: [], accountPeerId: otherAccount)
            restored.completeInitialMembership(peers: [], accountPeerId: otherAccount)
            restored.completeInitialMembership(peers: [peer], accountPeerId: otherAccount)
            XCTAssertFalse(restored.isApprovedGroup(peer, accountPeerId: otherAccount))
        }
    }

    func testPendingRequestsPersistDeduplicateAndNeverGrantApproval() {
        self.withApprovalStore { store, defaults in
            let peer = self.channel(.left, isBroadcast: true)
            let id = String(peer.id.toInt64())
            XCTAssertTrue(store.requestApproval(accountPeerId: self.accountPeerId, id: id, title: "Channel", time: 10))
            XCTAssertTrue(store.requestApproval(accountPeerId: self.accountPeerId, id: id, title: "Channel", time: 20))
            let restored = HarnessgramPolicyStore(defaults: defaults, approved: .init())
            let requests = restored.pendingRequests(accountPeerId: self.accountPeerId)
            XCTAssertEqual(requests.count, 1)
            XCTAssertEqual(requests.first?.id, id)
            XCTAssertEqual(requests.first?.title, "Channel")
            XCTAssertEqual(requests.first?.time, 10)
            XCTAssertFalse(restored.isApprovedGroup(peer, accountPeerId: self.accountPeerId))
            XCTAssertFalse(restored.isApprovedChatId(peer.id, accountPeerId: self.accountPeerId))
        }
    }

    func testUnapprovedJoinIsBlockedAndRecordsOneRequestAcrossRetries() {
        self.withApprovalStore { store, defaults in
            let peer = self.channel(.left, isBroadcast: true)
            let target = HarnessgramPolicyStore.JoinTarget.chat(id: peer.id, peer: peer)
            XCTAssertTrue(store.requestApproval(accountPeerId: self.accountPeerId, id: String(peer.id.toInt64()), title: "Channel", time: 10))
            XCTAssertEqual(store.evaluateJoin(target, accountPeerId: self.accountPeerId), .committeeApprovalRequired(requestRecorded: true))
            let restored = HarnessgramPolicyStore(defaults: defaults, approved: .init())
            XCTAssertEqual(restored.evaluateJoin(target, accountPeerId: self.accountPeerId), .committeeApprovalRequired(requestRecorded: true))
            let requests = restored.pendingRequests(accountPeerId: self.accountPeerId)
            XCTAssertEqual(requests.map(\.id), [String(peer.id.toInt64())])
            XCTAssertEqual(requests.map(\.title), ["Join Channel"])
            XCTAssertEqual(requests.map(\.time), [10])
        }
    }

    func testApprovedJoinProceedsForTheCorrectAccountWithoutRecordingARequest() {
        self.withApprovalStore { store, defaults in
            let peer = self.channel(.left, isBroadcast: true, username: "ApprovedChannel")
            let target = HarnessgramPolicyStore.JoinTarget.chat(id: peer.id, peer: peer)
            store.noteCreatedChat(peer.id, accountPeerId: self.accountPeerId)
            XCTAssertEqual(store.evaluateJoin(target, accountPeerId: self.accountPeerId), .allowed)
            XCTAssertTrue(store.pendingRequests(accountPeerId: self.accountPeerId).isEmpty)

            let other = EnginePeer.Id(namespace: Namespaces.Peer.CloudUser, id: EnginePeer.Id.Id._internalFromInt64Value(9))
            XCTAssertEqual(store.evaluateJoin(target, accountPeerId: other), .committeeApprovalRequired(requestRecorded: true))
            let configured = HarnessgramPolicyStore(defaults: defaults, approved: .init(usernames: ["@approvedchannel"]))
            XCTAssertEqual(configured.evaluateJoin(target, accountPeerId: other), .allowed)
        }
    }

    func testJoinFailsClosedWithoutAnAccountOrTrustworthyTargetAndApproval() {
        self.withApprovalStore { store, defaults in
            let peer = self.channel(.member, isBroadcast: true)
            let target = HarnessgramPolicyStore.JoinTarget.chat(id: peer.id, peer: peer)
            XCTAssertEqual(store.evaluateJoin(target, accountPeerId: nil), .committeeApprovalRequired(requestRecorded: false))
            XCTAssertTrue(store.pendingRequests(accountPeerId: self.accountPeerId).isEmpty)

            defaults.set(Data("invalid".utf8), forKey: "Harnessgram.approvals.v1.\(self.accountPeerId.toInt64())")
            let restored = HarnessgramPolicyStore(defaults: defaults, approved: .init())
            XCTAssertEqual(restored.evaluateJoin(target, accountPeerId: self.accountPeerId), .committeeApprovalRequired(requestRecorded: true))
            XCTAssertEqual(restored.evaluateJoin(.chat(id: peer.id, peer: nil), accountPeerId: self.accountPeerId), .committeeApprovalRequired(requestRecorded: true))

            let hash = "private-invite-token"
            let account = self.accountPeerId
            XCTAssertEqual(restored.evaluateJoin(.invite(hash: hash, title: "Hidden Group"), accountPeerId: account), .committeeApprovalRequired(requestRecorded: true))
            let request = restored.pendingRequests(accountPeerId: account).last
            XCTAssertEqual(request?.id, HarnessgramPolicy.inviteRequestId(hash))
            XCTAssertEqual(request?.title, "Join Hidden Group")
        }
    }

    func testCorruptStateFailsClosedInsteadOfGrandfatheringAgain() {
        self.withApprovalStore { store, defaults in
            defaults.set(Data("invalid".utf8), forKey: "Harnessgram.approvals.v1.\(self.accountPeerId.toInt64())")
            let peer = self.channel(.member, isBroadcast: true)
            store.captureMembership(peers: [peer], accountPeerId: self.accountPeerId)
            XCTAssertFalse(store.isApprovedGroup(peer, accountPeerId: self.accountPeerId))
        }
    }

    /// Owner, 2026-11-17: creating a channel, group or community is never filtered; the new chat is approved
    /// by its id at creation, and that approval survives restarts and the membership snapshots.
    func testOwnerCreatedChatsAreApprovedByIdWithTheFilterOn() {
        self.withApprovalStore { store, defaults in
            XCTAssertTrue(store.filter.isOn(.approvedChats))
            store.captureMembership(peers: [], accountPeerId: self.accountPeerId)
            let channel = self.channel(.member, isBroadcast: true)
            let group = EnginePeer.Id(namespace: Namespaces.Peer.CloudGroup, id: EnginePeer.Id.Id._internalFromInt64Value(3))
            XCTAssertFalse(store.isApprovedGroup(channel, accountPeerId: self.accountPeerId))
            XCTAssertTrue(store.noteCreatedChat(channel.id, accountPeerId: self.accountPeerId))
            XCTAssertTrue(store.noteCreatedChat(group, accountPeerId: self.accountPeerId))
            XCTAssertTrue(store.isApprovedGroup(channel, accountPeerId: self.accountPeerId))
            XCTAssertTrue(store.isApprovedChatId(channel.id, accountPeerId: self.accountPeerId))
            XCTAssertTrue(store.isApprovedChatId(group, accountPeerId: self.accountPeerId))
            XCTAssertTrue(store.isListedChat(channel, accountPeerId: self.accountPeerId))
            // Media inside it follows the approved-chat default, like any approved chat.
            XCTAssertEqual(store.mediaLevel(forChatId: channel.id, accountPeerId: self.accountPeerId), HarnessgramPolicy.approvedChatMedia)

            // Merging the server's membership snapshot (and a later capture) never drops it.
            store.completeInitialMembership(peers: [], accountPeerId: self.accountPeerId)
            let restored = HarnessgramPolicyStore(defaults: defaults, approved: .init())
            restored.captureMembership(peers: [], accountPeerId: self.accountPeerId)
            restored.completeInitialMembership(peers: [], accountPeerId: self.accountPeerId)
            XCTAssertTrue(restored.isApprovedGroup(channel, accountPeerId: self.accountPeerId))
            XCTAssertTrue(restored.isApprovedChatId(group, accountPeerId: self.accountPeerId))

            // Per account, and never for users or secret chats.
            let otherAccount = EnginePeer.Id(namespace: Namespaces.Peer.CloudUser, id: EnginePeer.Id.Id._internalFromInt64Value(9))
            restored.captureMembership(peers: [], accountPeerId: otherAccount)
            XCTAssertFalse(restored.isApprovedChatId(channel.id, accountPeerId: otherAccount))
            let user = EnginePeer.Id(namespace: Namespaces.Peer.CloudUser, id: EnginePeer.Id.Id._internalFromInt64Value(4))
            let secret = EnginePeer.Id(namespace: Namespaces.Peer.SecretChat, id: EnginePeer.Id.Id._internalFromInt64Value(5))
            XCTAssertFalse(restored.noteCreatedChat(user, accountPeerId: self.accountPeerId))
            XCTAssertFalse(restored.noteCreatedChat(secret, accountPeerId: self.accountPeerId))
        }
    }

    private func createdAnswer(_ action: Api.MessageAction, peer: Api.Peer, chats: [Api.Chat]) -> Api.Updates {
        let message: Api.Message = .messageService(.init(flags: 1 << 1, id: 1, fromId: nil, peerId: peer, savedPeerId: nil, replyTo: nil, date: 1, action: action, reactions: nil, ttlPeriod: nil))
        return StateSyncApi.updates([StateSyncApi.updateNewChannelMessage(message, pts: 1)], chats: chats, date: 1, seq: 0)
    }

    /// Final review: only the "created" service message of a chat named in the answer approves it, and never a
    /// supergroup made for a history import.
    func testOnlyTheCreatedServiceMessageOfAChatInTheAnswerApprovesIt() {
        let channel = StateSyncApi.broadcastChannel(id: 41)
        let channelId = EnginePeer.Id(namespace: Namespaces.Peer.CloudChannel, id: EnginePeer.Id.Id._internalFromInt64Value(41))
        let created = self.createdAnswer(.messageActionChannelCreate(.init(title: "New")), peer: StateSyncApi.peerChannel(41), chats: [channel])
        XCTAssertEqual(harnessgramCreatedChatId(created), channelId)
        XCTAssertNil(harnessgramCreatedChatId(created, isForHistoryImport: true))
        // The chat is not in the answer, or the message is another service message: nothing is approved.
        XCTAssertNil(harnessgramCreatedChatId(self.createdAnswer(.messageActionChannelCreate(.init(title: "New")), peer: StateSyncApi.peerChannel(41), chats: [StateSyncApi.broadcastChannel(id: 42)])))
        XCTAssertNil(harnessgramCreatedChatId(self.createdAnswer(.messageActionHistoryClear, peer: StateSyncApi.peerChannel(41), chats: [channel])))
        let group: Api.Chat = .chat(.init(flags: 0, id: 43, title: "G", photo: .chatPhotoEmpty, participantsCount: 1, date: 1, version: 1, migratedTo: nil, adminRights: nil, defaultBannedRights: nil))
        let groupAnswer = self.createdAnswer(.messageActionChatCreate(.init(title: "G", users: [])), peer: .peerChat(.init(chatId: 43)), chats: [group])
        XCTAssertEqual(harnessgramCreatedChatId(groupAnswer), EnginePeer.Id(namespace: Namespaces.Peer.CloudGroup, id: EnginePeer.Id.Id._internalFromInt64Value(43)))
        // An ordinary message is not a creation.
        let post = StateSyncApi.updates([StateSyncApi.updateNewChannelMessage(StateSyncApi.channelPost(id: 1, channelId: 41, date: 1), pts: 1)], chats: [channel], date: 1, seq: 0)
        XCTAssertNil(harnessgramCreatedChatId(post))
    }

    /// Final review: an approved basic group (created here or in the first-run snapshot) stays approved as the
    /// supergroup it became; any other upgrade keeps the usual rules.
    func testAnApprovedBasicGroupStaysApprovedAfterTheSupergroupUpgrade() {
        self.withApprovalStore { store, defaults in
            let created = EnginePeer.Id(namespace: Namespaces.Peer.CloudGroup, id: EnginePeer.Id.Id._internalFromInt64Value(50))
            let grandfathered = EnginePeer.Id(namespace: Namespaces.Peer.CloudGroup, id: EnginePeer.Id.Id._internalFromInt64Value(51))
            let stranger = EnginePeer.Id(namespace: Namespaces.Peer.CloudGroup, id: EnginePeer.Id.Id._internalFromInt64Value(52))
            let group = TelegramGroup(id: grandfathered, title: "Group", photo: [], participantCount: 1, role: .member, membership: .Member, flags: [], defaultBannedRights: nil, migrationReference: nil, creationDate: 0, version: 0)
            store.captureMembership(peers: [.legacyGroup(group)], accountPeerId: self.accountPeerId)
            store.noteCreatedChat(created, accountPeerId: self.accountPeerId)
            let channel: (Int64) -> EnginePeer.Id = { EnginePeer.Id(namespace: Namespaces.Peer.CloudChannel, id: EnginePeer.Id.Id._internalFromInt64Value($0)) }

            XCTAssertTrue(store.noteMigratedChat(from: created, to: channel(60), accountPeerId: self.accountPeerId))
            XCTAssertTrue(store.noteMigratedChat(from: grandfathered, to: channel(61), accountPeerId: self.accountPeerId))
            XCTAssertFalse(store.noteMigratedChat(from: stranger, to: channel(62), accountPeerId: self.accountPeerId))
            // Namespaces must be basic group -> channel.
            XCTAssertFalse(store.noteMigratedChat(from: channel(60), to: channel(63), accountPeerId: self.accountPeerId))
            XCTAssertFalse(store.noteMigratedChat(from: created, to: EnginePeer.Id(namespace: Namespaces.Peer.CloudGroup, id: EnginePeer.Id.Id._internalFromInt64Value(64)), accountPeerId: self.accountPeerId))

            let restored = HarnessgramPolicyStore(defaults: defaults, approved: .init())
            XCTAssertTrue(restored.isApprovedChatId(channel(60), accountPeerId: self.accountPeerId))
            XCTAssertTrue(restored.isApprovedChatId(channel(61), accountPeerId: self.accountPeerId))
            XCTAssertFalse(restored.isApprovedChatId(channel(62), accountPeerId: self.accountPeerId))
            XCTAssertFalse(restored.isApprovedChatId(channel(63), accountPeerId: self.accountPeerId))
            // A repeat (the server's own copy of the upgrade) changes nothing and still answers approved.
            XCTAssertTrue(restored.noteMigratedChat(from: created, to: channel(60), accountPeerId: self.accountPeerId))
        }
    }

    func testChatListReplayRecoversOnlyApprovedBasicGroupMigrationsAfterRestart() {
        self.withApprovalStore { store, defaults in
            let groupId: (Int64) -> EnginePeer.Id = { EnginePeer.Id(namespace: Namespaces.Peer.CloudGroup, id: EnginePeer.Id.Id._internalFromInt64Value($0)) }
            let channelId: (Int64) -> EnginePeer.Id = { EnginePeer.Id(namespace: Namespaces.Peer.CloudChannel, id: EnginePeer.Id.Id._internalFromInt64Value($0)) }
            let group: (Int64, Int64?) -> TelegramGroup = { id, migratedId in
                return TelegramGroup(id: groupId(id), title: "Group", photo: [], participantCount: 1, role: .member, membership: .Member, flags: [], defaultBannedRights: nil, migrationReference: migratedId.map { TelegramGroupToChannelMigrationReference(peerId: channelId($0), accessHash: 0) }, creationDate: 0, version: 0)
            }
            store.captureMembership(peers: [.legacyGroup(group(71, nil))], accountPeerId: self.accountPeerId)
            store.completeInitialMembership(peers: [], accountPeerId: self.accountPeerId)
            store.noteCreatedChat(groupId(70), accountPeerId: self.accountPeerId)
            store.noteCreatedChat(groupId(73), accountPeerId: self.accountPeerId)
            store.noteCreatedChat(channelId(74), accountPeerId: self.accountPeerId)

            // No queued service-message callback ran before termination; only the peers were persisted.
            let restarted = HarnessgramPolicyStore(defaults: defaults, approved: .init())
            XCTAssertEqual(Set(restarted.migrationReplayPeerIds(accountPeerId: self.accountPeerId)), [groupId(70), groupId(71), groupId(73)])
            XCTAssertFalse(restarted.isApprovedChatId(channelId(80), accountPeerId: self.accountPeerId))
            XCTAssertFalse(restarted.isApprovedChatId(channelId(81), accountPeerId: self.accountPeerId))
            let groups = [group(70, 80), group(71, 81), group(72, 82), group(73, nil)]
            restarted.replayMigratedChats(groups: groups, accountPeerId: self.accountPeerId)

            // The replay uses noteMigratedChat, so the recovered approvals survive another restart.
            let restored = HarnessgramPolicyStore(defaults: defaults, approved: .init())
            XCTAssertTrue(restored.isApprovedChatId(channelId(80), accountPeerId: self.accountPeerId))
            XCTAssertTrue(restored.isApprovedChatId(channelId(81), accountPeerId: self.accountPeerId))
            XCTAssertFalse(restored.isApprovedChatId(channelId(82), accountPeerId: self.accountPeerId))
            let otherAccount = EnginePeer.Id(namespace: Namespaces.Peer.CloudUser, id: EnginePeer.Id.Id._internalFromInt64Value(9))
            restored.replayMigratedChats(groups: groups, accountPeerId: otherAccount)
            XCTAssertFalse(restored.isApprovedChatId(channelId(80), accountPeerId: otherAccount))
            XCTAssertFalse(restored.isApprovedChatId(channelId(81), accountPeerId: otherAccount))

            let key = "Harnessgram.approvals.v1.\(self.accountPeerId.toInt64())"
            let data = defaults.data(forKey: key)
            restored.replayMigratedChats(groups: groups, accountPeerId: self.accountPeerId)
            XCTAssertEqual(defaults.data(forKey: key), data)
        }
    }

    func testOnlyExactlyOneReturnedCommunityGrantsCreationApproval() {
        let community: (Int64) -> TelegramCommunity = { id in
            return TelegramCommunity(id: EnginePeer.Id(namespace: Namespaces.Peer.CloudChannel, id: EnginePeer.Id.Id._internalFromInt64Value(id)), accessHash: nil, title: "Community", photo: [], creationDate: 0, participationStatus: .member, flags: [], collapsedInDialogs: nil, adminRights: nil, defaultBannedRights: nil)
        }
        let first = community(90)
        let second = community(91)
        XCTAssertNil(harnessgramCreatedCommunityId([]))
        XCTAssertEqual(harnessgramCreatedCommunityId([first]), first.id)
        XCTAssertNil(harnessgramCreatedCommunityId([first, second]))
    }

    /// A chat whose ownership was transferred to the owner is not created by him here: the creator flag
    /// alone never approves it.
    func testTransferredChatIsNotApprovedByTheCreatorFlag() {
        self.withApprovalStore { store, _ in
            store.captureMembership(peers: [], accountPeerId: self.accountPeerId)
            store.completeInitialMembership(peers: [], accountPeerId: self.accountPeerId)
            let transferred = EnginePeer.channel(TelegramChannel(id: EnginePeer.Id(namespace: Namespaces.Peer.CloudChannel, id: EnginePeer.Id.Id._internalFromInt64Value(6)), accessHash: nil, title: "Transferred", username: nil, photo: [], creationDate: 0, version: 0, participationStatus: .member, info: .broadcast(TelegramChannelBroadcastInfo(flags: [])), flags: [.isCreator], restrictionInfo: nil, adminRights: nil, bannedRights: nil, defaultBannedRights: nil, usernames: [], storiesHidden: nil, nameColor: nil, backgroundEmojiId: nil, profileColor: nil, profileBackgroundEmojiId: nil, emojiStatus: nil, approximateBoostLevel: nil, subscriptionUntilDate: nil, verificationIconFileId: nil, sendPaidMessageStars: nil, linkedMonoforumId: nil))
            XCTAssertFalse(store.isApprovedGroup(transferred, accountPeerId: self.accountPeerId))
            XCTAssertFalse(store.isApprovedChatId(transferred.id, accountPeerId: self.accountPeerId))
            XCTAssertFalse(store.isListedChat(transferred, accountPeerId: self.accountPeerId))
        }
    }

    private func mediaFile(mimeType: String, attributes: [TelegramMediaFileAttribute] = []) -> TelegramMediaFile {
        return TelegramMediaFile(fileId: EngineMedia.Id(namespace: Namespaces.Media.CloudFile, id: 10), partialReference: nil, resource: self.cloudResource(10), previewRepresentations: [], videoThumbnails: [], immediateThumbnailData: nil, mimeType: mimeType, size: 100, attributes: attributes, alternativeRepresentations: [])
    }

    func testMediaLevelsPermitPhotosAndOnlyDocumentsAtTheDocumentsLevel() {
        let photo = TelegramMediaImage(imageId: EngineMedia.Id(namespace: Namespaces.Media.CloudImage, id: 1), representations: [], immediateThumbnailData: nil, reference: nil, partialReference: nil, flags: [])
        let document = self.mediaFile(mimeType: "application/pdf")
        XCTAssertEqual(HarnessgramPolicy.media, .photos)
        XCTAssertFalse(HarnessgramPolicy.allowsMedia(.image(photo), level: .textOnly))
        XCTAssertFalse(HarnessgramPolicy.allowsMedia(.file(document), level: .textOnly))
        XCTAssertTrue(HarnessgramPolicy.allowsMedia(.image(photo), level: .photos))
        XCTAssertTrue(HarnessgramPolicy.allowsMedia(.file(self.mediaFile(mimeType: "image/jpeg")), level: .photos))
        XCTAssertFalse(HarnessgramPolicy.allowsMedia(.file(document), level: .photos))
        XCTAssertTrue(HarnessgramPolicy.allowsMedia(.file(document), level: .documents))
    }

    func testMotionAndAudioStayHiddenEvenAtTheDocumentsLevel() {
        let files = [
            self.mediaFile(mimeType: "video/mp4"),
            self.mediaFile(mimeType: "image/gif"),
            self.mediaFile(mimeType: "image/apng"),
            self.mediaFile(mimeType: "image/webp", attributes: [.Animated]),
            self.mediaFile(mimeType: "video/webm", attributes: [.Sticker(displayText: "", packReference: nil, maskData: nil)]),
            self.mediaFile(mimeType: "application/x-tgsticker"),
            self.mediaFile(mimeType: "audio/ogg"),
            self.mediaFile(mimeType: "application/octet-stream", attributes: [.Video(duration: 1.0, size: .init(width: 100, height: 100), flags: [.instantRoundVideo], preloadSize: nil, coverTime: nil, videoCodec: nil)])
        ]
        for level: HarnessgramPolicy.MediaLevel in [.textOnly, .photos, .documents] {
            for file in files {
                XCTAssertFalse(HarnessgramPolicy.allowsMedia(.file(file), level: level), file.mimeType)
            }
        }
    }

    func testPendingWebPreviewsAndTheirResourceRequestsAreHidden() {
        let webpage = TelegramMediaWebpage(webpageId: EngineMedia.Id(namespace: Namespaces.Media.CloudWebpage, id: 1), content: .Pending(0, nil))
        XCTAssertFalse(HarnessgramPolicy.allowsMedia(.webpage(webpage)))
        let file = self.mediaFile(mimeType: "video/mp4")
        XCTAssertFalse(HarnessgramPolicy.allowsResource(FileMediaReference.standalone(media: file).resourceReference(file.resource)))
        let photo = self.mediaFile(mimeType: "image/jpeg")
        XCTAssertTrue(HarnessgramPolicy.allowsResource(FileMediaReference.standalone(media: photo).resourceReference(photo.resource)))
    }

    func testDirectFetchCannotSkipThePolicyUsingOnlyAContentType() {
        let file = self.mediaFile(mimeType: "video/mp4")
        XCTAssertFalse(harnessgramAllowsResourceFetch(resource: file.resource, parameters: .init(tag: nil, info: nil, location: nil, contentType: .video, isRandomAccessAllowed: true)))
        let reference = FileMediaReference.standalone(media: file).resourceReference(file.resource)
        XCTAssertFalse(harnessgramAllowsResourceFetch(resource: file.resource, parameters: .init(tag: nil, info: TelegramCloudMediaResourceFetchInfo(reference: reference, preferBackgroundReferenceRevalidation: false, continueInBackground: false), location: nil, contentType: .image, isRandomAccessAllowed: true)))
    }

    private func photoMessage(attributes: [EngineMessage.Attribute] = [], peer: EnginePeer? = nil, incoming: Bool = true, representations: [TelegramMediaImageRepresentation] = [], flags: TelegramMediaImageFlags = []) -> EngineMessage {
        let photo = TelegramMediaImage(imageId: EngineMedia.Id(namespace: Namespaces.Media.CloudImage, id: 1), representations: representations, immediateThumbnailData: nil, reference: nil, partialReference: nil, flags: flags)
        return EngineMessage(
            stableId: 1, stableVersion: 0,
            id: EngineMessage.Id(peerId: peer?.id ?? self.accountPeerId, namespace: Namespaces.Message.Cloud, id: 1),
            globallyUniqueId: nil, groupingKey: nil, groupInfo: nil, threadId: nil, timestamp: 0,
            flags: incoming ? [.Incoming] : [], tags: [], globalTags: [], localTags: [], customTags: [], forwardInfo: nil,
            author: nil, text: "Caption", attributes: attributes, media: [.image(photo)],
            peers: peer.map { [$0.id: $0] } ?? [:], associatedMessages: [:], associatedMessageIds: [],
            associatedMedia: [:], associatedThreadInfo: nil, associatedStories: [:]
        )
    }

    func testSpoilerPhotoIsHiddenAtEveryLevelIncludingInAnApprovedChat() {
        let peer = self.channel(.member, isBroadcast: true)
        let spoiler = self.photoMessage(attributes: [MediaSpoilerMessageAttribute()], peer: peer)
        self.withApprovalStore { store, _ in
            store.captureMembership(peers: [peer], accountPeerId: self.accountPeerId)
            let level = store.mediaLevel(for: spoiler, accountPeerId: self.accountPeerId)
            XCTAssertEqual(level, .all)
            XCTAssertTrue(HarnessgramPolicy.hidesSpoilerMedia(spoiler, enabled: true))
            XCTAssertTrue(HarnessgramPolicy.hasHiddenMedia(spoiler, level: level))
        }
        for level: HarnessgramPolicy.MediaLevel in [.textOnly, .photos, .documents, .all] {
            XCTAssertTrue(HarnessgramPolicy.hasHiddenMedia(spoiler, level: level))
        }
        XCTAssertFalse(HarnessgramPolicy.allowsCurrentMessageResourceFetch(spoiler, peer: peer))
    }

    func testOwnOutgoingAndDeviceLocalSpoilerPhotosRemainVisible() {
        let attribute = MediaSpoilerMessageAttribute()
        let own = self.photoMessage(attributes: [attribute], incoming: false)
        XCTAssertFalse(HarnessgramPolicy.hasHiddenMedia(own, level: .all))
        let local = TelegramMediaImageRepresentation(dimensions: .init(width: 10, height: 10), resource: LocalFileMediaResource(fileId: 99), progressiveSizes: [], immediateThumbnailData: nil, hasVideo: false, isPersonal: false)
        let draft = self.photoMessage(attributes: [attribute], representations: [local])
        XCTAssertFalse(HarnessgramPolicy.hasHiddenMedia(draft, level: .all))
    }

    func testMediaSpoilerFlagIsSufficientWithoutAMessageAttribute() {
        let photo = self.photoMessage(flags: [.hasSpoiler])
        XCTAssertTrue(HarnessgramPolicy.hidesSpoilerMedia(photo, enabled: true))
        XCTAssertFalse(HarnessgramPolicy.hidesSpoilerMedia(photo, enabled: false))
        XCTAssertTrue(HarnessgramPolicy.hasHiddenMedia(photo, level: .all))
        XCTAssertFalse(HarnessgramPolicy.hasHiddenMedia(self.photoMessage(incoming: false, flags: [.hasSpoiler]), level: .all))
    }

    func testTelegramSpoilerFlagsSurviveParsingMediaWithoutMessageAttributes() {
        let photo: Api.Photo = .photo(.init(flags: 0, id: 1, accessHash: 0, fileReference: Buffer(data: Data()), date: 0, sizes: [], videoSizes: nil, dcId: 1))
        let photoMedia: Api.MessageMedia = .messageMediaPhoto(.init(flags: (1 << 0) | (1 << 3), photo: photo, ttlSeconds: nil, video: nil))
        let document: Api.Document = .document(.init(flags: 0, id: 2, accessHash: 0, fileReference: Buffer(data: Data()), date: 0, mimeType: "video/mp4", size: 1, thumbs: nil, videoThumbs: nil, dcId: 1, attributes: []))
        let documentMedia: Api.MessageMedia = .messageMediaDocument(.init(flags: (1 << 0) | (1 << 4), document: document, altDocuments: nil, videoCover: nil, videoTimestamp: nil, ttlSeconds: nil))
        for apiMedia in [photoMedia, documentMedia] {
            let parsed = textMediaAndExpirationTimerFromApiMedia(apiMedia, self.accountPeerId)
            XCTAssertEqual(parsed.hasSpoiler, true)
            guard let standalone = parsed.media, let nested = nestedMediaFromApi(apiMedia, self.accountPeerId) else {
                XCTFail("Expected attachment media")
                continue
            }
            let chat = self.reviewGroup(77)
            let ordinary = EngineMessage(self.reviewMessage(in: chat, outgoing: false, media: [standalone]))
            let embedded = EngineMessage(self.reviewMessage(in: chat, outgoing: false, media: [nested]))
            XCTAssertFalse(HarnessgramPolicy.hidesSpoilerMedia(ordinary, enabled: true))
            XCTAssertTrue(HarnessgramPolicy.hidesSpoilerMedia(embedded, enabled: true))
        }
    }

    func testUnmarkedPhotosKeepTheirMediaLevel() {
        let photo = self.photoMessage()
        XCTAssertFalse(HarnessgramPolicy.hidesSpoilerMedia(photo, enabled: true))
        XCTAssertFalse(HarnessgramPolicy.hasHiddenMedia(photo, level: .all))
        XCTAssertTrue(HarnessgramPolicy.hasHiddenMedia(photo, level: .textOnly))
    }

    func testSensitiveSettingsCannotOverrideTheLocalFilter() {
        XCTAssertTrue(HarnessgramPolicy.forceSensitiveFilter)
        var contentSettings = ContentSettings(ignoreContentRestrictionReasons: ["sensitive", "porn", "other"], addContentRestrictionReasons: [])
        XCTAssertEqual(contentSettings.ignoreContentRestrictionReasons, ["other"])
        contentSettings.ignoreContentRestrictionReasons = ["sensitive", "porn"]
        XCTAssertTrue(contentSettings.ignoreContentRestrictionReasons.isEmpty)
        var configuration = ContentSettingsConfiguration(sensitiveContentEnabled: true, canAdjustSensitiveContent: true)
        XCTAssertFalse(configuration.sensitiveContentEnabled)
        XCTAssertFalse(configuration.canAdjustSensitiveContent)
        configuration.sensitiveContentEnabled = true
        configuration.canAdjustSensitiveContent = true
        XCTAssertFalse(configuration.sensitiveContentEnabled)
        XCTAssertFalse(configuration.canAdjustSensitiveContent)
    }

    func testSensitivePhotosStayHiddenRegardlessOfPlatformOrIgnoredReasons() {
        XCTAssertFalse(HarnessgramPolicy.hasHiddenMedia(self.photoMessage()))
        for reason in ["sensitive", "porn"] {
            let restriction = RestrictedContentMessageAttribute(rules: [RestrictionRule(platform: "android", reason: reason, text: "Restricted")])
            let message = self.photoMessage(attributes: [restriction])
            XCTAssertTrue(HarnessgramPolicy.isSensitiveContent(message))
            XCTAssertTrue(HarnessgramPolicy.hasHiddenMedia(message))
            let reference = AnyMediaReference.message(message: MessageReference(message._asMessage()), media: message._asMessage().media[0])
            XCTAssertFalse(HarnessgramPolicy.allowsMediaReference(reference))
        }
    }

    func testSensitivePeerAlsoHidesUnflaggedPhotos() {
        let peer = self.channel(.member, isBroadcast: true, restrictionInfo: PeerAccessRestrictionInfo(rules: [RestrictionRule(platform: "all", reason: "sensitive", text: "Restricted")]))
        let message = self.photoMessage(peer: peer)
        XCTAssertTrue(HarnessgramPolicy.hasHiddenMedia(message))
        XCTAssertEqual(MessageReference(message._asMessage()).harnessgramSensitiveContent, true)
    }

    func testSensitiveAndUnknownReferencesCannotFetchEvenAnAllowedPhoto() {
        for sensitive in [false, true] {
            let attributes: [EngineMessage.Attribute] = sensitive ? [RestrictedContentMessageAttribute(rules: [RestrictionRule(platform: "all", reason: "sensitive", text: "Restricted")])] : []
            let message = self.photoMessage(attributes: attributes)
            let reference = MessageReference(message._asMessage())
            let encoder = PostboxEncoder()
            reference.encode(encoder)
            let restored = MessageReference(decoder: PostboxDecoder(buffer: MemoryBuffer(data: encoder.makeData())))
            XCTAssertEqual(restored.harnessgramSensitiveContent, sensitive)
            let resource = FileMediaReference.message(message: restored, media: self.mediaFile(mimeType: "image/jpeg")).resourceReference(self.cloudResource(10))
            XCTAssertEqual(HarnessgramPolicy.allowsResource(resource), !sensitive)
            XCTAssertEqual(harnessgramAllowsResourceFetch(resource: resource.resource, parameters: .init(tag: nil, info: TelegramCloudMediaResourceFetchInfo(reference: resource, preferBackgroundReferenceRevalidation: false, continueInBackground: false), location: nil, contentType: .image, isRandomAccessAllowed: true)), !sensitive)
        }
        let unknown = MessageReference(content: .none)
        let photoFile = self.mediaFile(mimeType: "image/jpeg")
        let unknownResource = FileMediaReference.message(message: unknown, media: photoFile).resourceReference(photoFile.resource)
        XCTAssertFalse(HarnessgramPolicy.allowsResource(unknownResource))
        let legacyEncoder = PostboxEncoder()
        legacyEncoder.encodeObject(unknown.content, forKey: "c")
        let legacy = MessageReference(decoder: PostboxDecoder(buffer: MemoryBuffer(data: legacyEncoder.makeData())))
        XCTAssertNil(legacy.harnessgramSensitiveContent)
        XCTAssertFalse(HarnessgramPolicy.allowsMediaReference(.message(message: legacy, media: photoFile)))
    }

    func testOldSafeReferenceCannotOverrideCurrentMessageOrPeerRestrictions() {
        let ordinaryPeer = self.channel(.member, isBroadcast: true)
        let originalMessage = self.photoMessage(peer: ordinaryPeer)
        let originalReference = MessageReference(originalMessage._asMessage())
        let photoFile = self.mediaFile(mimeType: "image/jpeg")
        let resource = FileMediaReference.message(message: originalReference, media: photoFile).resourceReference(photoFile.resource)
        XCTAssertTrue(HarnessgramPolicy.allowsResource(resource))
        XCTAssertTrue(HarnessgramPolicy.allowsCurrentMessageResourceFetch(originalMessage, peer: ordinaryPeer))

        let sensitiveRule = RestrictionRule(platform: "all", reason: "sensitive", text: "Restricted")
        let editedMessage = self.photoMessage(attributes: [RestrictedContentMessageAttribute(rules: [sensitiveRule])], peer: ordinaryPeer)
        XCTAssertFalse(HarnessgramPolicy.allowsCurrentMessageResourceFetch(editedMessage, peer: ordinaryPeer))
        let restrictedPeer = self.channel(.member, isBroadcast: true, restrictionInfo: PeerAccessRestrictionInfo(rules: [sensitiveRule]))
        XCTAssertFalse(HarnessgramPolicy.allowsCurrentMessageResourceFetch(originalMessage, peer: restrictedPeer))
        XCTAssertFalse(HarnessgramPolicy.allowsCurrentMessageResourceFetch(nil, peer: ordinaryPeer))
        XCTAssertFalse(HarnessgramPolicy.allowsCurrentMessageResourceFetch(originalMessage, peer: nil))
    }

    // MARK: Sticker filter

    private func sticker(_ pack: StickerPackReference?, mimeType: String = "application/x-tgsticker", customEmoji: Bool = false, id: Int64 = 10) -> TelegramMediaFile {
        let attribute: TelegramMediaFileAttribute = customEmoji ? .CustomEmoji(isPremium: false, isSingleColor: false, alt: "", packReference: pack) : .Sticker(displayText: "", packReference: pack, maskData: nil)
        return TelegramMediaFile(fileId: EngineMedia.Id(namespace: Namespaces.Media.CloudFile, id: id), partialReference: nil, resource: self.cloudResource(id), previewRepresentations: [], videoThumbnails: [], immediateThumbnailData: nil, mimeType: mimeType, size: 100, attributes: [attribute, .FileName(fileName: "sticker.tgs")], alternativeRepresentations: [])
    }

    /// Owner, 2026-11-17: the bridge's "🧑🏼‍💻" placeholder shows as Telegram's big animated emoji. Files of the
    /// system animated-emoji sets are approved by file id; a skin tone reuses the base file; any other pack stays hidden.
    func testStandardAnimatedEmojiShowsBigIncludingSkinTonesButOtherPacksStayHidden() {
        self.withStickerStore { store, _ in
            // The system set's file names its pack by an id nobody approved or learned yet.
            let technologist = self.sticker(.id(id: 7001, accessHash: 1), id: 501)
            let effect = self.sticker(.id(id: 7002, accessHash: 1), id: 502)
            let foreign = self.sticker(.id(id: 7003, accessHash: 1), id: 503)
            XCTAssertFalse(store.isApprovedSticker(technologist))

            store.noteSystemStickerPackFiles(reference: .animatedEmoji, fileIds: [technologist.fileId])
            store.noteSystemStickerPackFiles(reference: .animatedEmojiAnimations, fileIds: [effect.fileId])
            // A pack named by id or by name is not a system reference, whatever it claims to hold.
            store.noteSystemStickerPackFiles(reference: .id(id: 7003, accessHash: 1), fileIds: [foreign.fileId])
            store.noteSystemStickerPackFiles(reference: .name("AnimatedEmojies"), fileIds: [foreign.fileId])
            store.noteSystemStickerPackFiles(reference: .dice("🎲"), fileIds: [foreign.fileId])
            XCTAssertTrue(store.isApprovedSticker(technologist))
            XCTAssertTrue(store.isApprovedSticker(effect))
            XCTAssertFalse(store.isApprovedSticker(foreign))

            // The chat resolves the emoji like ChatMessageItemImpl: skin tone stripped, base file reused.
            let animatedEmoji: [String: TelegramMediaFile] = ["🧑‍💻": technologist, "🙂": foreign]
            let resolve: (String) -> TelegramMediaFile? = { text in
                let (emoji, _) = text.basicEmoji
                return animatedEmoji[emoji] ?? animatedEmoji[emoji.strippedEmoji]
            }
            XCTAssertEqual("🧑🏼‍💻".basicEmoji.1, "🏼")
            for text in ["🧑‍💻", "🧑🏼‍💻", "🧑🏿‍💻"] {
                XCTAssertTrue(HarnessgramPolicy.showsLargeAnimatedEmoji(text: text, hasEntities: false, file: resolve(text), level: .photos, stickers: store.isApprovedSticker), text)
            }
            // A file from an arbitrary pack, several emoji, entities, a text-only chat or no file: plain text.
            XCTAssertFalse(HarnessgramPolicy.showsLargeAnimatedEmoji(text: "🙂", hasEntities: false, file: resolve("🙂"), level: .all, stickers: store.isApprovedSticker))
            XCTAssertFalse(HarnessgramPolicy.showsLargeAnimatedEmoji(text: "🧑‍💻🧑‍💻", hasEntities: false, file: technologist, level: .all, stickers: store.isApprovedSticker))
            XCTAssertFalse(HarnessgramPolicy.showsLargeAnimatedEmoji(text: "🧑‍💻", hasEntities: true, file: technologist, level: .all, stickers: store.isApprovedSticker))
            XCTAssertFalse(HarnessgramPolicy.showsLargeAnimatedEmoji(text: "🧑‍💻", hasEntities: false, file: technologist, level: .textOnly, stickers: store.isApprovedSticker))
            XCTAssertFalse(HarnessgramPolicy.showsLargeAnimatedEmoji(text: "🧑‍💻", hasEntities: false, file: nil, level: .all, stickers: store.isApprovedSticker))
            XCTAssertFalse(HarnessgramPolicy.showsLargeAnimatedEmoji(text: "🧑‍💻", hasEntities: false, file: self.sticker(.id(id: 7001, accessHash: 1), customEmoji: true, id: 501), level: .all, stickers: store.isApprovedSticker))
        }
    }

    private func withStickerStore(bundled: HarnessgramPolicy.ApprovedStickerPacks = .init(), _ body: (HarnessgramPolicyStore, UserDefaults) -> Void) {
        let suite = "HarnessgramPolicyTests.stickers." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        body(HarnessgramPolicyStore(defaults: defaults, approved: .init(), stickerPacks: bundled), defaults)
    }

    func testStickerPackDecisionUsesApprovedIdsNamesAndOnlyOfficialSystemDefaults() {
        let approved = HarnessgramPolicy.ApprovedStickerPacks(ids: [5], shortNames: [" @SafePack "])
        XCTAssertTrue(HarnessgramPolicy.isApprovedStickerPack(.id(id: 5, accessHash: 99), approved: approved))
        XCTAssertFalse(HarnessgramPolicy.isApprovedStickerPack(.id(id: 6, accessHash: 0), approved: approved))
        XCTAssertTrue(HarnessgramPolicy.isApprovedStickerPack(.name("safepack"), approved: approved))
        XCTAssertFalse(HarnessgramPolicy.isApprovedStickerPack(.name("other"), approved: approved))
        XCTAssertFalse(HarnessgramPolicy.isApprovedStickerPack(nil, approved: approved))
        // Telegram's own system sets, addressed by official InputStickerSet types and never by name.
        for reference: StickerPackReference in [.animatedEmoji, .animatedEmojiAnimations, .emojiGenericAnimations, .iconStatusEmoji, .iconChannelStatusEmoji, .iconTopicEmoji] {
            XCTAssertTrue(HarnessgramPolicy.isSystemDefaultStickerPack(reference))
            XCTAssertTrue(HarnessgramPolicy.isApprovedStickerPack(reference, approved: .init()))
        }
        // Games of chance and paid gift art stay out; a pack is never a system pack by its id or name.
        for reference: StickerPackReference in [.dice("🎰"), .premiumGifts, .tonGifts, .id(id: 7, accessHash: 0), .name("AnimatedEmojies"), .name("TopicIcons")] {
            XCTAssertFalse(HarnessgramPolicy.isSystemDefaultStickerPack(reference))
            XCTAssertFalse(HarnessgramPolicy.isApprovedStickerPack(reference, approved: .init()))
        }
    }

    func testSystemDefaultPackIdsAreLearnedOnlyFromOfficialTypesAndRefreshCachedDecisions() {
        self.withStickerStore { store, defaults in
            let topicIcon = TelegramMediaFile.Accessor(self.sticker(.id(id: 11, accessHash: 0), customEmoji: true, id: 41))
            let statusIcon = TelegramMediaFile.Accessor(self.sticker(.id(id: 12, accessHash: 0), customEmoji: true, id: 42))
            let thirdParty = TelegramMediaFile.Accessor(self.sticker(.id(id: 13, accessHash: 0), customEmoji: true, id: 43))
            XCTAssertFalse(store.isApprovedSticker(topicIcon))
            XCTAssertFalse(store.isApprovedSticker(statusIcon))
            store.learnSystemStickerPack(reference: .iconTopicEmoji, id: 11)
            store.learnSystemStickerPack(reference: .iconStatusEmoji, id: 12)
            store.learnSystemStickerPack(reference: .id(id: 13, accessHash: 0), id: 13)
            store.learnSystemStickerPack(reference: .tonGifts, id: 14)
            // A cached "no" must not outlive the approval.
            XCTAssertTrue(store.isApprovedSticker(topicIcon))
            XCTAssertTrue(store.isApprovedSticker(statusIcon))
            XCTAssertFalse(store.isApprovedSticker(thirdParty))
            XCTAssertFalse(store.isApprovedStickerPack(.id(id: 14, accessHash: 0)))
            let restored = HarnessgramPolicyStore(defaults: defaults, approved: .init(), stickerPacks: .init())
            XCTAssertTrue(restored.isApprovedStickerPack(.id(id: 11, accessHash: 0)))
            XCTAssertTrue(restored.pickerShowsPackGroup(ItemCollectionId(namespace: Namespaces.ItemCollection.CloudEmojiPacks, id: 12)))
            XCTAssertFalse(restored.pickerShowsPackGroup(ItemCollectionId(namespace: Namespaces.ItemCollection.CloudEmojiPacks, id: 13)))
        }
    }

    func testPickersOmitUnapprovedPacksButKeepUnicodeEmojiAndApprovedPacks() {
        self.withStickerStore(bundled: .init(ids: [21])) { store, _ in
            for namespace in [Namespaces.ItemCollection.CloudEmojiPacks, Namespaces.ItemCollection.CloudStickerPacks, Namespaces.ItemCollection.CloudMaskPacks] {
                XCTAssertTrue(store.pickerShowsPackGroup(ItemCollectionId(namespace: namespace, id: 21)))
                XCTAssertFalse(store.pickerShowsPackGroup(ItemCollectionId(namespace: namespace, id: 22)))
            }
            // Mixed groups (recent, popular, search) are not packs and are filtered per item.
            XCTAssertTrue(store.pickerShowsPackGroup(ItemCollectionId(namespace: Namespaces.ItemCollection.CloudIconTopicEmoji, id: 0)))
            // Unicode emoji and action icons carry no file.
            XCTAssertTrue(store.pickerShowsItem(file: nil, isGift: false))
            XCTAssertTrue(store.pickerShowsItem(file: TelegramMediaFile.Accessor(self.sticker(.id(id: 21, accessHash: 0), customEmoji: true, id: 51)), isGift: false))
            XCTAssertTrue(store.pickerShowsItem(file: TelegramMediaFile.Accessor(self.sticker(.id(id: 21, accessHash: 0), id: 52)), isGift: false))
            for file in [self.sticker(.id(id: 22, accessHash: 0), customEmoji: true, id: 53), self.sticker(.id(id: 22, accessHash: 0), id: 54), self.sticker(nil, customEmoji: true, id: 55), self.sticker(.premiumGifts, id: 56)] {
                XCTAssertFalse(store.pickerShowsItem(file: TelegramMediaFile.Accessor(file), isGift: false))
            }
            XCTAssertFalse(store.pickerShowsItem(file: TelegramMediaFile.Accessor(self.sticker(.id(id: 21, accessHash: 0), id: 57)), isGift: true))
            XCTAssertFalse(store.pickerShowsItem(file: nil, isGift: true))
        }
    }

    func testStandardReactionFilesRenderButOnlyThroughATypedReference() {
        let ids: [Int64] = [61, 62, 63, 64, 65]
        let files = ids.map { self.sticker(.id(id: 999, accessHash: 0), id: $0) }
        XCTAssertFalse(HarnessgramPolicyStore.shared.isApprovedSticker(files[0]))
        let _ = AvailableReactions(hash: 0, reactions: [AvailableReactions.Reaction(isEnabled: true, isPremium: false, value: .builtin("👍"), title: "Like", staticIcon: files[0], appearAnimation: files[1], selectAnimation: files[2], activateAnimation: files[3], effectAnimation: files[4], aroundAnimation: nil, centerAnimation: nil)])
        for file in files {
            XCTAssertTrue(HarnessgramPolicyStore.shared.isApprovedSticker(file))
            XCTAssertTrue(HarnessgramPolicyStore.shared.isApprovedSticker(TelegramMediaFile.Accessor(file)))
        }
        // Registration is by file id: another file of the same pack stays unapproved.
        XCTAssertFalse(HarnessgramPolicyStore.shared.isApprovedSticker(self.sticker(.id(id: 999, accessHash: 0), id: 66)))
        // Pickers fetch with a typed reference so the pack decides; an untyped document never loads.
        let resource = CloudDocumentMediaResource(datacenterId: 1, fileId: 61, accessHash: 0, size: 100, fileReference: nil, fileName: nil)
        let reaction = TelegramMediaFile(fileId: EngineMedia.Id(namespace: Namespaces.Media.CloudFile, id: 61), partialReference: nil, resource: resource, previewRepresentations: [], videoThumbnails: [], immediateThumbnailData: nil, mimeType: "application/x-tgsticker", size: 100, attributes: [.Sticker(displayText: "", packReference: .id(id: 999, accessHash: 0), maskData: nil)], alternativeRepresentations: [])
        let typed = FileMediaReference.standalone(media: reaction).resourceReference(reaction.resource)
        XCTAssertTrue(HarnessgramPolicy.allowsResource(typed))
        XCTAssertTrue(harnessgramAllowsResourceFetch(resource: resource, parameters: .init(tag: nil, info: TelegramCloudMediaResourceFetchInfo(reference: typed, preferBackgroundReferenceRevalidation: false, continueInBackground: false), location: nil, contentType: .sticker, isRandomAccessAllowed: true)))
        XCTAssertFalse(harnessgramAllowsResourceFetch(resource: resource, parameters: .init(tag: nil, info: TelegramCloudMediaResourceFetchInfo(reference: .standalone(resource: resource), preferBackgroundReferenceRevalidation: false, continueInBackground: false), location: nil, contentType: .sticker, isRandomAccessAllowed: true)))
    }

    func testStickersRenderOnlyFromApprovedPacksAndNeverAtTextOnly() {
        let approved = HarnessgramPolicy.ApprovedStickerPacks(ids: [5])
        let check: (TelegramMediaFile) -> Bool = { HarnessgramPolicy.isApprovedSticker($0, approved: approved, topicIconFileIds: []) }
        let files = [
            self.sticker(.id(id: 5, accessHash: 0)),
            self.sticker(.id(id: 5, accessHash: 0), mimeType: "video/webm"),
            self.sticker(.id(id: 5, accessHash: 0), mimeType: "image/webp"),
            self.sticker(.id(id: 5, accessHash: 0), customEmoji: true)
        ]
        for file in files {
            XCTAssertTrue(HarnessgramPolicy.allowsMedia(.file(file), level: .photos, stickers: check), file.mimeType)
            XCTAssertFalse(HarnessgramPolicy.allowsMedia(.file(file), level: .textOnly, stickers: check), file.mimeType)
        }
        for file in [self.sticker(.id(id: 6, accessHash: 0)), self.sticker(nil, mimeType: "image/webp"), self.sticker(.id(id: 6, accessHash: 0), customEmoji: true), self.mediaFile(mimeType: "application/x-tgsticker")] {
            XCTAssertFalse(HarnessgramPolicy.allowsMedia(.file(file), level: .documents, stickers: check), file.mimeType)
        }
        // A GIF is not a sticker: an approved pack list never unlocks it.
        XCTAssertFalse(HarnessgramPolicy.allowsMedia(.file(self.mediaFile(mimeType: "image/gif")), level: .documents, stickers: { _ in true }))
        XCTAssertFalse(HarnessgramPolicy.allowsMedia(.file(self.mediaFile(mimeType: "video/mp4", attributes: [.Animated])), level: .documents, stickers: { _ in true }))
    }

    func testUnapprovedStickerResourceIsNeverFetchedIncludingThumbnailsAndPackThumbnails() {
        let file = self.sticker(.id(id: 424242, accessHash: 0))
        XCTAssertFalse(HarnessgramPolicy.allowsResource(FileMediaReference.standalone(media: file).resourceReference(file.resource)))
        XCTAssertFalse(HarnessgramPolicy.allowsResource(.stickerPackThumbnail(stickerPack: .id(id: 424242, accessHash: 0), resource: file.resource)))
        XCTAssertFalse(harnessgramAllowsResourceFetch(resource: file.resource, parameters: .init(tag: nil, info: TelegramCloudMediaResourceFetchInfo(reference: FileMediaReference.standalone(media: file).resourceReference(file.resource), preferBackgroundReferenceRevalidation: false, continueInBackground: false), location: nil, contentType: .sticker, isRandomAccessAllowed: true)))
    }

    func testStickerSnapshotGrandfathersOnceAndLaterInstallsNeverExtendIt() {
        self.withStickerStore(bundled: .init(shortNames: ["bundled"])) { store, defaults in
            XCTAssertTrue(store.needsStickerSnapshot())
            XCTAssertTrue(store.isApprovedStickerPack(.name("Bundled")))
            XCTAssertFalse(store.isApprovedStickerPack(.id(id: 1, accessHash: 0)))
            store.completeStickerSnapshot(.init(ids: [1], shortNames: ["installed"]))
            store.completeStickerSnapshot(.init(ids: [2]))
            let restored = HarnessgramPolicyStore(defaults: defaults, approved: .init(), stickerPacks: .init())
            XCTAssertFalse(restored.needsStickerSnapshot())
            XCTAssertTrue(restored.isApprovedStickerPack(.id(id: 1, accessHash: 0)))
            XCTAssertTrue(restored.isApprovedStickerPackInfo(id: 77, shortName: "INSTALLED"))
            XCTAssertFalse(restored.isApprovedStickerPack(.id(id: 2, accessHash: 0)))
            XCTAssertTrue(restored.requestApproval(accountPeerId: self.accountPeerId, id: HarnessgramPolicy.stickerPackRequestId(.id(id: 3, accessHash: 0))!, title: "Sticker pack 3"))
            XCTAssertFalse(restored.isApprovedStickerPack(.id(id: 3, accessHash: 0)))
        }
    }

    func testCorruptStickerStateFailsClosedAndSystemLearningIsOnlyForEmojiDefaults() {
        self.withStickerStore { store, defaults in
            defaults.set(Data("invalid".utf8), forKey: "Harnessgram.stickerPacks.v1")
            let restored = HarnessgramPolicyStore(defaults: defaults, approved: .init(), stickerPacks: .init())
            XCTAssertFalse(restored.needsStickerSnapshot())
            restored.completeStickerSnapshot(.init(ids: [1]))
            XCTAssertFalse(restored.isApprovedStickerPack(.id(id: 1, accessHash: 0)))
            restored.learnSystemStickerPack(reference: .dice("🎲"), id: 8)
            restored.learnSystemStickerPack(reference: .id(id: 9, accessHash: 0), id: 9)
            restored.learnSystemStickerPack(reference: .animatedEmoji, id: 10)
            XCTAssertFalse(restored.isApprovedStickerPack(.id(id: 8, accessHash: 0)))
            XCTAssertFalse(restored.isApprovedStickerPack(.id(id: 9, accessHash: 0)))
            XCTAssertTrue(restored.isApprovedStickerPack(.id(id: 10, accessHash: 0)))
        }
    }

    func testForumTopicIconsAlwaysLoadButOnlyTheirOwnCustomEmoji() {
        let icon = self.sticker(.id(id: 900, accessHash: 0), customEmoji: true, id: 31)
        let sameIdSticker = self.sticker(.id(id: 900, accessHash: 0), id: 31)
        let otherEmoji = self.sticker(.id(id: 900, accessHash: 0), customEmoji: true, id: 32)
        XCTAssertTrue(HarnessgramPolicy.isApprovedSticker(icon, approved: .init(), topicIconFileIds: [31]))
        XCTAssertFalse(HarnessgramPolicy.isApprovedSticker(sameIdSticker, approved: .init(), topicIconFileIds: [31]))
        XCTAssertFalse(HarnessgramPolicy.isApprovedSticker(otherEmoji, approved: .init(), topicIconFileIds: [31]))
        self.withStickerStore { store, _ in
            XCTAssertFalse(store.isApprovedSticker(icon))
            store.noteTopicIcon(fileId: 31)
            store.noteTopicIcon(fileId: nil)
            XCTAssertTrue(store.isApprovedSticker(icon))
            XCTAssertFalse(store.isApprovedSticker(otherEmoji))
        }
        // Building or decoding a topic's info registers its icon with the shared store before rendering.
        let info = EngineMessageHistoryThread.Info(title: "Topic", icon: 33, iconColor: 0)
        XCTAssertEqual(info.icon, 33)
        let topicIcon = self.sticker(.id(id: 901, accessHash: 0), customEmoji: true, id: 33)
        XCTAssertTrue(HarnessgramPolicyStore.shared.isApprovedSticker(topicIcon))
        XCTAssertTrue(HarnessgramPolicy.allowsMedia(.file(topicIcon), level: .photos))
        XCTAssertTrue(HarnessgramPolicy.allowsResource(FileMediaReference.standalone(media: topicIcon).resourceReference(topicIcon.resource)))
        let decoded = try? JSONDecoder().decode(EngineMessageHistoryThread.Info.self, from: Data(#"{"title":"T","icon":34,"iconColor":0}"#.utf8))
        XCTAssertEqual(decoded?.icon, 34)
        XCTAssertTrue(HarnessgramPolicyStore.shared.isApprovedSticker(self.sticker(nil, customEmoji: true, id: 34)))
    }

    func testStickerRequestIdsAndPlaceholderLookup() {
        XCTAssertEqual(HarnessgramPolicy.stickerPackRequestId(.id(id: 5, accessHash: 1)), "stickers:5")
        XCTAssertEqual(HarnessgramPolicy.stickerPackRequestId(.name(" @Pack ")), "stickers:name:pack")
        XCTAssertNil(HarnessgramPolicy.stickerPackRequestId(nil))
        XCTAssertNil(HarnessgramPolicy.stickerPackRequestId(.animatedEmoji))
        let file = self.sticker(.id(id: 6, accessHash: 0))
        let message = EngineMessage(
            stableId: 1, stableVersion: 0,
            id: EngineMessage.Id(peerId: self.accountPeerId, namespace: Namespaces.Message.Cloud, id: 1),
            globallyUniqueId: nil, groupingKey: nil, groupInfo: nil, threadId: nil, timestamp: 0,
            flags: [.Incoming], tags: [], globalTags: [], localTags: [], customTags: [], forwardInfo: nil,
            author: nil, text: "", attributes: [], media: [.file(file)],
            peers: [:], associatedMessages: [:], associatedMessageIds: [],
            associatedMedia: [:], associatedThreadInfo: nil, associatedStories: [:]
        )
        XCTAssertEqual(HarnessgramPolicy.unapprovedSticker(message, stickers: { _ in false })?.pack, .id(id: 6, accessHash: 0))
        XCTAssertNil(HarnessgramPolicy.unapprovedSticker(message, stickers: { _ in true }))
        XCTAssertTrue(HarnessgramPolicy.hasHiddenMedia(message))
    }

    // MARK: Links (slice 7)

    private func webpage(_ url: String, story: Bool = false, id: Int64 = 70) -> TelegramMediaWebpage {
        let content = TelegramMediaWebpageLoadedContent(url: url, displayUrl: url, hash: 0, type: "article", websiteName: "Site", title: "Title", text: "Text", embedUrl: nil, embedType: nil, embedSize: nil, duration: nil, author: nil, isMediaLargeByDefault: nil, imageIsVideoCover: false, image: nil, file: nil, story: story ? TelegramMediaStory(storyId: StoryId(peerId: self.accountPeerId, id: 1), isMention: false) : nil, attributes: [], instantPage: nil)
        return TelegramMediaWebpage(webpageId: EngineMedia.Id(namespace: Namespaces.Media.CloudWebpage, id: id), content: .Loaded(content))
    }

    func testWebLinksNeverOpenInsideTheApp() {
        XCTAssertFalse(HarnessgramPolicy.inAppBrowser)
        XCTAssertFalse(HarnessgramPolicy.instantView)
    }

    func testLinkPreviewDomainsMatchOnLabelBoundariesOnly() {
        let domains = ["Example.org", " *.chabad.org ", ".", ""]
        for url in ["https://example.org", "http://EXAMPLE.org/a?b", "https://news.example.org/x", "https://example.org./x", "https://www.chabad.org/library", "https://chabad.org"] {
            XCTAssertTrue(HarnessgramPolicy.isApprovedLinkDomain(url, domains: domains), url)
        }
        for url in ["https://badexample.org", "https://example.org.evil.com", "https://example.com", "ftp://example.org", "tg://resolve?domain=example.org", "javascript:example.org", "example.org", "not a url", "https://user@evil.com/example.org"] {
            XCTAssertFalse(HarnessgramPolicy.isApprovedLinkDomain(url, domains: domains), url)
        }
        XCTAssertFalse(HarnessgramPolicy.isApprovedLinkDomain("https://example.org", domains: []))
        XCTAssertEqual(HarnessgramPolicy.webLinkHost("HTTPS://Sub.Example.ORG./p"), "sub.example.org")
    }

    func testOnlyLoadedPreviewsOfApprovedDomainsShowAndOthersDropWithoutAPlaceholder() {
        let approved = self.webpage("https://example.org/page")
        let other = self.webpage("https://other.com/page")
        XCTAssertTrue(HarnessgramPolicy.isApprovedLinkPreview(approved, domains: ["example.org"]))
        XCTAssertFalse(HarnessgramPolicy.isApprovedLinkPreview(other, domains: ["example.org"]))
        XCTAssertFalse(HarnessgramPolicy.isApprovedLinkPreview(self.webpage("https://example.org/s", story: true), domains: ["example.org"]))
        XCTAssertFalse(HarnessgramPolicy.isApprovedLinkPreview(TelegramMediaWebpage(webpageId: EngineMedia.Id(namespace: Namespaces.Media.CloudWebpage, id: 71), content: .Pending(0, "https://example.org")), domains: ["example.org"]))
        let check: (TelegramMediaWebpage) -> Bool = { HarnessgramPolicy.isApprovedLinkPreview($0, domains: ["example.org"]) }
        XCTAssertTrue(HarnessgramPolicy.dropsMediaSilently(.webpage(other), linkPreviews: check))
        XCTAssertFalse(HarnessgramPolicy.dropsMediaSilently(.webpage(approved), linkPreviews: check))
        XCTAssertFalse(HarnessgramPolicy.dropsMediaSilently(.file(self.mediaFile(mimeType: "video/mp4")), linkPreviews: { _ in false }))

        // The shipped list is empty: every preview drops out, the message text stays, no "Media hidden".
        XCTAssertFalse(HarnessgramPolicy.allowsMedia(.webpage(approved), level: .documents))
        XCTAssertTrue(HarnessgramPolicy.dropsMediaSilently(.webpage(approved)))
        let message = EngineMessage(
            stableId: 1, stableVersion: 0,
            id: EngineMessage.Id(peerId: self.accountPeerId, namespace: Namespaces.Message.Cloud, id: 1),
            globallyUniqueId: nil, groupingKey: nil, groupInfo: nil, threadId: nil, timestamp: 0,
            flags: [.Incoming], tags: [], globalTags: [], localTags: [], customTags: [], forwardInfo: nil,
            author: nil, text: "https://other.com/page", attributes: [], media: [.webpage(other)],
            peers: [:], associatedMessages: [:], associatedMessageIds: [],
            associatedMedia: [:], associatedThreadInfo: nil, associatedStories: [:]
        )
        XCTAssertFalse(HarnessgramPolicy.hasHiddenMedia(message))
        // A preview's photo loads only for an approved domain.
        let photo = TelegramMediaImage(imageId: EngineMedia.Id(namespace: Namespaces.Media.CloudImage, id: 72), representations: [], immediateThumbnailData: nil, reference: nil, partialReference: nil, flags: [])
        XCTAssertFalse(HarnessgramPolicy.allowsMediaReference(.webPage(webPage: WebpageReference(other), media: photo)))
        XCTAssertFalse(HarnessgramPolicy.allowsMediaReference(.webPage(webPage: WebpageReference(TelegramMediaWebpage(webpageId: EngineMedia.Id(namespace: Namespaces.Media.CloudWebpage, id: 73), content: .Pending(0, nil))), media: photo)))
    }

    func testBundledLinkPreviewDomainsLoadAndMissingKeysApproveNone() {
        let store = HarnessgramPolicyStore(defaults: UserDefaults(suiteName: "HarnessgramPolicyTests.links." + UUID().uuidString)!, approved: .init(), stickerPacks: .init(), linkPreviewDomains: ["example.org"])
        XCTAssertTrue(store.isApprovedLinkPreviewUrl("https://www.example.org/x"))
        XCTAssertTrue(store.isApprovedLinkPreview(self.webpage("https://example.org/a")))
        XCTAssertFalse(store.isApprovedLinkPreviewUrl("https://other.org"))
        XCTAssertEqual(HarnessgramPolicyStore.shared.linkPreviewDomains, [])
    }

    // MARK: Strangers (slice 10)

    private func user(_ id: Int64, bot: Bool = false) -> EnginePeer {
        return .user(TelegramUser(
            id: EnginePeer.Id(namespace: Namespaces.Peer.CloudUser, id: EnginePeer.Id.Id._internalFromInt64Value(id)),
            accessHash: nil, firstName: "User \(id)", lastName: nil, username: nil, phone: nil, photo: [],
            botInfo: bot ? BotUserInfo(flags: [], inlinePlaceholder: nil) : nil, restrictionInfo: nil, flags: [], emojiStatus: nil, usernames: [],
            storiesHidden: nil, nameColor: nil, backgroundEmojiId: nil, profileColor: nil,
            profileBackgroundEmojiId: nil, subscriberCount: nil, verificationIconFileId: nil
        ))
    }

    func testPrivateChatsNeedAContactButBotsServiceAndSavedMessagesStay() {
        XCTAssertTrue(HarnessgramPolicy.contactsOnlyPrivateChats)
        let stranger = self.user(50)
        XCTAssertFalse(HarnessgramPolicy.isApprovedPeer(stranger, accountPeerId: self.accountPeerId, hasChat: true, isContact: false, grandfatheredPrivateIds: [51]))
        XCTAssertTrue(HarnessgramPolicy.isApprovedPeer(stranger, accountPeerId: self.accountPeerId, hasChat: true, isContact: true))
        XCTAssertTrue(HarnessgramPolicy.isApprovedPeer(stranger, accountPeerId: self.accountPeerId, hasChat: false, isContact: false, approved: .init(peerIds: [String(stranger.id.toInt64())])))
        XCTAssertTrue(HarnessgramPolicy.isApprovedPeer(self.user(52, bot: true), accountPeerId: self.accountPeerId, hasChat: true, isContact: false))
        XCTAssertTrue(HarnessgramPolicy.isApprovedPeer(self.user(HarnessgramPolicy.telegramServiceUserId), accountPeerId: self.accountPeerId, hasChat: true, isContact: false))
        XCTAssertTrue(HarnessgramPolicy.isApprovedPeer(self.user(1), accountPeerId: self.accountPeerId, hasChat: true, isContact: false))
        // Groups are not private chats and are never grandfathered by the private snapshot.
        let member = self.channel(.member, isBroadcast: false)
        XCTAssertEqual(HarnessgramPolicy.grandfatheredPrivateIds(peers: [stranger, member]), [stranger.id.toInt64()])
    }

    func testOnlyContactsMayAddTheAccountToGroups() {
        XCTAssertTrue(HarnessgramPolicy.isContactsOnly([.allowContacts]))
        XCTAssertTrue(HarnessgramPolicy.isContactsOnly([.disallowSome, .allowContacts]))
        XCTAssertTrue(HarnessgramPolicy.isContactsOnly([.disallowAll]))
        XCTAssertFalse(HarnessgramPolicy.isContactsOnly([]))
        XCTAssertFalse(HarnessgramPolicy.isContactsOnly([.allowAll]))
        XCTAssertFalse(HarnessgramPolicy.isContactsOnly([.allowSome, .allowContacts]))
        XCTAssertFalse(HarnessgramPolicy.isContactsOnly([.allowContacts, .allowAll]))
        XCTAssertFalse(HarnessgramPolicy.isContactsOnly([.allowSome, .disallowAll]))
        XCTAssertEqual(HarnessgramPolicy.contactsOnlyPrivacy, .enableContacts(enableFor: [:], disableFor: [:], enableForPremium: false, enableForBots: false))
    }

    func testNewStrangerChatsMustBeArchivedAndStayArchived() {
        var settings = GlobalPrivacySettings.default
        XCTAssertFalse(HarnessgramPolicy.archivesStrangerChats(settings))
        settings.automaticallyArchiveAndMuteNonContacts = true
        XCTAssertTrue(HarnessgramPolicy.archivesStrangerChats(settings))
        settings.keepArchivedUnmuted = false
        XCTAssertFalse(HarnessgramPolicy.archivesStrangerChats(settings))
    }

    func testPrivateSnapshotIsTakenOnceEvenOnExistingAccountsAndStrangersBecomeRequests() {
        self.withApprovalStore { store, defaults in
            // An account set up before slice 10: groups captured, private chats not yet.
            defaults.set(Data(#"{"grandfatheredIds":[],"serverSnapshotPending":false,"requests":[]}"#.utf8), forKey: "Harnessgram.approvals.v1.\(self.accountPeerId.toInt64())")
            let old = self.user(60)
            let stranger = self.user(61)
            store.captureMembership(peers: [old], accountPeerId: self.accountPeerId)
            store.captureMembership(peers: [old, stranger], accountPeerId: self.accountPeerId)
            XCTAssertFalse(store.needsServerSnapshot(accountPeerId: self.accountPeerId))
            XCTAssertTrue(store.isListedChat(old, accountPeerId: self.accountPeerId))
            // Before the contact list has loaded the chat is hidden but not yet a request.
            XCTAssertFalse(store.isListedChat(stranger, accountPeerId: self.accountPeerId))
            XCTAssertTrue(store.pendingRequests(accountPeerId: self.accountPeerId).isEmpty)
            store.updateContacts(accountPeerId: self.accountPeerId, peerIds: [])
            // Search results never become requests.
            XCTAssertTrue(store.pendingRequests(accountPeerId: self.accountPeerId).isEmpty)
            XCTAssertFalse(store.isListedChat(stranger, accountPeerId: self.accountPeerId))
            XCTAssertFalse(store.isListedChat(stranger, accountPeerId: self.accountPeerId))
            XCTAssertEqual(store.pendingRequests(accountPeerId: self.accountPeerId).map(\.id), ["user:\(stranger.id.toInt64())"])
            XCTAssertTrue(store.isListedChat(self.user(62, bot: true), accountPeerId: self.accountPeerId))
            // Adding the person as a contact lists the chat; removing the contact hides it again.
            store.updateContacts(accountPeerId: self.accountPeerId, peerIds: [stranger.id])
            XCTAssertTrue(store.isListedChat(stranger, accountPeerId: self.accountPeerId))
            XCTAssertTrue(store.isApprovedPeer(stranger, accountPeerId: self.accountPeerId, hasChat: true, isContact: false))
            store.updateContacts(accountPeerId: self.accountPeerId, peerIds: [])
            XCTAssertFalse(store.isListedChat(stranger, accountPeerId: self.accountPeerId))
            let otherAccount = EnginePeer.Id(namespace: Namespaces.Peer.CloudUser, id: EnginePeer.Id.Id._internalFromInt64Value(9))
            store.updateContacts(accountPeerId: otherAccount, peerIds: [stranger.id])
            XCTAssertFalse(store.isListedChat(stranger, accountPeerId: self.accountPeerId))
            let restored = HarnessgramPolicyStore(defaults: defaults, approved: .init())
            restored.captureMembership(peers: [stranger], accountPeerId: self.accountPeerId)
            XCTAssertFalse(restored.isListedChat(stranger, accountPeerId: self.accountPeerId))
            XCTAssertTrue(restored.isListedChat(old, accountPeerId: self.accountPeerId))
        }
    }

    func testCorruptStateNeverGrandfathersPrivateChats() {
        self.withApprovalStore { store, defaults in
            defaults.set(Data("invalid".utf8), forKey: "Harnessgram.approvals.v1.\(self.accountPeerId.toInt64())")
            let stranger = self.user(63)
            store.captureMembership(peers: [stranger], accountPeerId: self.accountPeerId)
            XCTAssertFalse(store.isListedChat(stranger, accountPeerId: self.accountPeerId))
        }
    }

    // MARK: Stories and profile photos (slice 9)

    func testStoriesAreOffIncludingPosting() {
        XCTAssertFalse(HarnessgramPolicy.stories)
        let story = TelegramMediaStory(storyId: StoryId(peerId: self.accountPeerId, id: 1), isMention: false)
        XCTAssertFalse(HarnessgramPolicy.allowsMedia(.story(story), level: .documents))
    }

    func testOnlyOwnAndContactsProfilePhotosShowAndLoad() {
        XCTAssertTrue(HarnessgramPolicy.showsProfilePhoto(ofUser: 1, contacts: [], accountPeerIds: [1]))
        XCTAssertTrue(HarnessgramPolicy.showsProfilePhoto(ofUser: 2, contacts: [2], accountPeerIds: [1]))
        XCTAssertFalse(HarnessgramPolicy.showsProfilePhoto(ofUser: 3, contacts: [2], accountPeerIds: [1]))
        let shown = EnginePeer.Id(namespace: Namespaces.Peer.CloudUser, id: EnginePeer.Id.Id._internalFromInt64Value(2))
        let shows: (EnginePeer.Id) -> Bool = { $0 == shown }
        XCTAssertTrue(HarnessgramPolicy.allowsAvatar(of: .user(id: 2, accessHash: 0), shows: shows))
        XCTAssertFalse(HarnessgramPolicy.allowsAvatar(of: .user(id: 3, accessHash: 0), shows: shows))
        XCTAssertTrue(HarnessgramPolicy.allowsAvatar(of: .channel(id: 3, accessHash: 0), shows: shows))
        XCTAssertTrue(HarnessgramPolicy.allowsAvatar(of: .group(id: 3), shows: shows))

        self.withApprovalStore { store, _ in
            let contact = EnginePeer.Id(namespace: Namespaces.Peer.CloudUser, id: EnginePeer.Id.Id._internalFromInt64Value(81))
            let stranger = EnginePeer.Id(namespace: Namespaces.Peer.CloudUser, id: EnginePeer.Id.Id._internalFromInt64Value(82))
            XCTAssertFalse(store.showsProfilePhoto(self.accountPeerId))
            store.noteAccount(self.accountPeerId)
            XCTAssertTrue(store.showsProfilePhoto(self.accountPeerId))
            XCTAssertFalse(store.showsProfilePhoto(contact))
            store.updateContacts(accountPeerId: self.accountPeerId, peerIds: [contact])
            XCTAssertTrue(store.showsProfilePhoto(contact))
            XCTAssertFalse(store.showsProfilePhoto(stranger))
            store.updateContacts(accountPeerId: self.accountPeerId, peerIds: [])
            XCTAssertFalse(store.showsProfilePhoto(contact))
        }

        // The shared gate: a stranger's photo is neither drawn nor fetched; groups and channels are.
        let resource = self.cloudResource(83)
        let representation = TelegramMediaImageRepresentation(dimensions: PixelDimensions(width: 160, height: 160), resource: resource, progressiveSizes: [], immediateThumbnailData: nil, hasVideo: false, isPersonal: false)
        let stranger = TelegramUser(
            id: EnginePeer.Id(namespace: Namespaces.Peer.CloudUser, id: EnginePeer.Id.Id._internalFromInt64Value(84)),
            accessHash: nil, firstName: "Stranger", lastName: nil, username: nil, phone: nil, photo: [representation],
            botInfo: nil, restrictionInfo: nil, flags: [], emojiStatus: nil, usernames: [],
            storiesHidden: nil, nameColor: nil, backgroundEmojiId: nil, profileColor: nil,
            profileBackgroundEmojiId: nil, subscriberCount: nil, verificationIconFileId: nil
        )
        XCTAssertTrue(stranger.profileImageRepresentations.isEmpty)
        XCTAssertNil(EnginePeer(stranger).smallProfileImage)
        XCTAssertFalse(HarnessgramPolicy.allowsResource(.avatar(peer: .user(id: 84, accessHash: 0), resource: resource)))
        XCTAssertFalse(HarnessgramPolicy.allowsResource(.avatarList(peer: .user(id: 84, accessHash: 0), resource: resource)))
        XCTAssertTrue(HarnessgramPolicy.allowsResource(.avatar(peer: .channel(id: 84, accessHash: 0), resource: resource)))
        let photo = TelegramMediaImage(imageId: EngineMedia.Id(namespace: Namespaces.Media.CloudImage, id: 85), representations: [representation], immediateThumbnailData: nil, reference: nil, partialReference: nil, flags: [])
        XCTAssertFalse(HarnessgramPolicy.allowsMediaReference(.avatarList(peer: .user(id: 84, accessHash: 0), media: photo)))
        HarnessgramPolicyStore.shared.noteAccount(stranger.id)
        XCTAssertEqual(stranger.profileImageRepresentations.count, 1)
        XCTAssertTrue(HarnessgramPolicy.allowsResource(.avatar(peer: .user(id: 84, accessHash: 0), resource: resource)))
    }

    // MARK: Review fixes

    func testMissingSnapshotFailsClosedAndNotificationsPassTheSameGate() {
        self.withApprovalStore { store, _ in
            // No capture at all: what an extension sees without the app group's state.
            let stranger = self.user(90)
            XCTAssertFalse(store.isListedChat(stranger, accountPeerId: self.accountPeerId))
            XCTAssertFalse(store.isApprovedPeer(stranger, accountPeerId: self.accountPeerId, hasChat: true, isContact: false))
            XCTAssertFalse(store.allowsNotification(from: stranger, isContact: false, accountPeerId: self.accountPeerId))
            XCTAssertTrue(store.allowsNotification(from: stranger, isContact: true, accountPeerId: self.accountPeerId))
            XCTAssertFalse(store.allowsNotification(from: nil, isContact: true, accountPeerId: self.accountPeerId))
            XCTAssertTrue(store.allowsNotification(from: self.user(91, bot: true), isContact: false, accountPeerId: self.accountPeerId))
            let group = self.channel(.member, isBroadcast: false)
            XCTAssertFalse(store.allowsNotification(from: group, isContact: false, accountPeerId: self.accountPeerId))
            store.captureMembership(peers: [group, stranger], accountPeerId: self.accountPeerId)
            XCTAssertTrue(store.allowsNotification(from: group, isContact: false, accountPeerId: self.accountPeerId))
            XCTAssertTrue(store.allowsNotification(from: stranger, isContact: false, accountPeerId: self.accountPeerId))
            XCTAssertTrue(store.pendingRequests(accountPeerId: self.accountPeerId).isEmpty)
        }
    }

    func testDecodedStateIsCachedAndWritesStayVisible() {
        self.withApprovalStore { store, defaults in
            let member = self.channel(.member, isBroadcast: true)
            store.captureMembership(peers: [member], accountPeerId: self.accountPeerId)
            // A later raw change to the defaults is not re-read per row; the store's own writes are.
            defaults.set(Data("invalid".utf8), forKey: "Harnessgram.approvals.v1.\(self.accountPeerId.toInt64())")
            XCTAssertTrue(store.isApprovedGroup(member, accountPeerId: self.accountPeerId))
            XCTAssertTrue(store.requestApproval(accountPeerId: self.accountPeerId, id: "x", title: "X"))
            XCTAssertEqual(store.pendingRequests(accountPeerId: self.accountPeerId).map(\.id), ["x"])
            XCTAssertFalse(store.isStrangerArchiveUnavailable(accountPeerId: self.accountPeerId))
            store.markStrangerArchiveUnavailable(accountPeerId: self.accountPeerId, now: 1000, appVersion: "1.0(5)")
            let restored = HarnessgramPolicyStore(defaults: defaults, approved: .init())
            XCTAssertTrue(restored.isStrangerArchiveUnavailable(accountPeerId: self.accountPeerId, now: 1000 + 6 * 86400, appVersion: "1.0(5)"))
            // Retried after 7 days, after an app update, or if the clock went back.
            XCTAssertFalse(restored.isStrangerArchiveUnavailable(accountPeerId: self.accountPeerId, now: 1000 + 7 * 86400, appVersion: "1.0(5)"))
            XCTAssertFalse(restored.isStrangerArchiveUnavailable(accountPeerId: self.accountPeerId, now: 2000, appVersion: "1.0(6)"))
            XCTAssertFalse(restored.isStrangerArchiveUnavailable(accountPeerId: self.accountPeerId, now: 500, appVersion: "1.0(5)"))
        }
    }

    func testUnapprovedPreviewMediaNeverLoadsThroughAnyReference() {
        let representation = TelegramMediaImageRepresentation(dimensions: PixelDimensions(width: 100, height: 100), resource: self.cloudResource(92), progressiveSizes: [], immediateThumbnailData: nil, hasVideo: false, isPersonal: false)
        let image = TelegramMediaImage(imageId: EngineMedia.Id(namespace: Namespaces.Media.CloudImage, id: 9292), representations: [representation], immediateThumbnailData: nil, reference: nil, partialReference: nil, flags: [])
        XCTAssertTrue(HarnessgramPolicy.allowsMediaReference(.standalone(media: image)))
        let content = TelegramMediaWebpageLoadedContent(url: "https://other.com/a", displayUrl: "other.com/a", hash: 0, type: "article", websiteName: nil, title: "T", text: nil, embedUrl: nil, embedType: nil, embedSize: nil, duration: nil, author: nil, isMediaLargeByDefault: nil, imageIsVideoCover: false, image: image, file: nil, story: nil, attributes: [], instantPage: nil)
        let _ = TelegramMediaWebpage(webpageId: EngineMedia.Id(namespace: Namespaces.Media.CloudWebpage, id: 93), content: .Loaded(content))
        XCTAssertTrue(HarnessgramPolicyStore.shared.isUnapprovedWebPreviewMedia(image.imageId))
        XCTAssertFalse(HarnessgramPolicy.allowsMediaReference(.standalone(media: image)))
        XCTAssertFalse(HarnessgramPolicy.allowsResource(.media(media: .standalone(media: image), resource: representation.resource)))
    }

    func testSponsoredMediaIsNeverShownOrPrefetched() {
        XCTAssertFalse(HarnessgramPolicy.sponsoredMedia)
        let message = self.photoMessage()
        XCTAssertTrue(HarnessgramPolicy.allowsPrefetch(message, media: message.engineMedia[0]))
    }

    /// Media from others always arrives as a cloud resource; local files are the owner's own.
    private func cloudResource(_ id: Int64) -> TelegramMediaResource {
        return CloudDocumentMediaResource(datacenterId: 1, fileId: id, accessHash: 0, size: 100, fileReference: nil, fileName: nil)
    }

    // MARK: Own content and bots (build 6)

    private func message(_ media: [Media], incoming: Bool, forwarded: Bool = false, id: Int32 = 1) -> Message {
        let forwardInfo: MessageForwardInfo? = forwarded ? MessageForwardInfo(author: nil, source: nil, sourceMessageId: nil, date: 0, authorSignature: "Someone", psaType: nil, flags: []) : nil
        let group = TelegramGroup(id: EnginePeer.Id(namespace: Namespaces.Peer.CloudGroup, id: EnginePeer.Id.Id._internalFromInt64Value(2)), title: "Group", photo: [], participantCount: 1, role: .member, membership: .Member, flags: [], defaultBannedRights: nil, migrationReference: nil, creationDate: 0, version: 0)
        var peers = SimpleDictionary<PeerId, Peer>()
        peers[group.id] = group
        return Message(
            stableId: UInt32(id), stableVersion: 0,
            id: EngineMessage.Id(peerId: group.id, namespace: Namespaces.Message.Cloud, id: id),
            globallyUniqueId: nil, groupingKey: nil, groupInfo: nil, threadId: nil, timestamp: 0,
            flags: incoming ? [.Incoming] : [], tags: [], globalTags: [], localTags: [], customTags: [], forwardInfo: forwardInfo,
            author: nil, text: "", attributes: [], media: media,
            peers: peers, associatedMessages: SimpleDictionary(), associatedMessageIds: [],
            associatedMedia: [:], associatedThreadInfo: nil, associatedStories: [:]
        )
    }

    private func voiceNote(_ resource: TelegramMediaResource = LocalFileMediaResource(fileId: 95), id: Int64 = 95) -> TelegramMediaFile {
        return TelegramMediaFile(fileId: EngineMedia.Id(namespace: Namespaces.Media.CloudFile, id: id), partialReference: nil, resource: resource, previewRepresentations: [], videoThumbnails: [], immediateThumbnailData: nil, mimeType: "audio/ogg", size: 100, attributes: [.Audio(isVoice: true, duration: 3, title: nil, performer: nil, waveform: nil)], alternativeRepresentations: [])
    }

    func testOwnVoiceNoteUploadsFromItsLocalFileAndShows() {
        // The recording is a local file attached to a voice-note media item (a pending upload has no
        // cloud message yet): the upload's own fetch must pass every gate.
        let voice = self.voiceNote()
        let pending = FileMediaReference.standalone(media: voice).resourceReference(voice.resource)
        XCTAssertTrue(HarnessgramPolicy.allowsResource(pending))
        XCTAssertTrue(harnessgramAllowsResourceFetch(resource: voice.resource, parameters: .init(tag: nil, info: TelegramCloudMediaResourceFetchInfo(reference: pending, preferBackgroundReferenceRevalidation: false, continueInBackground: false), location: nil, contentType: .audio, isRandomAccessAllowed: true)))
        // A local video, photo or file of his own is never filtered either.
        let video = self.mediaFile(mimeType: "video/mp4", attributes: [.Video(duration: 1.0, size: .init(width: 10, height: 10), flags: [], preloadSize: nil, coverTime: nil, videoCodec: nil)])
        XCTAssertTrue(HarnessgramPolicy.allowsResource(FileMediaReference.standalone(media: video).resourceReference(LocalFileMediaResource(fileId: 96))))

        // Once sent, his own message shows and fetches; someone else's video stays hidden.
        let cloudVideo = TelegramMediaFile(fileId: EngineMedia.Id(namespace: Namespaces.Media.CloudFile, id: 97), partialReference: nil, resource: CloudDocumentMediaResource(datacenterId: 1, fileId: 97, accessHash: 0, size: 100, fileReference: nil, fileName: nil), previewRepresentations: [], videoThumbnails: [], immediateThumbnailData: nil, mimeType: "video/mp4", size: 100, attributes: [.Video(duration: 1.0, size: .init(width: 10, height: 10), flags: [], preloadSize: nil, coverTime: nil, videoCodec: nil)], alternativeRepresentations: [])
        let own = self.message([cloudVideo], incoming: false)
        let theirs = self.message([cloudVideo], incoming: true, id: 2)
        let forwardedByHim = self.message([cloudVideo], incoming: false, forwarded: true, id: 3)
        XCTAssertTrue(HarnessgramPolicy.isOwnMessage(EngineMessage(own)))
        XCTAssertFalse(HarnessgramPolicy.hasHiddenMedia(EngineMessage(own)))
        XCTAssertTrue(HarnessgramPolicy.allowsPrefetch(EngineMessage(own), media: .file(cloudVideo)))
        XCTAssertTrue(HarnessgramPolicy.allowsMediaReference(.message(message: MessageReference(own), media: cloudVideo)))
        XCTAssertTrue(HarnessgramPolicy.allowsCurrentMessageResourceFetch(EngineMessage(own), peer: self.channel(.member, isBroadcast: false)))
        XCTAssertTrue(HarnessgramPolicy.hasHiddenMedia(EngineMessage(theirs)))
        XCTAssertFalse(HarnessgramPolicy.allowsMediaReference(.message(message: MessageReference(theirs), media: cloudVideo)))
        XCTAssertFalse(HarnessgramPolicy.allowsPrefetch(EngineMessage(theirs), media: .file(cloudVideo)))
        // Forwarding someone else's video does not make it his: hidden, and refused at the boundary.
        XCTAssertFalse(HarnessgramPolicy.isOwnMessage(EngineMessage(forwardedByHim)))
        XCTAssertTrue(HarnessgramPolicy.hasHiddenMedia(EngineMessage(forwardedByHim)))
        XCTAssertFalse(HarnessgramPolicy.allowsCurrentMessageResourceFetch(EngineMessage(forwardedByHim), peer: self.channel(.member, isBroadcast: false)))
    }

    func testIncomingVoiceNotesPlayButOtherAudioAndVideoNotesStayHidden() {
        let voice = self.voiceNote(CloudDocumentMediaResource(datacenterId: 1, fileId: 98, accessHash: 0, size: 100, fileReference: nil, fileName: nil), id: 98)
        XCTAssertTrue(HarnessgramPolicy.allowsMedia(.file(voice), level: .photos))
        XCTAssertFalse(HarnessgramPolicy.allowsMedia(.file(voice), level: .textOnly))
        let incoming = self.message([voice], incoming: true)
        XCTAssertFalse(HarnessgramPolicy.hasHiddenMedia(EngineMessage(incoming)))
        XCTAssertTrue(HarnessgramPolicy.allowsResource(.media(media: .message(message: MessageReference(incoming), media: voice), resource: voice.resource)))
        let music = self.mediaFile(mimeType: "audio/mpeg", attributes: [.Audio(isVoice: false, duration: 100, title: "Song", performer: nil, waveform: nil)])
        XCTAssertFalse(HarnessgramPolicy.allowsMedia(.file(music), level: .documents))
        let videoNote = self.mediaFile(mimeType: "video/mp4", attributes: [.Video(duration: 1.0, size: .init(width: 10, height: 10), flags: [.instantRoundVideo], preloadSize: nil, coverTime: nil, videoCodec: nil)])
        XCTAssertFalse(HarnessgramPolicy.allowsMedia(.file(videoNote), level: .documents))
    }

    func testBotsInApprovedChatsKeepTheirPhotosStrangersDoNot() {
        self.withApprovalStore { store, defaults in
            let bridgeBot = self.user(70, bot: true)
            let chatBot = self.user(71, bot: true)
            let otherBot = self.user(72, bot: true)
            let person = self.user(73)
            let approvedGroup = self.channel(.member, isBroadcast: false)
            store.captureMembership(peers: [approvedGroup, chatBot], accountPeerId: self.accountPeerId)
            XCTAssertFalse(store.showsProfilePhoto(bridgeBot.id))
            // A bot posting in an approved group keeps its photo; a person posting there does not.
            store.noteMessageAuthor(bridgeBot, chat: approvedGroup, accountPeerId: self.accountPeerId)
            store.noteMessageAuthor(person, chat: approvedGroup, accountPeerId: self.accountPeerId)
            XCTAssertTrue(store.showsProfilePhoto(bridgeBot.id))
            XCTAssertFalse(store.showsProfilePhoto(person.id))
            // A bot in an unapproved group does not.
            let unapproved = EnginePeer.channel(TelegramChannel(id: EnginePeer.Id(namespace: Namespaces.Peer.CloudChannel, id: EnginePeer.Id.Id._internalFromInt64Value(74)), accessHash: nil, title: "Other", username: nil, photo: [], creationDate: 0, version: 0, participationStatus: .member, info: .group(TelegramChannelGroupInfo(flags: [])), flags: [], restrictionInfo: nil, adminRights: nil, bannedRights: nil, defaultBannedRights: nil, usernames: [], storiesHidden: nil, nameColor: nil, backgroundEmojiId: nil, profileColor: nil, profileBackgroundEmojiId: nil, emojiStatus: nil, approximateBoostLevel: nil, subscriptionUntilDate: nil, verificationIconFileId: nil, sendPaidMessageStars: nil, linkedMonoforumId: nil))
            store.noteMessageAuthor(otherBot, chat: unapproved, accountPeerId: self.accountPeerId)
            XCTAssertFalse(store.showsProfilePhoto(otherBot.id))
            // A bot in the chat list keeps its photo; listing a person records nothing.
            XCTAssertTrue(store.isListedChat(chatBot, accountPeerId: self.accountPeerId))
            XCTAssertTrue(store.showsProfilePhoto(chatBot.id))
            store.noteApprovedBot(person)
            XCTAssertFalse(store.showsProfilePhoto(person.id))
            // Shared with the extensions through the same defaults.
            let restored = HarnessgramPolicyStore(defaults: defaults, approved: .init())
            XCTAssertTrue(restored.showsProfilePhoto(bridgeBot.id))
            XCTAssertTrue(restored.showsProfilePhoto(chatBot.id))
        }
        // An author avatar whose reference omits the author is decided at the boundary, not refused blindly.
        XCTAssertTrue(HarnessgramPolicy.allowsResource(.messageAuthorAvatar(message: MessageReference(self.message([], incoming: true)), resource: CloudPeerPhotoSizeMediaResource(datacenterId: 1, photoId: 1, sizeSpec: .small, volumeId: nil, localId: nil))))
    }

    // MARK: Media level per chat (build 7)

    func testApprovedChatsShowEverythingExceptWhatStaysOff() {
        let all: HarnessgramPolicy.MediaLevel = .all
        XCTAssertEqual(HarnessgramPolicy.approvedChatMedia, .all)
        XCTAssertEqual(HarnessgramPolicy.media, .photos)
        let video = self.mediaFile(mimeType: "video/mp4", attributes: [.Video(duration: 1.0, size: .init(width: 10, height: 10), flags: [], preloadSize: nil, coverTime: nil, videoCodec: nil)])
        let videoNote = self.mediaFile(mimeType: "video/mp4", attributes: [.Video(duration: 1.0, size: .init(width: 10, height: 10), flags: [.instantRoundVideo], preloadSize: nil, coverTime: nil, videoCodec: nil)])
        let music = self.mediaFile(mimeType: "audio/mpeg", attributes: [.Audio(isVoice: false, duration: 100, title: "Song", performer: nil, waveform: nil)])
        for file in [video, videoNote, music, self.mediaFile(mimeType: "image/gif"), self.mediaFile(mimeType: "video/mp4", attributes: [.Animated]), self.mediaFile(mimeType: "application/pdf"), self.mediaFile(mimeType: "application/zip")] {
            XCTAssertTrue(HarnessgramPolicy.allowsMedia(.file(file), level: all), file.mimeType)
            XCTAssertFalse(HarnessgramPolicy.allowsMedia(.file(file), level: .textOnly), file.mimeType)
        }
        // Stickers still need an approved pack; stories, dice and pending link previews stay off.
        XCTAssertFalse(HarnessgramPolicy.allowsMedia(.file(self.sticker(.id(id: 999, accessHash: 0))), level: all, stickers: { _ in false }))
        XCTAssertFalse(HarnessgramPolicy.allowsMedia(.story(TelegramMediaStory(storyId: StoryId(peerId: self.accountPeerId, id: 1), isMention: false)), level: all))
        XCTAssertFalse(HarnessgramPolicy.allowsMedia(.dice(TelegramMediaDice(emoji: "🎲")), level: all))
        XCTAssertFalse(HarnessgramPolicy.allowsMedia(.webpage(self.webpage("https://other.com")), level: all))
        let livePhoto = TelegramMediaImage(imageId: EngineMedia.Id(namespace: Namespaces.Media.CloudImage, id: 101), representations: [], videoRepresentations: [TelegramMediaImage.VideoRepresentation(dimensions: PixelDimensions(width: 10, height: 10), resource: self.cloudResource(102), startTimestamp: nil)], immediateThumbnailData: nil, reference: nil, partialReference: nil, flags: [])
        XCTAssertTrue(HarnessgramPolicy.allowsMedia(.image(livePhoto), level: all))
        XCTAssertFalse(HarnessgramPolicy.allowsMedia(.image(livePhoto), level: .photos))
    }

    func testEachApprovedChatHasItsOwnLevelAndEverythingElseFailsClosed() {
        self.withApprovalStore { store, defaults in
            let group = self.channel(.member, isBroadcast: false)
            let contact = self.user(110)
            let stranger = self.user(111)
            let bot = self.user(112, bot: true)
            store.noteAccount(self.accountPeerId)
            store.captureMembership(peers: [group], accountPeerId: self.accountPeerId)
            store.updateContacts(accountPeerId: self.accountPeerId, peerIds: [contact.id])
            XCTAssertEqual(store.mediaLevel(forChat: group), .all)
            XCTAssertEqual(store.mediaLevel(forChat: contact), .all)
            XCTAssertEqual(store.mediaLevel(forChat: bot), .all)
            XCTAssertEqual(store.mediaLevel(forChat: stranger), .photos)
            XCTAssertEqual(store.mediaLevel(forChatId: group.id), .all)
            XCTAssertEqual(store.mediaLevel(forChatId: contact.id), .all)
            XCTAssertEqual(store.mediaLevel(forChatId: stranger.id), .photos)
            XCTAssertEqual(store.mediaLevel(forChatId: EnginePeer.Id(namespace: Namespaces.Peer.SecretChat, id: EnginePeer.Id.Id._internalFromInt64Value(5))), .photos)
            // One chat tightened; the setting persists and never approves an unapproved chat.
            XCTAssertTrue(store.setMediaLevel(.photos, forChat: group.id, accountPeerId: self.accountPeerId))
            XCTAssertTrue(store.setMediaLevel(.all, forChat: stranger.id, accountPeerId: self.accountPeerId))
            let restored = HarnessgramPolicyStore(defaults: defaults, approved: .init(), mediaLevels: [:])
            restored.noteAccount(self.accountPeerId)
            XCTAssertEqual(restored.mediaLevel(forChat: group), .photos)
            XCTAssertEqual(restored.mediaLevel(forChat: stranger), .photos)
            XCTAssertTrue(restored.setMediaLevel(nil, forChat: group.id, accountPeerId: self.accountPeerId))
            XCTAssertEqual(restored.mediaLevel(forChat: group), .all)
        }
        // A level shipped in approved.json applies to that chat only.
        self.withApprovalStore { _, defaults in
            let group = self.channel(.member, isBroadcast: false)
            let store = HarnessgramPolicyStore(defaults: defaults, approved: .init(), mediaLevels: [String(group.id.toInt64()): .textOnly])
            store.noteAccount(self.accountPeerId)
            store.captureMembership(peers: [group], accountPeerId: self.accountPeerId)
            XCTAssertEqual(store.mediaLevel(forChat: group), .textOnly)
        }
    }

    func testForwardedMediaIsHeldToItsSourceLevel() {
        self.withApprovalStore { store, _ in
            let approvedGroup = TelegramGroup(id: EnginePeer.Id(namespace: Namespaces.Peer.CloudGroup, id: EnginePeer.Id.Id._internalFromInt64Value(120)), title: "Approved", photo: [], participantCount: 1, role: .member, membership: .Member, flags: [], defaultBannedRights: nil, migrationReference: nil, creationDate: 0, version: 0)
            let approvedSource = TelegramGroup(id: EnginePeer.Id(namespace: Namespaces.Peer.CloudGroup, id: EnginePeer.Id.Id._internalFromInt64Value(121)), title: "Source", photo: [], participantCount: 1, role: .member, membership: .Member, flags: [], defaultBannedRights: nil, migrationReference: nil, creationDate: 0, version: 0)
            let unapprovedSource = TelegramGroup(id: EnginePeer.Id(namespace: Namespaces.Peer.CloudGroup, id: EnginePeer.Id.Id._internalFromInt64Value(122)), title: "Other", photo: [], participantCount: 1, role: .member, membership: .Left, flags: [], defaultBannedRights: nil, migrationReference: nil, creationDate: 0, version: 0)
            store.noteAccount(self.accountPeerId)
            store.captureMembership(peers: [.legacyGroup(approvedGroup), .legacyGroup(approvedSource), .legacyGroup(unapprovedSource)], accountPeerId: self.accountPeerId)
            func message(forwardedFrom source: Peer?, hidden: Bool = false) -> EngineMessage {
                var peers = SimpleDictionary<PeerId, Peer>()
                peers[approvedGroup.id] = approvedGroup
                let forward: MessageForwardInfo? = (source != nil || hidden) ? MessageForwardInfo(author: nil, source: source, sourceMessageId: nil, date: 0, authorSignature: hidden ? "Hidden" : nil, psaType: nil, flags: []) : nil
                return EngineMessage(Message(stableId: 1, stableVersion: 0, id: EngineMessage.Id(peerId: approvedGroup.id, namespace: Namespaces.Message.Cloud, id: 1), globallyUniqueId: nil, groupingKey: nil, groupInfo: nil, threadId: nil, timestamp: 0, flags: [.Incoming], tags: [], globalTags: [], localTags: [], customTags: [], forwardInfo: forward, author: nil, text: "", attributes: [], media: [], peers: peers, associatedMessages: SimpleDictionary(), associatedMessageIds: [], associatedMedia: [:], associatedThreadInfo: nil, associatedStories: [:]))
            }
            XCTAssertEqual(store.mediaLevel(for: message(forwardedFrom: nil)), .all)
            XCTAssertEqual(store.mediaLevel(for: message(forwardedFrom: approvedSource)), .all)
            XCTAssertEqual(store.mediaLevel(for: message(forwardedFrom: unapprovedSource)), .photos)
            XCTAssertEqual(store.mediaLevel(for: message(forwardedFrom: nil, hidden: true)), .photos)
        }
    }

    // MARK: Build 7 review fixes

    func testSecretChatsKeepTheFallbackEvenWhenGrandfathered() {
        self.withApprovalStore { store, defaults in
            let secret = EnginePeer.Id(namespace: Namespaces.Peer.SecretChat, id: EnginePeer.Id.Id._internalFromInt64Value(130))
            defaults.set(Data(#"{"grandfatheredIds":[],"serverSnapshotPending":false,"requests":[],"grandfatheredPrivateIds":[\#(secret.toInt64())]}"#.utf8), forKey: "Harnessgram.approvals.v1.\(self.accountPeerId.toInt64())")
            store.noteAccount(self.accountPeerId)
            XCTAssertTrue(store.setMediaLevel(.all, forChat: secret, accountPeerId: self.accountPeerId))
            XCTAssertEqual(store.mediaLevel(forChatId: secret, accountPeerId: self.accountPeerId), .photos)
            XCTAssertEqual(store.mediaLevel(forChatId: secret), .photos)
        }
    }

    func testMediaLevelsNeverLeakBetweenAccounts() {
        self.withApprovalStore { store, _ in
            let accountA = self.accountPeerId
            let accountB = EnginePeer.Id(namespace: Namespaces.Peer.CloudUser, id: EnginePeer.Id.Id._internalFromInt64Value(131))
            let group = self.channel(.member, isBroadcast: false)
            store.noteAccount(accountA)
            store.noteAccount(accountB)
            store.captureMembership(peers: [group], accountPeerId: accountA)
            store.captureMembership(peers: [], accountPeerId: accountB)
            XCTAssertEqual(store.mediaLevel(forChat: group, accountPeerId: accountA), .all)
            XCTAssertEqual(store.mediaLevel(forChat: group, accountPeerId: accountB), .photos)
            XCTAssertEqual(store.mediaLevel(forChatId: group.id, accountPeerId: accountB), .photos)
            // Without a known viewer the strictest account wins.
            XCTAssertEqual(store.mediaLevel(forChat: group), .photos)
            // A level tightened in B is honored for B and never loosens A.
            store.updateContacts(accountPeerId: accountB, peerIds: [])
            let contact = self.user(132)
            store.updateContacts(accountPeerId: accountB, peerIds: [contact.id])
            XCTAssertTrue(store.setMediaLevel(.documents, forChat: contact.id, accountPeerId: accountB))
            XCTAssertEqual(store.mediaLevel(forChat: contact, accountPeerId: accountB), .documents)
            XCTAssertEqual(store.mediaLevel(forChat: contact, accountPeerId: accountA), .photos)
        }
    }

    func testReferencesApplyTheForwardSourceRule() {
        self.withApprovalStore { store, _ in
            let group = TelegramGroup(id: EnginePeer.Id(namespace: Namespaces.Peer.CloudGroup, id: EnginePeer.Id.Id._internalFromInt64Value(133)), title: "Approved", photo: [], participantCount: 1, role: .member, membership: .Member, flags: [], defaultBannedRights: nil, migrationReference: nil, creationDate: 0, version: 0)
            let source = TelegramGroup(id: EnginePeer.Id(namespace: Namespaces.Peer.CloudGroup, id: EnginePeer.Id.Id._internalFromInt64Value(134)), title: "Source", photo: [], participantCount: 1, role: .member, membership: .Member, flags: [], defaultBannedRights: nil, migrationReference: nil, creationDate: 0, version: 0)
            store.noteAccount(self.accountPeerId)
            store.captureMembership(peers: [.legacyGroup(group), .legacyGroup(source)], accountPeerId: self.accountPeerId)
            let video = TelegramMediaFile(fileId: EngineMedia.Id(namespace: Namespaces.Media.CloudFile, id: 135), partialReference: nil, resource: self.cloudResource(135), previewRepresentations: [], videoThumbnails: [], immediateThumbnailData: nil, mimeType: "video/mp4", size: 100, attributes: [.Video(duration: 1.0, size: .init(width: 10, height: 10), flags: [], preloadSize: nil, coverTime: nil, videoCodec: nil)], alternativeRepresentations: [])
            func reference(forward: MessageForwardInfo?) -> MessageReference {
                var peers = SimpleDictionary<PeerId, Peer>()
                peers[group.id] = group
                return MessageReference(Message(stableId: 1, stableVersion: 0, id: EngineMessage.Id(peerId: group.id, namespace: Namespaces.Message.Cloud, id: 1), globallyUniqueId: nil, groupingKey: nil, groupInfo: nil, threadId: nil, timestamp: 0, flags: [.Incoming], tags: [], globalTags: [], localTags: [], customTags: [], forwardInfo: forward, author: nil, text: "", attributes: [], media: [video], peers: peers, associatedMessages: SimpleDictionary(), associatedMessageIds: [], associatedMedia: [:], associatedThreadInfo: nil, associatedStories: [:]))
            }
            XCTAssertEqual(store.mediaLevel(for: reference(forward: nil), accountPeerId: self.accountPeerId), .all)
            XCTAssertEqual(store.mediaLevel(for: reference(forward: MessageForwardInfo(author: nil, source: source, sourceMessageId: nil, date: 0, authorSignature: nil, psaType: nil, flags: [])), accountPeerId: self.accountPeerId), .all)
            let unknown = reference(forward: MessageForwardInfo(author: nil, source: nil, sourceMessageId: nil, date: 0, authorSignature: "Hidden", psaType: nil, flags: []))
            XCTAssertEqual(unknown.harnessgramIsForward, true)
            XCTAssertEqual(store.mediaLevel(for: unknown, accountPeerId: self.accountPeerId), .photos)
            XCTAssertFalse(HarnessgramPolicy.allowsMedia(.file(video), level: store.mediaLevel(for: unknown, accountPeerId: self.accountPeerId)))
            XCTAssertFalse(HarnessgramPolicy.allowsMediaReference(.message(message: unknown, media: video)))
            // A reference that does not record whether it is a forward (legacy, partial) fails closed.
            let legacy = MessageReference(content: reference(forward: nil).content)
            XCTAssertNil(legacy.harnessgramIsForward)
            XCTAssertEqual(store.mediaLevel(for: legacy, accountPeerId: self.accountPeerId), .photos)
            // The forward fields survive saving and loading.
            let encoder = PostboxEncoder()
            unknown.encode(encoder)
            let decoded = MessageReference(decoder: PostboxDecoder(buffer: encoder.memoryBuffer()))
            XCTAssertEqual(decoded.harnessgramIsForward, true)
            XCTAssertNil(decoded.harnessgramForwardSourceId)
            XCTAssertEqual(store.mediaLevel(for: decoded, accountPeerId: self.accountPeerId), .photos)
        }
    }

    // MARK: Build 8 review fixes

    private func reviewGroup(_ id: Int64, member: Bool = true) -> TelegramGroup {
        return TelegramGroup(id: EnginePeer.Id(namespace: Namespaces.Peer.CloudGroup, id: EnginePeer.Id.Id._internalFromInt64Value(id)), title: "Group \(id)", photo: [], participantCount: 1, role: .member, membership: member ? .Member : .Left, flags: [], defaultBannedRights: nil, migrationReference: nil, creationDate: 0, version: 0)
    }

    private func reviewVideo(_ id: Int64) -> TelegramMediaFile {
        return TelegramMediaFile(fileId: EngineMedia.Id(namespace: Namespaces.Media.CloudFile, id: id), partialReference: nil, resource: self.cloudResource(id), previewRepresentations: [], videoThumbnails: [], immediateThumbnailData: nil, mimeType: "video/mp4", size: 100, attributes: [.Video(duration: 1.0, size: .init(width: 10, height: 10), flags: [], preloadSize: nil, coverTime: nil, videoCodec: nil)], alternativeRepresentations: [])
    }

    private func reviewMessage(in chat: TelegramGroup, outgoing: Bool, forwardedFrom source: Peer? = nil, hiddenForward: Bool = false, attributes: [MessageAttribute] = [], media: [Media]) -> Message {
        var peers = SimpleDictionary<PeerId, Peer>()
        peers[chat.id] = chat
        let forward: MessageForwardInfo? = (source != nil || hiddenForward) ? MessageForwardInfo(author: nil, source: source, sourceMessageId: nil, date: 0, authorSignature: hiddenForward ? "Hidden" : nil, psaType: nil, flags: []) : nil
        return Message(stableId: 1, stableVersion: 0, id: EngineMessage.Id(peerId: chat.id, namespace: Namespaces.Message.Cloud, id: 1), globallyUniqueId: nil, groupingKey: nil, groupInfo: nil, threadId: nil, timestamp: 0, flags: outgoing ? [] : [.Incoming], tags: [], globalTags: [], localTags: [], customTags: [], forwardInfo: forward, author: nil, text: "", attributes: attributes, media: media, peers: peers, associatedMessages: SimpleDictionary(), associatedMessageIds: [], associatedMedia: [:], associatedThreadInfo: nil, associatedStories: [:])
    }

    func testOutgoingForwardIsJudgedByItsSourceNotExemptAsOwn() {
        let chat = self.reviewGroup(140)
        let unapprovedSource = self.reviewGroup(141, member: false)
        let video = self.reviewVideo(142)
        // The owner's own outgoing (not forwarded) video stays his own.
        let own = MessageReference(self.reviewMessage(in: chat, outgoing: true, media: [video]))
        XCTAssertEqual(own.harnessgramIsOutgoing, true)
        XCTAssertTrue(HarnessgramPolicy.allowsMediaReference(.message(message: own, media: video)))
        // An outgoing forward of someone else's video is not the owner's own.
        for reference in [MessageReference(self.reviewMessage(in: chat, outgoing: true, forwardedFrom: unapprovedSource, media: [video])), MessageReference(self.reviewMessage(in: chat, outgoing: true, hiddenForward: true, media: [video]))] {
            XCTAssertEqual(reference.harnessgramIsForward, true)
            XCTAssertFalse(HarnessgramPolicy.allowsMediaReference(.message(message: reference, media: video)))
        }
    }

    func testSavedAndLegacyReferencesAreNeverTheOwnersOwn() {
        let chat = self.reviewGroup(143)
        let video = self.reviewVideo(144)
        let own = MessageReference(self.reviewMessage(in: chat, outgoing: true, media: [video]))
        // The content's incoming flag decodes as false; only the recorded Harnessgram field counts.
        let encoder = PostboxEncoder()
        own.encode(encoder)
        let decoded = MessageReference(decoder: PostboxDecoder(buffer: encoder.memoryBuffer()))
        XCTAssertEqual(decoded.harnessgramIsOutgoing, true)
        XCTAssertTrue(HarnessgramPolicy.allowsMediaReference(.message(message: decoded, media: video)))
        // An incoming message saved and loaded keeps its filter even though `incoming` decodes as false.
        let incoming = MessageReference(self.reviewMessage(in: chat, outgoing: false, media: [video]))
        let incomingEncoder = PostboxEncoder()
        incoming.encode(incomingEncoder)
        let decodedIncoming = MessageReference(decoder: PostboxDecoder(buffer: incomingEncoder.memoryBuffer()))
        XCTAssertEqual(decodedIncoming.isIncoming, false)
        XCTAssertEqual(decodedIncoming.harnessgramIsOutgoing, false)
        XCTAssertFalse(HarnessgramPolicy.allowsMediaReference(.message(message: decodedIncoming, media: video)))
        // A reference saved before build 9 has no record: unknown, never exempt.
        let legacyEncoder = PostboxEncoder()
        legacyEncoder.encodeObject(own.content, forKey: "c")
        legacyEncoder.encodeInt32(0, forKey: "hg.sc")
        legacyEncoder.encodeInt32(0, forKey: "hg.fw")
        let legacy = MessageReference(decoder: PostboxDecoder(buffer: legacyEncoder.memoryBuffer()))
        XCTAssertNil(legacy.harnessgramIsOutgoing)
        XCTAssertFalse(HarnessgramPolicy.allowsMediaReference(.message(message: legacy, media: video)))
    }

    func testQuotedMediaIsJudgedByTheQuoteOriginNotTheReply() {
        self.withApprovalStore { store, _ in
            let chat = self.reviewGroup(145)
            let unapprovedSource = self.reviewGroup(146, member: false)
            store.noteAccount(self.accountPeerId)
            store.captureMembership(peers: [.legacyGroup(chat)], accountPeerId: self.accountPeerId)
            let video = self.reviewVideo(147)
            func reply(quoting peerId: PeerId?) -> Message {
                let quote = QuotedReplyMessageAttribute(peerId: peerId, authorName: "Someone", quote: EngineMessageReplyQuote(text: "", offset: nil, entities: [], media: video), isQuote: true)
                return self.reviewMessage(in: chat, outgoing: false, attributes: [quote], media: [])
            }
            let levelOf: (EnginePeer.Id, EnginePeer.Id?) -> HarnessgramPolicy.MediaLevel = { store.mediaLevel(forChatId: $0, accountPeerId: $1) }
            XCTAssertEqual(store.mediaLevel(for: EngineMessage(reply(quoting: unapprovedSource.id)), accountPeerId: self.accountPeerId), .all)
            XCTAssertFalse(HarnessgramPolicy.allowsQuotedMedia(EngineMessage(reply(quoting: unapprovedSource.id)), accountPeerId: self.accountPeerId, levelOf: levelOf))
            XCTAssertFalse(HarnessgramPolicy.allowsQuotedMedia(EngineMessage(reply(quoting: nil)), accountPeerId: self.accountPeerId, levelOf: levelOf))
            XCTAssertTrue(HarnessgramPolicy.allowsQuotedMedia(EngineMessage(reply(quoting: chat.id)), accountPeerId: self.accountPeerId, levelOf: levelOf))
            // The reference shown in the reply panel names the quote's origin, not the text reply.
            let quoteReference = MessageReference.harnessgramQuote(parent: reply(quoting: unapprovedSource.id), sourcePeerId: unapprovedSource.id)
            XCTAssertEqual(quoteReference.harnessgramIsForward, true)
            XCTAssertEqual(quoteReference.harnessgramForwardSourceId, unapprovedSource.id.toInt64())
            XCTAssertNotEqual(quoteReference.harnessgramIsOutgoing, true)
            XCTAssertEqual(store.mediaLevel(for: quoteReference, accountPeerId: self.accountPeerId), .photos)
            XCTAssertEqual(store.mediaLevel(for: MessageReference.harnessgramQuote(parent: reply(quoting: nil), sourcePeerId: nil), accountPeerId: self.accountPeerId), .photos)
            XCTAssertFalse(HarnessgramPolicy.allowsMediaReference(.message(message: quoteReference, media: video)))
            // The account fetch boundary checks the same origin, also for the owner's own reply.
            XCTAssertFalse(HarnessgramPolicy.allowsCurrentMessageResourceFetch(EngineMessage(reply(quoting: unapprovedSource.id)), peer: .legacyGroup(chat), accountPeerId: self.accountPeerId))
            let ownReply = self.reviewMessage(in: chat, outgoing: true, attributes: [QuotedReplyMessageAttribute(peerId: nil, authorName: nil, quote: EngineMessageReplyQuote(text: "", offset: nil, entities: [], media: video), isQuote: true)], media: [])
            XCTAssertFalse(HarnessgramPolicy.allowsCurrentMessageResourceFetch(EngineMessage(ownReply), peer: .legacyGroup(chat), accountPeerId: self.accountPeerId))
        }
    }

    // MARK: Auto-download in approved chats (build 9)

    func testAutoDownloadUsesTheApprovedChatLevelOnlyWithTheSwitchAndAKnownAccount() {
        self.withApprovalStore { store, _ in
            let group = self.channel(.member, isBroadcast: false)
            let stranger = self.user(121)
            store.noteAccount(self.accountPeerId)
            store.captureMembership(peers: [group], accountPeerId: self.accountPeerId)
            let levelOf: (EngineMessage, EnginePeer.Id) -> HarnessgramPolicy.MediaLevel = { store.mediaLevel(for: $0, accountPeerId: $1) }
            let approved = self.photoMessage(peer: group)
            let unapproved = self.photoMessage(peer: stranger)
            XCTAssertEqual(HarnessgramPolicy.autoDownloadLevel(message: approved, accountPeerId: self.accountPeerId, enabled: true, levelOf: levelOf), .all)
            // Switch off, no message or no viewing account: the photos-only fallback.
            XCTAssertEqual(HarnessgramPolicy.autoDownloadLevel(message: approved, accountPeerId: self.accountPeerId, enabled: false, levelOf: levelOf), .photos)
            XCTAssertEqual(HarnessgramPolicy.autoDownloadLevel(message: approved, accountPeerId: nil, enabled: true, levelOf: levelOf), .photos)
            XCTAssertEqual(HarnessgramPolicy.autoDownloadLevel(message: nil, accountPeerId: self.accountPeerId, enabled: true, levelOf: levelOf), .photos)
            // An unapproved chat keeps the fallback whatever is set for it.
            XCTAssertTrue(store.setMediaLevel(.all, forChat: stranger.id, accountPeerId: self.accountPeerId))
            XCTAssertEqual(HarnessgramPolicy.autoDownloadLevel(message: unapproved, accountPeerId: self.accountPeerId, enabled: true, levelOf: levelOf), .photos)
            // A tightened approved chat downloads at its own level.
            XCTAssertTrue(store.setMediaLevel(.textOnly, forChat: group.id, accountPeerId: self.accountPeerId))
            XCTAssertEqual(HarnessgramPolicy.autoDownloadLevel(message: approved, accountPeerId: self.accountPeerId, enabled: true, levelOf: levelOf), .textOnly)
            // Another account on this device does not inherit the approval.
            let other = EnginePeer.Id(namespace: Namespaces.Peer.CloudUser, id: EnginePeer.Id.Id._internalFromInt64Value(99))
            store.noteAccount(other)
            XCTAssertEqual(HarnessgramPolicy.autoDownloadLevel(message: self.photoMessage(peer: group), accountPeerId: other, enabled: true, levelOf: levelOf), .photos)
        }
    }

    func testAutoDownloadIsNeverLooserThanTheChatLevelAndSkipsSensitiveAndSponsored() {
        let video = self.mediaFile(mimeType: "video/mp4", attributes: [.Video(duration: 3, size: PixelDimensions(width: 10, height: 10), flags: [], preloadSize: nil, coverTime: nil, videoCodec: nil)])
        for level: HarnessgramPolicy.MediaLevel in [.textOnly, .photos, .documents, .all] {
            let result = HarnessgramPolicy.autoDownloadLevel(message: self.photoMessage(), accountPeerId: self.accountPeerId, enabled: true, levelOf: { _, _ in level })
            XCTAssertEqual(result, level)
            XCTAssertEqual(HarnessgramPolicy.allowsMedia(.file(video), level: result), level == .all)
        }
        let sensitive = self.photoMessage(attributes: [RestrictedContentMessageAttribute(rules: [RestrictionRule(platform: "all", reason: "sensitive", text: "")])])
        XCTAssertEqual(HarnessgramPolicy.autoDownloadLevel(message: sensitive, accountPeerId: self.accountPeerId, enabled: true, levelOf: { _, _ in .all }), .textOnly)
        XCTAssertEqual(HarnessgramPolicy.autoDownloadLevel(message: sensitive, accountPeerId: nil, enabled: false, levelOf: { _, _ in .all }), .textOnly)
    }

    // MARK: Build 9 review fixes

    func testPollOptionMediaIsJudgedByThePollMessageNotTheReply() {
        self.withApprovalStore { store, _ in
            let chat = self.reviewGroup(160)
            let unapprovedSource = self.reviewGroup(161, member: false)
            store.noteAccount(self.accountPeerId)
            store.captureMembership(peers: [.legacyGroup(chat)], accountPeerId: self.accountPeerId)
            let video = self.reviewVideo(162)
            // The poll's own message (its option media lives in the poll): forwarded from an unapproved source.
            let forwardedPoll = self.reviewMessage(in: chat, outgoing: false, forwardedFrom: unapprovedSource, media: [])
            let reply = self.reviewMessage(in: chat, outgoing: false, media: [])
            // The reply alone would grant its chat's level; the poll's own message holds the forward's source level.
            XCTAssertEqual(store.mediaLevel(for: MessageReference(reply), accountPeerId: self.accountPeerId), .all)
            XCTAssertEqual(store.mediaLevel(for: MessageReference(forwardedPoll), accountPeerId: self.accountPeerId), .photos)
            XCTAssertFalse(HarnessgramPolicy.allowsMediaReference(.message(message: MessageReference(forwardedPoll), media: video), accountPeerId: self.accountPeerId))
        }
    }

    func testABlockedQuoteDoesNotHoldBackTheMessagesOwnAttachment() {
        let chat = self.reviewGroup(164)
        let photo = TelegramMediaImage(imageId: EngineMedia.Id(namespace: Namespaces.Media.CloudImage, id: 165), representations: [], immediateThumbnailData: nil, reference: nil, partialReference: nil, flags: [])
        let video = self.reviewVideo(166)
        let quote = QuotedReplyMessageAttribute(peerId: nil, authorName: nil, quote: EngineMessageReplyQuote(text: "", offset: nil, entities: [], media: video), isQuote: true)
        let message = EngineMessage(self.reviewMessage(in: chat, outgoing: false, attributes: [quote], media: [photo]))
        XCTAssertTrue(HarnessgramPolicy.allowsCurrentMessageResourceFetch(message, peer: .legacyGroup(chat), requestedMediaId: photo.imageId))
        XCTAssertFalse(HarnessgramPolicy.allowsCurrentMessageResourceFetch(message, peer: .legacyGroup(chat), requestedMediaId: video.fileId))
        XCTAssertFalse(HarnessgramPolicy.allowsCurrentMessageResourceFetch(message, peer: .legacyGroup(chat)))
    }

    func testAutoDownloadSwitchedOffIsNeverLooserThanATightenedChat() {
        for level: HarnessgramPolicy.MediaLevel in [.textOnly, .photos, .documents, .all] {
            let result = HarnessgramPolicy.autoDownloadLevel(message: self.photoMessage(), accountPeerId: self.accountPeerId, enabled: false, levelOf: { _, _ in level })
            XCTAssertEqual(result, HarnessgramPolicy.strictest(level, HarnessgramPolicy.media))
        }
    }

    // MARK: Harnessgram settings never loosen the filter (build 10)

    func testNoHarnessgramSwitchCanLoosenTheFilter() {
        self.withApprovalStore { store, defaults in
            let approved = self.channel(.member, isBroadcast: false)
            let stranger = self.user(151)
            let secret = EnginePeer.Id(namespace: Namespaces.Peer.SecretChat, id: EnginePeer.Id.Id._internalFromInt64Value(152))
            store.noteAccount(self.accountPeerId)
            store.captureMembership(peers: [approved], accountPeerId: self.accountPeerId)
            let video = self.reviewVideo(153)
            let levelOf: (EngineMessage, EnginePeer.Id) -> HarnessgramPolicy.MediaLevel = { store.mediaLevel(for: $0, accountPeerId: $1) }
            // The settings share the policy store's defaults; every combination of every switch is tried.
            let settings = HarnessgramSettings(defaults: defaults)
            for relay in [false, true] {
            for record in [false, true] {
                for autoDownload in [false, true] {
                    for justified in [false, true] {
                        for spacing in HarnessgramSettings.LineSpacing.allCases {
                            settings.connectThroughHomeRelay = relay
                            settings.recordWithBuiltInMic = record
                            settings.autoDownloadInApprovedChats = autoDownload
                            settings.justifiedText = justified
                            settings.lineSpacing = spacing
                            for chosen: HarnessgramPolicy.MediaLevel? in [nil, .textOnly, .photos, .documents, .all] {
                                store.setMediaLevel(chosen, forChat: stranger.id, accountPeerId: self.accountPeerId)
                                store.setMediaLevel(chosen, forChat: secret, accountPeerId: self.accountPeerId)
                                let reloaded = HarnessgramPolicyStore(defaults: defaults, approved: .init(), mediaLevels: [:])
                                reloaded.noteAccount(self.accountPeerId)
                                for check in [store, reloaded] {
                                    // An unapproved or secret chat never offers a choice and keeps the fallback.
                                    XCTAssertNil(check.configurableMediaLevel(forChat: stranger.id, accountPeerId: self.accountPeerId))
                                    XCTAssertNil(check.configurableMediaLevel(forChat: secret, accountPeerId: self.accountPeerId))
                                    XCTAssertEqual(check.mediaLevel(forChat: stranger, accountPeerId: self.accountPeerId), HarnessgramPolicy.media)
                                    XCTAssertEqual(check.mediaLevel(forChatId: secret, accountPeerId: self.accountPeerId), HarnessgramPolicy.media)
                                    XCTAssertNotNil(check.configurableMediaLevel(forChat: approved.id, accountPeerId: self.accountPeerId))
                                }
                                let strangerMessage = self.photoMessage(peer: stranger)
                                let level = HarnessgramPolicy.autoDownloadLevel(message: strangerMessage, accountPeerId: self.accountPeerId, enabled: settings.autoDownloadInApprovedChats, levelOf: levelOf)
                                XCTAssertEqual(HarnessgramPolicy.strictest(level, HarnessgramPolicy.media), level)
                                XCTAssertFalse(HarnessgramPolicy.allowsMedia(.file(video), level: level))
                                // Sensitive content stays out whatever is set.
                                let sensitive = self.photoMessage(attributes: [RestrictedContentMessageAttribute(rules: [RestrictionRule(platform: "all", reason: "sensitive", text: "")])], peer: approved)
                                XCTAssertEqual(HarnessgramPolicy.autoDownloadLevel(message: sensitive, accountPeerId: self.accountPeerId, enabled: settings.autoDownloadInApprovedChats, levelOf: levelOf), .textOnly)
                                XCTAssertTrue(HarnessgramPolicy.forceSensitiveFilter)
                                XCTAssertFalse(HarnessgramPolicy.globalSearch)
                                XCTAssertFalse(HarnessgramPolicy.inAppBrowser)
                            }
                        }
                    }
                }
            }
            }
            // No setting key lives in the store's namespace, so none can be read as an approval.
            for key in HarnessgramSettings.Key.allCases {
                XCTAssertFalse(key.rawValue.hasPrefix("Harnessgram."))
            }
        }
    }

    // MARK: Build 10 review fixes

    func testAChoiceOnTheDeviceNeverWidensABundledRestrictionOrAnyApproval() {
        self.withApprovalStore { _, defaults in
            let group = self.channel(.member, isBroadcast: false)
            let stranger = self.user(171)
            let store = HarnessgramPolicyStore(defaults: defaults, approved: .init(), mediaLevels: [String(group.id.toInt64()): .textOnly])
            store.noteAccount(self.accountPeerId)
            store.captureMembership(peers: [group], accountPeerId: self.accountPeerId)
            let settings = HarnessgramSettings(defaults: defaults)
            for chosen: HarnessgramPolicy.MediaLevel? in [nil, .textOnly, .photos, .documents, .all] {
                for on in [false, true] {
                    settings.connectThroughHomeRelay = on
                    settings.recordWithBuiltInMic = on
                    settings.autoDownloadInApprovedChats = on
                    settings.justifiedText = on
                    settings.lineSpacing = on ? .comfortable : .normal
                    settings.messageFont = on ? .frankRuhlLibre : .system
                    settings.fontWeight = on ? .semibold : .light
                    settings.textSizeSteps = on ? 4 : -2
                    settings.bubbleWidth = on ? .wide : .normal
                    store.setMediaLevel(chosen, forChat: group.id, accountPeerId: self.accountPeerId)
                    XCTAssertEqual(store.mediaLevel(forChat: group, accountPeerId: self.accountPeerId), .textOnly)
                    XCTAssertEqual(store.configurableMediaLevel(forChat: group.id, accountPeerId: self.accountPeerId), .textOnly)
                    // Domains, sticker packs and bots keep their approval state.
                    XCTAssertFalse(store.isApprovedLinkPreviewUrl("https://unapproved.example.net/page"))
                    XCTAssertFalse(store.isApprovedStickerPack(.name("unapprovedpack")))
                    XCTAssertFalse(store.showsProfilePhoto(stranger.id))
                }
            }
        }
    }

    // MARK: Build 13: the bridge's own widgets (owner decision 15.11)

    private func widgetBot(_ id: Int64, username: String) -> TelegramUser {
        return TelegramUser(
            id: EnginePeer.Id(namespace: Namespaces.Peer.CloudUser, id: EnginePeer.Id.Id._internalFromInt64Value(id)),
            accessHash: nil, firstName: "Bot \(id)", lastName: nil, username: username, phone: nil, photo: [],
            botInfo: BotUserInfo(flags: [], inlinePlaceholder: nil), restrictionInfo: nil, flags: [], emojiStatus: nil, usernames: [],
            storiesHidden: nil, nameColor: nil, backgroundEmojiId: nil, profileColor: nil,
            profileBackgroundEmojiId: nil, subscriberCount: nil, verificationIconFileId: nil
        )
    }

    private func forum(_ id: Int64, isForum: Bool = true) -> TelegramChannel {
        return TelegramChannel(id: EnginePeer.Id(namespace: Namespaces.Peer.CloudChannel, id: EnginePeer.Id.Id._internalFromInt64Value(id)), accessHash: nil, title: "Agents", username: nil, photo: [], creationDate: 0, version: 0, participationStatus: .member, info: .group(TelegramChannelGroupInfo(flags: [])), flags: isForum ? [.isForum] : [], restrictionInfo: nil, adminRights: nil, bannedRights: nil, defaultBannedRights: nil, usernames: [], storiesHidden: nil, nameColor: nil, backgroundEmojiId: nil, profileColor: nil, profileBackgroundEmojiId: nil, emojiStatus: nil, approximateBoostLevel: nil, subscriptionUntilDate: nil, verificationIconFileId: nil, sendPaidMessageStars: nil, linkedMonoforumId: nil)
    }

    private func widgetMessage(from author: TelegramUser, in chat: Peer, forwarded: Bool = false, viaBot: Bool = false) -> EngineMessage {
        let widget = TelegramMediaWidget(width: 300, height: 200, payload: Data("<p>?</p>".utf8))
        var peers = SimpleDictionary<PeerId, Peer>()
        peers[chat.id] = chat
        peers[author.id] = author
        let forwardInfo: MessageForwardInfo? = forwarded ? MessageForwardInfo(author: author, source: nil, sourceMessageId: nil, date: 0, authorSignature: nil, psaType: nil, flags: []) : nil
        let attributes: [MessageAttribute] = viaBot ? [InlineBotMessageAttribute(peerId: author.id, title: nil)] : []
        return EngineMessage(Message(
            stableId: 1, stableVersion: 0,
            id: EngineMessage.Id(peerId: chat.id, namespace: Namespaces.Message.Cloud, id: 1),
            globallyUniqueId: nil, groupingKey: nil, groupInfo: nil, threadId: nil, timestamp: 0,
            flags: [.Incoming], tags: [], globalTags: [], localTags: [], customTags: [], forwardInfo: forwardInfo,
            author: author, text: "", attributes: attributes, media: [widget],
            peers: peers, associatedMessages: SimpleDictionary(), associatedMessageIds: [],
            associatedMedia: [:], associatedThreadInfo: nil, associatedStories: [:]
        ))
    }

    func testOnlyTheBridgesOwnWidgetsShowAndOnlyInItsAgentChats() {
        let bridge = self.widgetBot(501, username: "ExampleBridgeBot")
        let otherBot = self.widgetBot(502, username: "SomeOtherBot")
        let agentGroup = self.forum(900000002)
        let groups = HarnessgramAgentGroups(ids: ["-100900000002"])
        let ordinaryForum = self.forum(42)
        let agentIdNotForum = self.forum(900000002, isForum: false)
        // The bridge is known by its pinned user id (build 14), never by its username.
        let suite = "HarnessgramPolicyTests.bridge." + UUID().uuidString
        let identityDefaults = UserDefaults(suiteName: suite)!
        defer { identityDefaults.removePersistentDomain(forName: suite) }
        let identity = HarnessgramBridgeIdentity(settings: HarnessgramSettings(defaults: identityDefaults))
        XCTAssertFalse(HarnessgramPolicy.allowsBridgeWidget(self.widgetMessage(from: bridge, in: agentGroup), agentGroups: groups, identity: identity), "not pinned yet: no bot is the bridge")
        identity.observePanel(botId: 501)
        let human = TelegramUser(id: EnginePeer.Id(namespace: Namespaces.Peer.CloudUser, id: EnginePeer.Id.Id._internalFromInt64Value(503)), accessHash: nil, firstName: "Friend", lastName: nil, username: nil, phone: nil, photo: [], botInfo: nil, restrictionInfo: nil, flags: [], emojiStatus: nil, usernames: [], storiesHidden: nil, nameColor: nil, backgroundEmojiId: nil, profileColor: nil, profileBackgroundEmojiId: nil, subscriberCount: nil, verificationIconFileId: nil)

        // The bridge bot in an agent group, and in its own chat with the owner: allowed.
        XCTAssertTrue(HarnessgramPolicy.allowsBridgeWidget(self.widgetMessage(from: bridge, in: agentGroup), agentGroups: groups, identity: identity))
        XCTAssertTrue(HarnessgramPolicy.allowsBridgeWidget(self.widgetMessage(from: bridge, in: bridge), agentGroups: groups, identity: identity))
        // The bridge bot in an ordinary chat: blocked.
        XCTAssertFalse(HarnessgramPolicy.allowsBridgeWidget(self.widgetMessage(from: bridge, in: ordinaryForum), agentGroups: groups, identity: identity))
        XCTAssertFalse(HarnessgramPolicy.allowsBridgeWidget(self.widgetMessage(from: bridge, in: agentIdNotForum), agentGroups: groups, identity: identity), "the group must be the agent forum")
        XCTAssertFalse(HarnessgramPolicy.allowsBridgeWidget(self.widgetMessage(from: bridge, in: human), agentGroups: groups, identity: identity), "a widget in someone else's chat")
        // Another bot in an agent group: blocked.
        XCTAssertFalse(HarnessgramPolicy.allowsBridgeWidget(self.widgetMessage(from: otherBot, in: agentGroup), agentGroups: groups, identity: identity))
        // A forwarded bridge widget: blocked, even in an agent group.
        XCTAssertFalse(HarnessgramPolicy.allowsBridgeWidget(self.widgetMessage(from: bridge, in: agentGroup, forwarded: true), agentGroups: groups, identity: identity))
        // Sent via the bridge by someone else (inline): blocked.
        XCTAssertFalse(HarnessgramPolicy.allowsBridgeWidget(self.widgetMessage(from: bridge, in: agentGroup, viaBot: true), agentGroups: groups, identity: identity))
        // Another bot that takes over the bridge's username has no privilege: the pinned id decides.
        let impostor = self.widgetBot(777, username: "ExampleBridgeBot")
        XCTAssertFalse(HarnessgramPolicy.allowsBridgeWidget(self.widgetMessage(from: impostor, in: agentGroup), agentGroups: groups, identity: identity))
        identity.observePanel(botId: 777)
        XCTAssertFalse(HarnessgramPolicy.allowsBridgeWidget(self.widgetMessage(from: bridge, in: agentGroup), agentGroups: groups, identity: identity), "a change of bot waits for the owner: nothing is the bridge")
        identity.observePanel(botId: 501)
        // A widget is still blocked media for everyone else (no level opens it).
        let widget = EngineMedia.widget(TelegramMediaWidget(width: 1, height: 1, payload: Data()))
        for level: HarnessgramPolicy.MediaLevel in [.textOnly, .photos, .documents, .all] {
            XCTAssertFalse(HarnessgramPolicy.allowsMedia(widget, level: level))
        }
        XCTAssertTrue(HarnessgramPolicy.isWidget(widget))
        XCTAssertTrue(HarnessgramAgentChat.isBridgeBot(username: "@examplebridgebot", configuredUsername: "ExampleBridgeBot"))
        XCTAssertFalse(HarnessgramAgentChat.isBridgeBot(username: "ExampleBridgeBot2"))
    }
}
