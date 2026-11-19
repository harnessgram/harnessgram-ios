import XCTest
@testable import HarnessgramSettingsUI
import HarnessgramSettings
import HarnessgramCockpitKit

/// The native Cockpit: its home states, its answer results, its copy table, its text fields and its two switches.
final class NativeCockpitUITests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_763_200_000)

    private func screen(decisions: Int = 2, quota: [HarnessgramCockpitScreen.Quota] = [], radio: HarnessgramCockpitSnapshot.Radio? = .init(enabled: true, on: true)) -> HarnessgramCockpitScreen {
        let items = (0 ..< decisions).map { index in
            HarnessgramCockpitScreen.Decision(base: HarnessgramCockpitSnapshot.Decision(id: String(format: "%016x", index + 1), title: "שאלה \(index)", topic: "נושא", yesLabel: "כן", noLabel: "לא", topicURL: "", sensitive: true), isOld: index > 0, routine: false, permissionRequest: nil, declineOnly: false)
        }
        return HarnessgramCockpitScreen(now: self.now, sessions: .init(working: 3, waiting: 1, idle: 2), waitingCount: 5, decisions: items, quota: quota, deliveries: [], radio: radio)
    }

    func testTheHomeStates() {
        XCTAssertEqual(NativeCockpitHome.make(screen: self.screen(), isConnected: true, isPaused: true, failure: nil, retryIn: nil, now: self.now), .disconnected(paused: true))
        XCTAssertEqual(NativeCockpitHome.make(screen: nil, isConnected: false, isPaused: false, failure: nil, retryIn: nil, now: self.now), .disconnected(paused: false))
        XCTAssertEqual(NativeCockpitHome.make(screen: nil, isConnected: true, isPaused: false, failure: nil, retryIn: nil, now: self.now), .loading)
        XCTAssertEqual(NativeCockpitHome.make(screen: nil, isConnected: true, isPaused: false, failure: .panelUnreachable, retryIn: 20.0, now: self.now), .unavailable(reason: HarnessgramPairFailure.panelUnreachable.text, retryIn: nil))
        XCTAssertEqual(NativeCockpitHome.make(screen: nil, isConnected: true, isPaused: false, failure: .panelBusy, retryIn: 20.0, now: self.now), .unavailable(reason: HarnessgramPairFailure.panelBusy.text, retryIn: 20.0))
    }

    func testTheHomeContent() {
        let quota = [HarnessgramCockpitScreen.Quota(account: "a", label: "ראשי", weekly: 95, resetsAt: self.now.addingTimeInterval(86_400.0), banked: 1), HarnessgramCockpitScreen.Quota(account: "b", label: "b", weekly: nil, resetsAt: nil, banked: 0)]
        guard case let .content(content) = NativeCockpitHome.make(screen: self.screen(quota: quota), isConnected: true, isPaused: false, failure: .panelUnreachable, retryIn: nil, now: self.now) else {
            return XCTFail("a screen shows its content, also after a later failed read")
        }
        XCTAssertEqual([content.working, content.waitingSessions, content.idle, content.decisions], [3, 1, 2, 2])
        XCTAssertEqual(content.waitingTotal, 5)
        XCTAssertEqual(content.radio, .on)
        XCTAssertEqual(content.quota.map { $0.fraction }, [0.95, nil])
        XCTAssertEqual(content.quota[1].used, "—")
        XCTAssertTrue(content.quota[0].used.contains("95"))
        XCTAssertFalse(content.quota[0].detail.isEmpty)
        XCTAssertEqual(content.quota[1].detail, "", "no reset and no banked resets: no detail line")
        guard case let .content(off) = NativeCockpitHome.make(screen: self.screen(radio: .init(enabled: false, on: false)), isConnected: true, isPaused: false, failure: nil, retryIn: nil, now: self.now) else {
            return XCTFail()
        }
        XCTAssertEqual(off.radio, .notSetUp)
    }

    func testEveryAnswerResultSaysWhatHappened() {
        let results: [HarnessgramDecisionAnswer.Result] = [.sent(key: "k", delivery: .queued), .sent(key: nil, delivery: .unknown), .alreadyClosed(choice: .no), .alreadyClosed(choice: nil), .notConfirmed, .loginExpired, .busy(retryAfter: 30.0), .busy(retryAfter: nil), .notAllowed, .failed]
        for result in results {
            let lines = NativeDecisionAnswerState.lines(result: result, choice: .yes, live: nil)
            XCTAssertFalse(lines.isEmpty, "\(result)")
            XCTAssertFalse(lines.contains(where: { $0.isEmpty }), "\(result)")
        }
        // The live receipt wins over the state the answer came back with.
        let live = HarnessgramCockpitScreen.Delivery(key: "k", id: "", state: .delivered, retrying: false)
        XCTAssertEqual(NativeDecisionAnswerState.lines(result: .sent(key: "k", delivery: .queued), choice: .yes, live: live)[1], NativeCockpitStrings.t(.resultDelivered))
        let retrying = HarnessgramCockpitScreen.Delivery(key: "k", id: "", state: .inFlight, retrying: true)
        XCTAssertEqual(NativeDecisionAnswerState.lines(result: .sent(key: "k", delivery: .queued), choice: .yes, live: retrying).last, NativeCockpitStrings.t(.resultRetrying))
        XCTAssertEqual(NativeDecisionAnswerState.lines(result: .alreadyClosed(choice: .no), choice: .yes, live: nil), [NativeCockpitStrings.t(.resultClosedChoice) + " " + NativeCockpitStrings.t(.answeredNo)])
        // Only an answer the bridge did not take may be tried again.
        XCTAssertTrue(NativeDecisionAnswerState.mayRetry(.notConfirmed))
        XCTAssertTrue(NativeDecisionAnswerState.mayRetry(.busy(retryAfter: nil)))
        XCTAssertFalse(NativeDecisionAnswerState.mayRetry(.sent(key: nil, delivery: .delivered)))
        XCTAssertFalse(NativeDecisionAnswerState.mayRetry(.alreadyClosed(choice: nil)))
    }

    func testTheCopyTableIsCompleteHebrewWithEnglish() {
        for key in NativeCockpitStrings.Key.allCases {
            let entry = NativeCockpitStrings.table[key]
            XCTAssertNotNil(entry, key.rawValue)
            XCTAssertFalse(entry?.he.isEmpty ?? true, key.rawValue)
            XCTAssertFalse(entry?.en.isEmpty ?? true, key.rawValue)
            // Latin letters only inside a bidi isolate (a short name such as Siri, the owner's rule); never loose.
            let outsideIsolates = (entry?.he ?? "").replacingOccurrences(of: "\u{2068}[^\u{2069}]*\u{2069}", with: "", options: .regularExpression)
            XCTAssertNil(outsideIsolates.range(of: "[A-Za-z]", options: .regularExpression), "\(key.rawValue): Hebrew copy has no loose Latin letters")
        }
    }

    func testAnEmptyFieldTakesThePageDirection() {
        XCTAssertEqual(NativeCockpitTextDirection.of(""), .rightToLeft)
        XCTAssertEqual(NativeCockpitTextDirection.of("   12 "), .rightToLeft)
        XCTAssertEqual(NativeCockpitTextDirection.of("אחרי הצהריים"), .rightToLeft)
        XCTAssertEqual(NativeCockpitTextDirection.of("Ship after lunch"), .leftToRight)
        XCTAssertEqual(NativeCockpitTextDirection.of("1. שלח"), .rightToLeft)
    }

    func testBothNativeSwitchesAreListedAndOffByDefault() {
        XCTAssertTrue(HarnessgramAddition.allCases.contains(.nativeCockpit))
        XCTAssertTrue(HarnessgramAddition.allCases.contains(.nativeDecisions))
        for addition in [HarnessgramAddition.nativeCockpit, .nativeDecisions] {
            XCTAssertFalse(addition.explanation.isEmpty)
            XCTAssertFalse(addition.title.isEmpty)
        }
        let suite = "NativeCockpitUITests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = HarnessgramSettings(defaults: defaults)
        // Build 34: the native Cockpit is on by default; answering is not.
        XCTAssertEqual(HarnessgramAdditionsState.current(settings: settings, filter: .shared, widgetsConnected: false).row(.nativeCockpit), .toggle(true))
        XCTAssertEqual(HarnessgramAdditionsState.current(settings: settings, filter: .shared, widgetsConnected: false).row(.nativeDecisions), .toggle(false))
        settings.setHouseFeature(.nativeCockpit, false)
        XCTAssertEqual(HarnessgramAdditionsState.current(settings: settings, filter: .shared, widgetsConnected: false).row(.nativeCockpit), .toggle(false))
        XCTAssertEqual(HarnessgramAdditionsState.current(settings: settings, filter: .shared, widgetsConnected: false).row(.nativeDecisions), .toggle(false))
    }
}
