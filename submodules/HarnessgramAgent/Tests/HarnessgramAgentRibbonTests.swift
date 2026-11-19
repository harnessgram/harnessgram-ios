import XCTest
import HarnessgramAgent
import HarnessgramSettings

final class HarnessgramAgentRibbonTests: XCTestCase {
    // Sequential example IDs are synthetic and are never production chat identities.
    private let exampleChannel: Int64 = 900000002
    private lazy var groups = HarnessgramAgentGroups(ids: ["-100900000002"])

    private func topic(_ threadId: Int64? = 42, channelId: Int64? = 900000002, isForum: Bool = true) -> HarnessgramAgentRibbon.Context {
        return HarnessgramAgentRibbon.Context(channelId: channelId, isForum: isForum, threadId: threadId, composeTextIsEmpty: true, isEditingMessage: false, isRecordingMedia: false, isSearching: false, isSelectingMessages: false, hasSubject: false, isInputPanelOccupied: false)
    }

    // The bridge matches its keyboard words exactly (see docs/harnessgram-local-config.md), emoji variation
    // selectors included; a different code point would reach the session as an ordinary message.
    func testSentTextsAreTheBridgeKeyboardWordsExactly() {
        func scalars(_ text: String) -> [UInt32] {
            return text.unicodeScalars.map { $0.value }
        }
        XCTAssertEqual(scalars(HarnessgramAgentRibbon.Action.continueSession.sentText), [0x25B6, 0xFE0F, 0x20, 0x05D4, 0x05DE, 0x05E9, 0x05DA]) // fixed_btn_continue
        XCTAssertEqual(scalars(HarnessgramAgentRibbon.Action.status.sentText), [0x1F4CB, 0x20, 0x05DE, 0x05E6, 0x05D1]) // fixed_btn_status -> /status
        XCTAssertEqual(scalars(HarnessgramAgentRibbon.Action.stop.sentText), [0x23F9, 0xFE0F, 0x20, 0x05E2, 0x05E6, 0x05D5, 0x05E8]) // fixed_btn_stop -> Escape
        XCTAssertEqual(HarnessgramAgentRibbon.Action.summary.sentText, "📝 סיכום: מה נעשה, מה נשאר ומה מחכה לי?")
    }

    func testSummaryIsNoBridgeCommandOrLiveButton() {
        let text = HarnessgramAgentRibbon.Action.summary.sentText
        XCTAssertFalse(text.hasPrefix("/"))
        // inbox.py _LIVE_ICONS: a message starting with one of these is read as a live keyboard cell.
        for icon in ["📏 ", "🎚 ", "🧠 ", "🔐 ", "👤 ", "⏱ ", "📅 "] {
            XCTAssertFalse(text.hasPrefix(icon), icon)
        }
    }

    func testLabelsAreHebrewWordsWithTheBridgeIcons() {
        XCTAssertEqual(HarnessgramAgentRibbon.Action.ordered, [.continueSession, .status, .summary, .stop])
        XCTAssertEqual(HarnessgramAgentRibbon.Action.ordered.map { $0.title }, ["המשך", "מצב", "סיכום", "עצור"])
        for action in HarnessgramAgentRibbon.Action.allCases {
            XCTAssertTrue(action.label.hasPrefix(action.icon + " "), action.rawValue)
            XCTAssertFalse(action.accessibilityLabel.isEmpty, action.rawValue)
        }
        XCTAssertEqual(HarnessgramAgentRibbon.Action.continueSession.label, HarnessgramAgentRibbon.Action.continueSession.sentText)
        XCTAssertEqual(HarnessgramAgentRibbon.Action.status.label, HarnessgramAgentRibbon.Action.status.sentText)
        XCTAssertEqual(HarnessgramAgentRibbon.Action.stop.label, HarnessgramAgentRibbon.Action.stop.sentText)
        XCTAssertTrue(HarnessgramAgentRibbon.Action.stop.isDestructive)
        XCTAssertFalse(HarnessgramAgentRibbon.Action.continueSession.isDestructive)
        XCTAssertTrue(HarnessgramAgentStrings.isRightToLeft)
        for key in HarnessgramAgentStrings.Key.allCases {
            XCTAssertFalse(HarnessgramAgentStrings.string(key).isEmpty, key.rawValue)
        }
    }

    func testShownOnlyInSessionTopicsOfAgentGroups() {
        XCTAssertTrue(HarnessgramAgentRibbon.isShown(self.topic(), enabled: true, groups: self.groups))
        XCTAssertFalse(HarnessgramAgentRibbon.isShown(self.topic(), enabled: false, groups: self.groups), "switched off")
        XCTAssertFalse(HarnessgramAgentRibbon.isShown(self.topic(channelId: 1234567890), enabled: true, groups: self.groups), "another group")
        XCTAssertFalse(HarnessgramAgentRibbon.isShown(self.topic(channelId: nil), enabled: true, groups: self.groups), "not a channel")
        XCTAssertFalse(HarnessgramAgentRibbon.isShown(self.topic(isForum: false), enabled: true, groups: self.groups), "not a forum")
        XCTAssertFalse(HarnessgramAgentRibbon.isShown(self.topic(nil), enabled: true, groups: self.groups), "the whole chat")
        XCTAssertFalse(HarnessgramAgentRibbon.isShown(self.topic(HarnessgramAgentRibbon.generalThreadId), enabled: true, groups: self.groups), "General")
        XCTAssertFalse(HarnessgramAgentRibbon.isShown(self.topic(), enabled: true, groups: HarnessgramAgentGroups(channelIds: [])), "no groups configured")
    }

    func testHiddenWhileTheComposerIsBusy() {
        let busy: [(String, (inout HarnessgramAgentRibbon.Context) -> Void)] = [
            ("typing", { $0.composeTextIsEmpty = false }),
            ("editing", { $0.isEditingMessage = true }),
            ("recording", { $0.isRecordingMedia = true }),
            ("searching", { $0.isSearching = true }),
            ("selecting", { $0.isSelectingMessages = true }),
            ("special view", { $0.hasSubject = true }),
            ("stickers or bot keyboard", { $0.isInputPanelOccupied = true }),
        ]
        for (name, change) in busy {
            var context = self.topic()
            change(&context)
            XCTAssertFalse(HarnessgramAgentRibbon.isShown(context, enabled: true, groups: self.groups), name)
        }
    }

    func testGroupIdsAreBotApiChatIds() {
        XCTAssertEqual(HarnessgramAgentGroups.channelId(fromChatId: "-100900000002"), self.exampleChannel)
        XCTAssertEqual(HarnessgramAgentGroups.channelId(fromChatId: " 900000002 "), self.exampleChannel)
        for bad in ["", "-100", "-12345", "abc", "-100abc", "-100900000002x", "0", "-1000", "٣٩٣٥"] {
            XCTAssertNil(HarnessgramAgentGroups.channelId(fromChatId: bad), bad)
        }
        let groups = HarnessgramAgentGroups(ids: ["-100900000002", "junk", "-100900000003"])
        XCTAssertEqual(groups.channelIds, [900000002, 900000003])
    }

    func testBundledListComesFromApprovedJson() {
        let json = #"{"peerIds": ["123"], "agentProjectGroups": ["-100900000002", "-100900000001"]}"#
        XCTAssertEqual(HarnessgramAgentGroups.decodeBundled(Data(json.utf8)).channelIds, [900000002, 900000001])
        XCTAssertEqual(HarnessgramAgentGroups.decodeBundled(Data(#"{"peerIds": []}"#.utf8)).channelIds, [])
        XCTAssertEqual(HarnessgramAgentGroups.decodeBundled(Data("not json".utf8)).channelIds, [])
        XCTAssertEqual(HarnessgramAgentGroups.decodeBundled(Data(#"{"agentProjectGroups": "-100900000002"}"#.utf8)).channelIds, [], "a malformed list marks nothing")
    }

    func testPublicDefaultHasNoAgentGroups() throws {
        let empty = Data(#"{"agentProjectGroups": []}"#.utf8)
        XCTAssertTrue(HarnessgramAgentGroups.decodeBundled(empty).channelIds.isEmpty)
        // Also pin the checked-in public resource, rather than only a hand-written fixture.
        var root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0 ..< 64 {
            let resource = root.appendingPathComponent("Telegram/Harnessgram/approved.json")
            if FileManager.default.fileExists(atPath: resource.path) {
                let data = try Data(contentsOf: resource)
                XCTAssertTrue(HarnessgramAgentGroups.decodeBundled(data).channelIds.isEmpty)
                let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
                XCTAssertEqual(json["agentProjectGroups"] as? [String], [])
                return
            }
            if root.path == "/" { break }
            root.deleteLastPathComponent()
        }
        throw XCTSkip("source resource is unavailable in this test environment")
    }

    func testSettingsAddGroupsAndTheSwitchDefaultsOff() {
        let suite = "HarnessgramAgentRibbonTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = HarnessgramSettings(defaults: defaults)
        XCTAssertFalse(settings.agentQuickActions)
        XCTAssertEqual(settings.agentProjectGroups, [])
        settings.agentProjectGroups = ["-1009999999999"]
        XCTAssertTrue(HarnessgramAgentGroups.current(settings: settings).contains(channelId: 9999999999))
        settings.agentProjectGroups = []
        XCTAssertNil(defaults.object(forKey: HarnessgramSettings.Key.agentProjectGroups.rawValue))
        XCTAssertFalse(HarnessgramAgentGroups.current(settings: settings).contains(channelId: 9999999999))
        settings.agentQuickActions = true
        XCTAssertTrue(HarnessgramSettings(defaults: defaults).agentQuickActions)
        defaults.set("yes", forKey: HarnessgramSettings.Key.agentQuickActions.rawValue)
        XCTAssertFalse(settings.agentQuickActions, "a corrupt value falls back to the default (off)")
        defaults.set([1, 2], forKey: HarnessgramSettings.Key.agentProjectGroups.rawValue)
        XCTAssertEqual(settings.agentProjectGroups, [], "a corrupt list falls back to none")
    }

    // The row keeps a 16 point gap above the composer (build 12: fewer mistaken taps), and the chat reserves room for both.
    func testTheRowKeepsItsGapAboveTheComposer() {
        let layout = HarnessgramAgentRibbon.Layout.self
        XCTAssertEqual(layout.composerGap, 16.0)
        XCTAssertEqual(layout.reservedHeight, layout.rowHeight + layout.composerGap)
        let panelsTop: CGFloat = 120.0
        let y = layout.rowOriginY(containerHeight: 800.0, panelsTopInset: panelsTop)
        XCTAssertEqual(800.0 - panelsTop - (y + layout.rowHeight), layout.composerGap, accuracy: 0.001, "gap between row and composer")
        XCTAssertEqual(layout.rowOriginY(containerHeight: 20.0, panelsTopInset: 120.0), 0.0, "never above the container")
    }

    /// Build 12 (owner, 15.11): the row is off for everyone who never chose it, build 11 users included,
    /// and an explicit choice made in Settings is kept.
    func testBuild11StoredDefaultMigratesToOffAndAChoiceIsKept() {
        let suite = "HarnessgramAgentRibbonTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: HarnessgramSettings.Key.agentQuickActions.rawValue)
        XCTAssertFalse(HarnessgramSettings(defaults: defaults).agentQuickActions, "a build 11 value without a choice is the old default")
        HarnessgramSettings(defaults: defaults).agentQuickActions = true
        XCTAssertTrue(HarnessgramSettings(defaults: defaults).agentQuickActions, "turned on in Settings stays on")
        HarnessgramSettings(defaults: defaults).agentQuickActions = false
        XCTAssertFalse(HarnessgramSettings(defaults: defaults).agentQuickActions, "turned off stays off")
        XCTAssertEqual(defaults.object(forKey: HarnessgramSettings.Key.agentQuickActionsChosen.rawValue) as? Bool, true)
    }

    func testDynamicNamesAreIsolatedFromHebrew() {
        XCTAssertEqual(HarnessgramAgentStrings.string(.radioReplaceText, ["host": "bridge.example.test"]), "הקישור החדש מגיע מהכתובת:\n\u{2068}bridge.example.test\u{2069}")
    }

    func testOnlyStopAsksBeforeSending() {
        XCTAssertEqual(HarnessgramAgentRibbon.Action.allCases.filter { $0.needsConfirmation }, [.stop])
        XCTAssertFalse(HarnessgramAgentStrings.string(.ribbonStopConfirmText).isEmpty)
        XCTAssertFalse(HarnessgramAgentStrings.string(.ribbonStopConfirm).isEmpty)
        XCTAssertFalse(HarnessgramAgentStrings.string(.ribbonStopCancel).isEmpty)
    }
}
