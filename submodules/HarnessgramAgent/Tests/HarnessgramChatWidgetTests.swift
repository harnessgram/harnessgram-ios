import XCTest
import HarnessgramAgent
import HarnessgramSettings

/// Build 18: Telegram's chat-list widget shows the bridge's chats only.
final class HarnessgramChatWidgetTests: XCTestCase {
    // Sequential example IDs are synthetic and are never production chat identities.
    private let groups = HarnessgramAgentGroups(ids: ["-100900000002"])

    private func identity(pinned: Int64?) -> (HarnessgramBridgeIdentity, () -> Void) {
        let suite = "HarnessgramChatWidgetTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        let identity = HarnessgramBridgeIdentity(settings: HarnessgramSettings(defaults: defaults))
        if let pinned {
            identity.observePanel(botId: pinned)
        }
        return (identity, { defaults.removePersistentDomain(forName: suite) })
    }

    func testOnlyAgentForumGroupsAndThePinnedBridgeBotAreAllowed() {
        let (identity, cleanup) = self.identity(pinned: 501)
        defer { cleanup() }
        typealias Kind = HarnessgramChatWidget.ChatKind
        XCTAssertTrue(HarnessgramChatWidget.isAllowed(Kind.channel(id: 900000002, isForum: true), groups: self.groups, identity: identity), "an agent forum group")
        XCTAssertTrue(HarnessgramChatWidget.isAllowed(Kind.user(id: 501, isBot: true), groups: self.groups, identity: identity), "the bridge bot's chat")
        XCTAssertFalse(HarnessgramChatWidget.isAllowed(Kind.channel(id: 900000002, isForum: false), groups: self.groups, identity: identity), "the agent group id, not a forum")
        XCTAssertFalse(HarnessgramChatWidget.isAllowed(Kind.channel(id: 42, isForum: true), groups: self.groups, identity: identity), "another forum")
        XCTAssertFalse(HarnessgramChatWidget.isAllowed(Kind.user(id: 777, isBot: true), groups: self.groups, identity: identity), "another bot")
        XCTAssertFalse(HarnessgramChatWidget.isAllowed(Kind.user(id: 501, isBot: false), groups: self.groups, identity: identity), "a person, even with that id")
        XCTAssertFalse(HarnessgramChatWidget.isAllowed(Kind.user(id: 12, isBot: false), groups: self.groups, identity: identity), "a personal chat")
        XCTAssertFalse(HarnessgramChatWidget.isAllowed(Kind.other, groups: self.groups, identity: identity), "a basic group or secret chat")
    }

    func testNoBridgeChatBeforeThePanelPinsItsId() {
        let (identity, cleanup) = self.identity(pinned: nil)
        defer { cleanup() }
        XCTAssertFalse(HarnessgramChatWidget.isAllowed(.user(id: 501, isBot: true), groups: self.groups, identity: identity))
        XCTAssertTrue(HarnessgramChatWidget.isAllowed(.channel(id: 900000002, isForum: true), groups: self.groups, identity: identity), "agent groups need no pin")
    }

    func testSavedChatsThatAreNoLongerAllowedAreDroppedAndDefaultsAreTheNewestAllowed() {
        let (identity, cleanup) = self.identity(pinned: 501)
        defer { cleanup() }
        typealias Kind = HarnessgramChatWidget.ChatKind
        // A saved setup (or the chat list, newest first) mixing allowed and other chats.
        let chats: [(String, Kind)] = [
            ("mom", .user(id: 12, isBot: false)),
            ("agents", .channel(id: 900000002, isForum: true)),
            ("bridge", .user(id: 501, isBot: true)),
            ("agents", .channel(id: 900000002, isForum: true)),
            ("shop", .user(id: 900, isBot: true)),
            ("forum", .channel(id: 42, isForum: true)),
        ]
        XCTAssertEqual(HarnessgramChatWidget.filter(chats, groups: self.groups, identity: identity), ["agents", "bridge"], "allowed only, in order, each once")
        XCTAssertEqual(HarnessgramChatWidget.filter(chats, groups: self.groups, identity: identity, limit: 1), ["agents"], "at most the limit")
        XCTAssertEqual(HarnessgramChatWidget.filter([(String, Kind)](), groups: self.groups, identity: identity), [])
        XCTAssertEqual(HarnessgramChatWidget.limit, 8)
    }
}
