import XCTest
import HarnessgramAgent
import HarnessgramSettings

final class HarnessgramAgentChatTests: XCTestCase {
    // Sequential example IDs are synthetic and are never production chat identities.
    private let groups = HarnessgramAgentGroups(ids: ["-100900000002"])
    private let agentTopic = HarnessgramAgentChat.Kind(isBotPrivateChat: false, channelId: 900000002, isForum: true)
    private let botChat = HarnessgramAgentChat.Kind(isBotPrivateChat: true, channelId: nil, isForum: false)
    private let personalChat = HarnessgramAgentChat.Kind(isBotPrivateChat: false, channelId: nil, isForum: false)
    private let otherForum = HarnessgramAgentChat.Kind(isBotPrivateChat: false, channelId: 42, isForum: true)
    private let agentGroupNotForum = HarnessgramAgentChat.Kind(isBotPrivateChat: false, channelId: 900000002, isForum: false)

    func testAgentChatsAreBotChatsAndTheBridgeForumGroups() {
        XCTAssertTrue(HarnessgramAgentChat.isAgentChat(self.botChat, groups: self.groups))
        XCTAssertTrue(HarnessgramAgentChat.isAgentChat(self.agentTopic, groups: self.groups))
        XCTAssertFalse(HarnessgramAgentChat.isAgentChat(self.personalChat, groups: self.groups))
        XCTAssertFalse(HarnessgramAgentChat.isAgentChat(self.otherForum, groups: self.groups))
        XCTAssertFalse(HarnessgramAgentChat.isAgentChat(self.agentGroupNotForum, groups: self.groups))
    }

    func testWideBubblesOnlyForTextInAgentChats() {
        for kind in [self.botChat, self.agentTopic] {
            XCTAssertTrue(HarnessgramAgentChat.usesWideBubble(setting: .wide, kind: kind, groups: self.groups, isTextOnly: true, isBubbleless: false))
            XCTAssertFalse(HarnessgramAgentChat.usesWideBubble(setting: .normal, kind: kind, groups: self.groups, isTextOnly: true, isBubbleless: false), "the switch off keeps Telegram's width")
            XCTAssertFalse(HarnessgramAgentChat.usesWideBubble(setting: .wide, kind: kind, groups: self.groups, isTextOnly: false, isBubbleless: false), "stickers and media keep their width")
            XCTAssertFalse(HarnessgramAgentChat.usesWideBubble(setting: .wide, kind: kind, groups: self.groups, isTextOnly: true, isBubbleless: true), "bubbleless layouts keep their column")
        }
        for kind in [self.personalChat, self.otherForum, self.agentGroupNotForum] {
            XCTAssertFalse(HarnessgramAgentChat.usesWideBubble(setting: .wide, kind: kind, groups: self.groups, isTextOnly: true, isBubbleless: false), "ordinary chats keep Telegram's width")
        }
    }

    func testOnlyTurningTheGateOffNeedsTheOwner() {
        XCTAssertTrue(HarnessgramAgentSwitches.turningGateNeedsOwner(from: true, to: false))
        XCTAssertFalse(HarnessgramAgentSwitches.turningGateNeedsOwner(from: false, to: true))
        XCTAssertFalse(HarnessgramAgentSwitches.turningGateNeedsOwner(from: true, to: true))
        XCTAssertFalse(HarnessgramAgentSwitches.turningGateNeedsOwner(from: false, to: false))
    }

    func testAgentSwitchDefaultsAndPersistence() {
        let suite = "HarnessgramAgentChatTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            return XCTFail("no defaults")
        }
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = HarnessgramSettings(defaults: defaults)
        XCTAssertFalse(settings.agentQuickActions, "the quick-button row is off until the owner turns it on")
        XCTAssertTrue(settings.topicStatusDots)
        XCTAssertTrue(settings.confirmSensitiveButtons)
        settings.agentQuickActions = true
        settings.topicStatusDots = false
        settings.confirmSensitiveButtons = false
        let reloaded = HarnessgramSettings(defaults: defaults)
        XCTAssertTrue(reloaded.agentQuickActions)
        XCTAssertFalse(reloaded.topicStatusDots)
        XCTAssertFalse(reloaded.confirmSensitiveButtons)
        reloaded.agentQuickActions = false
        XCTAssertFalse(HarnessgramSettings(defaults: defaults).agentQuickActions)
    }
}
