import XCTest
import HarnessgramCockpitKit
#if canImport(ActivityKit)
import ActivityKit
#endif

/// The lock screen pack: progress-card step windows (never all done early), the decision's age, the task card's
/// headline (one direction per line), the altimeter and the tower summary the lock screen accessories show.
final class HarnessgramFlightDeckTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_763_200_000)

    private func json(_ object: Any) -> Data {
        return try! JSONSerialization.data(withJSONObject: object)
    }

    private func steps(_ count: Int) -> [String] {
        return (0 ..< count).map { "s\($0)" }
    }

    private func parseCard(_ card: [String: Any], root: [String: Any] = [:]) throws -> HarnessgramCockpitSnapshot.Progress {
        var body: [String: Any] = ["ok": true, "decisions": [], "sessions": [], "cards": [card]]
        body.merge(root) { _, new in new }
        let snapshot = try HarnessgramCockpitParser.snapshot(state: self.json(body), radioPlayer: nil, now: self.now)
        return try XCTUnwrap(snapshot.progress.first)
    }

    // MARK: step window

    func testShortCardsKeepEveryStep() {
        XCTAssertEqual(HarnessgramCockpitParser.stepWindow(count: 0, at: 0), 0 ..< 0)
        XCTAssertEqual(HarnessgramCockpitParser.stepWindow(count: 5, at: 3), 0 ..< 5)
        XCTAssertEqual(HarnessgramCockpitParser.stepWindow(count: 12, at: 12), 0 ..< 12)
    }

    func testLongCardsWindowEndsAtTheCurrentStep() {
        // The bridge's rule: start = max(0, min(at - 11, count - 12)).
        XCTAssertEqual(HarnessgramCockpitParser.stepWindow(count: 20, at: 0), 0 ..< 12)
        XCTAssertEqual(HarnessgramCockpitParser.stepWindow(count: 20, at: 11), 0 ..< 12)
        XCTAssertEqual(HarnessgramCockpitParser.stepWindow(count: 20, at: 15), 4 ..< 16)
        XCTAssertEqual(HarnessgramCockpitParser.stepWindow(count: 20, at: 20), 8 ..< 20)
        XCTAssertEqual(HarnessgramCockpitParser.stepWindow(count: 20, at: 99), 8 ..< 20)
        XCTAssertEqual(HarnessgramCockpitParser.stepWindow(count: 20, at: -3), 0 ..< 12)
    }

    func testALongCardNeverShowsAllDoneWhileWorkGoesOn() throws {
        // Before the window, step 14 of 20 showed 12 of 12 done ("נחת בשלום") with the work still going.
        for at in 0 ..< 20 {
            let card = try self.parseCard(["id": "c1", "kind": "progress", "title": "Long", "steps": self.steps(20), "at": at])
            XCTAssertEqual(card.steps.count, 12, "at \(at)")
            let state = HarnessgramTaskState(progress: card)
            XCTAssertEqual(state.currentStep, "s\(at)", "at \(at)")
            XCTAssertNotEqual(state.stepLine, HarnessgramWidgetStrings.allStepsDone, "at \(at)")
            XCTAssertEqual(card.originalSteps ?? [], card.steps, "at \(at)")
        }
        let landed = try self.parseCard(["id": "c1", "kind": "progress", "title": "Long", "steps": self.steps(20), "at": 20])
        XCTAssertEqual(landed.done, 12)
        XCTAssertEqual(landed.steps.last, "s19")
        XCTAssertNil(HarnessgramTaskState(progress: landed).currentStep)
    }

    func testAWindowedCardGetsTheTruePercent() throws {
        let card = try self.parseCard(["id": "c1", "kind": "progress", "title": "Long", "steps": self.steps(20), "at": 15])
        XCTAssertEqual(card.steps.first, "s4")
        XCTAssertEqual(card.done, 11)
        XCTAssertEqual(card.percent, 75)
        // The card's own percent wins.
        let own = try self.parseCard(["id": "c1", "kind": "progress", "title": "Long", "steps": self.steps(20), "at": 15, "percent": 40])
        XCTAssertEqual(own.percent, 40)
        // Half to even, like the bridge's Python round(): 1 of 40 is 2.5 %.
        let half = try self.parseCard(["id": "c1", "kind": "progress", "title": "Long", "steps": self.steps(40), "at": 1])
        XCTAssertEqual(half.percent, 2)
        // A short card keeps no percent of its own (the app shows done / steps).
        let short = try self.parseCard(["id": "c1", "kind": "progress", "title": "Short", "steps": self.steps(4), "at": 1])
        XCTAssertNil(short.percent)
    }

    // MARK: decision age

    func testDecisionAgeUsesThePanelClock() throws {
        let decision: [String: Any] = ["id": "00000000000000a1", "title": "Merge?", "yes": "כן", "no": "לא", "topic": "", "url": "", "age": 240, "sensitive": false]
        let body: [String: Any] = ["ok": true, "now": 1_763_199_000, "decisions": [decision], "sessions": [], "cards": []]
        let snapshot = try HarnessgramCockpitParser.snapshot(state: self.json(body), radioPlayer: nil, now: self.now)
        XCTAssertEqual(snapshot.decisions.first?.askedAt, Date(timeIntervalSince1970: 1_763_199_000 - 240))
        // Without the panel's "now", the device's clock.
        let noClock: [String: Any] = ["ok": true, "decisions": [decision], "sessions": [], "cards": []]
        let local = try HarnessgramCockpitParser.snapshot(state: self.json(noClock), radioPlayer: nil, now: self.now)
        XCTAssertEqual(local.decisions.first?.askedAt, self.now.addingTimeInterval(-240))
    }

    func testAMalformedAgeShowsNoAge() throws {
        for age: Any in ["2m", true, -5, 1.5, 400 * 24 * 3600] {
            let decision: [String: Any] = ["id": "00000000000000a1", "title": "Merge?", "age": age]
            let snapshot = try HarnessgramCockpitParser.snapshot(state: self.json(["ok": true, "decisions": [decision]]), radioPlayer: nil, now: self.now)
            XCTAssertNil(snapshot.decisions.first?.askedAt, "\(age)")
        }
    }

    func testAStoredDecisionWithoutAgeStillDecodes() throws {
        let stored = #"{"id":"00000000000000a1","title":"t","topic":"","yesLabel":"כן","noLabel":"לא","topicURL":"","sensitive":true}"#
        let decision = try JSONDecoder().decode(HarnessgramCockpitSnapshot.Decision.self, from: Data(stored.utf8))
        XCTAssertNil(decision.askedAt)
    }

    // MARK: headline

    func testHeadlineKeepsOneDirectionPerLine() {
        XCTAssertEqual(HarnessgramTaskHeadline.make(topic: "", title: "בדיקות"), HarnessgramTaskHeadline(eyebrow: nil, line: "בדיקות"))
        XCTAssertEqual(HarnessgramTaskHeadline.make(topic: "מנדין", title: "הסבב הבא של כלים לעוזר").line, "מנדין: הסבב הבא של כלים לעוזר")
        // A short English name joins inside an isolate.
        XCTAssertEqual(HarnessgramTaskHeadline.make(topic: "Harnessgram", title: "בניית גרסה 13").line, "\u{2068}Harnessgram\u{2069}: בניית גרסה 13")
        XCTAssertEqual(HarnessgramTaskHeadline.make(topic: "\u{2068}Wings\u{2069}", title: "בדיקות").line, "\u{2068}Wings\u{2069}: בדיקות")
        // A long English topic gets its own line.
        let long = HarnessgramTaskHeadline.make(topic: "Native lock screen widgets pack", title: "בניית גרסה")
        XCTAssertEqual(long, HarnessgramTaskHeadline(eyebrow: "Native lock screen widgets pack", line: "בניית גרסה"))
        // An English title under a Hebrew topic: own lines.
        XCTAssertEqual(HarnessgramTaskHeadline.make(topic: "מנדין", title: "Build 13").eyebrow, "מנדין")
        // English only: one line, nothing Hebrew on it.
        XCTAssertEqual(HarnessgramTaskHeadline.make(topic: "Wings", title: "Build 13").line, "Wings: Build 13")
        // Numbers mix with anything.
        XCTAssertEqual(HarnessgramTaskHeadline.make(topic: "13", title: "בנייה").line, "13: בנייה")
    }

    func testBadgeFollowsTheTask() {
        var state = HarnessgramTaskState(title: "t", topic: "", steps: ["a"], done: 0, percent: nil, finished: false)
        XCTAssertEqual(state.badge(isStale: false), HarnessgramWidgetStrings.activeTask)
        XCTAssertEqual(state.badge(isStale: true), HarnessgramWidgetStrings.taskNoSignal)
        state.finished = true
        XCTAssertEqual(state.badge(isStale: true), HarnessgramWidgetStrings.taskLanded)
    }

    func testWatchSizeStepCount() {
        let running = HarnessgramTaskState(title: "t", topic: "", steps: ["a", "b", "c", "d", "e"], done: 1, percent: nil, finished: false)
        XCTAssertEqual(running.stepShort, "שלב 2/5")
        let landed = HarnessgramTaskState(title: "t", topic: "", steps: ["a"], done: 1, percent: nil, finished: true)
        XCTAssertEqual(landed.stepShort, HarnessgramWidgetStrings.allStepsDone)
        XCTAssertNil(HarnessgramTaskState(title: "t", topic: "", steps: [], done: 0, percent: nil, finished: false).stepShort)
    }

    // MARK: altimeter

    func testAltimeterFollowsProgress() {
        XCTAssertEqual(HarnessgramAltimeter.altitude(fraction: 0), 0)
        XCTAssertEqual(HarnessgramAltimeter.altitude(fraction: 0.72), 12_240)
        XCTAssertEqual(HarnessgramAltimeter.altitude(fraction: 1), HarnessgramAltimeter.cruise)
        XCTAssertEqual(HarnessgramAltimeter.altitude(fraction: 7), HarnessgramAltimeter.cruise)
        XCTAssertEqual(HarnessgramAltimeter.altitude(fraction: -1), 0)
        XCTAssertEqual(HarnessgramAltimeter.altitude(fraction: .nan), 0)
        XCTAssertLessThan(HarnessgramAltimeter.altitude(fraction: 0.3), HarnessgramAltimeter.altitude(fraction: 0.31))
    }

    func testAltimeterTicks() {
        let ticks = HarnessgramAltimeter.ticks(around: 12_240)
        XCTAssertEqual(ticks.first?.value, 10_750)
        XCTAssertEqual(ticks.last?.value, 13_750)
        XCTAssertEqual(ticks.filter { $0.major }.map { $0.value }, [11_000, 12_000, 13_000])
        XCTAssertTrue(ticks.allSatisfy { abs($0.offset) <= 1.0 })
        // Never below the runway.
        XCTAssertEqual(HarnessgramAltimeter.ticks(around: 0).first?.value, 0)
        XCTAssertEqual(HarnessgramAltimeter.label(12_240), "12,240")
        XCTAssertEqual(HarnessgramAltimeter.label(500), "500")
        XCTAssertEqual(HarnessgramAltimeter.needleDegrees(fraction: 0), -135)
        XCTAssertEqual(HarnessgramAltimeter.needleDegrees(fraction: 0.5), 0)
        XCTAssertEqual(HarnessgramAltimeter.needleDegrees(fraction: 1), 135)
    }

    // MARK: tower summary

    func testTowerSummaryFromTheSnapshot() {
        XCTAssertNil(HarnessgramTowerSummary(snapshot: nil))
        let summary = HarnessgramTowerSummary(snapshot: .sample)
        XCTAssertEqual(summary?.running, 2)
        XCTAssertEqual(summary?.waiting, 3)
        XCTAssertEqual(summary?.nextTitle, HarnessgramCockpitSnapshot.sample.decisions.first?.title)
        XCTAssertEqual(summary?.moreWaiting, 2)
        XCTAssertEqual(summary?.inlineLine, "2 משימות באוויר · 3 מחכים לך")
        XCTAssertEqual(summary?.nextAge(now: HarnessgramCockpitSnapshot.sample.updatedAt.addingTimeInterval(120)), "לפני 4 דק׳")

        let empty = HarnessgramCockpitSnapshot(updatedAt: self.now, waitingCount: 0, decisions: [], runningAgents: 0, agents: [], radio: nil, progress: [])
        let quiet = HarnessgramTowerSummary(snapshot: empty)
        XCTAssertNil(quiet?.nextTitle)
        XCTAssertNil(quiet?.nextAge(now: self.now))
        XCTAssertEqual(quiet?.moreWaiting, 0)
        XCTAssertEqual(quiet?.inlineLine, "אין משימות באוויר · אין ממתינים")
        XCTAssertEqual(quiet?.blips, [])
    }

    func testRadarBlipsAreCappedAndStable() {
        let summary = HarnessgramTowerSummary(running: 9, waiting: 1, nextTitle: "x", nextSensitive: false, nextAskedAt: nil, moreWaiting: 0)
        XCTAssertEqual(summary.blips.filter { !$0.waiting }.count, HarnessgramTowerSummary.maxBlips)
        XCTAssertEqual(summary.blips.filter { $0.waiting }.count, 1)
        XCTAssertEqual(summary.blips, summary.blips)
        XCTAssertTrue(summary.blips.allSatisfy { (0 ... 1).contains($0.distance) })
        let sweep = HarnessgramTowerSummary.sweepBearing(at: self.now)
        XCTAssertTrue((0 ..< 360).contains(sweep))
        XCTAssertNotEqual(sweep, HarnessgramTowerSummary.sweepBearing(at: self.now.addingTimeInterval(15 * 60)))
    }

    func testFlightDeckStrings() {
        XCTAssertEqual(HarnessgramWidgetStrings.tasksInAir(1), "משימה אחת באוויר")
        XCTAssertEqual(HarnessgramWidgetStrings.waitingForYou(1), "1 מחכה לך")
        XCTAssertEqual(HarnessgramWidgetStrings.askedAgo(20), "עכשיו")
        XCTAssertEqual(HarnessgramWidgetStrings.askedAgo(3 * 3600), "לפני 3 שע׳")
        XCTAssertEqual(HarnessgramWidgetStrings.askedAgo(26 * 3600), "לפני יום")
        XCTAssertEqual(HarnessgramWidgetStrings.askedAgo(-50), "עכשיו")
        XCTAssertEqual(HarnessgramWidgetStrings.next("למזג?"), "הבא: למזג?")
        XCTAssertEqual(HarnessgramWidgetStrings.moreTasksInAir(4), "עוד 4 משימות באוויר")
        // The brand stands alone; no Hebrew string carries a bare English word.
        for text in [HarnessgramWidgetStrings.activeTask, HarnessgramWidgetStrings.taskLanded, HarnessgramWidgetStrings.taskNoSignal, HarnessgramWidgetStrings.openCockpit] {
            XCTAssertFalse(HarnessgramTaskHeadline.hasLatin(text), text)
        }
    }

    // MARK: Live Activity reuse

    #if canImport(ActivityKit)
    func testOnlyLiveActivitiesAreReused() throws {
        guard #available(iOS 16.2, *) else {
            throw XCTSkip("ActivityKit states need iOS 16.2")
        }
        XCTAssertTrue(HarnessgramTaskActivityPlan.isLive(.active))
        XCTAssertTrue(HarnessgramTaskActivityPlan.isLive(.stale))
        XCTAssertFalse(HarnessgramTaskActivityPlan.isLive(.ended))
        XCTAssertFalse(HarnessgramTaskActivityPlan.isLive(.dismissed))
    }
    #endif
}
