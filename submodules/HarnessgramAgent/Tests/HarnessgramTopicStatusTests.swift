import XCTest
import HarnessgramAgent
import HarnessgramSettings

final class HarnessgramTopicStatusTests: XCTestCase {
    // The bridge's names: (STATE_ICONS[state] + " " + name).strip() (see docs/harnessgram-local-config.md).
    func testBridgeStateIconsMapToDots() {
        XCTAssertEqual(HarnessgramTopicStatus.from(title: "⚙️ פרויקט לדוגמה: מסך כניסה"), .working)
        XCTAssertEqual(HarnessgramTopicStatus.from(title: "❓ Harnessgram iOS: build 10"), .waitingForYou)
        XCTAssertEqual(HarnessgramTopicStatus.from(title: "✅ חנות לדוגמה: דף מוצר"), .done)
    }

    func testIconsWithOrWithoutTheEmojiSelectorAndAloneStillCount() {
        XCTAssertEqual(HarnessgramTopicStatus.from(title: "\u{2699} name"), .working, "no variation selector")
        XCTAssertEqual(HarnessgramTopicStatus.from(title: "\u{2753}\u{FE0F} name"), .waitingForYou, "with variation selector")
        XCTAssertEqual(HarnessgramTopicStatus.from(title: "⚙️"), .working, "a topic with no name left")
        XCTAssertEqual(HarnessgramTopicStatus.from(title: "\u{200F} ✅ name"), .done, "leading RLM and space")
    }

    func testOtherTitlesHaveNoDot() {
        for title in ["", " ", "פרויקט לדוגמה: מסך כניסה", "Claude", "✅x", "name ✅", "🟢 name", "⏳ name", "❔ name", "✔️ name", "💡 idea", "⚙️✅ name"] {
            XCTAssertNil(HarnessgramTopicStatus.from(title: title), title)
        }
    }

    func testDotColoursAreDistinct() {
        let colours = Set(HarnessgramTopicStatus.allCases.map { $0.rgb })
        XCTAssertEqual(colours.count, HarnessgramTopicStatus.allCases.count)
        XCTAssertEqual(HarnessgramTopicStatus.done.rgb, 0x30D158)
        XCTAssertEqual(HarnessgramTopicStatus.waitingForYou.rgb, 0xFF9F0A)
        XCTAssertEqual(HarnessgramTopicStatus.working.rgb, 0x0A84FF)
        XCTAssertEqual(HarnessgramTopicStatus.dotText.unicodeScalars.first?.value, 0x25CF)
    }

    func testTheSwitchDefaultsOn() {
        let suite = "HarnessgramTopicStatusTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = HarnessgramSettings(defaults: defaults)
        XCTAssertTrue(settings.topicStatusDots)
        settings.topicStatusDots = false
        XCTAssertFalse(HarnessgramSettings(defaults: defaults).topicStatusDots)
    }

    func testTheHouseThemeRecoloursTheDotsAndNothingElse() {
        for status in HarnessgramTopicStatus.allCases {
            // Off: Telegram's colours, in both appearances.
            XCTAssertEqual(status.rgb(house: false, darkAppearance: false), status.rgb)
            XCTAssertEqual(status.rgb(house: false, darkAppearance: true), status.rgb)
            // On: a colour of the House palette, different from Telegram's blue/orange/green.
            XCTAssertNotEqual(status.rgb(house: true, darkAppearance: false), status.rgb)
            XCTAssertNotEqual(status.rgb(house: true, darkAppearance: true), status.rgb)
        }
        XCTAssertEqual(HarnessgramTopicStatus.working.rgb(house: true, darkAppearance: false), 0x5FA83A)
        XCTAssertEqual(HarnessgramTopicStatus.working.rgb(house: true, darkAppearance: true), 0x7CC653)
        XCTAssertEqual(Set(HarnessgramTopicStatus.allCases.map { $0.rgb(house: true, darkAppearance: false) }).count, 3)
    }
}
