import XCTest
@testable import HarnessgramSettingsUI
import HarnessgramSettings

final class HarnessgramRadioPlaybackStateTests: XCTestCase {
    func testPlayAndSessionActivationDoNotMeanPlaying() {
        var playback = HarnessgramRadioPlaybackState()
        playback.start()
        XCTAssertEqual(playback.state, .connecting)
        playback.observe(.playing, at: 0.0)
        XCTAssertEqual(playback.state, .connecting, "no active audio session")
        playback.sessionActivated(at: 1.0)
        XCTAssertEqual(playback.state, .connecting)
        playback.observe(.waiting, at: 2.0)
        XCTAssertEqual(playback.state, .connecting)
        playback.observe(.playing, at: 3.0)
        XCTAssertEqual(playback.state, .playing)
        playback.observe(.waiting, at: 4.0)
        XCTAssertEqual(playback.state, .connecting)
        playback.observe(.paused, at: 5.0)
        XCTAssertEqual(playback.state, .paused)
        playback.observe(.playing, at: 6.0)
        XCTAssertEqual(playback.state, .paused, "a late event must not undo a pause")
    }

    func testActivationFailureCannotPublishPlayingAndCanBeRetried() {
        var playback = HarnessgramRadioPlaybackState()
        playback.start()
        XCTAssertEqual(playback.retry(after: .audioSession, at: 0.0), 2.0)
        XCTAssertEqual(playback.state, .failed)
        XCTAssertEqual(playback.failure, .audioSession)
        playback.sessionActivated(at: 1.0)
        playback.observe(.playing, at: 1.0)
        XCTAssertEqual(playback.state, .failed)
        XCTAssertTrue(playback.beginRetry())
        playback.sessionActivated(at: 2.0)
        playback.observe(.playing, at: 3.0)
        XCTAssertEqual(playback.state, .playing)
        XCTAssertNil(playback.failure)
    }

    func testRepeatedWaitingEventsCannotPostponeTheWatchdog() {
        var playback = HarnessgramRadioPlaybackState()
        playback.start()
        XCTAssertFalse(playback.isStalled(at: 100.0), "waiting behind a recording is not a stream stall")
        playback.sessionActivated(at: 100.0)
        playback.observe(.waiting, at: 110.0)
        playback.observe(.waiting, at: 114.0)
        XCTAssertFalse(playback.isStalled(at: 114.99))
        XCTAssertTrue(playback.isStalled(at: 115.0))
        XCTAssertEqual(playback.retry(after: .stalled, at: 115.0), 2.0)
        XCTAssertFalse(playback.isStalled(at: 200.0), "only one reconnect for the same stall")
    }

    func testPlayingCancelsTheWatchdogAndANewStallGetsItsOwnDeadline() {
        var playback = HarnessgramRadioPlaybackState()
        playback.start()
        playback.sessionActivated(at: 0.0)
        playback.observe(.playing, at: 10.0)
        XCTAssertFalse(playback.isStalled(at: 100.0))
        playback.observe(.waiting, at: 100.0)
        XCTAssertFalse(playback.isStalled(at: 114.0))
        XCTAssertTrue(playback.isStalled(at: 115.0))
    }

    func testRetriesAreBoundedEvenIfEachAttemptBrieflyPlays() {
        var playback = HarnessgramRadioPlaybackState()
        playback.start()
        for (index, delay) in [2.0, 4.0, 8.0].enumerated() {
            let time = Double(index * 10)
            playback.sessionActivated(at: time)
            playback.observe(.playing, at: time)
            XCTAssertEqual(playback.retry(after: .stream, at: time + 1.0), delay)
            XCTAssertNil(playback.retry(after: .stream, at: time + 1.5), "duplicate failure")
            XCTAssertEqual(playback.retryCount, index + 1)
            XCTAssertTrue(playback.beginRetry())
        }
        playback.sessionActivated(at: 30.0)
        playback.observe(.playing, at: 30.0)
        XCTAssertNil(playback.retry(after: .stalled, at: 31.0))
        XCTAssertEqual(playback.state, .failed)
        XCTAssertFalse(playback.beginRetry())
        playback.observe(.playing, at: 32.0)
        XCTAssertEqual(playback.state, .failed)
        playback.start()
        XCTAssertEqual(playback.retryCount, 0, "an explicit Retry grants a new budget")
        XCTAssertEqual(playback.state, .connecting)
    }

    func testStablePlaybackReplenishesTheRetryBudget() {
        var playback = HarnessgramRadioPlaybackState()
        playback.start()
        XCTAssertEqual(playback.retry(after: .audioSession, at: 0.0), 2.0)
        XCTAssertTrue(playback.beginRetry())
        playback.sessionActivated(at: 2.0)
        playback.observe(.playing, at: 3.0)
        playback.observe(.playing, at: 20.0)
        playback.observe(.waiting, at: 33.0)
        XCTAssertEqual(playback.retry(after: .stalled, at: 48.0), 2.0)
    }

    func testPauseAndStopCancelPendingRecoveryAndLateEvents() {
        for stop in [false, true] {
            var playback = HarnessgramRadioPlaybackState()
            playback.start()
            XCTAssertEqual(playback.retry(after: .stream, at: 0.0), 2.0)
            if stop { playback.stop() } else { playback.pause() }
            XCTAssertFalse(playback.beginRetry())
            playback.sessionActivated(at: 3.0)
            playback.observe(.playing, at: 3.0)
            XCTAssertEqual(playback.state, stop ? .stopped : .paused)
            XCTAssertFalse(playback.isStalled(at: 100.0))
            XCTAssertNil(playback.retry(after: .stream, at: 100.0))
        }
    }

    func testRecoveryUsesTheSameRecordingHoldAsManualAndRemotePlay() {
        var policy = HarnessgramRadioResumePolicy()
        var playback = HarnessgramRadioPlaybackState()
        playback.start()
        XCTAssertEqual(policy.userPlay(), .reactivateSession)
        XCTAssertEqual(policy.sessionActivated(at: 0.0), .startAtLiveEdge)
        playback.sessionActivated(at: 0.0)
        XCTAssertEqual(playback.retry(after: .stalled, at: 15.0), 2.0)
        XCTAssertTrue(playback.beginRetry())
        XCTAssertEqual(policy.userPlay(), .reactivateSession)
        XCTAssertEqual(policy.sessionActivated(at: 17.0, isRecordingActive: true), .none)
        XCTAssertEqual(playback.state, .connecting)
        XCTAssertFalse(playback.isStalled(at: 100.0))
        XCTAssertEqual(policy.sessionActivated(at: 101.0, isRecordingActive: false), .startAtLiveEdge)
        playback.sessionActivated(at: 101.0)
        playback.observe(.playing, at: 102.0)
        XCTAssertEqual(playback.state, .playing)
    }
}
