import XCTest
import HarnessgramSettings
@testable import HarnessgramCockpitKit

/// Build 23: one waiting count for the Cockpit tab's badge, the floating button and the app icon.
final class HarnessgramCockpitWaitingTests: XCTestCase {
    private func snapshot(waiting: Int, lines: Int) -> HarnessgramCockpitSnapshot {
        let decisions = Array(HarnessgramCockpitSnapshot.houseDemoOpenDecisions.prefix(lines))
        return HarnessgramCockpitSnapshot(updatedAt: Date(), waitingCount: waiting, decisions: decisions, runningAgents: 0, agents: [], radio: nil, progress: [])
    }

    func testEachSourceCounts() {
        // The widget snapshot's count, which covers decisions beyond its own five lines.
        XCTAssertEqual(HarnessgramCockpitWaiting.count(snapshot: self.snapshot(waiting: 7, lines: 5), openDecisions: nil, isConnected: true), 7)
        // The full list of open decisions when the app has it (the waiting list is these, never counted twice).
        XCTAssertEqual(HarnessgramCockpitWaiting.count(snapshot: self.snapshot(waiting: 2, lines: 2), openDecisions: HarnessgramCockpitSnapshot.houseDemoOpenDecisions, isConnected: true), HarnessgramCockpitSnapshot.houseDemoOpenDecisions.count)
        // A snapshot whose count lags its own lines.
        XCTAssertEqual(HarnessgramCockpitWaiting.count(snapshot: self.snapshot(waiting: 0, lines: 3), openDecisions: nil, isConnected: true), 3)
        // The owner's open reminders add on top.
        XCTAssertEqual(HarnessgramCockpitWaiting.count(snapshot: self.snapshot(waiting: 2, lines: 2), openDecisions: nil, reminders: 3, isConnected: true), 5)
        XCTAssertEqual(HarnessgramCockpitWaiting.count(snapshot: nil, openDecisions: nil, reminders: -4, isConnected: true), 0)
    }

    func testNotConnectedOrNothingWaitingMeansNoBadge() {
        XCTAssertEqual(HarnessgramCockpitWaiting.count(snapshot: self.snapshot(waiting: 4, lines: 4), openDecisions: nil, isConnected: false), 0)
        XCTAssertEqual(HarnessgramCockpitWaiting.count(snapshot: nil, openDecisions: nil, isConnected: true), 0)
        XCTAssertNil(HarnessgramCockpitWaiting.badgeText(0))
        XCTAssertNil(HarnessgramCockpitWaiting.badgeText(-1))
        XCTAssertEqual(HarnessgramCockpitWaiting.badgeText(2), "2")
        XCTAssertEqual(HarnessgramCockpitWaiting.badgeText(140), "99+")
    }

    func testTheIconCountsTheCockpitOnlyWhileTheSwitchIsOn() {
        let suite = "HarnessgramCockpitWaitingTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = HarnessgramSettings(defaults: defaults)
        XCTAssertTrue(settings.cockpitAppBadge, "on by default")
        XCTAssertEqual(HarnessgramCockpitWaiting.appBadge(telegramUnread: 4, waiting: 3, include: settings.cockpitAppBadge), 7)
        settings.cockpitAppBadge = false
        XCTAssertEqual(HarnessgramCockpitWaiting.appBadge(telegramUnread: 4, waiting: 3, include: settings.cockpitAppBadge), 4)
        XCTAssertEqual(HarnessgramCockpitWaiting.appBadge(telegramUnread: 0, waiting: 0, include: true), 0)
    }

    func testViewStateCountRequiresAnActivePairedSessionAndUsesFullDecisionList() {
        let session = HarnessgramCockpitStore.Session(accountId: 7, epoch: "epoch")
        let connected = HarnessgramCockpitStore.ViewState(
            session: session,
            isPaused: false,
            hasLogin: true,
            snapshot: self.snapshot(waiting: 1, lines: 1),
            openDecisions: Array(HarnessgramCockpitSnapshot.houseDemoOpenDecisions.prefix(7))
        )
        XCTAssertEqual(HarnessgramCockpitWaiting.count(state: connected), 7)

        let snapshotFallback = HarnessgramCockpitStore.ViewState(
            session: session,
            isPaused: false,
            hasLogin: true,
            snapshot: self.snapshot(waiting: 3, lines: 2),
            openDecisions: nil
        )
        XCTAssertEqual(HarnessgramCockpitWaiting.count(state: snapshotFallback), 3)

        XCTAssertEqual(HarnessgramCockpitWaiting.count(state: HarnessgramCockpitStore.ViewState(
            session: session, isPaused: false, hasLogin: false,
            snapshot: self.snapshot(waiting: 4, lines: 4), openDecisions: nil
        )), 0)
        XCTAssertEqual(HarnessgramCockpitWaiting.count(state: HarnessgramCockpitStore.ViewState(
            session: nil, isPaused: false, hasLogin: true,
            snapshot: self.snapshot(waiting: 4, lines: 4), openDecisions: nil
        )), 0)
        XCTAssertEqual(HarnessgramCockpitWaiting.count(state: HarnessgramCockpitStore.ViewState(
            session: session, isPaused: true, hasLogin: true,
            snapshot: self.snapshot(waiting: 4, lines: 4), openDecisions: nil
        )), 0)
    }
}
