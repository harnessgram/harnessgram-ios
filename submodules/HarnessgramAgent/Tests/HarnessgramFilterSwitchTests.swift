import XCTest
import HarnessgramSettings
@testable import HarnessgramAgent

final class HarnessgramFilterSwitchTests: XCTestCase {
    private func make(confirm: Bool, allowsPersonalOff: Bool = true, asked: @escaping () -> Void) -> (HarnessgramFilterSwitch, HarnessgramFilterSettings, () -> Void) {
        let suite = "HarnessgramFilterSwitchTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        let filter = HarnessgramFilterSettings(defaults: defaults, allowsPersonalOff: allowsPersonalOff)
        let confirmation = HarnessgramOwnerConfirmation(authenticator: { _, completion in
            asked()
            completion(confirm)
        })
        return (HarnessgramFilterSwitch(filter: filter, confirmation: confirmation), filter, { defaults.removePersistentDomain(forName: suite) })
    }

    func testTurningARuleOffNeedsTheOwnerAndOnDoesNot() {
        var asks = 0
        let (sw, filter, cleanup) = self.make(confirm: true, asked: { asks += 1 })
        defer { cleanup() }
        let off = self.expectation(description: "off")
        sw.set(.stories, on: false, reason: "test", completion: { outcome in
            XCTAssertEqual(outcome, .changed)
            off.fulfill()
        })
        self.wait(for: [off], timeout: 2)
        XCTAssertEqual(asks, 1)
        XCTAssertFalse(filter.isOn(.stories))
        sw.set(.stories, on: true, reason: "test", completion: { outcome in
            XCTAssertEqual(outcome, .changed)
        })
        XCTAssertEqual(asks, 1)
        XCTAssertTrue(filter.isOn(.stories))
    }

    func testACancelledFaceIDKeepsTheRuleOn() {
        let (sw, filter, cleanup) = self.make(confirm: false, asked: {})
        defer { cleanup() }
        let done = self.expectation(description: "done")
        sw.set(.approvedChats, on: false, reason: "test", completion: { outcome in
            XCTAssertEqual(outcome, .notConfirmed)
            done.fulfill()
        })
        self.wait(for: [done], timeout: 2)
        XCTAssertTrue(filter.isOn(.approvedChats))
    }

    /// Build 21: turning a rule off is refused at once, without asking for Face ID; turning one on still works.
    func testTurningARuleOffIsCommitteeOnlyWithoutAskingTheOwner() {
        var asks = 0
        let (sw, filter, cleanup) = self.make(confirm: true, allowsPersonalOff: false, asked: { asks += 1 })
        defer { cleanup() }
        for rule in HarnessgramFilterRule.allCases {
            var outcome: HarnessgramFilterSwitch.Outcome?
            sw.set(rule, on: false, reason: "test", completion: { outcome = $0 })
            // Synchronous: no prompt was shown and nothing is pending.
            XCTAssertEqual(outcome, .committeeOnly, rule.rawValue)
            XCTAssertTrue(filter.isOn(rule), rule.rawValue)
            var onOutcome: HarnessgramFilterSwitch.Outcome?
            sw.set(rule, on: true, reason: "test", completion: { onOutcome = $0 })
            XCTAssertEqual(onOutcome, .unchanged, rule.rawValue)
        }
        XCTAssertEqual(asks, 0)
    }

    func testOnlyTurningOffAsksTheOwner() {
        XCTAssertTrue(HarnessgramFilterSwitch.needsOwner(from: true, to: false))
        XCTAssertFalse(HarnessgramFilterSwitch.needsOwner(from: false, to: true))
        XCTAssertFalse(HarnessgramFilterSwitch.needsOwner(from: true, to: true))
    }
}
