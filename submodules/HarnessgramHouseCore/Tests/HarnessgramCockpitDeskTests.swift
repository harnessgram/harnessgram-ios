import XCTest
import HarnessgramCockpitKit
import HarnessgramHouseCore

/// The Cockpit tab's wide layout ("מגדל פיקוח"): when the tower list and the desk show, how many desk columns fit,
/// the selection across list changes and arrow keys, and every decision on screen exactly once.
final class HarnessgramCockpitDeskTests: XCTestCase {
    private func card(_ id: String, topicURL: String, steps: [String] = ["קוד", "בדיקות", "בנייה", "העלאה"], done: Int = 1, finished: Bool = false, updated: Double? = nil) -> HarnessgramCockpitSnapshot.Progress {
        return HarnessgramCockpitSnapshot.Progress(id: id, title: "משימה " + id, topic: "גשר", steps: steps, done: done, percent: nil, topicURL: topicURL, finished: finished, updated: updated)
    }

    private func decision(_ id: String, topicURL: String) -> HarnessgramCockpitSnapshot.Decision {
        return HarnessgramCockpitSnapshot.Decision(id: id, title: "לאשר?", topic: "גשר", yesLabel: "כן", noLabel: "לא", topicURL: topicURL, sensitive: false)
    }

    private func tasks(_ cards: [HarnessgramCockpitSnapshot.Progress]) -> [HarnessgramCockpitTabViewModel.Task] {
        return HarnessgramCockpitTabViewModel.orderedTasks(cards)
    }

    private func one(_ card: HarnessgramCockpitSnapshot.Progress) -> HarnessgramCockpitTabViewModel.Task {
        return HarnessgramCockpitTabViewModel.orderedTasks([card])[0]
    }

    // MARK: Layout decision

    func testTheTowerListNeedsTheRegularWidthClassAndContent() {
        XCTAssertEqual(HarnessgramCockpitDesk.listStyle(isRegularWidth: true, state: .content), .tower)
        // The phone (compact) keeps its list whatever it shows.
        XCTAssertEqual(HarnessgramCockpitDesk.listStyle(isRegularWidth: false, state: .content), .phone)
        // States without content keep the phone pages on any width.
        for state: HarnessgramCockpitTabViewModel.State in [.notPaired(paused: false), .notPaired(paused: true), .loading, .unavailable(nil), .unavailable(.panelUnreachable), .empty] {
            XCTAssertEqual(HarnessgramCockpitDesk.listStyle(isRegularWidth: true, state: state), .phone, "\(state)")
            XCTAssertEqual(HarnessgramCockpitDesk.listStyle(isRegularWidth: false, state: state), .phone, "\(state)")
        }
    }

    func testTheWideCockpitSwitchOffKeepsThePhoneListEverywhere() {
        XCTAssertEqual(HarnessgramCockpitDesk.listStyle(isRegularWidth: true, state: .content, wideCockpit: false), .phone)
        XCTAssertEqual(HarnessgramCockpitDesk.listStyle(isRegularWidth: true, state: .content, wideCockpit: true), .tower)
        // From the snapshot: missing means on, explicit false means off.
        let missing = HarnessgramCockpitTabViewModel.make(snapshot: .houseDemo, openDecisions: nil, isPaired: true, isPaused: false)
        XCTAssertTrue(missing.wideCockpit)
        var off = HarnessgramCockpitSnapshot.houseDemo
        off.appSwitches = HarnessgramCockpitSnapshot.AppSwitches(wideCockpit: false)
        let offModel = HarnessgramCockpitTabViewModel.make(snapshot: off, openDecisions: nil, isPaired: true, isPaused: false)
        XCTAssertFalse(offModel.wideCockpit)
        XCTAssertEqual(HarnessgramCockpitDesk.listStyle(isRegularWidth: true, state: offModel.state, wideCockpit: offModel.wideCockpit), .phone)
        var on = HarnessgramCockpitSnapshot.houseDemo
        on.appSwitches = HarnessgramCockpitSnapshot.AppSwitches(wideCockpit: true, summaryRows: false)
        XCTAssertTrue(HarnessgramCockpitTabViewModel.make(snapshot: on, openDecisions: nil, isPaired: true, isPaused: false).wideCockpit)
    }

    func testThePhoneTowerSwitchDecidesTheCompactLookOnly() {
        let states: [HarnessgramCockpitTabViewModel.State] = [.content, .empty, .loading, .notPaired(paused: false), .notPaired(paused: true), .unavailable(nil), .unavailable(.panelUnreachable)]
        for state in states {
            // On: the phone tower on compact width, in every state.
            XCTAssertEqual(HarnessgramCockpitDesk.listStyle(isRegularWidth: false, state: state, towerPhone: true), .towerPhone, "\(state)")
            XCTAssertEqual(HarnessgramCockpitDesk.listStyle(isRegularWidth: false, state: state, wideCockpit: false, towerPhone: true), .towerPhone, "\(state)")
            // Off: today's phone list exactly.
            XCTAssertEqual(HarnessgramCockpitDesk.listStyle(isRegularWidth: false, state: state, towerPhone: false), .phone, "\(state)")
            // The regular width keeps its own rule whatever the phone switch says.
            for towerPhone in [true, false] {
                let expected: HarnessgramCockpitDesk.ListStyle = state == .content ? .tower : .phone
                XCTAssertEqual(HarnessgramCockpitDesk.listStyle(isRegularWidth: true, state: state, towerPhone: towerPhone), expected, "\(state)")
                XCTAssertEqual(HarnessgramCockpitDesk.listStyle(isRegularWidth: true, state: state, wideCockpit: false, towerPhone: towerPhone), .phone, "\(state)")
            }
        }
        // From the snapshot: missing means on, explicit false means off; the other switches stay apart.
        let missing = HarnessgramCockpitTabViewModel.make(snapshot: .houseDemo, openDecisions: nil, isPaired: true, isPaused: false)
        XCTAssertTrue(missing.towerPhone)
        var off = HarnessgramCockpitSnapshot.houseDemo
        off.appSwitches = HarnessgramCockpitSnapshot.AppSwitches(towerPhone: false)
        let offModel = HarnessgramCockpitTabViewModel.make(snapshot: off, openDecisions: nil, isPaired: true, isPaused: false)
        XCTAssertFalse(offModel.towerPhone)
        XCTAssertTrue(offModel.wideCockpit)
        XCTAssertEqual(HarnessgramCockpitDesk.listStyle(isRegularWidth: false, state: offModel.state, wideCockpit: offModel.wideCockpit, towerPhone: offModel.towerPhone), .phone)
        var on = HarnessgramCockpitSnapshot.houseDemo
        on.appSwitches = HarnessgramCockpitSnapshot.AppSwitches(wideCockpit: false, towerPhone: true)
        let onModel = HarnessgramCockpitTabViewModel.make(snapshot: on, openDecisions: nil, isPaired: true, isPaused: false)
        XCTAssertTrue(onModel.towerPhone)
        XCTAssertEqual(HarnessgramCockpitDesk.listStyle(isRegularWidth: false, state: onModel.state, wideCockpit: onModel.wideCockpit, towerPhone: onModel.towerPhone), .towerPhone)
        // Not paired: no snapshot, so the look stays on.
        XCTAssertTrue(HarnessgramCockpitTabViewModel.make(snapshot: nil, openDecisions: nil, isPaired: false, isPaused: false).towerPhone)
    }

    /// Review of ebc6527e: the "towerPhone" switch a snapshot carried also reaches the pages without a snapshot
    /// (pairing, loading, an error) and a cold launch, through the app group's defaults.
    func testTheLastTowerPhoneSwitchIsRememberedForPagesWithoutASnapshot() {
        let suite = "HarnessgramCockpitDeskTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let memory = HarnessgramCockpitLookMemory(defaults: defaults)
        XCTAssertNil(memory.towerPhone)
        memory.remember(towerPhone: false)
        XCTAssertEqual(HarnessgramCockpitLookMemory(defaults: defaults).towerPhone, false)
        let failure = HarnessgramPairFailure.allCases.first
        let now = Date()
        let pages = [
            HarnessgramCockpitTabViewModel.make(snapshot: nil, openDecisions: nil, isPaired: false, isPaused: false, failure: nil, loadingSince: nil, now: now, rememberedTowerPhone: memory.towerPhone),
            HarnessgramCockpitTabViewModel.make(snapshot: nil, openDecisions: nil, isPaired: true, isPaused: false, failure: nil, loadingSince: now, now: now, rememberedTowerPhone: memory.towerPhone),
            HarnessgramCockpitTabViewModel.make(snapshot: nil, openDecisions: nil, isPaired: true, isPaused: false, failure: failure, loadingSince: now, now: now, rememberedTowerPhone: memory.towerPhone),
        ]
        for page in pages {
            XCTAssertFalse(page.towerPhone, "\(page.state)")
            XCTAssertEqual(HarnessgramCockpitDesk.listStyle(isRegularWidth: false, state: page.state, towerPhone: page.towerPhone), .phone)
        }
        // A snapshot always wins over the remembered value.
        XCTAssertTrue(HarnessgramCockpitTabViewModel.make(snapshot: .houseDemo, openDecisions: nil, isPaired: true, isPaused: false, failure: nil, loadingSince: nil, now: now, rememberedTowerPhone: false).towerPhone)
        memory.remember(towerPhone: true)
        XCTAssertTrue(HarnessgramCockpitTabViewModel.make(snapshot: nil, openDecisions: nil, isPaired: false, isPaused: false, failure: nil, loadingSince: nil, now: now, rememberedTowerPhone: memory.towerPhone).towerPhone)
    }

    /// Review of ebc6527e: the first look follows the window (Telegram's 690 x 650 rule), so an iPad starts with the
    /// tower list and its navigation bar instead of one frame of the phone tower.
    func testTheWindowSizeSeedsTheWidthClassBeforeTheFirstLayout() {
        for size in [CGSize(width: 1024, height: 768), CGSize(width: 768, height: 1024), CGSize(width: 1366, height: 1024)] {
            XCTAssertTrue(HarnessgramCockpitDesk.isRegularWidth(windowSize: size), "\(size)")
            XCTAssertEqual(HarnessgramCockpitDesk.listStyle(isRegularWidth: HarnessgramCockpitDesk.isRegularWidth(windowSize: size), state: .content, towerPhone: true), .tower)
        }
        for size in [CGSize(width: 390, height: 844), CGSize(width: 932, height: 430), CGSize(width: 320, height: 1024)] {
            XCTAssertFalse(HarnessgramCockpitDesk.isRegularWidth(windowSize: size), "\(size)")
        }
    }

    /// Review of ebc6527e: the phone tower keeps every section of the old phone list, in the same order, in every state.
    func testThePhoneTowerContainsEverySectionOfThePhoneListInOrder() {
        let states: [HarnessgramCockpitTabViewModel.State] = [.notPaired(paused: false), .notPaired(paused: true), .loading, .unavailable(nil), .unavailable(HarnessgramPairFailure.allCases.first), .empty, .content]
        for state in states {
            let list = HarnessgramCockpitDesk.pageSections(state: state, tower: false)
            let tower = HarnessgramCockpitDesk.pageSections(state: state, tower: true)
            XCTAssertEqual(tower.filter { list.contains($0) }, list, "\(state)")
            XCTAssertEqual(Set(tower).subtracting(list), state == .content ? [.instruments, .agents] : [], "\(state)")
            XCTAssertEqual(list.last, .fullCockpit)
        }
        XCTAssertEqual(HarnessgramCockpitDesk.pageSections(state: .content, tower: false), [.decisions, .tasks, .radio, .waitingList, .fullCockpit])
        XCTAssertEqual(HarnessgramCockpitDesk.pageSections(state: .notPaired(paused: false), tower: true), [.pairing, .radio, .fullCockpit])
    }

    func testThePhoneTowerShowsEveryTaskOnceWithTheFirstFlightInTheAirOnTop() {
        let list = self.tasks([self.card("landed", topicURL: "x", finished: true, updated: 90), self.card("a", topicURL: "y", updated: 30), self.card("b", topicURL: "z", updated: 20)])
        XCTAssertEqual(HarnessgramCockpitDesk.leadTask(list)?.id, "a")
        XCTAssertEqual(HarnessgramCockpitDesk.stripTasks(list).map { $0.id }, ["landed", "b"])
        // Every task on screen exactly once.
        let shown = [HarnessgramCockpitDesk.leadTask(list)?.id].compactMap { $0 } + HarnessgramCockpitDesk.stripTasks(list).map { $0.id }
        XCTAssertEqual(Set(shown), Set(list.map { $0.id }))
        XCTAssertEqual(shown.count, list.count)
        // All landed: no lead flight, every task a strip.
        let landed = self.tasks([self.card("p", topicURL: "x", finished: true), self.card("q", topicURL: "y", finished: true)])
        XCTAssertNil(HarnessgramCockpitDesk.leadTask(landed))
        XCTAssertEqual(HarnessgramCockpitDesk.stripTasks(landed).count, 2)
        XCTAssertNil(HarnessgramCockpitDesk.leadTask([]))
        XCTAssertTrue(HarnessgramCockpitDesk.stripTasks([]).isEmpty)
    }

    func testTheDeskAddsTheRadarColumnOnlyWhenItFits() {
        XCTAssertEqual(HarnessgramCockpitDesk.railMinWidth, 720.0)
        // iPad 13" landscape detail (1366 - 455) and 11" landscape (1194 - 398): two columns.
        XCTAssertEqual(HarnessgramCockpitDesk.deskColumns(width: 911), 2)
        XCTAssertEqual(HarnessgramCockpitDesk.deskColumns(width: 796), 2)
        XCTAssertEqual(HarnessgramCockpitDesk.deskColumns(width: 720), 2)
        // iPad portrait detail (834 - 320), 13" portrait (1024 - 341), the unfolded phone's half, Split View: one.
        XCTAssertEqual(HarnessgramCockpitDesk.deskColumns(width: 719.5), 1)
        XCTAssertEqual(HarnessgramCockpitDesk.deskColumns(width: 683), 1)
        XCTAssertEqual(HarnessgramCockpitDesk.deskColumns(width: 514), 1)
        XCTAssertEqual(HarnessgramCockpitDesk.deskColumns(width: 0), 1)
        XCTAssertEqual(HarnessgramCockpitDesk.deskColumns(width: .nan), 1)
        XCTAssertEqual(HarnessgramCockpitDesk.deskColumns(width: .infinity), 1)
    }

    // MARK: Selection

    func testTheFirstTaskIsSelectedByDefaultAndASelectionSurvivesListChanges() {
        let list = self.tasks([self.card("a", topicURL: "x", updated: 30), self.card("b", topicURL: "y", updated: 20), self.card("c", topicURL: "z", updated: 10)])
        XCTAssertEqual(list.map { $0.id }, ["a", "b", "c"])
        XCTAssertEqual(HarnessgramCockpitDesk.resolvedSelection(nil, tasks: list), "a")
        XCTAssertEqual(HarnessgramCockpitDesk.resolvedSelection("b", tasks: list), "b")
        // A refresh reorders the list: the same task stays selected.
        let reordered = self.tasks([self.card("a", topicURL: "x", updated: 30), self.card("b", topicURL: "y", updated: 50), self.card("c", topicURL: "z", updated: 10)])
        XCTAssertEqual(reordered.first?.id, "b")
        XCTAssertEqual(HarnessgramCockpitDesk.resolvedSelection("c", tasks: reordered), "c")
        // The selected task left the list: the first one.
        XCTAssertEqual(HarnessgramCockpitDesk.resolvedSelection("gone", tasks: list), "a")
        XCTAssertNil(HarnessgramCockpitDesk.resolvedSelection("a", tasks: []))
        XCTAssertNil(HarnessgramCockpitDesk.resolvedSelection(nil, tasks: []))
    }

    func testTheSelectionIsTheSameBeforeAndAfterARotation() {
        // A rotation or a window resize rebuilds the view, never the list: resolving again changes nothing, whatever
        // the width class does in between.
        let list = self.tasks([self.card("a", topicURL: "x", updated: 30), self.card("b", topicURL: "y", updated: 20)])
        var selected = HarnessgramCockpitDesk.resolvedSelection(nil, tasks: list)
        selected = HarnessgramCockpitDesk.movedSelection(selected, by: 1, tasks: list)
        XCTAssertEqual(selected, "b")
        for _ in 0 ..< 3 {
            _ = HarnessgramCockpitDesk.listStyle(isRegularWidth: false, state: .content)
            selected = HarnessgramCockpitDesk.resolvedSelection(selected, tasks: list)
            _ = HarnessgramCockpitDesk.listStyle(isRegularWidth: true, state: .content)
            selected = HarnessgramCockpitDesk.resolvedSelection(selected, tasks: list)
        }
        XCTAssertEqual(selected, "b")
    }

    func testArrowKeysMoveTheSelectionAndStopAtTheEnds() {
        let list = self.tasks([self.card("a", topicURL: "x", updated: 30), self.card("b", topicURL: "y", updated: 20), self.card("c", topicURL: "z", updated: 10)])
        XCTAssertEqual(HarnessgramCockpitDesk.movedSelection("a", by: 1, tasks: list), "b")
        XCTAssertEqual(HarnessgramCockpitDesk.movedSelection("b", by: 1, tasks: list), "c")
        XCTAssertEqual(HarnessgramCockpitDesk.movedSelection("c", by: 1, tasks: list), "c")
        XCTAssertEqual(HarnessgramCockpitDesk.movedSelection("b", by: -1, tasks: list), "a")
        XCTAssertEqual(HarnessgramCockpitDesk.movedSelection("a", by: -1, tasks: list), "a")
        XCTAssertEqual(HarnessgramCockpitDesk.movedSelection(nil, by: 1, tasks: list), "a")
        XCTAssertEqual(HarnessgramCockpitDesk.movedSelection("gone", by: -1, tasks: list), "a")
        XCTAssertNil(HarnessgramCockpitDesk.movedSelection("a", by: 1, tasks: []))
    }

    // MARK: Decisions

    func testEveryDecisionShowsExactlyOnceBesideItsTaskOrInTheList() {
        let list = self.tasks([self.card("a", topicURL: "https://t.me/c/1/42", updated: 30), self.card("b", topicURL: "", updated: 20)])
        let decisions = [
            self.decision("d1", topicURL: "https://T.me/c/1/42/"),
            self.decision("d2", topicURL: "https://t.me/c/1/43"),
            self.decision("d3", topicURL: ""),
            self.decision("d4", topicURL: "https://t.me/c/1/42"),
        ]
        XCTAssertEqual(HarnessgramCockpitDesk.decisions(for: list[0], in: decisions).map { $0.id }, ["d1", "d4"])
        // A task without a topic link holds none (an empty link never matches an empty link).
        XCTAssertTrue(HarnessgramCockpitDesk.decisions(for: list[1], in: decisions).isEmpty)
        XCTAssertEqual(HarnessgramCockpitDesk.unassignedDecisions(decisions, tasks: list).map { $0.id }, ["d2", "d3"])
        let shown = list.flatMap { HarnessgramCockpitDesk.decisions(for: $0, in: decisions) } + HarnessgramCockpitDesk.unassignedDecisions(decisions, tasks: list)
        XCTAssertEqual(shown.map { $0.id }.sorted(), decisions.map { $0.id }.sorted())
        XCTAssertEqual(HarnessgramCockpitDesk.waitingByTask(tasks: list, decisions: decisions), ["a": 2])
        // No tasks: every decision is in the list.
        XCTAssertEqual(HarnessgramCockpitDesk.unassignedDecisions(decisions, tasks: []).count, decisions.count)
    }

    func testTopicKeys() {
        XCTAssertNil(HarnessgramCockpitDesk.topicKey(""))
        XCTAssertNil(HarnessgramCockpitDesk.topicKey("  / "))
        XCTAssertEqual(HarnessgramCockpitDesk.topicKey(" https://t.me/c/1/2/ "), "https://t.me/c/1/2")
    }

    // MARK: The plan

    func testStepRowsAndPosition() {
        let task = self.one(self.card("a", topicURL: "x", done: 2))
        XCTAssertEqual(task.steps, ["קוד", "בדיקות", "בנייה", "העלאה"])
        XCTAssertEqual(task.done, 2)
        XCTAssertEqual(HarnessgramCockpitDesk.stepRows(task).map { $0.state }, [.done, .done, .current, .ahead])
        XCTAssertEqual(HarnessgramCockpitDesk.stepRows(task).map { $0.title }, task.steps)
        XCTAssertEqual(HarnessgramCockpitDesk.stepPosition(task)?.current, 3)
        XCTAssertEqual(HarnessgramCockpitDesk.stepPosition(task)?.total, 4)

        let landed = self.one(self.card("b", topicURL: "x", done: 4, finished: true))
        XCTAssertEqual(HarnessgramCockpitDesk.stepRows(landed).map { $0.state }, [.done, .done, .done, .done])
        XCTAssertEqual(HarnessgramCockpitDesk.stepPosition(landed)?.current, 4)

        // A done count past the end is clamped; no steps, no position.
        let over = self.one(self.card("c", topicURL: "x", done: 9))
        XCTAssertEqual(HarnessgramCockpitDesk.stepRows(over).map { $0.state }, [.done, .done, .done, .done])
        XCTAssertEqual(HarnessgramCockpitDesk.stepPosition(over)?.current, 4)
        let bare = self.one(self.card("d", topicURL: "x", steps: [], done: 0))
        XCTAssertTrue(HarnessgramCockpitDesk.stepRows(bare).isEmpty)
        XCTAssertNil(HarnessgramCockpitDesk.stepPosition(bare))
    }

    func testTheTabCarriesTheTowerCountsAndAgents() {
        let snapshot = HarnessgramCockpitSnapshot.houseDemo
        let model = HarnessgramCockpitTabViewModel.make(snapshot: snapshot, openDecisions: HarnessgramCockpitSnapshot.houseDemoOpenDecisions, isPaired: true, isPaused: false)
        XCTAssertEqual(model.tower?.running, snapshot.runningAgents)
        XCTAssertEqual(model.tower?.waiting, model.waitingCount)
        XCTAssertEqual(model.agents, snapshot.agents)
        XCTAssertNil(HarnessgramCockpitTabViewModel.make(snapshot: nil, openDecisions: nil, isPaired: true, isPaused: false).tower)
    }
}
