import XCTest
import HarnessgramCockpitKit
import HarnessgramSettings

final class HarnessgramCockpitKitTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_763_200_000)

    private func json(_ object: Any) -> Data {
        return try! JSONSerialization.data(withJSONObject: object)
    }

    private func state(decisions: [[String: Any]] = [], sessions: [[String: Any]] = [], cards: [[String: Any]] = []) -> Data {
        return json(["ok": true, "decisions": decisions, "sessions": sessions, "cards": cards, "reminders": []])
    }

    private func decision(_ id: String, title: String = "Merge?", stale: String = "", sensitive: Bool? = nil) -> [String: Any] {
        var item: [String: Any] = ["id": id, "title": title, "detail": "", "yes": "כן", "no": "לא", "topic": "Example project", "age": "2m", "stale": stale, "old": false, "url": "https://t.me/c/900000002/77", "here": false]
        if let sensitive {
            item["sensitive"] = sensitive
        }
        return item
    }

    // MARK: parser

    func testDecisionsWithoutTheMarkAreSensitive() throws {
        let snapshot = try HarnessgramCockpitParser.snapshot(state: self.state(decisions: [self.decision("00000000000000a1"), self.decision("00000000000000a2", sensitive: false), self.decision("00000000000000a3", sensitive: true)]), radioPlayer: nil, now: self.now)
        XCTAssertEqual(snapshot.decisions.map { $0.sensitive }, [true, false, true])
    }

    func testStaleAndMalformedDecisionsAreDropped() throws {
        let snapshot = try HarnessgramCockpitParser.snapshot(state: self.state(decisions: [
            self.decision("00000000000000a1", stale: "ended"),
            self.decision("00000000000000a2"),
            self.decision("NOTHEX0000000000"),
            self.decision("00000000000000a3", title: "   "),
            ["title": "no id"],
        ]), radioPlayer: nil, now: self.now)
        XCTAssertEqual(snapshot.decisions.map { $0.id }, ["00000000000000a2"])
        XCTAssertEqual(snapshot.waitingCount, 1)
    }

    func testCountKeepsAllWhileLinesAreCapped() throws {
        let many = (0 ..< 8).map { self.decision(String(format: "%016x", $0 + 1)) }
        let snapshot = try HarnessgramCockpitParser.snapshot(state: self.state(decisions: many), radioPlayer: nil, now: self.now)
        XCTAssertEqual(snapshot.waitingCount, 8)
        XCTAssertEqual(snapshot.decisions.count, HarnessgramCockpitSnapshot.maxDecisions)
        XCTAssertEqual(snapshot.decisions.first?.id, "0000000000000001")
    }

    func testOnlyWorkingSessionsAreRunningAgents() throws {
        let snapshot = try HarnessgramCockpitParser.snapshot(state: self.state(sessions: [
            ["id": "aaaaaaaa", "name": "Harnessgram", "state": "working", "now": "Building", "url": "https://t.me/c/1/2"],
            ["id": "bbbbbbbb", "name": "Idle one", "state": "idle", "now": ""],
            ["id": "cccccccc", "name": "Done", "state": "ended"],
        ]), radioPlayer: nil, now: self.now)
        XCTAssertEqual(snapshot.runningAgents, 1)
        XCTAssertEqual(snapshot.agents.first?.name, "Harnessgram")
        XCTAssertEqual(snapshot.agents.first?.step, "Building")
    }

    func testProgressCardsUnfinishedFirstAndEndedDropped() throws {
        let snapshot = try HarnessgramCockpitParser.snapshot(state: self.state(cards: [
            ["id": "c1", "kind": "progress", "title": "Done task", "steps": ["a", "b"], "at": 2, "finished": true, "ended": false, "stale": false],
            ["id": "c2", "kind": "progress", "title": "Build 13", "steps": ["code", "tests", "build"], "at": 1, "percent": 40, "finished": false, "ended": false, "stale": false, "topic": "Harnessgram", "topic_url": "https://t.me/c/1/9"],
            ["id": "c3", "kind": "progress", "title": "Gone", "steps": [], "at": 0, "ended": true],
            ["id": "c4", "kind": "ask", "title": "Not progress"],
            ["id": "c5", "kind": "progress", "title": "Bad at", "steps": ["x"], "at": 99, "percent": 250, "ended": false],
        ]), radioPlayer: nil, now: self.now)
        XCTAssertEqual(snapshot.progress.map { $0.id }, ["c2", "c5", "c1"])
        XCTAssertEqual(snapshot.progress[1].done, 1)
        XCTAssertEqual(snapshot.progress[1].percent, 100)
    }

    func testRadioNeedsEnabledAndOn() throws {
        let off = try HarnessgramCockpitParser.snapshot(state: self.state(), radioPlayer: json(["ok": true, "enabled": false, "on": true]), now: self.now)
        XCTAssertEqual(off.radio, HarnessgramCockpitSnapshot.Radio(enabled: false, on: false))
        let on = try HarnessgramCockpitParser.snapshot(state: self.state(), radioPlayer: json(["ok": true, "enabled": true, "on": true]), now: self.now)
        XCTAssertEqual(on.radio, HarnessgramCockpitSnapshot.Radio(enabled: true, on: true))
        let missing = try HarnessgramCockpitParser.snapshot(state: self.state(), radioPlayer: nil, now: self.now)
        XCTAssertNil(missing.radio)
    }

    func testNotOKStateIsRefused() {
        XCTAssertThrowsError(try HarnessgramCockpitParser.snapshot(state: json(["ok": false]), radioPlayer: nil, now: self.now))
        XCTAssertThrowsError(try HarnessgramCockpitParser.snapshot(state: Data("<html>".utf8), radioPlayer: nil, now: self.now))
    }

    func testTitlesCannotFlipReadingOrderOrSpanLines() throws {
        let snapshot = try HarnessgramCockpitParser.snapshot(state: self.state(decisions: [self.decision("00000000000000a1", title: "\u{202E}evil\nline\u{2066}two")]), radioPlayer: nil, now: self.now)
        XCTAssertEqual(snapshot.decisions.first?.title, "evil linetwo")
    }

    func testRemovingADecisionUpdatesTheCount() {
        let snapshot = HarnessgramCockpitSnapshot.sample.withNotice("x").removingDecision("0000000000000001")
        XCTAssertEqual(snapshot.waitingCount, 2)
        XCTAssertFalse(snapshot.decisions.contains(where: { $0.id == "0000000000000001" }))
        XCTAssertNil(snapshot.notice)
        XCTAssertEqual(snapshot.removingDecision("ffffffffffffffff").waitingCount, 2)
    }

    // MARK: links

    func testTopicLinksOpenInsideTheApp() {
        XCTAssertEqual(HarnessgramCockpitLinks.appURL(forTopicURL: "https://t.me/c/900000002/77")?.absoluteString, "tg://privatepost?channel=900000002&thread=77")
        XCTAssertNil(HarnessgramCockpitLinks.appURL(forTopicURL: "https://evil.example/c/1/2"))
        XCTAssertNil(HarnessgramCockpitLinks.appURL(forTopicURL: "http://t.me/c/1/2"))
        XCTAssertNil(HarnessgramCockpitLinks.appURL(forTopicURL: "https://t.me/c/1/2/3"))
        XCTAssertNil(HarnessgramCockpitLinks.appURL(forTopicURL: ""))
    }

    func testDecideLinksRoundTripAndRejectTampering() {
        let url = HarnessgramCockpitLinks.decideURL(id: "00000000000000a1", choice: .yes)!
        XCTAssertEqual(HarnessgramCockpitLinks.parseWidgetLink(url.absoluteString), .decide(id: "00000000000000a1", choice: .yes))
        XCTAssertEqual(HarnessgramCockpitLinks.parseWidgetLink("harnessgram://widget/decide?id=00000000000000a1"), .decide(id: "00000000000000a1", choice: nil))
        XCTAssertEqual(HarnessgramCockpitLinks.parseWidgetLink("harnessgram://widget/open"), .open)
        XCTAssertEqual(HarnessgramCockpitLinks.parseWidgetLink(HarnessgramCockpitLinks.pairURL.absoluteString), .pair, "the unpaired widget's tap")
        XCTAssertNil(HarnessgramCockpitLinks.parseWidgetLink("harnessgram://widget/pair?token=x"), "the pair link carries nothing")
        XCTAssertNil(HarnessgramCockpitLinks.parseWidgetLink("harnessgram://widget/decide?id=00000000000000a1&choice=maybe"))
        XCTAssertNil(HarnessgramCockpitLinks.parseWidgetLink("harnessgram://widget/decide?id=00000000000000a1&id=00000000000000a2"))
        XCTAssertNil(HarnessgramCockpitLinks.parseWidgetLink("harnessgram://widget/decide?id=00000000000000a1&note=yes"))
        XCTAssertNil(HarnessgramCockpitLinks.parseWidgetLink("harnessgram://widget/decide?id=xyz"))
        XCTAssertNil(HarnessgramCockpitLinks.parseWidgetLink("harnessgram://radio?link=x"))
        XCTAssertNil(HarnessgramCockpitLinks.parseWidgetLink("https://widget/decide?id=00000000000000a1"))
        XCTAssertNil(HarnessgramCockpitLinks.decideURL(id: "../../x", choice: .no))
    }

    // MARK: login and the answer rule

    private let menu = "https://mac.private.example.test:10000/?x=1"

    private func webAppURL(authDate: Int, hash: Bool = true) -> String {
        var initData = "user=%7B%22id%22%3A1%7D&auth_date=\(authDate)"
        if hash {
            initData += "&hash=abc123"
        }
        let encoded = initData.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
        return "https://mac.private.example.test:10000/#tgWebAppData=\(encoded)&tgWebAppVersion=8.0"
    }

    func testLoginComesFromTheWebAppFragment() {
        let credential = HarnessgramCockpitCredential.from(webAppURL: self.webAppURL(authDate: 1_763_200_000), menuURL: self.menu, configuration: HarnessgramLocalConfig(bridgeHostSuffixes: [".private.example.test"]))
        XCTAssertEqual(credential?.initData, "user=%7B%22id%22%3A1%7D&auth_date=1763200000&hash=abc123")
        XCTAssertEqual(credential?.origin, "https://mac.private.example.test:10000")
        XCTAssertEqual(credential?.authDate, self.now)
        XCTAssertNil(HarnessgramCockpitCredential.from(webAppURL: self.webAppURL(authDate: 1_763_200_000, hash: false), menuURL: self.menu, configuration: HarnessgramLocalConfig(bridgeHostSuffixes: [".private.example.test"])))
        XCTAssertNil(HarnessgramCockpitCredential.from(webAppURL: "https://mac.private.example.test:10000/#%zz", menuURL: self.menu, configuration: HarnessgramLocalConfig(bridgeHostSuffixes: [".private.example.test"])))
    }

    func testLoginIsNeverSentOffTheTailnet() {
        XCTAssertNil(HarnessgramCockpitCredential.origin(ofMenuURL: "https://evil.example/"))
        XCTAssertNil(HarnessgramCockpitCredential.origin(ofMenuURL: "https://other.example.test/"))
        XCTAssertNil(HarnessgramCockpitCredential.origin(ofMenuURL: "http://mac.private.example.test/"))
        XCTAssertNil(HarnessgramCockpitCredential.origin(ofMenuURL: "https://user:pw@mac.private.example.test/"))
        XCTAssertNil(HarnessgramCockpitCredential.from(webAppURL: self.webAppURL(authDate: 1_763_200_000), menuURL: "https://evil.example/"))
        let forged = HarnessgramCockpitCredential(initData: "x", origin: "https://evil.example", authDate: self.now)
        XCTAssertNil(forged.originURL)
        XCTAssertFalse(forged.canRead(now: self.now))
        XCTAssertNil(HarnessgramCockpitClient.request(origin: URL(string: "https://evil.example")!, path: HarnessgramCockpitClient.statePath, credential: forged, body: Data()))
    }

    func testPairingRequiresConfigurationAndAuthorizesOnlyThePairedHost() throws {
        let config = HarnessgramLocalConfig(bridgeOrigin: "https://mac.private.example.test:10000")
        XCTAssertNil(HarnessgramCockpitCredential.origin(ofMenuURL: self.menu, configuration: HarnessgramLocalConfig()))
        let credential = try XCTUnwrap(HarnessgramCockpitCredential.from(webAppURL: self.webAppURL(authDate: 1_763_200_000), menuURL: self.menu, configuration: config))
        XCTAssertTrue(HarnessgramRadioLink.isAllowedHost("mac.private.example.test", trustedHost: nil, pairedOrigin: credential.origin, configuration: HarnessgramLocalConfig()))
        XCTAssertFalse(HarnessgramRadioLink.isAllowedHost("other.example.test", trustedHost: nil, pairedOrigin: credential.origin, configuration: HarnessgramLocalConfig()))
        XCTAssertNil(HarnessgramCockpitCredential.from(webAppURL: self.webAppURL(authDate: 1_763_200_000).replacingOccurrences(of: "mac.private.example.test", with: "other.example.test"), menuURL: self.menu, configuration: config))
        XCTAssertNil(HarnessgramCockpitClient.request(origin: URL(string: "https://other.example.test")!, path: HarnessgramCockpitClient.statePath, credential: credential, body: Data()))
        let restored = try JSONDecoder().decode(HarnessgramCockpitCredential.self, from: JSONEncoder().encode(credential))
        XCTAssertEqual(restored.originURL, credential.originURL, "protected pairing survives a restart without global host defaults")
        var changed = restored
        changed.origin = "https://other.example.test"
        XCTAssertNil(changed.originURL, "changing a credential does not authorize another origin")
    }

    func testLoginWindows() {
        let credential = HarnessgramCockpitCredential(initData: "x", origin: "https://mac.private.example.test:10000", authDate: self.now, configuration: HarnessgramLocalConfig(bridgeHostSuffixes: [".private.example.test"]))
        XCTAssertTrue(credential.canAnswer(now: self.now.addingTimeInterval(700)))
        XCTAssertFalse(credential.canAnswer(now: self.now.addingTimeInterval(800)))
        XCTAssertTrue(credential.canRead(now: self.now.addingTimeInterval(3000)))
        XCTAssertFalse(credential.canRead(now: self.now.addingTimeInterval(3400)))
        XCTAssertFalse(credential.canRead(now: self.now.addingTimeInterval(-120)))
    }

    func testSensitiveDecisionsAreNeverAnsweredOnTheWidget() {
        let fresh = HarnessgramCockpitCredential(initData: "x", origin: "https://mac.private.example.test:10000", authDate: self.now, configuration: HarnessgramLocalConfig(bridgeHostSuffixes: [".private.example.test"]))
        XCTAssertEqual(HarnessgramDecisionGate.route(sensitive: true, credential: fresh, now: self.now), .answerInAppWithFaceID)
        XCTAssertEqual(HarnessgramDecisionGate.route(sensitive: true, credential: nil, now: self.now), .answerInAppWithFaceID)
        XCTAssertEqual(HarnessgramDecisionGate.route(sensitive: false, credential: fresh, now: self.now), .answerOnWidget)
        XCTAssertEqual(HarnessgramDecisionGate.route(sensitive: false, credential: fresh, now: self.now.addingTimeInterval(900)), .answerInApp)
        XCTAssertEqual(HarnessgramDecisionGate.route(sensitive: false, credential: nil, now: self.now), .answerInApp)
    }

    // MARK: requests

    func testRequestsCarryTheLoginOnlyToKnownRoutes() throws {
        let credential = HarnessgramCockpitCredential(initData: "user=1&hash=2", origin: "https://mac.private.example.test:10000", authDate: self.now, configuration: HarnessgramLocalConfig(bridgeHostSuffixes: [".private.example.test"]))
        let request = try XCTUnwrap(HarnessgramCockpitClient.request(origin: credential.originURL!, path: HarnessgramCockpitClient.decidePath, credential: credential, body: HarnessgramCockpitClient.decideBody(id: "00000000000000a1", choice: .no)!))
        XCTAssertEqual(request.url?.absoluteString, "https://mac.private.example.test:10000/api/decide")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Telegram-Init-Data"), "user=1&hash=2")
        XCTAssertEqual(String(data: request.httpBody!, encoding: .utf8), "{\"choice\":\"no\",\"id\":\"00000000000000a1\"}")
        XCTAssertNil(HarnessgramCockpitClient.request(origin: credential.originURL!, path: "/api/radio", credential: credential, body: Data()))
        XCTAssertNil(HarnessgramCockpitClient.decideBody(id: "bad", choice: .yes))
    }

    func testDecideAnswersMapToOutcomes() {
        XCTAssertEqual(HarnessgramCockpitClient.answerOutcome(status: 200, body: json(["ok": true, "key": "k"])), .sent)
        XCTAssertEqual(HarnessgramCockpitClient.answerOutcome(status: 403, body: json(["error": "forbidden"])), .expired)
        XCTAssertEqual(HarnessgramCockpitClient.answerOutcome(status: 409, body: json(["error": "closed", "state": "answered"])), .closed)
        XCTAssertEqual(HarnessgramCockpitClient.answerOutcome(status: 409, body: json(["error": "queue full"])), .failed)
        XCTAssertEqual(HarnessgramCockpitClient.answerOutcome(status: 404, body: json(["error": "not found"])), .closed)
        XCTAssertEqual(HarnessgramCockpitClient.answerOutcome(status: 503, body: Data()), .failed)
    }

    // MARK: store

    func testStoreRoundTripsAndForgetsTheLogin() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = HarnessgramCockpitStore(directory: directory)
        XCTAssertNil(store.loadSnapshot())
        XCTAssertFalse(store.saveSnapshot(.sample), "no active account: nothing is stored")
        store.setActiveAccount(11)
        XCTAssertTrue(store.saveSnapshot(.sample))
        XCTAssertEqual(store.loadSnapshot(), .sample)
        let credential = HarnessgramCockpitCredential(initData: "x", origin: "https://mac.private.example.test:10000", authDate: self.now, configuration: HarnessgramLocalConfig(bridgeHostSuffixes: [".private.example.test"]))
        XCTAssertTrue(store.saveCredential(credential))
        XCTAssertEqual(store.loadCredential(), credential)
        XCTAssertEqual(store.viewState()?.bridgeOrigin, credential.originURL?.absoluteString)
        XCTAssertFalse(store.saveCredential(HarnessgramCockpitCredential(initData: "x", origin: "https://evil.example", authDate: self.now)))
        store.forgetCredential()
        XCTAssertNil(store.loadCredential())
        XCTAssertNil(store.viewState()?.bridgeOrigin)
    }

    func testRejectedLoginDoesNotEraseItsReplacement() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = HarnessgramCockpitStore(directory: directory)
        let session = try XCTUnwrap(store.setActiveAccount(11))
        let origin = "https://mac.private.example.test:10000"
        let configuration = HarnessgramLocalConfig(bridgeHostSuffixes: [".private.example.test"])
        let rejected = HarnessgramCockpitCredential(initData: "old", origin: origin, authDate: self.now, configuration: configuration)
        let replacement = HarnessgramCockpitCredential(initData: "new", origin: origin, authDate: self.now, configuration: configuration)
        XCTAssertTrue(store.saveCredential(rejected, forSession: session))
        XCTAssertTrue(store.saveCredential(replacement, forSession: session))
        store.forgetCredential(forSession: session, matching: rejected)
        XCTAssertEqual(store.loadCredential(forSession: session), replacement)
        store.forgetCredential(forSession: session, matching: replacement)
        XCTAssertNil(store.loadCredential(forSession: session))
    }

    // MARK: Build 14: per-account files and transactional updates (review P1/P2)

    private func tempStore(now: @escaping () -> Date = Date.init) -> (HarnessgramCockpitStore, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        return (HarnessgramCockpitStore(directory: directory, now: now), directory)
    }

    func testLogoutAndAccountSwitchRemoveTheEarlierAccountsLoginAndSnapshot() {
        let (store, directory) = self.tempStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let credential = HarnessgramCockpitCredential(initData: "x", origin: "https://mac.private.example.test:10000", authDate: self.now, configuration: HarnessgramLocalConfig(bridgeHostSuffixes: [".private.example.test"]))
        let a = store.setActiveAccount(11)
        XCTAssertNotNil(a)
        XCTAssertTrue(store.saveCredential(credential, forSession: a))
        XCTAssertTrue(store.saveSnapshot(.sample, forSession: a))
        XCTAssertTrue(store.hasLogin)
        XCTAssertEqual(store.setActiveAccount(11), a, "the same account keeps its session")
        // Switch: account 22 sees nothing of 11, and 11's files are gone even when switching back.
        store.setActiveAccount(22)
        XCTAssertEqual(store.activeAccount, 22)
        XCTAssertNil(store.loadCredential())
        XCTAssertNil(store.loadSnapshot())
        XCTAssertFalse(store.hasLogin)
        let a2 = store.setActiveAccount(11)
        XCTAssertNotEqual(a2, a, "back to 11 is a new session")
        XCTAssertNil(store.loadCredential(), "removed on the switch, not just hidden")
        XCTAssertNil(store.loadSnapshot())
        // Logout clears everything.
        XCTAssertTrue(store.saveCredential(credential))
        store.setActiveAccount(nil)
        XCTAssertNil(store.session)
        XCTAssertNil(store.loadCredential())
        XCTAssertFalse(store.saveCredential(credential), "logged out: no login is stored")
        store.setActiveAccount(11)
        XCTAssertNil(store.loadCredential())
    }

    // MARK: Build 15: session epoch (review P1/P2)

    func testAResultOfAnOlderSessionIsDropped() {
        let (store, directory) = self.tempStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let credential = HarnessgramCockpitCredential(initData: "x", origin: "https://mac.private.example.test:10000", authDate: self.now, configuration: HarnessgramLocalConfig(bridgeHostSuffixes: [".private.example.test"]))
        // A refresh or login starts in session A ...
        guard let a = store.setActiveAccount(11) else {
            return XCTFail("no session")
        }
        // ... the owner switches to B (or logs out) before it ends ...
        let b = store.setActiveAccount(22)
        XCTAssertFalse(store.isCurrent(a))
        XCTAssertFalse(store.saveCredential(credential, forSession: a), "A's late login is dropped")
        XCTAssertFalse(store.saveSnapshot(.sample, forSession: a), "A's late refresh is dropped")
        XCTAssertNil(store.markAnswered("0000000000000001", forSession: a))
        XCTAssertTrue(store.saveCredential(credential, forSession: b))
        // ... and even back on A, the old session's result stays dropped (A, B, A).
        let a2 = store.setActiveAccount(11)
        XCTAssertNotEqual(a2, a)
        XCTAssertFalse(store.saveSnapshot(.sample, forSession: a), "an A result from before the switch")
        XCTAssertNil(store.loadSnapshot())
        XCTAssertTrue(store.saveSnapshot(.sample, forSession: a2))
    }

    func testTheBuild13FilesAreRemovedOnEveryAccountEvent() throws {
        let (store, directory) = self.tempStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for name in ["login.json", "snapshot.json"] {
            try Data("{}".utf8).write(to: directory.appendingPathComponent(name))
        }
        store.setActiveAccount(11)
        for name in ["login.json", "snapshot.json"] {
            XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent(name).path), name)
        }
        try Data("{}".utf8).write(to: directory.appendingPathComponent("login.json"))
        store.setActiveAccount(nil)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("login.json").path), "logout removes it too")
    }

    func testTheAnswerContextIsOneConsistentRead() {
        let (store, directory) = self.tempStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let credential = HarnessgramCockpitCredential(initData: "x", origin: "https://mac.private.example.test:10000", authDate: self.now, configuration: HarnessgramLocalConfig(bridgeHostSuffixes: [".private.example.test"]))
        XCTAssertNil(store.answerContext(), "logged out")
        let a = store.setActiveAccount(11)
        store.saveSnapshot(.sample, forSession: a)
        store.saveCredential(credential, forSession: a)
        let context = store.answerContext()
        XCTAssertEqual(context?.session, a)
        XCTAssertEqual(context?.snapshot.decisions.count, 3)
        XCTAssertEqual(context?.credential, credential)
        store.setActiveAccount(22)
        XCTAssertNil(store.answerContext(), "B has no snapshot: nothing of A is mixed in")
    }

    /// Holds the store's cross-process lock the way the app or another extension would (a second open file description).
    private func holdLock(_ directory: URL) throws -> Int32 {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fd = open(directory.appendingPathComponent(".lock").path, O_CREAT | O_RDWR, 0o600)
        XCTAssertGreaterThanOrEqual(fd, 0)
        XCTAssertEqual(flock(fd, LOCK_EX | LOCK_NB), 0)
        return fd
    }

    private func isBusy<T>(_ result: HarnessgramCockpitStore.MutationResult<T>) -> Bool {
        if case .lockUnavailable = result {
            return true
        }
        return false
    }

    private func release(_ fd: Int32) {
        flock(fd, LOCK_UN)
        close(fd)
    }

    /// A busy lock is "unknown", never "logged out", "not paired", "paused" or "no snapshot".
    func testABusyLockIsNotAbsentState() throws {
        let (store, directory) = self.tempStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        XCTAssertEqual(store.answerContextChecked().completedValue.map { $0 == nil }, true, "absent: logged out")
        let a = store.setActiveAccount(11)
        XCTAssertNotNil(a)
        XCTAssertEqual(store.answerContextChecked().completedValue.map { $0 == nil }, true, "absent: no snapshot yet")
        store.saveSnapshot(.sample, forSession: a)

        let fd = try self.holdLock(directory)
        XCTAssertTrue(self.isBusy(store.answerContextChecked()), "busy, not absent")
        XCTAssertEqual(store.sessionChecked(), .lockUnavailable)
        XCTAssertEqual(store.hasLoginChecked(), .lockUnavailable)
        XCTAssertEqual(store.isPausedChecked(), .lockUnavailable)
        XCTAssertEqual(store.isCurrentChecked(a!), .lockUnavailable)
        XCTAssertEqual(store.markAnsweredChecked("d1", forSession: a), .lockUnavailable, "not remembered while busy")
        XCTAssertEqual(store.storeSnapshot(.sample, openDecisions: [], forSession: a), .lockUnavailable, "not stored while busy")
        self.release(fd)

        XCTAssertEqual(store.sessionChecked(), .completed(a))
        XCTAssertEqual(store.isCurrentChecked(a!), .completed(true))
        XCTAssertEqual(store.hasLoginChecked(), .completed(false))
        XCTAssertEqual(store.isPausedChecked(), .completed(false))
        XCTAssertEqual(store.answerContextChecked().completedValue??.session, a)
        XCTAssertEqual(store.loadSnapshot()?.decisions.count, 3, "the busy calls changed nothing")
    }

    /// A refresh stores the snapshot and the full open list in one step; once the lock is free, a retried answer is
    /// remembered and an older snapshot cannot bring the decision back.
    func testTheSnapshotAndOpenListAreStoredTogetherAndARetriedAnswerSticks() throws {
        let (store, directory) = self.tempStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let a = store.setActiveAccount(11)
        let decisions = HarnessgramCockpitSnapshot.sample.decisions
        XCTAssertEqual(store.storeSnapshot(.sample, openDecisions: decisions, forSession: a).completedValue??.decisions.count, decisions.count)
        XCTAssertEqual(store.loadOpenDecisions()?.count, decisions.count)
        let id = decisions[0].id

        let fd = try self.holdLock(directory)
        XCTAssertEqual(store.markAnsweredChecked(id, forSession: a), .lockUnavailable, "busy: not remembered yet")
        self.release(fd)
        XCTAssertFalse(self.isBusy(store.markAnsweredChecked(id, forSession: a)), "remembered once the lock is free")

        XCTAssertEqual(store.storeSnapshot(.sample, openDecisions: decisions, forSession: a).completedValue??.decisions.contains(where: { $0.id == id }), false)
        XCTAssertEqual(store.loadOpenDecisions()?.contains(where: { $0.id == id }), false)
        XCTAssertEqual(store.storeSnapshot(.sample, openDecisions: decisions, forSession: HarnessgramCockpitStore.Session(accountId: 11, epoch: "old")), .completed(nil), "an old session stores nothing")
    }

    func testRetryingWaitsForTheLock() async throws {
        let (store, directory) = self.tempStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let a = store.setActiveAccount(11)
        let fd = try self.holdLock(directory)
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.08) {
            flock(fd, LOCK_UN)
            close(fd)
        }
        let result = await HarnessgramCockpitStore.retrying(attempts: 6, initialDelay: 0.05, { store.sessionChecked() })
        XCTAssertEqual(result, .completed(a))
    }

    /// An answer the bridge accepted while the store stayed busy is kept pending and written by the next successful
    /// locked write: it is never forgotten while the process lives, and an older snapshot cannot bring it back.
    func testABusyAnswerStaysPendingUntilTheNextWrite() throws {
        let (store, directory) = self.tempStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let a = store.setActiveAccount(11)
        let decisions = HarnessgramCockpitSnapshot.sample.decisions
        store.saveSnapshot(.sample, forSession: a)
        let id = decisions[0].id
        let fd = try self.holdLock(directory)
        XCTAssertEqual(store.markAnsweredChecked(id, forSession: a), .lockUnavailable)
        self.release(fd)
        let context = store.answerContextChecked().completedValue ?? nil
        XCTAssertEqual(context?.snapshot.decisions.contains(where: { $0.id == id }), false, "reads hide a pending answer too")
        let stored = store.storeSnapshot(.sample, openDecisions: decisions, forSession: a).completedValue ?? nil
        XCTAssertEqual(stored?.decisions.contains(where: { $0.id == id }), false, "the pending answer filters the next snapshot")
        XCTAssertEqual(store.loadOpenDecisions()?.contains(where: { $0.id == id }), false)
        // Written to the shared files: another process (a fresh store on the same folder) keeps it out too.
        let other = HarnessgramCockpitStore(directory: directory)
        XCTAssertTrue(other.saveSnapshot(.sample, forSession: a))
        XCTAssertEqual(other.loadSnapshot()?.decisions.contains(where: { $0.id == id }), false)
    }

    /// A pending answer of an old session is dropped with that session, never written into the next account.
    func testAPendingAnswerNeverCrossesAccounts() throws {
        let (store, directory) = self.tempStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let a = store.setActiveAccount(11)
        let id = HarnessgramCockpitSnapshot.sample.decisions[0].id
        let fd = try self.holdLock(directory)
        XCTAssertEqual(store.markAnsweredChecked(id, forSession: a), .lockUnavailable)
        self.release(fd)
        let b = store.setActiveAccount(22)
        XCTAssertEqual(store.storeSnapshot(.sample, openDecisions: nil, forSession: b).completedValue??.decisions.contains(where: { $0.id == id }), true)
        XCTAssertEqual(HarnessgramWidgetStrings.emptyText(needsPairing: true, oneLine: true, unavailable: true), HarnessgramWidgetStrings.temporarilyUnavailable, "busy is never the pairing text")
    }

    /// The whole widget answer through a stub network: the account switches while the answer is on its way. The answer
    /// was checked before sending (same session for decision and login); what comes back afterwards is dropped.
    func testAWidgetAnswerNeverWritesIntoAnotherAccount() {
        let (store, directory) = self.tempStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let credential = HarnessgramCockpitCredential(initData: "x", origin: "https://mac.private.example.test:10000", authDate: self.now, configuration: HarnessgramLocalConfig(bridgeHostSuffixes: [".private.example.test"]))
        let a = store.setActiveAccount(11)
        store.saveSnapshot(.sample, forSession: a)
        store.saveCredential(credential, forSession: a)
        HarnessgramStubProtocol.onRequest = {
            // The owner switches to B while A's answer is in flight; B has its own snapshot.
            let b = store.setActiveAccount(22)
            store.saveSnapshot(.sample, forSession: b)
        }
        defer { HarnessgramStubProtocol.onRequest = nil }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HarnessgramStubProtocol.self]
        let client = HarnessgramCockpitClient(session: URLSession(configuration: configuration))
        let done = expectation(description: "answer")
        var result: HarnessgramWidgetAnswer.Result?
        Task {
            result = await HarnessgramWidgetAnswer.run(id: "0000000000000001", choice: "yes", store: store, client: client, now: self.now)
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
        XCTAssertEqual(result, .answered(.sent))
        XCTAssertEqual(store.activeAccount, 22)
        XCTAssertEqual(store.loadSnapshot()?.decisions.count, 3, "A's answer does not touch B's snapshot")
    }

    func testTheEmptyWidgetAsksForPairingUntilPaired() {
        XCTAssertEqual(HarnessgramWidgetStrings.emptyText(needsPairing: true, oneLine: false), "צריך לחבר את הווידג׳ט לגשר\nהקשה כאן מחברת אותו", "the line says what the owner does: the tap connects")
        XCTAssertEqual(HarnessgramWidgetStrings.emptyText(needsPairing: true, oneLine: true), "צריך לחבר את הווידג׳ט לגשר")
        XCTAssertEqual(HarnessgramWidgetStrings.emptyText(needsPairing: false, oneLine: false), HarnessgramWidgetStrings.openAppToRefresh)
    }

    func testThePanelNamesTheBridgeBotId() throws {
        let base: [String: Any] = ["ok": true, "decisions": [], "sessions": [], "cards": []]
        let cases: [(Any, Int64?)] = [(Int64(7_123_456_789), 7_123_456_789), ("7123456789", 7_123_456_789), (-5, nil), ("12a", nil), (1.5, nil)]
        for (value, expected) in cases {
            var root = base
            root["bot_id"] = value
            let data = try JSONSerialization.data(withJSONObject: root)
            XCTAssertEqual(try HarnessgramCockpitParser.snapshot(state: data, radioPlayer: nil, now: self.now).botId, expected, "\(value)")
        }
        let data = try JSONSerialization.data(withJSONObject: base)
        XCTAssertNil(try HarnessgramCockpitParser.snapshot(state: data, radioPlayer: nil, now: self.now).botId, "no bot_id: nothing is pinned")
    }

    func testAnAnsweredDecisionNeverComesBackFromAnOlderSnapshot() {
        var clock = Date(timeIntervalSince1970: 1_000_000)
        let (store, directory) = self.tempStore(now: { clock })
        defer { try? FileManager.default.removeItem(at: directory) }
        store.setActiveAccount(11)
        store.saveSnapshot(.sample)
        let id = HarnessgramCockpitSnapshot.sample.decisions[0].id
        store.markAnswered(id)
        XCTAssertFalse(store.loadSnapshot()?.decisions.contains(where: { $0.id == id }) ?? true)
        // A refresh fetched before the answer landed must not bring it back.
        store.saveSnapshot(.sample)
        XCTAssertFalse(store.loadSnapshot()?.decisions.contains(where: { $0.id == id }) ?? true)
        // Long after, the bridge is the source of truth again.
        clock = clock.addingTimeInterval(HarnessgramCockpitStore.answeredMemory + 1)
        store.saveSnapshot(.sample)
        XCTAssertTrue(store.loadSnapshot()?.decisions.contains(where: { $0.id == id }) ?? false)
    }

    /// Two processes (here: separate store objects on one folder, each with its own file lock handle) answering at
    /// the same time never undo each other's answer.
    func testConcurrentAnswersFromSeparateStoresAreAllKept() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let setup = HarnessgramCockpitStore(directory: directory)
        setup.setActiveAccount(11)
        var snapshot = HarnessgramCockpitSnapshot.sample
        let template = snapshot.decisions[0]
        snapshot.decisions = (0 ..< 24).map { index in
            var decision = template
            decision.id = String(format: "%016x", index + 0x100)
            return decision
        }
        XCTAssertTrue(setup.saveSnapshot(snapshot))
        let ids = snapshot.decisions.map { $0.id }
        DispatchQueue.concurrentPerform(iterations: ids.count) { index in
            let store = HarnessgramCockpitStore(directory: directory)
            store.markAnswered(ids[index])
            store.updateSnapshot { $0.withNotice(nil) }
        }
        XCTAssertEqual(setup.loadSnapshot()?.decisions.count, 0, "every answer stays answered")
    }

    // MARK: Build 16: one account only, pause until re-paired

    func testTheAccountRule() {
        let session = HarnessgramCockpitStore.Session(accountId: 11, epoch: "e")
        typealias Rule = HarnessgramAccountRule
        XCTAssertEqual(Rule.action(primary: 11, loggedInCount: 1, session: nil, isPaused: false), .start(11), "one account, first time: it pairs")
        XCTAssertEqual(Rule.action(primary: 11, loggedInCount: 1, session: session, isPaused: false), .none, "nothing changed")
        XCTAssertEqual(Rule.action(primary: 11, loggedInCount: 2, session: session, isPaused: false), .pause, "a second login completed")
        XCTAssertEqual(Rule.action(primary: 22, loggedInCount: 2, session: session, isPaused: false), .pause, "a switch")
        XCTAssertEqual(Rule.action(primary: 22, loggedInCount: 1, session: session, isPaused: false), .pause, "another account than the paired one")
        XCTAssertEqual(Rule.action(primary: nil, loggedInCount: 0, session: session, isPaused: false), .pause, "logout")
        XCTAssertEqual(Rule.action(primary: nil, loggedInCount: 0, session: nil, isPaused: false), .none, "never paired: nothing to wipe")
        XCTAssertEqual(Rule.action(primary: 11, loggedInCount: 2, session: nil, isPaused: false), .pause, "two accounts from the start")
        XCTAssertFalse(Rule.requiresPause(previousPrimary: nil, previousLoggedInCount: 0, primary: 11, loggedInCount: 1, alreadyPending: false), "first account does not require a pause")
        XCTAssertTrue(Rule.requiresPause(previousPrimary: 11, previousLoggedInCount: 1, primary: 22, loggedInCount: 1, alreadyPending: false), "A to B requires a pause even before B reaches storage")
        XCTAssertTrue(Rule.requiresPause(previousPrimary: 22, previousLoggedInCount: 1, primary: 11, loggedInCount: 1, alreadyPending: true), "A to B to A keeps the pause while persistence is delayed")
        XCTAssertFalse(Rule.requiresPause(previousPrimary: 11, previousLoggedInCount: 1, primary: 11, loggedInCount: 1, alreadyPending: false), "the same account needs no pause")
        for count in [0, 1, 2] {
            XCTAssertEqual(Rule.action(primary: 11, loggedInCount: count, session: nil, isPaused: true), .none, "paused stays paused until re-paired (\(count))")
        }
    }

    func testPauseWipesEverythingAndOnlyARepairStartsAgain() throws {
        let (store, directory) = self.tempStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let credential = HarnessgramCockpitCredential(initData: "x", origin: "https://mac.private.example.test:10000", authDate: self.now, configuration: HarnessgramLocalConfig(bridgeHostSuffixes: [".private.example.test"]))
        let a = store.setActiveAccount(11)
        store.saveSnapshot(.sample, forSession: a)
        store.saveCredential(credential, forSession: a)
        try Data("{}".utf8).write(to: directory.appendingPathComponent("login.json"))
        store.pause()
        XCTAssertTrue(store.isPaused)
        XCTAssertNil(store.session)
        XCTAssertNil(store.loadSnapshot())
        XCTAssertNil(store.loadCredential())
        XCTAssertFalse(store.hasLogin)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("login.json").path))
        XCTAssertNil(store.setActiveAccount(11), "an account event does not restart a paused Cockpit")
        XCTAssertFalse(store.saveSnapshot(.sample, forSession: a), "nothing of the old session comes back")
        let repaired = store.resume(accountId: 11)
        XCTAssertNotNil(repaired)
        XCTAssertNotEqual(repaired, a, "a fresh session")
        XCTAssertFalse(store.isPaused)
        XCTAssertNil(store.loadSnapshot(), "re-pairing starts empty")
    }

    // MARK: Build 18: the chat-list widget follows the one-account rule

    func testTheChatWidgetGateNeedsOneUnpausedSessionOfThatAccount() {
        let session = HarnessgramCockpitStore.Session(accountId: 11, epoch: "e")
        XCTAssertTrue(HarnessgramChatWidgetGate.isEnabled(session: session, isPaused: false, accountPeerId: 11))
        XCTAssertFalse(HarnessgramChatWidgetGate.isEnabled(session: session, isPaused: false, accountPeerId: 22), "another account")
        XCTAssertFalse(HarnessgramChatWidgetGate.isEnabled(session: session, isPaused: true, accountPeerId: 11), "paused (2+ accounts, switch, logout)")
        XCTAssertFalse(HarnessgramChatWidgetGate.isEnabled(session: nil, isPaused: false, accountPeerId: 11), "no session")
    }

    func testTheShownChatsAreKeptWithTheSessionAndWipedWithIt() {
        let (store, directory) = self.tempStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        guard let a = store.setActiveAccount(11) else {
            return XCTFail("no session")
        }
        XCTAssertTrue(store.saveChatWidgetShown([7: [101, 102]], forSession: a))
        XCTAssertEqual(store.loadChatWidgetShown(), [7: [101, 102]])
        let b = store.setActiveAccount(22)
        XCTAssertEqual(store.loadChatWidgetShown(), [:], "a switch wipes them")
        XCTAssertFalse(store.saveChatWidgetShown([7: [103]], forSession: a), "an old session's result is dropped")
        if let b {
            store.saveChatWidgetShown([8: [104]], forSession: b)
        }
        store.pause()
        XCTAssertEqual(store.loadChatWidgetShown(), [:], "pause wipes them")
    }

    // MARK: widget answer (no request is ever made on these paths)

    private func answerStore() -> (HarnessgramCockpitStore, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = HarnessgramCockpitStore(directory: directory)
        store.setActiveAccount(11)
        store.saveSnapshot(.sample)
        return (store, directory)
    }

    private func run(_ store: HarnessgramCockpitStore, id: String, choice: String = "yes") -> HarnessgramWidgetAnswer.Result {
        let done = expectation(description: "answer")
        var result: HarnessgramWidgetAnswer.Result?
        Task {
            result = await HarnessgramWidgetAnswer.run(id: id, choice: choice, store: store, client: HarnessgramCockpitClient(), now: self.now)
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
        return result!
    }

    func testWidgetNeverAnswersASensitiveDecision() {
        let (store, directory) = self.answerStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        store.saveCredential(HarnessgramCockpitCredential(initData: "x", origin: "https://mac.private.example.test:10000", authDate: self.now, configuration: HarnessgramLocalConfig(bridgeHostSuffixes: [".private.example.test"])))
        // 0000000000000002 is the sensitive line of the sample.
        XCTAssertEqual(self.run(store, id: "0000000000000002"), .refused)
        XCTAssertEqual(store.loadSnapshot()?.waitingCount, 3)
        XCTAssertEqual(store.loadSnapshot()?.notice, HarnessgramWidgetStrings.answerNotSent)
    }

    func testWidgetAnswersOnlyWhatItShowedAndOnlyWithALogin() {
        let (store, directory) = self.answerStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        XCTAssertEqual(self.run(store, id: "00000000000000ff"), .refused)
        XCTAssertEqual(self.run(store, id: "0000000000000001", choice: "maybe"), .refused)
        XCTAssertEqual(self.run(store, id: "0000000000000001"), .refused)
        XCTAssertEqual(store.loadSnapshot()?.waitingCount, 3)
    }

    // MARK: Live Activity

    func testTaskStateProgress() {
        let state = HarnessgramTaskState(title: "Build", topic: "", steps: ["a", "b", "c", "d"], done: 1, percent: nil, finished: false)
        XCTAssertEqual(state.fraction, 0.25, accuracy: 0.0001)
        XCTAssertEqual(state.currentStep, "b")
        XCTAssertEqual(state.stepLine, "שלב 2 מתוך 4")
        let percent = HarnessgramTaskState(title: "Build", topic: "", steps: ["a"], done: 0, percent: 70, finished: false)
        XCTAssertEqual(percent.percentShown, 70)
        let done = HarnessgramTaskState(title: "Build", topic: "", steps: ["a", "b"], done: 5, percent: nil, finished: true)
        XCTAssertEqual(done.done, 2)
        XCTAssertNil(done.currentStep)
        XCTAssertEqual(done.stepLine, "נחת בשלום")
        XCTAssertEqual(done.percentShown, 100)
    }

    private func card(_ id: String, updated: Double?, finished: Bool = false, stale: Bool? = nil) -> HarnessgramCockpitSnapshot.Progress {
        return HarnessgramCockpitSnapshot.Progress(id: id, title: id, topic: "", steps: ["a", "b"], done: 0, percent: nil, topicURL: "", finished: finished, updated: updated, stale: stale)
    }

    private func ids(_ plan: [HarnessgramTaskActivityPlan.Shown]) -> [String] {
        return plan.map { $0.cardId }
    }

    func testThePlanWithZeroOneThreeAndFiveCards() {
        let t = self.now.timeIntervalSince1970
        XCTAssertEqual(HarnessgramTaskActivityPlan.choose([], now: self.now), [])
        let one = self.card("one", updated: t - 60)
        XCTAssertEqual(HarnessgramTaskActivityPlan.choose([one], now: self.now), [HarnessgramTaskActivityPlan.Shown(cardId: "one", state: HarnessgramTaskState(progress: one))])
        let three = [self.card("a", updated: t - 300), self.card("b", updated: t - 100), self.card("c", updated: t - 200)]
        XCTAssertEqual(self.ids(HarnessgramTaskActivityPlan.choose(three, now: self.now)), ["b", "c", "a"])
        let five = three + [self.card("d", updated: t - 50), self.card("e", updated: t - 400)]
        let plan = HarnessgramTaskActivityPlan.choose(five, now: self.now)
        XCTAssertEqual(self.ids(plan), ["d", "b", HarnessgramTaskActivityPlan.summaryCardId])
        XCTAssertEqual(plan.last?.state.title, "+3 משימות נוספות")
        XCTAssertEqual(plan.last?.state.overflowCount, 3)
        let four = three + [self.card("d", updated: t - 50)]
        XCTAssertEqual(HarnessgramTaskActivityPlan.choose(four, now: self.now).last?.state.title, "+2 משימות נוספות")
        let shown = Dictionary(uniqueKeysWithValues: plan.map { ($0.cardId, $0.state) })
        XCTAssertEqual(self.ids(HarnessgramTaskActivityPlan.pushes(HarnessgramTaskActivityPlan.choose(four, now: self.now), lastShown: shown, lastTop: "d")), [HarnessgramTaskActivityPlan.summaryCardId, "d"])
    }

    func testThePlanOrdersByUpdateNotByListOrderAndSkipsFinishedCards() {
        let t = self.now.timeIntervalSince1970
        let cards = [self.card("old", updated: t - 3600), self.card("done", updated: t - 5, finished: true), self.card("new", updated: t - 60), self.card("mid", updated: t - 600)]
        XCTAssertEqual(self.ids(HarnessgramTaskActivityPlan.choose(cards, now: self.now)), ["new", "mid", "old"])
    }

    func testThePlanSkipsStaleCardsButKeepsQuietCards() {
        let t = self.now.timeIntervalSince1970
        let cards = [self.card("quiet", updated: t - 900), self.card("stuck", updated: t - 30, stale: true),
                     self.card("forgotten", updated: t - 7201),
                     self.card("edge", updated: t - 7200)]
        XCTAssertEqual(self.ids(HarnessgramTaskActivityPlan.choose(cards, now: self.now)), ["quiet", "edge", "forgotten"])
        let none = [self.card("done", updated: t - 5, finished: true), self.card("stuck", updated: t - 5, stale: true)]
        XCTAssertEqual(HarnessgramTaskActivityPlan.choose(none, now: self.now), [])
    }

    func testThePlanKeepsTheSnapshotOrderOnTiesAndWithoutTimes() {
        let t = self.now.timeIntervalSince1970
        XCTAssertEqual(self.ids(HarnessgramTaskActivityPlan.choose([self.card("a", updated: t - 60), self.card("b", updated: t - 60)], now: self.now)), ["a", "b"])
        XCTAssertEqual(self.ids(HarnessgramTaskActivityPlan.choose([self.card("a", updated: nil), self.card("b", updated: nil)], now: self.now)), ["a", "b"])
        // An older bridge without times: never dropped as old; a card with a time still ranks first.
        XCTAssertEqual(self.ids(HarnessgramTaskActivityPlan.choose([self.card("a", updated: nil), self.card("b", updated: t - 7000)], now: self.now)), ["b", "a"])
    }

    func testPushesSendTheNewestCardLastAndSkipIdenticalStates() {
        let t = self.now.timeIntervalSince1970
        let plan = HarnessgramTaskActivityPlan.choose([self.card("a", updated: t - 300), self.card("b", updated: t - 100), self.card("c", updated: t - 200)], now: self.now)
        // First sync: every card, oldest first, so the newest ("b") ends in front.
        XCTAssertEqual(self.ids(HarnessgramTaskActivityPlan.pushes(plan, lastShown: [:], lastTop: nil)), ["a", "c", "b"])
        let shown = Dictionary(uniqueKeysWithValues: plan.map { ($0.cardId, $0.state) })
        // Nothing changed: nothing is sent.
        XCTAssertEqual(HarnessgramTaskActivityPlan.pushes(plan, lastShown: shown, lastTop: "b"), [])
        // A lower card changed (same order): it is sent, then the top card again so it stays in front.
        var changed = shown
        changed["a"] = HarnessgramTaskState(title: "a", topic: "", steps: ["x"], done: 0, percent: nil, finished: false)
        XCTAssertEqual(self.ids(HarnessgramTaskActivityPlan.pushes(plan, lastShown: changed, lastTop: "b")), ["a", "b"])
        // The order changed with identical states: the new top card gets the final update.
        XCTAssertEqual(self.ids(HarnessgramTaskActivityPlan.pushes(plan, lastShown: shown, lastTop: "c")), ["b"])
        XCTAssertEqual(HarnessgramTaskActivityPlan.pushes([], lastShown: shown, lastTop: "b"), [])
    }

    func testParserKeepsAllCardsOrderedForTheActivitySummary() throws {
        let t = self.now.timeIntervalSince1970
        let snapshot = try HarnessgramCockpitParser.snapshot(state: self.state(cards: [
            ["id": "c1", "kind": "progress", "title": "Oldest", "steps": ["a"], "at": 0, "updated": t - 4000],
            ["id": "c2", "kind": "progress", "title": "Older", "steps": ["a"], "at": 0, "updated": t - 3000],
            ["id": "c3", "kind": "progress", "title": "Done", "steps": ["a"], "at": 1, "finished": true, "updated": t - 5],
            ["id": "c4", "kind": "progress", "title": "Old", "steps": ["a"], "at": 0, "updated": t - 2000],
            ["id": "c5", "kind": "progress", "title": "Newest", "steps": ["a"], "at": 0, "updated": t - 10],
            ["id": "c6", "kind": "progress", "title": "Bad time", "steps": ["a"], "at": 0, "updated": true],
        ]), radioPlayer: nil, now: self.now)
        XCTAssertEqual(snapshot.progress.map { $0.id }, ["c5", "c4", "c2", "c1", "c6", "c3"])
        XCTAssertEqual(snapshot.progress.first?.updated, t - 10)
        XCTAssertEqual(snapshot.progress.first?.stale, nil)
        let plan = HarnessgramTaskActivityPlan.choose(snapshot.progress, now: self.now)
        XCTAssertEqual(self.ids(plan), ["c5", "c4", HarnessgramTaskActivityPlan.summaryCardId])
        XCTAssertEqual(plan.last?.state.title, "+3 משימות נוספות")
    }

    func testAStoredSnapshotWithoutTheNewFieldsStillDecodes() throws {
        let stored = #"{"id":"p","title":"T","topic":"","steps":[],"done":0,"topicURL":"","finished":false}"#
        let card = try JSONDecoder().decode(HarnessgramCockpitSnapshot.Progress.self, from: Data(stored.utf8))
        XCTAssertNil(card.updated)
        XCTAssertNil(card.stale)
    }

    func testStringsReadRightToLeftAndKeepEnglishIsolated() {
        XCTAssertTrue(HarnessgramWidgetStrings.isRightToLeft)
        XCTAssertTrue(HarnessgramWidgetStrings.needsFaceID.contains("\u{2068}Face ID\u{2069}"))
        XCTAssertEqual(HarnessgramWidgetStrings.waitingCount(1), "אישור המראה אחד ממתין")
        XCTAssertEqual(HarnessgramWidgetStrings.updated(30), "עודכן עכשיו")
        XCTAssertEqual(HarnessgramWidgetStrings.updated(300), "עודכן לפני 5 דק׳")
    }

    func testLiveActivityTokenBodyMatchesTheBridgeContract() throws {
        let token = Data([0x0a, 0xff, 0x10])
        let body = try XCTUnwrap(HarnessgramCockpitClient.liveActivityTokenBody(cardId: "card-1", token: token, sandbox: false))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: String])
        XCTAssertEqual(json, ["card_id": "card-1", "token": "0aff10", "env": "production"])
        let sandbox = try XCTUnwrap(HarnessgramCockpitClient.liveActivityTokenBody(cardId: "card-1", token: token, sandbox: true))
        XCTAssertEqual((try JSONSerialization.jsonObject(with: sandbox) as? [String: String])?["env"], "sandbox")
        let ended = try XCTUnwrap(HarnessgramCockpitClient.liveActivityTokenBody(cardId: "card-1", token: nil, sandbox: false))
        let endedJson = try XCTUnwrap(JSONSerialization.jsonObject(with: ended) as? [String: Any])
        XCTAssertEqual(Set(endedJson.keys), ["card_id", "ended"])
        XCTAssertEqual(endedJson["ended"] as? Bool, true)
        XCTAssertNil(HarnessgramCockpitClient.liveActivityTokenBody(cardId: "bad id/../x", token: token, sandbox: false))
        XCTAssertNil(HarnessgramCockpitClient.liveActivityTokenBody(cardId: "", token: token, sandbox: false))
        XCTAssertNil(HarnessgramCockpitClient.liveActivityTokenBody(cardId: "card-1", token: Data(), sandbox: false))
    }

    func testPushedTaskStateIsClampedLikeLocalOnes() throws {
        let json = #"{"title":"t","topic":"p","steps":["a","b"],"done":-3,"percent":250,"finished":false}"#
        let state = try JSONDecoder().decode(HarnessgramTaskState.self, from: Data(json.utf8))
        XCTAssertEqual(state.done, 0)
        XCTAssertEqual(state.percent, 100)
        XCTAssertEqual(state.currentStep, "a")
        let over = try JSONDecoder().decode(HarnessgramTaskState.self, from: Data(#"{"title":"t","topic":"p","steps":["a"],"done":9,"finished":false,"overflowCount":2}"#.utf8))
        XCTAssertEqual(over.done, 1)
        XCTAssertNil(over.percent)
        XCTAssertEqual(over.overflowCount, 2)
        XCTAssertNil(over.currentStep)
    }
}

/// A stub network for the widget answer test: every request gets 200 {"ok": true}, after `onRequest` runs.
final class HarnessgramStubProtocol: URLProtocol {
    static var onRequest: (() -> Void)?

    override class func canInit(with request: URLRequest) -> Bool {
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override func startLoading() {
        HarnessgramStubProtocol.onRequest?()
        let response = HTTPURLResponse(url: self.request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        self.client?.urlProtocol(self, didLoad: Data(#"{"ok":true}"#.utf8))
        self.client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {
    }
}

