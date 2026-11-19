import XCTest
import HarnessgramSettings

/// Build 18: the team radio in Telegram's now-playing bar.
final class HarnessgramNowPlayingTests: XCTestCase {
    private final class FakeRadio: HarnessgramNowPlayingSource {
        var isActive = true
        var isPlaying = true
        var liveTitle: String?
        var toggles = 0
        var closes = 0
        var opens = 0
        func togglePlayPause() { self.toggles += 1 }
        func close() { self.closes += 1 }
        func open() { self.opens += 1 }
    }

    func testTheBarShowsTheRadioOnlyWhenSwitchedOnActiveAndTelegramIsSilent() {
        XCTAssertTrue(HarnessgramNowPlaying.showsRadio(enabled: true, radioActive: true, telegramPlaying: false))
        XCTAssertFalse(HarnessgramNowPlaying.showsRadio(enabled: false, radioActive: true, telegramPlaying: false), "House radio switch off")
        XCTAssertFalse(HarnessgramNowPlaying.showsRadio(enabled: true, radioActive: false, telegramPlaying: false), "radio stopped")
        XCTAssertFalse(HarnessgramNowPlaying.showsRadio(enabled: true, radioActive: true, telegramPlaying: true), "a voice note or music keeps the bar")
    }

    func testTheRegistryHoldsTheSourceWeaklyAndAnnouncesChanges() {
        var notifications = 0
        let observer = NotificationCenter.default.addObserver(forName: HarnessgramNowPlaying.didChangeNotification, object: nil, queue: nil, using: { _ in
            notifications += 1
        })
        defer {
            NotificationCenter.default.removeObserver(observer)
            HarnessgramNowPlaying.register(nil)
        }
        var radio: FakeRadio? = FakeRadio()
        HarnessgramNowPlaying.register(radio)
        XCTAssertTrue(HarnessgramNowPlaying.source === radio)
        XCTAssertEqual(notifications, 1)
        HarnessgramNowPlaying.source?.togglePlayPause()
        HarnessgramNowPlaying.source?.open()
        HarnessgramNowPlaying.source?.close()
        XCTAssertEqual(radio?.toggles, 1)
        XCTAssertEqual(radio?.opens, 1)
        XCTAssertEqual(radio?.closes, 1)
        radio = nil
        XCTAssertNil(HarnessgramNowPlaying.source, "the registry never keeps the radio alive")
        HarnessgramNowPlaying.notifyChanged()
        XCTAssertEqual(notifications, 2)
    }

    func testTheBarSpeaksHebrew() {
        for text in [HarnessgramNowPlaying.Strings.title, HarnessgramNowPlaying.Strings.subtitle, HarnessgramNowPlaying.Strings.play, HarnessgramNowPlaying.Strings.pause, HarnessgramNowPlaying.Strings.close, HarnessgramNowPlaying.Strings.bar] {
            XCTAssertFalse(text.isEmpty)
            XCTAssertTrue(text.unicodeScalars.contains(where: { (0x05D0 ... 0x05EA).contains($0.value) }), text)
        }
        XCTAssertEqual(HarnessgramNowPlaying.radioItemKey, "harnessgram.radio")
    }

    func testTheBarShowsTheLiveTitleWhenTheRadioSaysWhatItIsOn() {
        XCTAssertEqual(HarnessgramNowPlaying.barLines(liveTitle: nil).title, "שידורי הקוקפיט")
        XCTAssertEqual(HarnessgramNowPlaying.barLines(liveTitle: nil).subtitle, "שידור חי")
        XCTAssertEqual(HarnessgramNowPlaying.barLines(liveTitle: "  ").title, "שידורי הקוקפיט", "a blank title is no title")
        let lines = HarnessgramNowPlaying.barLines(liveTitle: "סיכום הבוקר של פרויקט לדוגמה")
        XCTAssertEqual(lines.title, "סיכום הבוקר של פרויקט לדוגמה")
        XCTAssertEqual(lines.subtitle, "שידורי הקוקפיט", "the station name moves under the live title")
        XCTAssertEqual(HarnessgramNowPlaying.barLines(liveTitle: String(repeating: "א", count: 200)).title.count, 80, "one short line")
        XCTAssertEqual(HarnessgramNowPlaying.Strings.barLabel(title: lines.title, subtitle: lines.subtitle), "סיכום הבוקר של פרויקט לדוגמה, שידורי הקוקפיט. הקשה פותחת את מסך השידורים")
    }
}

