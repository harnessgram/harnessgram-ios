import XCTest
import HarnessgramSettings
@testable import HarnessgramCockpitKit

/// The native Cockpit's model (from `/api/state`), its polling rule and its decision answers (fake transport).
final class HarnessgramNativeCockpitTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_763_200_000)
    private let origin = "https://mac.private.example.test:10000"

    private func json(_ object: Any) -> Data {
        return try! JSONSerialization.data(withJSONObject: object)
    }

    private func decision(_ id: String, title: String = "Ship it?", url: String = "", stale: String = "", sensitive: Any? = nil, extra: [String: Any] = [:]) -> [String: Any] {
        var item: [String: Any] = ["id": id, "title": title, "detail": "Line one\nLine two", "yes": "Ship", "no": "Hold", "topic": "Harnessgram", "age": 120, "stale": stale, "old": stale == "old", "url": url]
        if let sensitive {
            item["sensitive"] = sensitive
        }
        for (key, value) in extra {
            item[key] = value
        }
        return item
    }

    private func state(decisions: [[String: Any]] = [], sessions: [[String: Any]] = [], quota: [[String: Any]] = [], deliveries: [[String: Any]] = [], waiting: Any? = 4) -> Data {
        var root: [String: Any] = ["ok": true, "now": 1_763_200_000, "decisions": decisions, "sessions": sessions, "quota": quota, "deliveries": deliveries, "cards": []]
        if let waiting {
            root["waiting_count"] = waiting
        }
        return self.json(root)
    }

    // MARK: The screen model

    /// Review P1: an id listed twice is ambiguous (text and Face ID mark could come from different entries): both drop.
    func testADuplicatedDecisionIdIsDroppedNotMerged() throws {
        let data = self.state(decisions: [
            self.decision("bbbbbbbbbbbbbbb1", title: "Routine old", stale: "old", sensitive: false),
            self.decision("bbbbbbbbbbbbbbb1", title: "Sensitive new"),
            self.decision("bbbbbbbbbbbbbbb2", sensitive: false),
        ])
        let screen = try HarnessgramCockpitScreen.parse(state: data, radio: nil, now: self.now)
        XCTAssertEqual(screen.decisions.map(\.id), ["bbbbbbbbbbbbbbb2"])
        XCTAssertNil(screen.decision(id: "bbbbbbbbbbbbbbb1"))
    }

    /// Review P2: a question with its own options (or another kind) is never answered with yes/no here.
    func testOptionsAndOtherKindsAreNotAnsweredHere() throws {
        let data = self.state(decisions: [
            self.decision("ccccccccccccccc1", extra: ["kind": "choice", "options": ["A", "B", "C"]]),
            self.decision("ccccccccccccccc2", extra: ["options": ["A", "B"]]),
            self.decision("ccccccccccccccc3", extra: ["kind": "ask"]),
            self.decision("ccccccccccccccc4", extra: ["kind": "yesno"]),
            self.decision("ccccccccccccccc5"),
        ])
        let screen = try HarnessgramCockpitScreen.parse(state: data, radio: nil, now: self.now)
        let answerable = Dictionary(uniqueKeysWithValues: screen.decisions.map { ($0.id, $0.answerableHere) })
        XCTAssertEqual(answerable["ccccccccccccccc1"], false)
        XCTAssertEqual(answerable["ccccccccccccccc2"], false)
        XCTAssertEqual(answerable["ccccccccccccccc3"], false)
        XCTAssertEqual(answerable["ccccccccccccccc4"], true)
        XCTAssertEqual(answerable["ccccccccccccccc5"], true)
    }

    func testAnswerGuardSendsOnceAndReleasesLocalCancellation() {
        var guardState = HarnessgramAnswerGuard()
        let key = HarnessgramAnswerGuard.key(account: 7, decisionId: "ddddddddddddddd1")
        XCTAssertTrue(guardState.begin(key, now: self.now, stillOpen: true, hasDelivery: false))
        XCTAssertFalse(guardState.begin(key, now: self.now, stillOpen: true, hasDelivery: false), "in flight: a second page cannot send")
        guardState.finish(key, result: .sent(key: nil, delivery: .delivered), now: self.now)
        XCTAssertFalse(guardState.begin(key, now: self.now.addingTimeInterval(500), stillOpen: true, hasDelivery: false), "done stays done")

        let other = HarnessgramAnswerGuard.key(account: 7, decisionId: "ddddddddddddddd2")
        XCTAssertTrue(guardState.begin(other, now: self.now, stillOpen: true, hasDelivery: false))
        guardState.finish(other, result: .cancelledLocally, now: self.now)
        XCTAssertFalse(guardState.isBlocked(other, now: self.now), "Nothing was sent")
        XCTAssertTrue(guardState.begin(other, now: self.now, stillOpen: true, hasDelivery: false))

        XCTAssertEqual(HarnessgramDecisionAnswer.Result.cancelledLocally.guardOutcome, .notSent)
        XCTAssertEqual(HarnessgramDecisionAnswer.Result.failed.guardOutcome, .uncertain)
        XCTAssertEqual(HarnessgramDecisionAnswer.Result.notConfirmed.guardOutcome, .notSent)
        XCTAssertEqual(HarnessgramDecisionAnswer.Result.alreadyClosed(choice: nil).guardOutcome, .done)
        XCTAssertNotEqual(HarnessgramAnswerGuard.key(account: 7, decisionId: "x"), HarnessgramAnswerGuard.key(account: 8, decisionId: "x"))
    }

    func testUncertainAndUnfinishedSendsSurviveLaunchAndExpire() throws {
        let suite = "HarnessgramNativeCockpitTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let key = HarnessgramAnswerGuard.key(account: 7, decisionId: "ddddddddddddddd1")
        let unfinished = HarnessgramAnswerGuard.key(account: 7, decisionId: "ddddddddddddddd2")
        var guardState = HarnessgramAnswerGuard(defaults: defaults, now: self.now)
        XCTAssertTrue(guardState.begin(key, now: self.now, stillOpen: true, hasDelivery: false))
        guardState.markSending(key, now: self.now)
        guardState.finish(key, result: .failed, now: self.now)
        XCTAssertTrue(guardState.begin(unfinished, now: self.now, stillOpen: true, hasDelivery: false))
        guardState.markSending(unfinished, now: self.now)
        guardState.saveUncertain(to: defaults)

        let reopenedDefaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let expiry = self.now.addingTimeInterval(86_400)
        let justBeforeExpiry = expiry.addingTimeInterval(-1)
        var reopened = HarnessgramAnswerGuard(defaults: reopenedDefaults, now: justBeforeExpiry)
        XCTAssertEqual(reopened.timedBlock(key, now: justBeforeExpiry), .uncertain(until: expiry))
        XCTAssertFalse(reopened.begin(key, now: justBeforeExpiry, stillOpen: true, hasDelivery: false))
        XCTAssertFalse(reopened.begin(unfinished, now: justBeforeExpiry, stillOpen: true, hasDelivery: false))
        XCTAssertNil(reopened.timedBlock(key, now: expiry))
        XCTAssertFalse(reopened.begin(key, now: expiry, stillOpen: true, hasDelivery: true))
        XCTAssertFalse(reopened.begin(key, now: expiry, stillOpen: false, hasDelivery: false))
        XCTAssertTrue(reopened.begin(key, now: expiry, stillOpen: true, hasDelivery: false))

        let reopenedAfterExpiry = HarnessgramAnswerGuard(defaults: reopenedDefaults, now: expiry)
        XCTAssertFalse(reopenedAfterExpiry.isBlocked(unfinished, now: expiry))
    }

    func testBusyBlocksOnlyThatDecisionUntilRetryAfter() {
        var guardState = HarnessgramAnswerGuard()
        let until = self.now.addingTimeInterval(45)
        XCTAssertTrue(guardState.begin("busy", now: self.now, stillOpen: true, hasDelivery: false))
        guardState.finish("busy", result: .busy(retryAfter: 45), now: self.now)
        XCTAssertEqual(guardState.timedBlock("busy", now: self.now), .busy(until: until))
        XCTAssertFalse(guardState.begin("busy", now: until.addingTimeInterval(-1), stillOpen: true, hasDelivery: false))
        XCTAssertTrue(guardState.begin("other", now: self.now, stillOpen: true, hasDelivery: false))
        XCTAssertNil(guardState.timedBlock("busy", now: until))
        XCTAssertTrue(guardState.begin("busy", now: until, stillOpen: true, hasDelivery: false))
    }

    func testAnswerOriginMustMatchTheShownBridge() {
        let shown = URL(string: "https://mac.private.example.test:10000")
        XCTAssertTrue(HarnessgramAnswerGuard.sameOrigin(shown: shown, minted: URL(string: "https://MAC.private.example.test:10000/x")))
        XCTAssertFalse(HarnessgramAnswerGuard.sameOrigin(shown: shown, minted: URL(string: "https://other.private.example.test:10000")))
        XCTAssertFalse(HarnessgramAnswerGuard.sameOrigin(shown: shown, minted: URL(string: "https://mac.private.example.test:10001")))
        XCTAssertFalse(HarnessgramAnswerGuard.sameOrigin(shown: shown, minted: URL(string: "http://mac.private.example.test:10000")))
        XCTAssertFalse(HarnessgramAnswerGuard.sameOrigin(shown: nil, minted: shown))
        XCTAssertFalse(HarnessgramAnswerGuard.sameOrigin(shown: shown, minted: nil))
    }

    func testOldDecisionsStayAnswerableWhileEndedAndReplacedOnesAreDropped() throws {
        let data = self.state(decisions: [
            self.decision("aaaaaaaaaaaaaaa1", stale: "old"),
            self.decision("aaaaaaaaaaaaaaa2"),
            self.decision("aaaaaaaaaaaaaaa3", stale: "ended"),
            self.decision("aaaaaaaaaaaaaaa4", stale: "replaced"),
        ])
        let screen = try HarnessgramCockpitScreen.parse(state: data, radio: nil, now: self.now)
        XCTAssertEqual(screen.decisions.map { $0.id }, ["aaaaaaaaaaaaaaa2", "aaaaaaaaaaaaaaa1"], "fresh first, old after, ended and replaced gone")
        XCTAssertEqual(screen.freshDecisions.map { $0.id }, ["aaaaaaaaaaaaaaa2"])
        XCTAssertEqual(screen.oldDecisions.map { $0.id }, ["aaaaaaaaaaaaaaa1"])
        XCTAssertEqual(screen.decisions.first?.base.detail, "Line one\nLine two", "the full detail, line breaks kept")
        // The whole question, not the widget's 140 characters, and the Hebrew copy first.
        let long = String(repeating: "word ", count: 60).trimmingCharacters(in: .whitespaces)
        let full = try HarnessgramCockpitScreen.parse(state: self.state(decisions: [self.decision("aaaaaaaaaaaaaaa5", title: long, extra: ["detail_he": "שורה א\nשורה ב"])]), radio: nil, now: self.now)
        XCTAssertEqual(full.decisions.first?.base.title, long)
        XCTAssertEqual(full.decisions.first?.base.detail, "שורה א\nשורה ב")
        // The widget list keeps leaving the old one out.
        XCTAssertEqual(try HarnessgramCockpitParser.openDecisions(state: data).map { $0.id }, ["aaaaaaaaaaaaaaa2"])
    }

    func testOnlyAnExplicitFalseIsRoutine() throws {
        let data = self.state(decisions: [
            self.decision("bbbbbbbbbbbbbbb1", sensitive: false),
            self.decision("bbbbbbbbbbbbbbb2", sensitive: true),
            self.decision("bbbbbbbbbbbbbbb3"),
            self.decision("bbbbbbbbbbbbbbb4", sensitive: 0),
            self.decision("bbbbbbbbbbbbbbb5", sensitive: "false"),
        ])
        let screen = try HarnessgramCockpitScreen.parse(state: data, radio: nil, now: self.now)
        XCTAssertEqual(screen.decisions.map { $0.requiresOwnerCheck }, [false, true, true, true, true])
    }

    func testAPermissionRequestIsShownWholeAndAnsweredOnlyInTheFullCockpit() throws {
        let data = self.state(decisions: [self.decision("ccccccccccccccc1", sensitive: false, extra: ["request": "Bash: rm -rf build\nin /repo", "decline_only": true])])
        let decision = try XCTUnwrap(try HarnessgramCockpitScreen.parse(state: data, radio: nil, now: self.now).decisions.first)
        XCTAssertEqual(decision.permissionRequest, "Bash: rm -rf build\nin /repo")
        XCTAssertTrue(decision.declineOnly)
        XCTAssertTrue(decision.requiresOwnerCheck, "a permission request always needs Face ID")
        XCTAssertFalse(decision.answerableHere)
    }

    func testSessionsCountOnceAndAnOpenDecisionMakesASessionWaiting() throws {
        let topic = "https://t.me/c/1234567890/42"
        let data = self.state(decisions: [self.decision("ddddddddddddddd1", url: topic)], sessions: [
            ["id": "s1", "state": "working", "url": topic],
            ["id": "s2", "state": "working", "url": "https://t.me/c/1234567890/43"],
            ["id": "s3", "state": "idle", "url": ""],
            ["id": "s4", "state": "idle", "url": "https://t.me/c/1234567890/44"],
            ["id": "s5", "state": "ended", "url": topic],
            ["id": "s6", "state": "bogus"],
        ])
        let screen = try HarnessgramCockpitScreen.parse(state: data, radio: nil, now: self.now)
        XCTAssertEqual(screen.sessions, .init(working: 1, waiting: 1, idle: 2))
        XCTAssertEqual(screen.waitingCount, 4)
    }

    func testQuotaAndDeliveriesAreReadAndBadValuesDropped() throws {
        let data = self.state(quota: [
            ["account": "main", "label": "Main", "weekly": 63.4, "weekly_resets": 1_763_400_000, "banked": 2],
            ["account": "spare", "label": "", "weekly": NSNull(), "weekly_resets": "", "banked": true],
            ["account": "", "label": "No account"],
        ], deliveries: [
            ["key": "k1", "id": "eeeeeeeeeeeeeee1", "kind": "decision", "state": "queued", "retrying": true],
            ["key": "k2", "id": "x", "state": "nonsense"],
            ["key": "", "state": "delivered"],
        ], waiting: true)
        let screen = try HarnessgramCockpitScreen.parse(state: data, radio: .init(enabled: true, on: false), now: self.now)
        XCTAssertEqual(screen.quota, [
            .init(account: "main", label: "Main", weekly: 63, resetsAt: Date(timeIntervalSince1970: 1_763_400_000), banked: 2),
            .init(account: "spare", label: "spare", weekly: nil, resetsAt: nil, banked: nil),
        ])
        XCTAssertEqual(screen.deliveries, [
            .init(key: "k1", id: "eeeeeeeeeeeeeee1", state: .queued, retrying: true),
            .init(key: "k2", id: "x", state: .unknown, retrying: false),
        ])
        XCTAssertNil(screen.waitingCount, "a bool is not a count")
        XCTAssertEqual(screen.radio, .init(enabled: true, on: false))
        XCTAssertEqual(screen.delivery(key: "k1")?.state, .queued)
    }

    func testRemovingAnsweredDecisions() throws {
        let data = self.state(decisions: [self.decision("fffffffffffffff1"), self.decision("fffffffffffffff2")])
        let screen = try HarnessgramCockpitScreen.parse(state: data, radio: nil, now: self.now)
        XCTAssertEqual(screen.removingDecisions(["fffffffffffffff1"]).decisions.map { $0.id }, ["fffffffffffffff2"])
        XCTAssertEqual(screen.removingDecisions([]), screen)
    }

    func testANotOKAnswerIsRefused() {
        XCTAssertThrowsError(try HarnessgramCockpitScreen.parse(state: self.json(["ok": false]), radio: nil, now: self.now))
        XCTAssertThrowsError(try HarnessgramCockpitScreen.parse(state: Data("nope".utf8), radio: nil, now: self.now))
    }

    // MARK: Polling

    func testThePollBacksOffAfterFailuresAndResetsAfterASuccess() {
        var schedule = HarnessgramCockpitPollSchedule()
        XCTAssertEqual(schedule.delay(now: self.now), 45.0)
        schedule.noteFailure(now: self.now, retryAfter: nil)
        XCTAssertEqual(schedule.delay(now: self.now), 90.0)
        schedule.noteFailure(now: self.now, retryAfter: nil)
        XCTAssertEqual(schedule.delay(now: self.now), 180.0)
        for _ in 0 ..< 10 {
            schedule.noteFailure(now: self.now, retryAfter: nil)
        }
        XCTAssertEqual(schedule.delay(now: self.now), HarnessgramCockpitPollSchedule.maxBackoff)
        XCTAssertTrue(schedule.mayRequest(now: self.now))
        schedule.noteSuccess()
        XCTAssertEqual(schedule.delay(now: self.now), 45.0)
        XCTAssertEqual(schedule.delay(now: self.now, base: 60.0), 60.0)
    }

    func testRetryAfterHoldsEveryReadUntilItPasses() {
        var schedule = HarnessgramCockpitPollSchedule()
        schedule.noteFailure(now: self.now, retryAfter: 900.0)
        XCTAssertFalse(schedule.mayRequest(now: self.now.addingTimeInterval(899.0)))
        XCTAssertTrue(schedule.mayRequest(now: self.now.addingTimeInterval(900.0)))
        XCTAssertEqual(schedule.delay(now: self.now), 900.0)
        // A huge wait is capped.
        var capped = HarnessgramCockpitPollSchedule()
        capped.noteFailure(now: self.now, retryAfter: 86_400.0)
        XCTAssertEqual(capped.delay(now: self.now), HarnessgramCockpitPollSchedule.maxRetryAfter)
    }

    func testRetryAfterIsReadFromTheHeaderOrTheBody() {
        XCTAssertEqual(HarnessgramCockpitPollSchedule.retryAfter(header: "120", body: nil, now: self.now), 120.0)
        let date = DateFormatter()
        date.locale = Locale(identifier: "en_US_POSIX")
        date.timeZone = TimeZone(identifier: "GMT")
        date.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        XCTAssertEqual(HarnessgramCockpitPollSchedule.retryAfter(header: date.string(from: self.now.addingTimeInterval(30.0)), body: nil, now: self.now), 30.0)
        XCTAssertEqual(HarnessgramCockpitPollSchedule.retryAfter(header: nil, body: self.json(["error": "rate", "retry": 60]), now: self.now), 60.0)
        XCTAssertNil(HarnessgramCockpitPollSchedule.retryAfter(header: "soon", body: self.json(["retry": true]), now: self.now))
        XCTAssertEqual(HarnessgramCockpitPollSchedule.retryAfter(header: "0", body: nil, now: self.now), 1.0, "never zero")
    }

    func testAReadTheBridgeRateLimitsSaysHowLongToWait() async {
        let transport = FakeTransport(responses: [HarnessgramCockpitHTTPResponse(status: 429, body: self.json(["error": "rate", "retry": 60]), retryAfter: 60.0)])
        let client = HarnessgramCockpitClient(transport: transport)
        do {
            _ = try await client.fetch(credential: self.credential(age: 10.0), now: self.now)
            XCTFail("a rate-limited read must throw")
        } catch let error as HarnessgramCockpitClient.FetchError {
            XCTAssertEqual(error, .rateLimited(60.0))
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    func testFetchedDecisionKeepsTheOriginThatServedIt() async throws {
        let transport = FakeTransport(responses: [
            .init(status: 200, body: self.state(decisions: [self.decision("0123456789abcdef")])),
            .init(status: 404, body: Data()),
        ])
        let client = HarnessgramCockpitClient(transport: transport)
        let fetched = try await client.fetch(credential: self.credential(age: 1), now: self.now)
        XCTAssertEqual(fetched.screen?.decisions.first?.bridgeOrigin, URL(string: self.origin))
    }

    // MARK: Answers

    private func credential(age: TimeInterval, origin: String? = nil) -> HarnessgramCockpitCredential {
        return HarnessgramCockpitCredential(initData: "query_id=1&user=%7B%7D&auth_date=1&hash=abc", origin: origin ?? self.origin, authDate: self.now.addingTimeInterval(-age), configuration: HarnessgramLocalConfig(bridgeHostSuffixes: [".private.example.test"]))
    }

    private func screenDecision(sensitive: Any? = nil, extra: [String: Any] = [:]) throws -> HarnessgramCockpitScreen.Decision {
        let data = self.state(decisions: [self.decision("0123456789abcdef", sensitive: sensitive, extra: extra)])
        return try XCTUnwrap(try HarnessgramCockpitScreen.parse(state: data, radio: nil, now: self.now, bridgeOrigin: URL(string: self.origin)).decisions.first)
    }

    private func run(_ decision: HarnessgramCockpitScreen.Decision, choice: HarnessgramCockpitLinks.Choice = .yes, note: String = "", confirmed: Bool = true, credential: HarnessgramCockpitCredential?, transport: FakeTransport, log: EventLog, stillAllowed: @MainActor () -> Bool = { true }) async -> HarnessgramDecisionAnswer.Result {
        let now = self.now
        return await HarnessgramDecisionAnswer.run(decision: decision, choice: choice, note: note, reason: "Confirm", confirm: { _ in
            log.add("faceid")
            return confirmed
        }, credential: {
            log.add("login")
            return credential
        }, stillAllowed: stillAllowed, transport: transport, now: { now })
    }

    func testFreshStoredLoginCannotAnswerForAnotherBridge() async throws {
        let shown = try self.screenDecision(sensitive: false)
        let other = self.credential(age: 1, origin: "https://other.private.example.test:10000")
        XCTAssertTrue(other.canAnswer(now: self.now))
        XCTAssertTrue(HarnessgramDecisionAnswer.matchesBridge(self.credential(age: 1), for: shown))
        XCTAssertFalse(HarnessgramDecisionAnswer.matchesBridge(other, for: shown))

        let transport = FakeTransport(responses: [])
        let result = await self.run(shown, credential: other, transport: transport, log: EventLog())
        XCTAssertEqual(result, .cancelledLocally)
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testLocalCancellationAfterFaceIDAndLoginNeverSends() async throws {
        let transport = FakeTransport(responses: [])
        let log = EventLog()
        let result = await self.run(try self.screenDecision(sensitive: true), credential: self.credential(age: 1), transport: transport, log: log, stillAllowed: {
            log.add("authorization")
            return false
        })
        XCTAssertEqual(result, .cancelledLocally)
        XCTAssertEqual(log.events, ["faceid", "login", "authorization"])
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testAuthorizationIsCheckedAgainAtTheSendPoint() async throws {
        let transport = FakeTransport(responses: [])
        let log = EventLog()
        let result = await self.run(try self.screenDecision(sensitive: false), credential: self.credential(age: 1), transport: transport, log: log, stillAllowed: {
            let firstCheck = log.events == ["login"]
            log.add("authorization")
            return firstCheck
        })
        XCTAssertEqual(result, .cancelledLocally)
        XCTAssertEqual(log.events, ["login", "authorization", "authorization"])
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testARoutineDecisionIsSentWithoutFaceIDAndShowsItsDelivery() async throws {
        let transport = FakeTransport(responses: [HarnessgramCockpitHTTPResponse(status: 200, body: self.json(["ok": true, "key": "k-17", "delivery": "queued"]))])
        let log = EventLog()
        let result = await self.run(try self.screenDecision(sensitive: false), note: "  after lunch ", credential: self.credential(age: 60.0), transport: transport, log: log)
        XCTAssertEqual(result, .sent(key: "k-17", delivery: .queued))
        XCTAssertEqual(log.events, ["login"], "no Face ID for a routine decision")
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url?.absoluteString, self.origin + "/api/decide")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: HarnessgramCockpitClient.initHeader), "query_id=1&user=%7B%7D&auth_date=1&hash=abc")
        let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: String])
        XCTAssertEqual(body, ["id": "0123456789abcdef", "choice": "yes", "note": "after lunch"])
    }

    func testASensitiveOrUnmarkedDecisionAsksForFaceIDBeforeTheLoginIsTaken() async throws {
        for sensitive: Any? in [true, nil] {
            let transport = FakeTransport(responses: [HarnessgramCockpitHTTPResponse(status: 200, body: self.json(["ok": true, "key": "k", "delivery": "delivered"]))])
            let log = EventLog()
            let result = await self.run(try self.screenDecision(sensitive: sensitive), choice: .no, credential: self.credential(age: 60.0), transport: transport, log: log)
            XCTAssertEqual(result, .sent(key: "k", delivery: .delivered))
            XCTAssertEqual(log.events, ["faceid", "login"], "Face ID first, then the login (its freshness is checked after Face ID)")
            let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: XCTUnwrap(transport.requests.first?.httpBody)) as? [String: String])
            XCTAssertEqual(body, ["id": "0123456789abcdef", "choice": "no"], "an empty note is left out")
        }
    }

    func testACancelledFaceIDSendsNothing() async throws {
        let transport = FakeTransport(responses: [])
        let log = EventLog()
        let result = await self.run(try self.screenDecision(sensitive: true), confirmed: false, credential: self.credential(age: 60.0), transport: transport, log: log)
        XCTAssertEqual(result, .notConfirmed)
        XCTAssertEqual(log.events, ["faceid"], "no login is taken")
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testALoginTooOldToAnswerSendsNothing() async throws {
        let transport = FakeTransport(responses: [])
        let result = await self.run(try self.screenDecision(sensitive: false), credential: self.credential(age: HarnessgramCockpitCredential.answerWindow + 1.0), transport: transport, log: EventLog())
        XCTAssertEqual(result, .loginExpired)
        XCTAssertTrue(transport.requests.isEmpty)
        let none = await self.run(try self.screenDecision(sensitive: false), credential: nil, transport: transport, log: EventLog())
        XCTAssertEqual(none, .loginExpired)
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testWhatThisScreenNeverSends() async throws {
        let transport = FakeTransport(responses: [])
        let log = EventLog()
        let permission = try self.screenDecision(sensitive: false, extra: ["request": "Bash: ls", "decline_only": true])
        let tooLong = String(repeating: "א", count: HarnessgramDecisionAnswer.noteLimit + 1)
        let r1 = await self.run(permission, choice: .no, credential: self.credential(age: 1.0), transport: transport, log: log)
        let r2 = await self.run(try self.screenDecision(sensitive: false), note: tooLong, credential: self.credential(age: 1.0), transport: transport, log: log)
        XCTAssertEqual(r1, .notAllowed)
        XCTAssertEqual(r2, .notAllowed)
        XCTAssertTrue(log.events.isEmpty, "refused before Face ID and the login")
        XCTAssertTrue(transport.requests.isEmpty)
        // A note of exactly the limit is fine.
        XCTAssertNotNil(HarnessgramDecisionAnswer.body(id: "0123456789abcdef", choice: .yes, note: String(repeating: "א", count: HarnessgramDecisionAnswer.noteLimit)))
        XCTAssertNil(HarnessgramDecisionAnswer.body(id: "not-an-id", choice: .yes, note: ""))
    }

    func testTheBridgesAnswersMapToResults() {
        func result(_ status: Int, _ body: [String: Any], retryAfter: TimeInterval? = nil) -> HarnessgramDecisionAnswer.Result {
            return HarnessgramDecisionAnswer.result(HarnessgramCockpitHTTPResponse(status: status, body: self.json(body), retryAfter: retryAfter))
        }
        XCTAssertEqual(result(200, ["ok": true, "key": NSNull(), "delivery": "delivered"]), .sent(key: nil, delivery: .delivered))
        XCTAssertEqual(result(200, ["ok": false]), .failed)
        XCTAssertEqual(result(409, ["error": "closed", "state": "answered", "choice": "no"]), .alreadyClosed(choice: .no))
        XCTAssertEqual(result(409, ["error": "closed", "state": "stale", "choice": ""]), .alreadyClosed(choice: nil))
        XCTAssertEqual(result(404, ["error": "not found"]), .alreadyClosed(choice: nil))
        XCTAssertEqual(result(409, ["error": "queue full"]), .busy(retryAfter: nil))
        XCTAssertEqual(result(429, ["error": "rate", "retry": 30], retryAfter: 30.0), .busy(retryAfter: 30.0))
        XCTAssertEqual(result(403, ["error": "forbidden"]), .loginExpired)
        XCTAssertEqual(result(500, ["error": "unavailable"]), .failed)
    }

    func testServiceUnavailableIsUncertainUnlessBridgeExplicitlyRejectedTheAnswer() {
        let ambiguous = HarnessgramDecisionAnswer.result(.init(status: 503, body: self.json(["error": "busy"]), retryAfter: 30))
        XCTAssertEqual(ambiguous, .failed)
        XCTAssertEqual(ambiguous.guardOutcome, .uncertain)
        let gateway = HarnessgramDecisionAnswer.result(.init(status: 503, body: Data("Unavailable".utf8)))
        XCTAssertEqual(gateway.guardOutcome, .uncertain)
        let rejected = HarnessgramDecisionAnswer.result(.init(status: 503, body: self.json(["ok": false, "error": "queue full"]), retryAfter: 30))
        XCTAssertEqual(rejected, .busy(retryAfter: 30))
        XCTAssertEqual(rejected.guardOutcome, .notSent)
    }

    func testANetworkFailureIsReportedAsFailed() async throws {
        let transport = FakeTransport(responses: [])
        let result = await self.run(try self.screenDecision(sensitive: false), credential: self.credential(age: 1.0), transport: transport, log: EventLog())
        XCTAssertEqual(result, .failed)
        XCTAssertEqual(transport.requests.count, 1, "sent once, never retried by itself")
    }
}

/// Answers from a script, in order; throws when the script ran out (no network).
private final class FakeTransport: HarnessgramCockpitTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var responses: [HarnessgramCockpitHTTPResponse]
    private var recorded: [URLRequest] = []

    init(responses: [HarnessgramCockpitHTTPResponse]) {
        self.responses = responses
    }

    var requests: [URLRequest] {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.recorded
    }

    func perform(_ request: URLRequest) async throws -> HarnessgramCockpitHTTPResponse {
        self.lock.lock()
        defer { self.lock.unlock() }
        self.recorded.append(request)
        guard !self.responses.isEmpty else {
            throw URLError(.notConnectedToInternet)
        }
        return self.responses.removeFirst()
    }
}

private final class EventLog: @unchecked Sendable {
    private let lock = NSLock()
    private var list: [String] = []

    func add(_ event: String) {
        self.lock.lock()
        self.list.append(event)
        self.lock.unlock()
    }

    var events: [String] {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.list
    }
}
