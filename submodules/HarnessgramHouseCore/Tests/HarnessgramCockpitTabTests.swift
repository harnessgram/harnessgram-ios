import XCTest
import CoreGraphics
import HarnessgramSettings
import HarnessgramCockpitKit
import HarnessgramHouseCore

/// Build 23: the native Cockpit tab's rules (what it shows, where the tab sits, where the floating button rests).
final class HarnessgramCockpitTabTests: XCTestCase {
    private func card(_ id: String, updated: Double?, done: Int = 1, percent: Int? = nil, finished: Bool = false, stale: Bool? = nil) -> HarnessgramCockpitSnapshot.Progress {
        return HarnessgramCockpitSnapshot.Progress(id: id, title: "משימה " + id, topic: "גשר", steps: ["קוד", "בדיקות", "בנייה"], done: done, percent: percent, topicURL: "", finished: finished, updated: updated, stale: stale)
    }

    private func snapshot(decisions: [HarnessgramCockpitSnapshot.Decision], progress: [HarnessgramCockpitSnapshot.Progress], waiting: Int? = nil) -> HarnessgramCockpitSnapshot {
        return HarnessgramCockpitSnapshot(updatedAt: Date(timeIntervalSince1970: 1_763_200_000), waitingCount: waiting ?? decisions.count, decisions: decisions, runningAgents: 0, agents: [], radio: nil, progress: progress)
    }

    func testUnpairedShowsThePairingStateWhateverTheSnapshotHolds() {
        let model = HarnessgramCockpitTabViewModel.make(snapshot: .sample, openDecisions: nil, isPaired: false, isPaused: false)
        XCTAssertEqual(model.state, .notPaired(paused: false))
        XCTAssertTrue(model.decisions.isEmpty)
        XCTAssertTrue(model.tasks.isEmpty)
        XCTAssertEqual(HarnessgramCockpitTabViewModel.make(snapshot: nil, openDecisions: nil, isPaired: false, isPaused: true).state, .notPaired(paused: true))
    }

    func testPairedBeforeTheFirstReadIsLoading() {
        XCTAssertEqual(HarnessgramCockpitTabViewModel.make(snapshot: nil, openDecisions: nil, isPaired: true, isPaused: false).state, .loading)
    }

    func testAFailedReadWithoutASnapshotSaysWhyInsteadOfLoading() {
        let now = Date(timeIntervalSince1970: 1_000)
        let model = HarnessgramCockpitTabViewModel.make(snapshot: nil, openDecisions: nil, isPaired: true, isPaused: false, failure: .panelUnreachable, loadingSince: now, now: now)
        XCTAssertEqual(model.state, .unavailable(.panelUnreachable))
        XCTAssertTrue(model.decisions.isEmpty)
        // Not paired: the pairing state, whatever the last read said.
        XCTAssertEqual(HarnessgramCockpitTabViewModel.make(snapshot: nil, openDecisions: nil, isPaired: false, isPaused: false, failure: .panelUnreachable, loadingSince: now, now: now).state, .notPaired(paused: false))
        // A stored snapshot wins over a later failed read: the last known lines stay on screen.
        XCTAssertEqual(HarnessgramCockpitTabViewModel.make(snapshot: .sample, openDecisions: nil, isPaired: true, isPaused: false, failure: .panelUnreachable, loadingSince: now, now: now).state, .content)
    }

    func testLoadingNeverSpinsPastTheTimeLimit() {
        let since = Date(timeIntervalSince1970: 1_000)
        let limit = HarnessgramCockpitTabViewModel.loadingTimeout
        XCTAssertEqual(limit, 15.0)
        let make: (Date?, TimeInterval) -> HarnessgramCockpitTabViewModel.State = { loadingSince, elapsed in
            HarnessgramCockpitTabViewModel.make(snapshot: nil, openDecisions: nil, isPaired: true, isPaused: false, failure: nil, loadingSince: loadingSince, now: since.addingTimeInterval(elapsed)).state
        }
        XCTAssertEqual(make(since, 0), .loading)
        XCTAssertEqual(make(since, limit - 0.5), .loading)
        XCTAssertEqual(make(since, limit), .unavailable(nil))
        XCTAssertEqual(make(since, 600), .unavailable(nil))
        // Off view there is no wait running, so no time limit either.
        XCTAssertEqual(make(nil, 600), .loading)
        XCTAssertEqual(HarnessgramCockpitTabViewModel.loadingDeadline(loadingSince: since), since.addingTimeInterval(limit))
        XCTAssertNil(HarnessgramCockpitTabViewModel.loadingDeadline(loadingSince: nil))
        // The short form keeps its old meaning (no failure, no wait).
        XCTAssertEqual(HarnessgramCockpitTabViewModel.make(snapshot: nil, openDecisions: nil, isPaired: true, isPaused: false).state, .loading)
    }

    func testNothingWaitingAndNothingFlyingIsEmpty() {
        let model = HarnessgramCockpitTabViewModel.make(snapshot: self.snapshot(decisions: [], progress: []), openDecisions: [], isPaired: true, isPaused: false)
        XCTAssertEqual(model.state, .empty)
        XCTAssertEqual(model.waitingCount, 0)
    }

    func testTheFullOpenListWinsOverTheWidgetFiveAndKeepsTheBridgeOrder() {
        let all = HarnessgramCockpitSnapshot.houseDemoOpenDecisions
        let model = HarnessgramCockpitTabViewModel.make(snapshot: HarnessgramCockpitSnapshot.houseDemo, openDecisions: all, isPaired: true, isPaused: false)
        XCTAssertEqual(model.state, .content)
        XCTAssertEqual(model.decisions.map { $0.id }, all.map { $0.id })
        XCTAssertEqual(model.waitingCount, all.count)
        // Without the full list, the snapshot's own lines and its count.
        let fallback = HarnessgramCockpitTabViewModel.make(snapshot: .sample, openDecisions: nil, isPaired: true, isPaused: false)
        XCTAssertEqual(fallback.decisions.map { $0.id }, HarnessgramCockpitSnapshot.sample.decisions.map { $0.id })
        XCTAssertEqual(fallback.waitingCount, 3)
    }

    func testTaskCardsAreNewestUpdatedFirstAndStaleCardsStayOut() {
        let progress = [
            self.card("a", updated: 100),
            self.card("b", updated: nil),
            self.card("c", updated: 300),
            self.card("d", updated: 200, stale: true),
            self.card("e", updated: nil),
        ]
        let model = HarnessgramCockpitTabViewModel.make(snapshot: self.snapshot(decisions: [], progress: progress), openDecisions: nil, isPaired: true, isPaused: false)
        XCTAssertEqual(model.state, .content)
        XCTAssertEqual(model.tasks.map { $0.id }, ["c", "a", "b", "e"])
    }

    func testTaskStepAndPercent() {
        let tasks = HarnessgramCockpitTabViewModel.orderedTasks([
            self.card("a", updated: 4, done: 1),
            self.card("b", updated: 3, done: 2, percent: 140),
            self.card("c", updated: 2, done: 3, finished: true),
            self.card("d", updated: 1, done: -2, percent: -5),
        ])
        XCTAssertEqual(tasks[0].step, "בדיקות")
        XCTAssertEqual(tasks[0].percent, 33)
        XCTAssertEqual(tasks[1].percent, 100)
        XCTAssertEqual(tasks[2].step, "בנייה")
        XCTAssertEqual(tasks[2].percent, 100)
        XCTAssertTrue(tasks[2].finished)
        XCTAssertEqual(tasks[3].step, "קוד")
        XCTAssertEqual(tasks[3].percent, 0)
        XCTAssertEqual(tasks[1].fraction, 1.0)
    }

    func testTranslatedTaskKeepsTheOriginalCurrentStep() {
        var card = self.card("a", updated: 1, done: 1)
        card.originalTitle = "Build"
        card.originalTopic = "Bridge"
        card.originalSteps = ["Code", "Tests", "Build"]
        let tasks = HarnessgramCockpitTabViewModel.orderedTasks([card])
        XCTAssertEqual(tasks.first?.originalTitle, "Build")
        XCTAssertEqual(tasks.first?.originalTopic, "Bridge")
        XCTAssertEqual(tasks.first?.originalStep, "Tests")
        XCTAssertEqual(tasks.first?.step, "בדיקות")
        XCTAssertEqual(tasks.first?.hasOriginalText, true)

        card.done = 99
        XCTAssertEqual(HarnessgramCockpitTabViewModel.orderedTasks([card]).first?.originalStep, "Build")
        card.originalSteps = []
        XCTAssertNil(HarnessgramCockpitTabViewModel.orderedTasks([card]).first?.originalStep)
        XCTAssertEqual(HarnessgramCockpitTabViewModel.orderedTasks([self.card("old", updated: nil)]).first?.hasOriginalText, false)
    }

    func testShortenedSourceTaskDoesNotOfferOriginalText() throws {
        let source = String(repeating: "English ", count: 240)
        let data = try JSONSerialization.data(withJSONObject: ["ok": true, "cards": [[
            "id": "p", "kind": "progress", "title": source, "topic": source, "steps": [source]
        ]]])
        let snapshot = try HarnessgramCockpitParser.snapshot(state: data, radioPlayer: nil, now: Date(timeIntervalSince1970: 1))
        var task = try XCTUnwrap(HarnessgramCockpitTabViewModel.orderedTasks(snapshot.progress).first)
        XCTAssertNotEqual(task.title, task.originalTitle)
        XCTAssertFalse(task.hasOriginalText)
        task.step = "שלב בעברית"
        XCTAssertTrue(task.hasOriginalText)
    }

    func testTheTabFollowsItsSwitchAndSitsRightAfterChats() {
        let suite = "HarnessgramCockpitTabTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = HarnessgramSettings(defaults: defaults)
        XCTAssertTrue(HarnessgramCockpitTabPlacement.isIncluded(settings: settings), "on by default")

        let tabs = ["calls", "chats", "settings"]
        let arrange: (Bool) -> [String] = { include in
            HarnessgramCockpitTabPlacement.arrange(tabs, cockpit: "cockpit", include: include, isChats: { $0 == "chats" }, isCockpit: { $0 == "cockpit" })
        }
        XCTAssertEqual(arrange(HarnessgramCockpitTabPlacement.isIncluded(settings: settings)), ["calls", "chats", "cockpit", "settings"])
        settings.cockpitTab = false
        XCTAssertFalse(HarnessgramCockpitTabPlacement.isIncluded(settings: settings))
        XCTAssertEqual(arrange(HarnessgramCockpitTabPlacement.isIncluded(settings: settings)), tabs)
        // Already present: one copy, in its place; switched off: removed.
        XCTAssertEqual(HarnessgramCockpitTabPlacement.arrange(["cockpit", "chats", "settings"], cockpit: "cockpit", include: true, isChats: { $0 == "chats" }, isCockpit: { $0 == "cockpit" }), ["chats", "cockpit", "settings"])
        XCTAssertEqual(HarnessgramCockpitTabPlacement.arrange(["chats", "cockpit", "settings"], cockpit: "cockpit", include: false, isChats: { $0 == "chats" }, isCockpit: { $0 == "cockpit" }), ["chats", "settings"])
        // No Chats tab: before the last one.
        XCTAssertEqual(HarnessgramCockpitTabPlacement.arrange(["a", "settings"], cockpit: "cockpit", include: true, isChats: { _ in false }, isCockpit: { $0 == "cockpit" }), ["a", "cockpit", "settings"])
    }

    func testTheFloatingButtonIsOffByDefaultAndRemembersItsPlace() {
        let suite = "HarnessgramCockpitTabTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = HarnessgramSettings(defaults: defaults)
        XCTAssertFalse(settings.cockpitFloatingButton)
        XCTAssertNil(settings.cockpitFloatingButtonPosition)
        settings.cockpitFloatingButtonPosition = (true, 1.7)
        XCTAssertEqual(settings.cockpitFloatingButtonPosition?.rightEdge, true)
        XCTAssertEqual(settings.cockpitFloatingButtonPosition?.y, 1.0)
        settings.cockpitFloatingButtonPosition = nil
        XCTAssertNil(settings.cockpitFloatingButtonPosition)
    }

    func testTheFloatingButtonStaysClearOfTheBarsAndTheKeyboardAndSnapsToAnEdge() {
        let d = HarnessgramCockpitFloatingButtonLayout.diameter, m = HarnessgramCockpitFloatingButtonLayout.margin
        let size = CGSize(width: 390.0, height: 844.0)
        // Status bar 47, tab bar 83.
        let area = HarnessgramCockpitFloatingButtonLayout.centerArea(bounds: size, top: 47.0, bottom: 83.0)
        XCTAssertEqual(area.minX, m + d / 2.0)
        XCTAssertEqual(area.maxX, size.width - m - d / 2.0)
        XCTAssertEqual(area.minY, 47.0 + m + d / 2.0)
        XCTAssertEqual(area.maxY, size.height - 83.0 - m - d / 2.0)

        // Dragged past the bottom into the tab bar: back above it, on the nearer (left) edge.
        let low = HarnessgramCockpitFloatingButtonLayout.snapped(CGPoint(x: 120.0, y: 900.0), area: area)
        XCTAssertEqual(low, CGPoint(x: area.minX, y: area.maxY))
        // Off the top, nearer the right edge.
        let high = HarnessgramCockpitFloatingButtonLayout.snapped(CGPoint(x: 300.0, y: -20.0), area: area)
        XCTAssertEqual(high, CGPoint(x: area.maxX, y: area.minY))
        // Within the area only x snaps.
        XCTAssertEqual(HarnessgramCockpitFloatingButtonLayout.snapped(CGPoint(x: 200.0, y: 400.0), area: area), CGPoint(x: area.maxX, y: 400.0))

        // The keyboard (336) takes over the bottom: the same stored place moves up with it.
        let keyboard = HarnessgramCockpitFloatingButtonLayout.centerArea(bounds: size, top: 47.0, bottom: 336.0)
        let stored = HarnessgramCockpitFloatingButtonLayout.position(of: low, area: area)
        XCTAssertFalse(stored.rightEdge)
        XCTAssertEqual(stored.y, 1.0)
        let lifted = HarnessgramCockpitFloatingButtonLayout.center(rightEdge: stored.rightEdge, y: stored.y, area: keyboard)
        XCTAssertEqual(lifted.y, size.height - 336.0 - m - d / 2.0)
        XCTAssertLessThanOrEqual(lifted.y + d / 2.0, size.height - 336.0)

        // A screen too small for any free area pins the button instead of inverting the range.
        let tiny = HarnessgramCockpitFloatingButtonLayout.centerArea(bounds: CGSize(width: 40.0, height: 60.0), top: 20.0, bottom: 40.0)
        XCTAssertGreaterThanOrEqual(tiny.width, 0.0)
        XCTAssertGreaterThanOrEqual(tiny.height, 0.0)
        XCTAssertEqual(HarnessgramCockpitFloatingButtonLayout.center(rightEdge: true, y: .nan, area: area).y, area.minY + area.height * CGFloat(HarnessgramCockpitFloatingButtonLayout.defaultY))
    }
}
