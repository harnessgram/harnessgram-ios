import XCTest
import LocalAuthentication
import HarnessgramAgent
import HarnessgramSettings

final class HarnessgramSensitiveActionTests: XCTestCase {
    private func needs(_ title: String?, data: String? = nil, text: String = "", fromBot: Bool = true) -> Bool {
        return HarnessgramSensitiveAction.requiresConfirmation(kind: .callback(data: Data((data ?? "").utf8)), buttonTitle: title, messageText: text, fromBot: fromBot)
    }

    func testSensitiveButtonTitlesNeedConfirmation() {
        let sensitive = [
            // money
            "💳 Pay now", "Buy credits", "Refund the order", "Approve payment", "שלם ₪120", "Charge $5", "אשר תשלום", "לרכוש מנוי",
            // deletion
            "🗑 Delete the branch", "Remove user", "Drop table orders", "Force push", "מחק את הקובץ", "למחוק הכול", "הסרה",
            // publication
            "Publish the video", "Make it public", "Send message to parents", "פרסם עכשיו", "לפרסם בסטטוס",
            // production and stores
            "Promote to production", "Deploy", "🚀 Go live", "Submit for review", "Upload to TestFlight", "העלה לחנות", "פריסה לפרודקשן",
            // accounts and credentials
            "Sign in", "Reset password", "Rotate API key", "Switch account", "החלף חשבון", "שנה סיסמה", "הרשאות מנהל",
        ]
        for title in sensitive {
            XCTAssertTrue(self.needs(title), title)
        }
    }

    func testOrdinaryButtonsPass() {
        let ordinary = ["▶️ המשך", "📋 מצב", "כן", "Yes", "Show diff", "Open log", "מחקר חדש", "הסרטון מוכן", "Product page", "📝 סיכום", "Screen", "🖥️ מסך", "More", "⚙️ עוד", "Retry", "נסה שוב", "שמור טיוטה"]
        for title in ordinary {
            XCTAssertFalse(self.needs(title), title)
        }
    }

    func testAPlainRefusalPasses() {
        for (title, data) in [("No", "say:no"), ("❌ לא", "say:no"), ("Cancel", "close:no"), ("ביטול", "x:cancel"), ("« Back", "more:back"), ("חזרה", "more:back"), ("Not now", "later"), ("לא עכשיו", "say:no"), ("אחר-כך", "skip"), ("Dismiss", "more:dismiss"), ("סגור", "close")] {
            XCTAssertFalse(self.needs(title, data: data, text: "Promote build 10 to production?"), title)
        }
        XCTAssertTrue(self.needs("Cancel subscription"), "a refusal word inside a sensitive action is not a refusal")
    }

    // Review fix: a refusal title does not exempt sensitive data or a card marked sensitive.
    func testARefusalTitleCannotHideASensitiveAction() {
        XCTAssertTrue(self.needs("No", data: "deploy:prod:no"), "sensitive data")
        XCTAssertTrue(self.needs("❌ לא", data: "confirmDelete"), "sensitive camelCase data")
        XCTAssertTrue(self.needs("ביטול", data: "say:no", text: "🔒 Sensitive question\nPromote build 10?"), "card marked sensitive")
        XCTAssertFalse(self.needs("ביטול", data: "x:17"), "not a plain refusal, but nothing sensitive either")
        XCTAssertTrue(self.needs("No", data: "say:no:yes", text: "Delete the branch?"), "data that also says yes is no plain refusal")
    }

    // Review fix: the bridge's "✅ כן" (say:yes) approves the action its question names.
    func testAYesApprovesWhatTheQuestionNames() {
        XCTAssertTrue(self.needs("✅ כן", data: "say:yes", text: "לפרסם את הסרטון בערוץ?"))
        XCTAssertTrue(self.needs("✅ כן", data: "say:yes", text: "Deploy to production?"))
        XCTAssertTrue(self.needs("Yes", data: "q:1", text: "Delete the old builds?"))
        XCTAssertTrue(self.needs("אישור", data: "q:1", text: "למחוק את הענף?"))
        XCTAssertTrue(self.needs("Approve", data: "q:1", text: "Send message to parents?"))
        XCTAssertTrue(self.needs("1", data: "approve:3", text: "Publish the episode?"), "yes in the data")
        XCTAssertFalse(self.needs("✅ כן", data: "say:yes", text: "להמשיך לשלב הבא?"), "a harmless question")
        XCTAssertFalse(self.needs("Yes", data: "say:yes", text: "Run the tests again?"), "a harmless question")
        XCTAssertFalse(self.needs("Show more", data: "more:1", text: "Deploy to production?"), "not a yes")
    }

    func testOtherButtonKinds() {
        for kind in [HarnessgramSensitiveAction.ButtonKind.urlAuth, .payment, .webApp] {
            XCTAssertTrue(HarnessgramSensitiveAction.requiresConfirmation(kind: kind, buttonTitle: "Open", messageText: "", fromBot: true))
            XCTAssertTrue(HarnessgramSensitiveAction.requiresConfirmation(kind: kind, buttonTitle: "Open", messageText: "", fromBot: false))
        }
        XCTAssertTrue(HarnessgramSensitiveAction.requiresConfirmation(kind: .text, buttonTitle: "🚀 Deploy to production", messageText: "", fromBot: true))
        XCTAssertTrue(HarnessgramSensitiveAction.requiresConfirmation(kind: .text, buttonTitle: "מחק הכול", messageText: "", fromBot: true))
        XCTAssertFalse(HarnessgramSensitiveAction.requiresConfirmation(kind: .text, buttonTitle: "▶️ המשך", messageText: "", fromBot: true))
        XCTAssertFalse(HarnessgramSensitiveAction.requiresConfirmation(kind: .text, buttonTitle: "⏹️ עצור", messageText: "", fromBot: true))
        XCTAssertFalse(HarnessgramSensitiveAction.requiresConfirmation(kind: .other, buttonTitle: "Delete", messageText: "", fromBot: true))
    }

    // Re-review fix: a reply-keyboard yes approves what the keyboard's question names, like an inline yes.
    func testAReplyKeyboardYesFollowsTheYesRule() {
        func text(_ title: String, _ message: String) -> Bool {
            return HarnessgramSensitiveAction.requiresConfirmation(kind: .text, buttonTitle: title, messageText: message, fromBot: true)
        }
        XCTAssertTrue(text("✅ כן", "Deploy to production?"))
        XCTAssertTrue(text("כן", "לפרסם את הסרטון בערוץ?"))
        XCTAssertTrue(text("Yes", "🔒 Sensitive question\nShip build 10?"), "card marked sensitive")
        XCTAssertFalse(text("✅ כן", "להמשיך לשלב הבא?"), "a harmless question")
        XCTAssertFalse(text("▶️ המשך", "🔒 Sensitive question"), "not a yes")
        XCTAssertFalse(text("❌ לא", "Deploy to production?"), "a no")
        // The ribbon's own texts never look sensitive.
        for action in HarnessgramAgentRibbon.Action.allCases {
            XCTAssertFalse(HarnessgramSensitiveAction.namesSensitiveAction(action.sentText), action.rawValue)
        }
    }

    func testTheBridgeSensitiveCardMarksEveryOtherButton() {
        let card = "🔒 Sensitive question\nShip build 10?"
        XCTAssertTrue(self.needs("✅ כן", data: "say:yes", text: card))
        XCTAssertFalse(self.needs("✅ כן", data: "say:yes", text: "Ship build 10?"), "without the marker a plain yes passes")
    }

    func testCallbackDataNamingASensitiveActionCounts() {
        XCTAssertTrue(self.needs("✅", data: "deploy_prod:42"))
        XCTAssertTrue(self.needs("OK", data: "rm:delete:7"))
        XCTAssertTrue(self.needs("✅", data: "confirmDelete"), "camelCase")
        XCTAssertTrue(self.needs("Go", data: "doPublish2"), "camelCase and digits")
        XCTAssertTrue(self.needs("Go", data: "release2prod"), "letters and digits")
        XCTAssertTrue(self.needs(nil, data: "publish:video:3"), "title unknown")
        // The bridge's everyday callbacks (see docs/harnessgram-local-config.md): never gated.
        for data in ["say:yes", "say:no", "say:stop", "say:continue", "say:status", "more:delivery", "more:autocompact", "close:restart", "mv:12", "fork:go", "ls:1", "more:back"] {
            XCTAssertFalse(self.needs("x", data: data), data)
        }
        XCTAssertFalse(self.needs("x", data: String(decoding: [0xFF, 0xFE, 0x00, 0x12], as: UTF8.self)), "binary data")
    }

    func testOnlyBotCardsAreGated() {
        XCTAssertFalse(self.needs("Delete", fromBot: false))
        XCTAssertFalse(self.needs("✅", text: "🔒 Sensitive", fromBot: false))
    }

    func testAGrantPassesTheGateOnceWhileFresh() {
        var now = Date(timeIntervalSince1970: 1_000_000)
        let confirmation = HarnessgramOwnerConfirmation(now: { now })
        let key = HarnessgramOwnerConfirmation.key(messageId: "1:0:5", callbackData: Data("deploy".utf8))
        XCTAssertNotEqual(key, HarnessgramOwnerConfirmation.key(messageId: "1:0:6", callbackData: Data("deploy".utf8)))
        XCTAssertNotEqual(key, HarnessgramOwnerConfirmation.key(messageId: "1:0:5", callbackData: Data("delete".utf8)))
        XCTAssertFalse(confirmation.consume(key), "nothing granted")
        confirmation.grant(key)
        XCTAssertTrue(confirmation.consume(key))
        XCTAssertFalse(confirmation.consume(key), "one replay only")
        confirmation.grant(key)
        now = now.addingTimeInterval(HarnessgramOwnerConfirmation.grantLifetime + 1.0)
        XCTAssertFalse(confirmation.consume(key), "expired")
    }

    func testThePromptNamesTheButton() {
        // The strings module wraps the English name in a bidi isolate (U+2068 ... U+2069) inside the Hebrew line.
        XCTAssertEqual(HarnessgramOwnerConfirmation.reason(buttonTitle: "Deploy"), "אישור פעולה רגישה: \u{2068}Deploy\u{2069}")
        XCTAssertEqual(HarnessgramOwnerConfirmation.reason(buttonTitle: "  "), "אישור פעולה רגישה")
        XCTAssertEqual(HarnessgramOwnerConfirmation.reason(buttonTitle: nil), "אישור פעולה רגישה")
        XCTAssertLessThanOrEqual(HarnessgramOwnerConfirmation.reason(buttonTitle: String(repeating: "x", count: 500)).count, 82, "60 characters of the title plus the prefix and the two isolate marks")
    }

    func testTheSwitchDefaultsOn() {
        let suite = "HarnessgramSensitiveActionTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = HarnessgramSettings(defaults: defaults)
        XCTAssertTrue(settings.confirmSensitiveButtons)
        settings.confirmSensitiveButtons = false
        XCTAssertFalse(HarnessgramSettings(defaults: defaults).confirmSensitiveButtons)
    }

    // MARK: Build 13: marker contract (review P1)

    func testMarkedButtonsAlwaysAsk() {
        // An opaque callback with a generic title: only the marker reveals it.
        XCTAssertFalse(self.needs("Continue", data: "action:42"), "unmarked, harmless text: passes")
        XCTAssertTrue(self.needs("Continue", data: "hg!action:42"), "marked callback data")
        XCTAssertTrue(self.needs("❌ לא", data: "hg!say:no", text: "Ship it?"), "a marked refusal asks too")
        XCTAssertTrue(HarnessgramSensitiveAction.requiresConfirmation(kind: .text, buttonTitle: "🔐 המשך", messageText: "", fromBot: true), "marked reply-keyboard title")
        XCTAssertTrue(HarnessgramSensitiveAction.requiresConfirmation(kind: .other, buttonTitle: " 🔐 Open", messageText: "", fromBot: true), "marked title on any kind")
        XCTAssertFalse(self.needs("Continue", data: "xhg!action"), "the marker is a prefix only")
        XCTAssertFalse(HarnessgramSensitiveAction.isMarked(kind: .callback(data: Data("HG!x".utf8)), buttonTitle: nil), "exact bytes")
    }

    func testAnUnmarkedBotsButtonsAskUnderMoneyDeletionOrPublication() {
        let text = "Your order #42 will be deleted in 5 minutes."
        XCTAssertTrue(self.needs("Continue", data: "action:42", text: text), "an unknown bot")
        XCTAssertTrue(HarnessgramSensitiveAction.requiresConfirmation(kind: .callback(data: Data("action:42".utf8)), buttonTitle: "Continue", messageText: "לשלם ₪40 עכשיו?", fromBot: true, botIsBridge: false))
        XCTAssertTrue(self.needs("Next", data: "n:1", text: "Publish the post to the channel?"))
        XCTAssertFalse(self.needs("❌ No", data: "say:no", text: text), "a plain refusal still passes")
        // The bridge follows the contract: its unmarked everyday buttons keep passing under such words.
        XCTAssertFalse(HarnessgramSensitiveAction.requiresConfirmation(kind: .callback(data: Data("say:continue".utf8)), buttonTitle: "▶️ המשך", messageText: text, fromBot: true, botIsBridge: true))
        XCTAssertTrue(HarnessgramSensitiveAction.requiresConfirmation(kind: .callback(data: Data("say:continue".utf8)), buttonTitle: "▶️ המשך", messageText: text, fromBot: true, botIsBridge: false), "the same button from any other bot asks")
        // Production or accounts words alone do not widen the rule (the yes rule and title rules still apply).
        XCTAssertFalse(self.needs("Show more", data: "more:1", text: "Deploy to production?"))
    }

    func testBridgeUsernamesAreNormalisedForResolvingOnly() {
        XCTAssertTrue(HarnessgramAgentChat.isBridgeBot(username: " @ExampleBridgeBot ", configuredUsername: "ExampleBridgeBot"))
        XCTAssertFalse(HarnessgramAgentChat.isBridgeBot(username: nil))
        XCTAssertFalse(HarnessgramAgentChat.isBridgeBot(username: "examplebridgebot2"))
    }

    // MARK: Build 14: the bridge by its pinned user id (review P2)

    private func identity() -> (HarnessgramBridgeIdentity, UserDefaults, String) {
        let suite = "HarnessgramBridgeIdentity." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        return (HarnessgramBridgeIdentity(settings: HarnessgramSettings(defaults: defaults)), defaults, suite)
    }

    func testOnlyTheBridgesOwnPanelPinsItsId() {
        let (identity, defaults, suite) = self.identity()
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(identity.state, .unknown)
        XCTAssertFalse(identity.isBridge(userId: 501), "nothing is the bridge before the panel names it (fail closed)")
        XCTAssertTrue(identity.mayLogIn(userId: 777), "before a pin, the login's own origin check guards it")
        identity.observePanel(botId: 501)
        XCTAssertEqual(identity.state, .pinned(501))
        XCTAssertTrue(identity.isBridge(userId: 501))
        XCTAssertFalse(identity.isBridge(userId: 502))
        XCTAssertFalse(identity.isBridge(userId: nil))
        XCTAssertTrue(identity.mayLogIn(userId: 501))
        XCTAssertFalse(identity.mayLogIn(userId: 777), "once pinned, the login goes only to the pinned bot")
        identity.observePanel(botId: 501)
        XCTAssertEqual(identity.state, .pinned(501), "the same id changes nothing")
        identity.observePanel(botId: 0)
        XCTAssertEqual(identity.state, .pinned(501), "an invalid id is ignored")
        XCTAssertEqual(HarnessgramBridgeIdentity(settings: HarnessgramSettings(defaults: defaults)).state, .pinned(501), "persisted")
    }

    func testADifferentPanelIdRemovesEveryPrivilegeUntilTheOwnerConfirms() {
        let (identity, defaults, suite) = self.identity()
        defer { defaults.removePersistentDomain(forName: suite) }
        identity.observePanel(botId: 501)
        identity.observePanel(botId: 777)
        XCTAssertEqual(identity.state, .changed(pinned: 501, seen: 777))
        XCTAssertFalse(identity.isBridge(userId: 501), "no privileges while a change waits")
        XCTAssertFalse(identity.isBridge(userId: 777))
        XCTAssertFalse(identity.mayLogIn(userId: 501))
        identity.observePanel(botId: 501)
        XCTAssertEqual(identity.state, .pinned(501), "the panel named the pinned bot again: the change is dropped")
        identity.observePanel(botId: 888)
        identity.confirmChangedBot()
        XCTAssertEqual(identity.state, .pinned(888), "the owner confirmed the new bot")
        XCTAssertTrue(identity.isBridge(userId: 888))
        XCTAssertFalse(identity.isBridge(userId: 501))
        identity.confirmChangedBot()
        XCTAssertEqual(identity.state, .pinned(888), "confirming with nothing pending changes nothing")
    }

    func testAPinFromBeforeThePanelIsDiscarded() {
        let (identity, defaults, suite) = self.identity()
        defer { defaults.removePersistentDomain(forName: suite) }
        // A build 13-14 pin: taken from the username, no source mark.
        defaults.set(NSNumber(value: Int64(777)), forKey: HarnessgramSettings.Key.bridgeBotId.rawValue)
        XCTAssertEqual(identity.state, .unknown, "not trusted")
        XCTAssertFalse(identity.isBridge(userId: 777))
        XCTAssertNil(defaults.object(forKey: HarnessgramSettings.Key.bridgeBotId.rawValue), "dropped")
        XCTAssertTrue(identity.mayLogIn(userId: 501), "the Cockpit login is not blocked by a missing pin")
        identity.observePanel(botId: 501)
        XCTAssertEqual(identity.state, .pinned(501))
        XCTAssertEqual(defaults.string(forKey: HarnessgramSettings.Key.bridgeBotIdSource.rawValue), "panel")
        XCTAssertTrue(HarnessgramBridgeIdentity(settings: HarnessgramSettings(defaults: defaults)).isBridge(userId: 501), "a panel pin survives a relaunch")
    }

    func testAStoredIdIsOnlyAPositiveInteger() {
        let (identity, defaults, suite) = self.identity()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("501", forKey: HarnessgramSettings.Key.bridgeBotId.rawValue)
        XCTAssertEqual(identity.state, .unknown)
        defaults.set(-5, forKey: HarnessgramSettings.Key.bridgeBotId.rawValue)
        XCTAssertEqual(identity.state, .unknown)
        defaults.set(501.5, forKey: HarnessgramSettings.Key.bridgeBotId.rawValue)
        XCTAssertEqual(identity.state, .unknown)
    }

    // MARK: Build 14: widget requests (review P1)

    func testACardRequestIsSentOnlyForTheSameLiveMessageOfTheSameAccount() {
        let captured = HarnessgramWidgetActions.Target(accountId: 11, messageKey: "m1")
        XCTAssertTrue(HarnessgramWidgetActions.mayStillSend(captured: captured, current: captured, messageExists: true, widgetAlive: true))
        XCTAssertFalse(HarnessgramWidgetActions.mayStillSend(captured: captured, current: .init(accountId: 11, messageKey: "m2"), messageExists: true, widgetAlive: true), "the cell now shows another message")
        XCTAssertFalse(HarnessgramWidgetActions.mayStillSend(captured: captured, current: .init(accountId: 22, messageKey: "m1"), messageExists: true, widgetAlive: true), "another account")
        XCTAssertFalse(HarnessgramWidgetActions.mayStillSend(captured: captured, current: nil, messageExists: true, widgetAlive: true), "the card is gone")
        XCTAssertFalse(HarnessgramWidgetActions.mayStillSend(captured: captured, current: captured, messageExists: false, widgetAlive: true), "the message was deleted")
        XCTAssertFalse(HarnessgramWidgetActions.mayStillSend(captured: captured, current: captured, messageExists: true, widgetAlive: false), "the widget was destroyed")
    }

    func testEveryWidgetRequestIsSensitiveUntilTheBridgeSaysOtherwise() {
        XCTAssertTrue(HarnessgramWidgetActions.isSensitive(bridgeFlag: nil))
        XCTAssertTrue(HarnessgramWidgetActions.isSensitive(bridgeFlag: true))
        XCTAssertFalse(HarnessgramWidgetActions.isSensitive(bridgeFlag: false))
    }

    func testAWidgetRequestIsSentOnlyAfterTheOwnerAndOnlyOnce() {
        let fake = FakeAuthenticator()
        let confirmation = HarnessgramOwnerConfirmation(authenticator: fake.authenticate)
        var sent = 0
        var refused = 0
        confirmation.confirmOnce(key: "widget|1", reason: "r", perform: { sent += 1 }, refuse: { refused += 1 })
        XCTAssertEqual(sent, 0, "nothing is sent before the owner")
        confirmation.confirmOnce(key: "widget|1", reason: "r", perform: { sent += 1 }, refuse: { refused += 1 })
        XCTAssertEqual(refused, 1, "a second request while the prompt is open is refused at once")
        XCTAssertEqual(fake.reasons.count, 1)
        fake.completions[0](true)
        XCTAssertEqual(sent, 1)
        confirmation.confirmOnce(key: "widget|1", reason: "r", perform: { sent += 1 }, refuse: { refused += 1 })
        fake.completions[1](false)
        XCTAssertEqual(sent, 1, "a cancel or a failure sends nothing")
        XCTAssertEqual(refused, 2)
        XCTAssertFalse(confirmation.isPending("widget|1"))
    }

    // MARK: Build 13: authentication outcomes (review P2)

    private final class FakeAuthenticator {
        var reasons: [String] = []
        var completions: [(Bool) -> Void] = []

        func authenticate(_ reason: String, _ completion: @escaping (Bool) -> Void) {
            self.reasons.append(reason)
            self.completions.append(completion)
        }
    }

    /// The native Cockpit asks for biometrics only (no passcode fallback); every other caller keeps the owner check.
    /// Review P2: the native Cockpit's biometrics policy is Face ID only.
    func testTheBiometricPolicyAcceptsFaceIDOnly() {
        XCTAssertTrue(HarnessgramOwnerConfirmation.isFaceID(.faceID))
        XCTAssertFalse(HarnessgramOwnerConfirmation.isFaceID(.touchID))
        XCTAssertFalse(HarnessgramOwnerConfirmation.isFaceID(.none))
    }

    func testTheBiometricPolicyUsesItsOwnCheck() {
        let owner = FakeAuthenticator()
        let biometric = FakeAuthenticator()
        let confirmation = HarnessgramOwnerConfirmation(authenticator: owner.authenticate, biometricAuthenticator: biometric.authenticate)
        var results: [Bool] = []
        confirmation.confirm(reason: "native", policy: .biometrics, completion: { results.append($0) })
        XCTAssertEqual(biometric.reasons, ["native"])
        XCTAssertTrue(owner.reasons.isEmpty)
        biometric.completions[0](false)
        confirmation.confirm(reason: "button", completion: { results.append($0) })
        XCTAssertEqual(owner.reasons, ["button"], "the default stays the owner check")
        owner.completions[0](true)
        XCTAssertEqual(results, [false, true])
    }

    func testAGatedPressProceedsOnlyAfterSuccessAndReplaysOnce() {
        let fake = FakeAuthenticator()
        let confirmation = HarnessgramOwnerConfirmation(authenticator: fake.authenticate)
        var proceeded = 0
        XCTAssertFalse(confirmation.gate(key: "k", reason: "r", proceed: { proceeded += 1 }))
        XCTAssertEqual(fake.reasons, ["r"])
        XCTAssertTrue(confirmation.isPending("k"))
        fake.completions[0](true)
        XCTAssertEqual(proceeded, 1)
        XCTAssertFalse(confirmation.isPending("k"))
        // The replay of the confirmed press passes once; the next press asks again.
        XCTAssertTrue(confirmation.gate(key: "k", reason: "r", proceed: { proceeded += 1 }))
        XCTAssertFalse(confirmation.gate(key: "k", reason: "r", proceed: { proceeded += 1 }))
        XCTAssertEqual(fake.reasons.count, 2)
    }

    func testCancelAndFailureSendNothing() {
        for outcome in ["cancel", "fail"] {
            let fake = FakeAuthenticator()
            let confirmation = HarnessgramOwnerConfirmation(authenticator: fake.authenticate)
            var proceeded = 0
            XCTAssertFalse(confirmation.gate(key: "k", reason: "r", proceed: { proceeded += 1 }), outcome)
            fake.completions[0](false)
            XCTAssertEqual(proceeded, 0, outcome)
            XCTAssertFalse(confirmation.isPending("k"), outcome)
            XCTAssertFalse(confirmation.consume("k"), "\(outcome): nothing granted")
        }
    }

    func testRepeatedPressesWhileThePromptIsOpenAskOnce() {
        let fake = FakeAuthenticator()
        let confirmation = HarnessgramOwnerConfirmation(authenticator: fake.authenticate)
        var proceeded = 0
        for _ in 0 ..< 3 {
            XCTAssertFalse(confirmation.gate(key: "k", reason: "r", proceed: { proceeded += 1 }))
        }
        XCTAssertEqual(fake.reasons.count, 1, "one prompt")
        XCTAssertFalse(confirmation.gate(key: "other", reason: "r2", proceed: {}))
        XCTAssertEqual(fake.reasons.count, 2, "another button gets its own prompt")
        fake.completions[0](true)
        XCTAssertEqual(proceeded, 1, "one send")
    }

    func testTheGateSwitchAsksOnlyToTurnOffAndKeepsTheGateOnAfterACancelOrFailure() {
        let suite = "HarnessgramSensitiveActionTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = HarnessgramSettings(defaults: defaults)
        let fake = FakeAuthenticator()
        let gate = HarnessgramGateSwitch(settings: settings, confirmation: HarnessgramOwnerConfirmation(authenticator: fake.authenticate), reason: "off")
        var changes = 0
        gate.onChange = { changes += 1 }
        XCTAssertTrue(gate.isOn)

        gate.set(false)
        XCTAssertTrue(gate.isConfirming)
        gate.set(false)
        gate.set(true)
        XCTAssertEqual(fake.reasons, ["off"], "taps while the prompt is open are ignored")
        fake.completions[0](false)
        XCTAssertFalse(gate.isConfirming)
        XCTAssertTrue(gate.isOn, "a cancel or a failure keeps the gate on")
        XCTAssertTrue(HarnessgramSettings(defaults: defaults).confirmSensitiveButtons)

        gate.set(false)
        fake.completions[1](true)
        XCTAssertFalse(gate.isOn)
        XCTAssertFalse(HarnessgramSettings(defaults: defaults).confirmSensitiveButtons, "a success turns it off and persists")

        gate.set(true)
        XCTAssertTrue(gate.isOn, "turning it on never asks")
        XCTAssertEqual(fake.reasons.count, 2)
        XCTAssertGreaterThanOrEqual(changes, 5)
    }
}
