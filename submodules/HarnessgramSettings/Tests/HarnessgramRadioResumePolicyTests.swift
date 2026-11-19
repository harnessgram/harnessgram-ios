import XCTest
import CoreGraphics
import HarnessgramSettings

/// The radio around voice notes and calls (owner report on build 10: "recording in the middle of the
/// broadcast changes the radio").
final class HarnessgramRadioResumePolicyTests: XCTestCase {
    private func playing() -> HarnessgramRadioResumePolicy {
        var policy = HarnessgramRadioResumePolicy()
        XCTAssertEqual(policy.userPlay(), .reactivateSession)
        XCTAssertEqual(policy.sessionActivated(at: 0.0), .startAtLiveEdge)
        XCTAssertEqual(policy.phase, .playing)
        return policy
    }

    func testVoiceNoteInTheMiddlePausesAndThenResumesAtTheLiveEdge() {
        var policy = self.playing()
        XCTAssertEqual(policy.sessionDeactivated(at: 100.0), .pause)
        XCTAssertEqual(policy.phase, .interrupted(since: 100.0, system: false))
        // The recording's holder is removed; Telegram's session manager makes the radio's holder active again.
        XCTAssertEqual(policy.sessionActivated(at: 130.0), .startAtLiveEdge)
        XCTAssertEqual(policy.phase, .playing)
    }

    func testATelegramCallResumesOnItsOwnButALongCallWaitsForATap() {
        var short = self.playing()
        XCTAssertEqual(short.sessionDeactivated(at: 0.0), .pause)
        XCTAssertEqual(short.sessionActivated(at: 9.0 * 60.0), .startAtLiveEdge)

        var long = self.playing()
        XCTAssertEqual(long.sessionDeactivated(at: 0.0), .pause)
        XCTAssertEqual(long.sessionActivated(at: 11.0 * 60.0), .offerResume)
        XCTAssertEqual(long.phase, .waitingForTap)
        // Nothing plays until the owner taps.
        XCTAssertEqual(long.sessionActivated(at: 12.0 * 60.0), .none)
        XCTAssertEqual(long.userPlay(), .reactivateSession)
        XCTAssertEqual(long.sessionActivated(at: 13.0 * 60.0), .startAtLiveEdge)
    }

    func testAPhoneCallWithShouldResumeResumesThroughANewActivation() {
        var policy = self.playing()
        XCTAssertEqual(policy.systemInterruptionBegan(at: 10.0), .pause)
        // The session manager reactivates the radio's holder right away; the call is still going on.
        XCTAssertEqual(policy.sessionActivated(at: 11.0), .none)
        XCTAssertEqual(policy.systemInterruptionEnded(at: 200.0, shouldResume: true), .reactivateSession)
        XCTAssertEqual(policy.sessionActivated(at: 201.0), .startAtLiveEdge)
        XCTAssertEqual(policy.phase, .playing)
    }

    func testManualPlayIncludingAResumeNotificationWaitsForTheRecording() {
        var policy = HarnessgramRadioResumePolicy()
        XCTAssertEqual(policy.userPlay(), .reactivateSession)
        XCTAssertEqual(policy.sessionActivated(at: 10.0, isRecordingActive: true), .none)
        XCTAssertEqual(policy.sessionActivated(at: 20.0, isRecordingActive: true), .none)
        XCTAssertEqual(policy.phase, .starting)
        XCTAssertEqual(policy.sessionActivated(at: 30.0, isRecordingActive: false), .startAtLiveEdge)
        XCTAssertEqual(policy.phase, .playing)
    }

    func testSystemResumeWaitsForTheCameraRecordingToEnd() {
        var policy = self.playing()
        XCTAssertEqual(policy.systemInterruptionBegan(at: 10.0), .pause)
        XCTAssertEqual(policy.systemInterruptionEnded(at: 20.0, shouldResume: true), .reactivateSession)
        XCTAssertEqual(policy.sessionActivated(at: 21.0, isRecordingActive: true), .none)
        XCTAssertEqual(policy.phase, .starting)
        XCTAssertEqual(policy.sessionActivated(at: 40.0, isRecordingActive: false), .startAtLiveEdge)
    }

    func testManagedSessionResumeKeepsThePauseTimeWhileRecording() {
        var policy = self.playing()
        XCTAssertEqual(policy.sessionDeactivated(at: 10.0), .pause)
        XCTAssertEqual(policy.sessionActivated(at: 20.0, isRecordingActive: true), .none)
        XCTAssertEqual(policy.phase, .interrupted(since: 10.0, system: false))
        XCTAssertEqual(policy.sessionActivated(at: 10.0 + HarnessgramRadioResumePolicy.autoResumeLimit + 1.0, isRecordingActive: false), .offerResume)
    }

    func testPauseAndStopCancelAPlayWaitingForTheRecording() {
        var policy = HarnessgramRadioResumePolicy()
        XCTAssertEqual(policy.userPlay(), .reactivateSession)
        XCTAssertEqual(policy.sessionActivated(at: 10.0, isRecordingActive: true), .none)
        XCTAssertEqual(policy.userPause(), .pause)
        XCTAssertEqual(policy.sessionActivated(at: 20.0, isRecordingActive: false), .none)
        XCTAssertEqual(policy.userPlay(), .reactivateSession)
        XCTAssertEqual(policy.sessionActivated(at: 30.0, isRecordingActive: true), .none)
        policy.stop()
        XCTAssertEqual(policy.sessionActivated(at: 40.0, isRecordingActive: false), .none)
        XCTAssertEqual(policy.phase, .off)
    }

    func testAPhoneCallEndedWithoutShouldResumeWaitsForATap() {
        var policy = self.playing()
        XCTAssertEqual(policy.systemInterruptionBegan(at: 10.0), .pause)
        XCTAssertEqual(policy.systemInterruptionEnded(at: 40.0, shouldResume: false), .offerResume)
        XCTAssertEqual(policy.phase, .waitingForTap)
        XCTAssertEqual(policy.sessionActivated(at: 41.0), .none)
    }

    func testALongPhoneCallWaitsForATapEvenWithShouldResume() {
        var policy = self.playing()
        XCTAssertEqual(policy.systemInterruptionBegan(at: 0.0), .pause)
        XCTAssertEqual(policy.systemInterruptionEnded(at: 15.0 * 60.0, shouldResume: true), .offerResume)
    }

    func testAPhoneCallDuringAVoiceNoteInterruptionKeepsTheFirstPauseTime() {
        var policy = self.playing()
        XCTAssertEqual(policy.sessionDeactivated(at: 0.0), .pause)
        XCTAssertEqual(policy.systemInterruptionBegan(at: 30.0), .none)
        XCTAssertEqual(policy.phase, .interrupted(since: 0.0, system: true))
        XCTAssertEqual(policy.systemInterruptionEnded(at: 60.0, shouldResume: true), .reactivateSession)
    }

    func testThePausedOrStoppedRadioNeverStartsByItself() {
        var policy = self.playing()
        XCTAssertEqual(policy.userPause(), .pause)
        XCTAssertEqual(policy.sessionActivated(at: 5.0), .none)
        XCTAssertEqual(policy.sessionDeactivated(at: 6.0), .none)
        XCTAssertEqual(policy.systemInterruptionBegan(at: 7.0), .none)
        XCTAssertEqual(policy.systemInterruptionEnded(at: 8.0, shouldResume: true), .none)
        policy.stop()
        XCTAssertEqual(policy.sessionActivated(at: 9.0), .none)
        XCTAssertEqual(policy.phase, .off)
    }

    /// The lock-screen artwork is the listen page's mark: navy corners, a white centre dot, white arcs above it.
    func testRadioArtworkIsTheListenPageMark() {
        guard let image = HarnessgramRadioArtwork.image(pixels: 512) else {
            return XCTFail("no artwork")
        }
        XCTAssertEqual(image.width, 512)
        XCTAssertEqual(image.height, 512)
        let width = image.width, bytesPerRow = width * 4
        var bytes = [UInt8](repeating: 0, count: bytesPerRow * image.height)
        bytes.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: width, height: image.height, bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            context?.draw(image, in: CGRect(x: 0, y: 0, width: width, height: image.height))
        }
        // Rows from the top of the image (the bitmap's first row is its top).
        func pixel(_ x: Int, _ y: Int) -> (Int, Int, Int, Int) {
            let o = y * bytesPerRow + x * 4
            return (Int(bytes[o]), Int(bytes[o + 1]), Int(bytes[o + 2]), Int(bytes[o + 3]))
        }
        let centre = pixel(256, 256)
        XCTAssertGreaterThan(centre.0, 230, "white centre dot")
        let navy = pixel(256, 470)
        XCTAssertLessThanOrEqual(abs(navy.0 - 0x1F), 3, "navy background")
        XCTAssertLessThanOrEqual(abs(navy.2 - 0x5F), 3, "navy background")
        XCTAssertGreaterThan(pixel(256, 256 - 126).0, 230, "the inner arc is above the dot")
        XCTAssertLessThan(pixel(256, 256 + 126).0, 60, "no arc below the dot")
        XCTAssertEqual(pixel(1, 1).3, 0, "rounded corner is transparent")
    }

    // MARK: Build 13: remote-command ownership (review P2)

    private final class FakeCommand: HarnessgramRemoteCommandSwitch {
        var isEnabled: Bool
        init(_ isEnabled: Bool) {
            self.isEnabled = isEnabled
        }
    }

    func testTheRadioGivesBackEveryCommandItBorrowed() {
        let play = FakeCommand(false), pause = FakeCommand(true), toggle = FakeCommand(false)
        let skip = FakeCommand(true), next = FakeCommand(true), stop = FakeCommand(false)
        let ownership = HarnessgramCommandOwnership<FakeCommand>(authority: HarnessgramRemoteCommandAuthority())
        ownership.take(enabled: [play, pause, toggle], disabled: [skip, next, stop])
        XCTAssertTrue(ownership.isOwning)
        XCTAssertEqual([play, pause, toggle].map { $0.isEnabled }, [true, true, true])
        XCTAssertEqual([skip, next, stop].map { $0.isEnabled }, [false, false, false])
        ownership.take(enabled: [play, pause, toggle], disabled: [skip, next, stop])
        ownership.release()
        XCTAssertFalse(ownership.isOwning)
        XCTAssertEqual([play, pause, toggle].map { $0.isEnabled }, [false, true, false], "untouched by Telegram: back to what the radio found")
        XCTAssertEqual([skip, next, stop].map { $0.isEnabled }, [true, true, false], "the first recorded state, not the second take's")
    }

    func testTelegramsAuthoritativeStateWinsOverTheSnapshot() {
        let authority = HarnessgramRemoteCommandAuthority()
        let play = FakeCommand(false), skip = FakeCommand(true), next = FakeCommand(false), pause = FakeCommand(false)
        let ownership = HarnessgramCommandOwnership<FakeCommand>(authority: authority)
        ownership.take(enabled: [play, pause], disabled: [skip, next])
        // Telegram's player took the audio meanwhile and wrote its own states.
        skip.isEnabled = true
        authority.telegramSet(skip, enabled: true)
        play.isEnabled = false
        authority.telegramSet(play, enabled: false)
        // A same-value write: the radio had pause on, Telegram also set it on. The old boolean comparison could not
        // see it and put back the snapshot (off).
        pause.isEnabled = true
        authority.telegramSet(pause, enabled: true)
        ownership.release()
        XCTAssertTrue(skip.isEnabled, "Telegram's state")
        XCTAssertFalse(play.isEnabled, "Telegram's state")
        XCTAssertTrue(pause.isEnabled, "Telegram's same-value write is kept")
        XCTAssertFalse(next.isEnabled, "untouched by Telegram: back to its earlier state")
        ownership.release()
        XCTAssertTrue(skip.isEnabled, "a second release changes nothing")
    }
}
