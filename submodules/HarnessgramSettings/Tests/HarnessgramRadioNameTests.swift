import XCTest
@testable import HarnessgramSettings

/// Build 23: the team radio is "שידורי הקוקפיט" in the whole app UI and in Now Playing, with the owner's tower artwork.
final class HarnessgramRadioNameTests: XCTestCase {
    func testTheStationIsCalledCockpitBroadcasts() {
        XCTAssertEqual(HarnessgramNowPlaying.Strings.title, "שידורי הקוקפיט")
        XCTAssertEqual(HarnessgramRadioArtwork.bundledImageName, "House/Radio/radio-tower")
    }

    func testNoScreenStillSaysTheOldName() throws {
        let folders = ["HarnessgramSettings/Sources", "HarnessgramCockpitKit/Sources", "HarnessgramAgent/Sources", "TelegramUI/Components/HarnessgramSettingsUI/Sources", "TelegramUI/Components/HarnessgramHouseUI/Sources"]
        var scanned = 0
        for folder in folders {
            for file in HarnessgramSourceScan.swiftFiles(folder, anchor: HarnessgramRadioNameTests.self) {
                scanned += 1
                XCTAssertFalse(file.text.contains("רדיו הצוות"), file.name)
            }
        }
        if scanned == 0 {
            throw XCTSkip("the sources are not reachable from this test run")
        }
    }

    func testTheTowerArtworkIsInTheCatalog() throws {
        guard let radio = HarnessgramSourceScan.directory("HarnessgramHouseKit/Resources/HarnessgramHouse.xcassets/House/Radio", anchor: HarnessgramRadioNameTests.self) else {
            throw XCTSkip("the asset catalog is not reachable from this test run")
        }
        let contents = radio.appendingPathComponent("radio-tower.imageset/Contents.json")
        let data = try Data(contentsOf: contents)
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains("radio-tower@2x.png"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: radio.appendingPathComponent("radio-tower.imageset/radio-tower@2x.png").path))
    }
}
