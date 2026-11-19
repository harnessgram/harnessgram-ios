import XCTest
import AVFoundation
import TelegramAudio
import HarnessgramSettings

/// Harnessgram "Record with the iPhone microphone" (harnessgram-ios issue #1): a voice recording with
/// a car or headset connected must not route the microphone through Bluetooth hands-free.
final class HarnessgramRecordMicrophoneTests: XCTestCase {
    private var handsFree: AVAudioSession.CategoryOptions {
        #if canImport(AlarmKit)
        return .allowBluetoothHFP
        #else
        return .allowBluetooth
        #endif
    }

    func testVoiceRecordingWithBuiltInMicDropsHandsFreeAndKeepsCarSpeakers() {
        let options = ManagedAudioSessionType.recordCategoryOptions(video: false, mixWithOthers: false, preferBuiltInMic: true)
        XCTAssertFalse(options.contains(self.handsFree))
        XCTAssertTrue(options.contains(.allowBluetoothA2DP))
        XCTAssertFalse(options.contains(.mixWithOthers))
    }

    func testVoiceRecordingWithBuiltInMicKeepsMixWithOthers() {
        let options = ManagedAudioSessionType.recordCategoryOptions(video: false, mixWithOthers: true, preferBuiltInMic: true)
        XCTAssertEqual(options, [.allowBluetoothA2DP, .mixWithOthers])
    }

    func testSwitchOffKeepsTelegramOptions() {
        XCTAssertEqual(ManagedAudioSessionType.recordCategoryOptions(video: false, mixWithOthers: false, preferBuiltInMic: false), [self.handsFree])
        XCTAssertEqual(ManagedAudioSessionType.recordCategoryOptions(video: false, mixWithOthers: true, preferBuiltInMic: false), [self.handsFree, .mixWithOthers])
    }

    func testVideoRecordingIsUnchangedBySwitch() {
        let expected: AVAudioSession.CategoryOptions = [self.handsFree, .allowBluetoothA2DP]
        XCTAssertEqual(ManagedAudioSessionType.recordCategoryOptions(video: true, mixWithOthers: false, preferBuiltInMic: true), expected)
        XCTAssertEqual(ManagedAudioSessionType.recordCategoryOptions(video: true, mixWithOthers: false, preferBuiltInMic: false), expected)
    }

    func testOnlyVoiceRecordingPinsBuiltInMic() {
        XCTAssertTrue(ManagedAudioSessionType.voiceMessageRecording(beginWithTone: false, pauseMusicOnRecording: true).prefersBuiltInMicInput(preferBuiltInMic: true))
        XCTAssertTrue(ManagedAudioSessionType.voiceMessageRecording(beginWithTone: true, pauseMusicOnRecording: false).prefersBuiltInMicInput(preferBuiltInMic: true))
        XCTAssertFalse(ManagedAudioSessionType.voiceMessageRecording(beginWithTone: false, pauseMusicOnRecording: true).prefersBuiltInMicInput(preferBuiltInMic: false))
        // Round videos (VideoMessageCameraScreen), the camera and the editor ask for video: false without voiceNote.
        let others: [ManagedAudioSessionType] = [.record(speaker: false, video: false, withOthers: false), .record(speaker: false, video: false, withOthers: true), .record(speaker: false, video: true, withOthers: false), .voiceCall, .videoCall, .play(mixWithOthers: false), .playWithPossiblePortOverride, .ambient]
        for type in others {
            XCTAssertFalse(type.prefersBuiltInMicInput(preferBuiltInMic: true), "\(type)")
        }
    }

    func testSettingIsOnByDefault() {
        let defaults = UserDefaults(suiteName: "HarnessgramRecordMicrophoneTests")!
        defaults.removePersistentDomain(forName: "HarnessgramRecordMicrophoneTests")
        let settings = HarnessgramSettings(defaults: defaults)
        XCTAssertTrue(settings.recordWithBuiltInMic)
        settings.recordWithBuiltInMic = false
        XCTAssertFalse(HarnessgramSettings(defaults: defaults).recordWithBuiltInMic)
        defaults.removePersistentDomain(forName: "HarnessgramRecordMicrophoneTests")
    }
}
