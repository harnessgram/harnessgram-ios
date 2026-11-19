import XCTest

final class HarnessgramCameraAudioWaitTests: XCTestCase {
    func testActivationStartsImmediatelyOnSuccess() {
        var wait = HarnessgramCameraAudioWait()
        let request = wait.begin(now: 10.0)
        XCTAssertEqual(wait.complete(generation: request, succeeded: true, now: 10.01), .ready)
        XCTAssertFalse(wait.isPending)
        // The cancellation timer cannot complete an already successful request again.
        XCTAssertNil(wait.complete(generation: request, succeeded: false, now: 13.0))
    }

    func testActivationFailureDoesNotPermitCaptureAndAllowsRetry() {
        var wait = HarnessgramCameraAudioWait()
        let failed = wait.begin(now: 10.0)
        XCTAssertEqual(wait.complete(generation: failed, succeeded: false, now: 10.1), .failed)
        let retry = wait.begin(now: 10.2)
        XCTAssertNil(wait.complete(generation: failed, succeeded: true, now: 10.3))
        XCTAssertEqual(wait.complete(generation: retry, succeeded: true, now: 10.4), .ready)
    }

    func testBlockedHolderTimesOutAndLateSuccessIsIgnored() {
        var wait = HarnessgramCameraAudioWait()
        let request = wait.begin(now: 10.0)
        XCTAssertEqual(wait.complete(generation: request, succeeded: false, now: 13.0), .timedOut)
        XCTAssertNil(wait.complete(generation: request, succeeded: true, now: 13.1))
    }

    func testSuccessDeliveredAfterDeadlineIsStillTimeout() {
        var wait = HarnessgramCameraAudioWait()
        let request = wait.begin(now: 10.0)
        // A stalled main queue may deliver success before the timer; the deadline still wins.
        XCTAssertEqual(wait.complete(generation: request, succeeded: true, now: 13.01), .timedOut)
    }

    func testReleaseOrDismissInvalidatesPendingActivation() {
        var wait = HarnessgramCameraAudioWait()
        let released = wait.begin(now: 10.0)
        wait.cancel()
        XCTAssertFalse(wait.isPending)
        let retry = wait.begin(now: 10.2)
        XCTAssertNil(wait.complete(generation: released, succeeded: true, now: 10.3))
        XCTAssertEqual(wait.complete(generation: retry, succeeded: true, now: 10.4), .ready)
    }
}
