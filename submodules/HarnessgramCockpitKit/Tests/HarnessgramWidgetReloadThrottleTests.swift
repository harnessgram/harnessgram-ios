import Foundation
import XCTest
@testable import HarnessgramCockpitKit

final class HarnessgramWidgetReloadThrottleTests: XCTestCase {
    private func defaults() -> UserDefaults {
        let suite = "HarnessgramWidgetReloadThrottleTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    func testOneReloadPerKindPerFiveMinutes() {
        let defaults = self.defaults()
        var clock = Date(timeIntervalSince1970: 1_800_000_000)
        let throttle = HarnessgramWidgetReloadThrottle(defaults: defaults, now: { clock })
        XCTAssertEqual(HarnessgramWidgetReloadThrottle.minimumInterval, 300)
        XCTAssertEqual(throttle.claimBridgeKinds(), ["HarnessgramToday", "HarnessgramWaiting"])
        XCTAssertEqual(throttle.claimBridgeKinds(), [], "a second notification right away reloads nothing")
        clock = clock.addingTimeInterval(299)
        XCTAssertEqual(throttle.claimBridgeKinds(), [], "still inside the five minutes")
        clock = clock.addingTimeInterval(1)
        XCTAssertEqual(throttle.claimBridgeKinds(), ["HarnessgramToday", "HarnessgramWaiting"])
    }

    func testKindsAreIndependentAndSharedAcrossInstances() {
        let defaults = self.defaults()
        let clock = Date(timeIntervalSince1970: 1_800_000_000)
        let first = HarnessgramWidgetReloadThrottle(defaults: defaults, now: { clock })
        XCTAssertTrue(first.claim(kind: "HarnessgramToday"))
        // Another extension process reads the same app-group defaults.
        let second = HarnessgramWidgetReloadThrottle(defaults: defaults, now: { clock.addingTimeInterval(10) })
        XCTAssertFalse(second.claim(kind: "HarnessgramToday"))
        XCTAssertTrue(second.claim(kind: "HarnessgramWaiting"))
    }

    func testAFutureTimestampDoesNotBlock() {
        let defaults = self.defaults()
        let clock = Date(timeIntervalSince1970: 1_800_000_000)
        let ahead = HarnessgramWidgetReloadThrottle(defaults: defaults, now: { clock.addingTimeInterval(3600) })
        XCTAssertTrue(ahead.claim(kind: "HarnessgramToday"))
        let back = HarnessgramWidgetReloadThrottle(defaults: defaults, now: { clock })
        XCTAssertTrue(back.claim(kind: "HarnessgramToday"), "a clock moved back never blocks reloads")
        XCTAssertFalse(back.claim(kind: "HarnessgramToday"))
    }
}
