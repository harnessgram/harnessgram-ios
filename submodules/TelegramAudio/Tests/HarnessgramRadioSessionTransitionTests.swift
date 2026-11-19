import XCTest
import SwiftSignalKit
import TelegramAudio

/// Owner report on build 10: recording a voice note in the middle of the radio "changes the radio".
/// The radio's playback holder must come back after the recording, and the recording's iPhone-microphone
/// pin must not outlive it.
final class HarnessgramRadioSessionTransitionTests: XCTestCase {
    private var disposables: [Disposable] = []

    override func tearDown() {
        for disposable in self.disposables {
            disposable.dispose()
        }
        self.disposables.removeAll()
        super.tearDown()
    }

    private func settle() {
        let settled = self.expectation(description: "holders settled")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            settled.fulfill()
        }
        self.wait(for: [settled], timeout: 2.0)
    }

    /// Pushes a holder whose activation control is left untouched (the test never configures AVAudioSession).
    private func push(_ session: ManagedAudioSessionImpl, _ type: ManagedAudioSessionType, once: Bool, activated: @escaping () -> Void, deactivated: @escaping (Bool) -> Void = { _ in }) -> Disposable {
        return session.push(audioSessionType: type, once: once, manualActivate: { _ in
            activated()
        }, deactivate: { temporary in
            deactivated(temporary)
            // Like the radio player, complete asynchronously (a synchronous completion leaves the manager's
            // deactivating marker set and nothing is activated again).
            return Signal { subscriber in
                DispatchQueue.main.async {
                    subscriber.putCompletion()
                }
                return EmptyDisposable
            }
        })
    }

    private func radioActivationsAroundAVoiceNote(once: Bool) -> (activations: Int, deactivations: [Bool]) {
        let session = ManagedAudioSessionImpl()
        var activations = 0
        var deactivations: [Bool] = []
        self.disposables.append(self.push(session, .play(mixWithOthers: false), once: once, activated: { activations += 1 }, deactivated: { deactivations.append($0) }))
        self.settle()
        for pauseMusic in [true, false] {
            let recording = self.push(session, .voiceMessageRecording(beginWithTone: false, pauseMusicOnRecording: pauseMusic), once: false, activated: {})
            self.settle()
            recording.dispose()
            self.settle()
        }
        return (activations, deactivations)
    }

    func testTheRadioHolderComesBackAfterVoiceNotes() {
        // Kept registration (the radio since this fix): active again after each recording.
        let kept = self.radioActivationsAroundAVoiceNote(once: false)
        XCTAssertEqual(kept.activations, 3)
        XCTAssertEqual(kept.deactivations.count, 2)
    }

    func testAOnceRegistrationIsDroppedByTheFirstRecording() {
        // Build 10's registration (once: true) was removed by the first recording, so the radio stayed paused.
        let dropped = self.radioActivationsAroundAVoiceNote(once: true)
        XCTAssertEqual(dropped.activations, 1)
    }

    func testTheMicrophonePinIsClearedWhenTheRecordingEnds() {
        let voice = ManagedAudioSessionType.voiceMessageRecording(beginWithTone: false, pauseMusicOnRecording: true)
        let radio = ManagedAudioSessionType.play(mixWithOthers: false)
        XCTAssertTrue(ManagedAudioSessionType.clearsPinnedBuiltInMic(pinned: true, next: radio, preferBuiltInMic: true))
        XCTAssertTrue(ManagedAudioSessionType.clearsPinnedBuiltInMic(pinned: true, next: .voiceCall, preferBuiltInMic: true))
        XCTAssertTrue(ManagedAudioSessionType.clearsPinnedBuiltInMic(pinned: true, next: .record(speaker: false, video: false, withOthers: false), preferBuiltInMic: true))
        XCTAssertTrue(ManagedAudioSessionType.clearsPinnedBuiltInMic(pinned: true, next: voice, preferBuiltInMic: false))
        XCTAssertFalse(ManagedAudioSessionType.clearsPinnedBuiltInMic(pinned: true, next: voice, preferBuiltInMic: true))
        XCTAssertFalse(ManagedAudioSessionType.clearsPinnedBuiltInMic(pinned: false, next: radio, preferBuiltInMic: true))
    }

    func testPlaybackAfterARecordingGetsPlaybackOptionsWithoutHandsFree() {
        // The radio's own session type never asks for Bluetooth hands-free (mono) or the receiver.
        XCTAssertFalse(ManagedAudioSessionType.play(mixWithOthers: false).prefersBuiltInMicInput(preferBuiltInMic: true))
        let recording = ManagedAudioSessionType.recordCategoryOptions(video: false, mixWithOthers: false, preferBuiltInMic: true)
        XCTAssertTrue(recording.contains(.allowBluetoothA2DP))
    }
}
