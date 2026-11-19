import XCTest
import HarnessgramCockpitKit

/// The House groundwork in the Cockpit kit (plan step 0): the room a topic link names, the optional fields the
/// bridge will fill later, the uncapped list of open decisions and its app-only file.
final class HarnessgramCockpitHouseTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_763_200_000)

    private func state(decisions: [[String: Any]] = [], sessions: [[String: Any]] = [], cards: [[String: Any]] = []) -> Data {
        return try! JSONSerialization.data(withJSONObject: ["ok": true, "decisions": decisions, "sessions": sessions, "cards": cards])
    }

    private func decision(_ id: String, url: String = "https://t.me/c/900000002/77", extra: [String: Any] = [:]) -> [String: Any] {
        var item: [String: Any] = ["id": id, "title": "Merge?", "yes": "כן", "no": "לא", "topic": "Example project", "url": url, "stale": ""]
        for (key, value) in extra {
            item[key] = value
        }
        return item
    }

    func testTheRoomIsTheChannelOfTheTopicLink() {
        XCTAssertEqual(HarnessgramCockpitLinks.channelId(fromTopicURL: "https://t.me/c/900000002/77"), 900000002)
        XCTAssertNil(HarnessgramCockpitLinks.channelId(fromTopicURL: "https://evil.example/c/1/2"))
        XCTAssertNil(HarnessgramCockpitLinks.channelId(fromTopicURL: "http://t.me/c/1/2"))
        XCTAssertNil(HarnessgramCockpitLinks.channelId(fromTopicURL: "https://t.me/c/1/2/3"))
        XCTAssertNil(HarnessgramCockpitLinks.channelId(fromTopicURL: "https://t.me/c/0/2"))
        XCTAssertNil(HarnessgramCockpitLinks.channelId(fromTopicURL: "https://t.me/c/abc/2"))
        XCTAssertNil(HarnessgramCockpitLinks.channelId(fromTopicURL: ""))
    }

    func testItemsCarryTheirRoom() throws {
        let snapshot = try HarnessgramCockpitParser.snapshot(state: self.state(
            decisions: [self.decision("00000000000000a1")],
            sessions: [["id": "aaaaaaaa", "name": "Harnessgram", "state": "working", "now": "Building", "url": "https://t.me/c/42/7"]],
            cards: [["id": "p1", "kind": "progress", "title": "Build", "steps": ["a", "b"], "at": 1, "topic_url": "https://t.me/c/99/5"]]
        ), radioPlayer: nil, now: self.now)
        XCTAssertEqual(snapshot.decisions.first?.roomChannelId, 900000002)
        XCTAssertEqual(snapshot.agents.first?.roomChannelId, 42)
        XCTAssertEqual(snapshot.progress.first?.roomChannelId, 99)
    }

    func testKindAndOptionsAreOptionalAndCleaned() throws {
        let plain = try HarnessgramCockpitParser.snapshot(state: self.state(decisions: [self.decision("00000000000000a1")]), radioPlayer: nil, now: self.now)
        XCTAssertNil(plain.decisions.first?.kind)
        XCTAssertNil(plain.decisions.first?.options)
        let choice = try HarnessgramCockpitParser.snapshot(state: self.state(decisions: [self.decision("00000000000000a2", extra: ["kind": "choice", "options": ["א", "  ", "ב\u{202E}", 7]])]), radioPlayer: nil, now: self.now)
        XCTAssertEqual(choice.decisions.first?.kind, "choice")
        XCTAssertEqual(choice.decisions.first?.options, ["א", "ב"])
    }

    func testAnOlderSnapshotFileWithoutTheNewFieldsStillDecodes() throws {
        let old = """
        {"updatedAt":1763200000,"waitingCount":1,"decisions":[{"id":"00000000000000a1","title":"t","topic":"x","yesLabel":"כן","noLabel":"לא","topicURL":"","sensitive":true}],"runningAgents":1,"agents":[{"id":"a","name":"n","step":"","topicURL":""}],"progress":[{"id":"p","title":"t","topic":"x","steps":["a"],"done":0,"topicURL":"","finished":false}]}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let snapshot = try decoder.decode(HarnessgramCockpitSnapshot.self, from: Data(old.utf8))
        XCTAssertNil(snapshot.decisions[0].roomChannelId)
        XCTAssertNil(snapshot.decisions[0].kind)
        XCTAssertNil(snapshot.agents[0].roomChannelId)
        XCTAssertNil(snapshot.progress[0].roomChannelId)
    }

    func testTheOpenListIsNotCappedButTheWidgetSnapshotIs() throws {
        let many = (0 ..< 9).map { self.decision(String(format: "%016x", $0 + 1)) }
        let data = self.state(decisions: many)
        XCTAssertEqual(try HarnessgramCockpitParser.openDecisions(state: data).count, 9)
        let snapshot = try HarnessgramCockpitParser.snapshot(state: data, radioPlayer: nil, now: self.now)
        XCTAssertEqual(snapshot.decisions.count, HarnessgramCockpitSnapshot.maxDecisions)
        XCTAssertEqual(snapshot.waitingCount, 9)
        XCTAssertThrowsError(try HarnessgramCockpitParser.openDecisions(state: Data("nope".utf8)))
    }

    func testTheOpenListIsAppOnlyPerAccountAndHonoursAnswers() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = HarnessgramCockpitStore(directory: directory)
        XCTAssertNil(store.loadOpenDecisions())
        store.setActiveAccount(11)
        let open = try HarnessgramCockpitParser.openDecisions(state: self.state(decisions: (0 ..< 7).map { self.decision(String(format: "%016x", $0 + 1)) }))
        XCTAssertTrue(store.saveOpenDecisions(open))
        XCTAssertEqual(store.loadOpenDecisions()?.count, 7)
        // The widget snapshot file is a different file and keeps its own cap.
        store.saveSnapshot(.sample)
        XCTAssertEqual(store.loadSnapshot()?.decisions.count, 3)
        XCTAssertEqual(store.loadOpenDecisions()?.count, 7)
        store.markAnswered("0000000000000001")
        XCTAssertEqual(store.loadOpenDecisions()?.count, 6)
        // A list fetched before the answer landed must not bring it back.
        store.saveOpenDecisions(open)
        XCTAssertFalse(store.loadOpenDecisions()?.contains(where: { $0.id == "0000000000000001" }) ?? true)
        // A new account starts empty.
        store.setActiveAccount(22)
        XCTAssertNil(store.loadOpenDecisions())
        // A result of an older session is refused.
        let session = store.session
        store.setActiveAccount(33)
        XCTAssertFalse(store.saveOpenDecisions(open, forSession: session))
    }

    func testTheHouseDemoIsMadeUpAndConsistent() {
        let demo = HarnessgramCockpitSnapshot.houseDemo
        let all = HarnessgramCockpitSnapshot.houseDemoOpenDecisions
        XCTAssertGreaterThan(all.count, HarnessgramCockpitSnapshot.maxDecisions)
        XCTAssertEqual(demo.decisions.count, HarnessgramCockpitSnapshot.maxDecisions)
        XCTAssertEqual(demo.waitingCount, all.count)
        XCTAssertEqual(Set(all.map(\.id)).count, all.count)
        for decision in all {
            XCTAssertTrue(HarnessgramCockpitLinks.isDecisionId(decision.id))
            XCTAssertEqual(HarnessgramCockpitLinks.channelId(fromTopicURL: decision.topicURL), decision.roomChannelId)
        }
        XCTAssertTrue(all.contains(where: { $0.kind == "choice" && ($0.options?.count ?? 0) >= 2 }))
    }
}
