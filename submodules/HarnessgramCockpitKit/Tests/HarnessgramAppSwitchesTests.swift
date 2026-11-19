import XCTest
import HarnessgramCockpitKit

/// The bridge's switches for new looks ("appSwitches"): missing means on, explicit false brings back the old look;
/// parsed tolerantly and kept with the stored snapshot, so the widgets and the Live Activity read the same values.
final class HarnessgramAppSwitchesTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_763_300_000)

    private func parse(_ json: String) throws -> HarnessgramCockpitSnapshot {
        return try HarnessgramCockpitParser.snapshot(state: Data(json.utf8), radioPlayer: nil, now: self.now)
    }

    func testMissingObjectOrKeysMeanOn() throws {
        let none = try self.parse(#"{"ok":true}"#)
        XCTAssertNil(none.appSwitches)
        XCTAssertTrue(HarnessgramCockpitSnapshot.wideCockpitOn(none))
        XCTAssertTrue(HarnessgramCockpitSnapshot.summaryRowsOn(none))
        XCTAssertTrue(HarnessgramCockpitSnapshot.wideCockpitOn(nil))
        XCTAssertTrue(HarnessgramCockpitSnapshot.summaryRowsOn(nil))
        let empty = try self.parse(#"{"ok":true,"appSwitches":{}}"#)
        XCTAssertTrue(HarnessgramCockpitSnapshot.wideCockpitOn(empty))
        XCTAssertTrue(HarnessgramCockpitSnapshot.summaryRowsOn(empty))
    }

    func testExplicitValuesWin() throws {
        let off = try self.parse(#"{"ok":true,"appSwitches":{"wideCockpit":false,"summaryRows":false}}"#)
        XCTAssertFalse(HarnessgramCockpitSnapshot.wideCockpitOn(off))
        XCTAssertFalse(HarnessgramCockpitSnapshot.summaryRowsOn(off))
        let on = try self.parse(#"{"ok":true,"appSwitches":{"wideCockpit":true,"summaryRows":true}}"#)
        XCTAssertTrue(HarnessgramCockpitSnapshot.wideCockpitOn(on))
        XCTAssertTrue(HarnessgramCockpitSnapshot.summaryRowsOn(on))
        let mixed = try self.parse(#"{"ok":true,"app_switches":{"wide_cockpit":0,"summaryRows":"on"}}"#)
        XCTAssertFalse(HarnessgramCockpitSnapshot.wideCockpitOn(mixed))
        XCTAssertTrue(HarnessgramCockpitSnapshot.summaryRowsOn(mixed))
    }

    func testOddValuesCountAsMissing() throws {
        let odd = try self.parse(#"{"ok":true,"appSwitches":{"wideCockpit":"maybe","summaryRows":7}}"#)
        XCTAssertEqual(odd.appSwitches, HarnessgramCockpitSnapshot.AppSwitches(wideCockpit: nil, summaryRows: nil))
        XCTAssertTrue(HarnessgramCockpitSnapshot.wideCockpitOn(odd))
        XCTAssertTrue(HarnessgramCockpitSnapshot.summaryRowsOn(odd))
        let notObject = try self.parse(#"{"ok":true,"appSwitches":false}"#)
        XCTAssertNil(notObject.appSwitches)
        XCTAssertTrue(HarnessgramCockpitSnapshot.wideCockpitOn(notObject))
        XCTAssertEqual(HarnessgramCockpitSnapshot.AppSwitches.parse(["wideCockpit": "OFF", "summaryRows": 1]), HarnessgramCockpitSnapshot.AppSwitches(wideCockpit: false, summaryRows: true))
        XCTAssertEqual(HarnessgramCockpitSnapshot.AppSwitches.parse(["wideCockpit": 0.5]), HarnessgramCockpitSnapshot.AppSwitches())
    }

    /// The phone tower ("towerPhone"): missing means on, explicit false brings back today's list, the same tolerant
    /// values as the other switches, and it never moves the other switches.
    func testTowerPhoneSwitchOnOffAndMissing() throws {
        let none = try self.parse(#"{"ok":true}"#)
        XCTAssertTrue(HarnessgramCockpitSnapshot.towerPhoneOn(none))
        XCTAssertTrue(HarnessgramCockpitSnapshot.towerPhoneOn(nil))
        let missingKey = try self.parse(#"{"ok":true,"appSwitches":{"wideCockpit":false}}"#)
        XCTAssertNil(missingKey.appSwitches?.towerPhone)
        XCTAssertTrue(HarnessgramCockpitSnapshot.towerPhoneOn(missingKey))
        XCTAssertFalse(HarnessgramCockpitSnapshot.wideCockpitOn(missingKey))
        let off = try self.parse(#"{"ok":true,"appSwitches":{"towerPhone":false}}"#)
        XCTAssertEqual(off.appSwitches, HarnessgramCockpitSnapshot.AppSwitches(towerPhone: false))
        XCTAssertFalse(HarnessgramCockpitSnapshot.towerPhoneOn(off))
        XCTAssertTrue(HarnessgramCockpitSnapshot.wideCockpitOn(off))
        XCTAssertTrue(HarnessgramCockpitSnapshot.summaryRowsOn(off))
        let on = try self.parse(#"{"ok":true,"appSwitches":{"towerPhone":true}}"#)
        XCTAssertTrue(HarnessgramCockpitSnapshot.towerPhoneOn(on))
        let snake = try self.parse(#"{"ok":true,"app_switches":{"tower_phone":"off"}}"#)
        XCTAssertFalse(HarnessgramCockpitSnapshot.towerPhoneOn(snake))
        let odd = try self.parse(#"{"ok":true,"appSwitches":{"towerPhone":"maybe"}}"#)
        XCTAssertNil(odd.appSwitches?.towerPhone)
        XCTAssertTrue(HarnessgramCockpitSnapshot.towerPhoneOn(odd))
        XCTAssertEqual(HarnessgramCockpitSnapshot.AppSwitches.parse(["towerPhone": 0]), HarnessgramCockpitSnapshot.AppSwitches(towerPhone: false))
        // Stored with the snapshot (the tab reads the stored copy).
        var snapshot = HarnessgramCockpitSnapshot.sample
        snapshot.appSwitches = HarnessgramCockpitSnapshot.AppSwitches(towerPhone: false)
        let decoded = try JSONDecoder().decode(HarnessgramCockpitSnapshot.self, from: JSONEncoder().encode(snapshot))
        XCTAssertFalse(HarnessgramCockpitSnapshot.towerPhoneOn(decoded))
    }

    func testTheSwitchesAreStoredWithTheSnapshotAndOldStoresStillDecode() throws {
        var snapshot = HarnessgramCockpitSnapshot.sample
        snapshot.appSwitches = HarnessgramCockpitSnapshot.AppSwitches(wideCockpit: false, summaryRows: nil)
        let decoded = try JSONDecoder().decode(HarnessgramCockpitSnapshot.self, from: JSONEncoder().encode(snapshot))
        XCTAssertEqual(decoded.appSwitches, snapshot.appSwitches)
        XCTAssertFalse(HarnessgramCockpitSnapshot.wideCockpitOn(decoded))
        XCTAssertTrue(HarnessgramCockpitSnapshot.summaryRowsOn(decoded))
        // A snapshot stored before the field existed decodes with every look on.
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(HarnessgramCockpitSnapshot.sample)) as? [String: Any])
        object.removeValue(forKey: "appSwitches")
        let old = try JSONDecoder().decode(HarnessgramCockpitSnapshot.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(old.appSwitches)
        XCTAssertTrue(HarnessgramCockpitSnapshot.summaryRowsOn(old))
        // Answering a decision keeps the switches.
        XCTAssertEqual(snapshot.removingDecision(snapshot.decisions[0].id).appSwitches, snapshot.appSwitches)
    }

    func testTheSummaryRowsSwitchOffKeepsTheOldSummaryExactly() {
        let t = self.now.timeIntervalSince1970
        let cards = (0 ..< 5).map { HarnessgramCockpitSnapshot.Progress(id: "c\($0)", title: "משימה", topic: "גשר", steps: ["קוד"], done: 0, percent: 10, topicURL: "", finished: false, updated: t - Double($0) * 60) }
        let waiting = HarnessgramTaskActivityPlan.Waiting(count: 2, firstTitle: "לאשר?")
        let off = HarnessgramTaskActivityPlan.choose(cards, waiting: waiting, summaryRows: false, now: self.now)
        var old = HarnessgramTaskState(title: HarnessgramWidgetStrings.moreTasks(3), topic: "", steps: [], done: 0, percent: nil, finished: false)
        old.overflowCount = 3
        XCTAssertEqual(off.last?.state, old)
        let on = HarnessgramTaskActivityPlan.choose(cards, waiting: waiting, now: self.now)
        XCTAssertEqual(on.last?.state.steps.count, 3)
        // The shown cards are the same either way.
        XCTAssertEqual(off.dropLast(), on.dropLast())
    }
}
