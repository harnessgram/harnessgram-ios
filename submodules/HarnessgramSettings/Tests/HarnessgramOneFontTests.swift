import XCTest
@testable import HarnessgramSettings

/// Build 23: one font for the app and the messages, an optional message font, and the carry-over from build 22.
final class HarnessgramOneFontTests: XCTestCase {
    private func withDefaults(_ body: (UserDefaults) -> Void) {
        let suite = "HarnessgramOneFontTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        body(defaults)
    }

    func testMessagesFollowTheAppFontByDefault() {
        self.withDefaults { defaults in
            let settings = HarnessgramSettings(defaults: defaults)
            XCTAssertFalse(settings.separateMessageFont)
            XCTAssertEqual(settings.messageFont, .system)
            settings.appFont = .secularOne
            XCTAssertEqual(settings.messageFont, .secularOne, "the messages draw in the app font")
            settings.appFont = .frankRuhlLibre
            XCTAssertEqual(settings.messageFont, .frankRuhlLibre)
        }
    }

    func testASeparateMessageFontOnlyWhileItsSwitchIsOn() {
        self.withDefaults { defaults in
            let settings = HarnessgramSettings(defaults: defaults)
            settings.appFont = .heebo
            settings.separateMessageFont = true
            XCTAssertEqual(settings.messageFont, .heebo, "turned on, it starts from the font the messages had")
            settings.messageFontChoice = .secularOne
            XCTAssertEqual(settings.messageFont, .secularOne)
            settings.separateMessageFont = false
            XCTAssertEqual(settings.messageFont, .heebo, "off again, the app font")
            XCTAssertEqual(settings.messageFontChoice, .secularOne, "the message choice is kept for next time")
        }
    }

    func testBothFontListsHoldAllFiveFontsAndTheSystemFont() {
        XCTAssertEqual(HarnessgramSettings.MessageFont.allCases.map(\.rawValue).sorted(), HarnessgramSettings.AppFont.allCases.map(\.rawValue).sorted())
        XCTAssertEqual(HarnessgramSettings.MessageFont.allCases.count, 6)
        for font in HarnessgramSettings.AppFont.allCases {
            XCTAssertEqual(HarnessgramSettings.MessageFont(font).rawValue, font.rawValue)
        }
    }

    func testAMessageFontAloneBecomesTheAppFont() {
        self.withDefaults { defaults in
            defaults.set("rubik", forKey: HarnessgramSettings.Key.messageFont.rawValue)
            let settings = HarnessgramSettings(defaults: defaults)
            settings.migrateToOneFontIfNeeded()
            XCTAssertEqual(settings.appFont, .rubik)
            XCTAssertFalse(settings.separateMessageFont)
            XCTAssertEqual(settings.messageFont, .rubik)
        }
    }

    func testTwoDifferentFontsAreBothKeptWithTheSwitchOn() {
        self.withDefaults { defaults in
            // The owner's build 22 phone: Secular One for the app, Rubik for the messages.
            defaults.set("rubik", forKey: HarnessgramSettings.Key.messageFont.rawValue)
            defaults.set("secularOne", forKey: HarnessgramSettings.Key.appFont.rawValue)
            let settings = HarnessgramSettings(defaults: defaults)
            settings.migrateToOneFontIfNeeded()
            XCTAssertEqual(settings.appFont, .secularOne)
            XCTAssertTrue(settings.separateMessageFont)
            XCTAssertEqual(settings.messageFont, .rubik)
        }
    }

    func testTheSameFontTwiceOrNoMessageFontChangesNothingAndRunsOnce() {
        self.withDefaults { defaults in
            defaults.set("heebo", forKey: HarnessgramSettings.Key.messageFont.rawValue)
            defaults.set("heebo", forKey: HarnessgramSettings.Key.appFont.rawValue)
            let settings = HarnessgramSettings(defaults: defaults)
            settings.migrateToOneFontIfNeeded()
            XCTAssertFalse(settings.separateMessageFont)
            XCTAssertEqual(settings.messageFont, .heebo)
            // Once only: a later message font set in build 23 is never folded again.
            defaults.set("rubik", forKey: HarnessgramSettings.Key.messageFont.rawValue)
            defaults.removeObject(forKey: HarnessgramSettings.Key.appFont.rawValue)
            settings.migrateToOneFontIfNeeded()
            XCTAssertEqual(settings.appFont, .system)
        }
        self.withDefaults { defaults in
            defaults.set("system", forKey: HarnessgramSettings.Key.messageFont.rawValue)
            defaults.set("assistant", forKey: HarnessgramSettings.Key.appFont.rawValue)
            let settings = HarnessgramSettings(defaults: defaults)
            settings.migrateToOneFontIfNeeded()
            XCTAssertFalse(settings.separateMessageFont)
            XCTAssertEqual(settings.messageFont, .assistant)
        }
    }

    // MARK: Apply modes (PART G)

    func testEverySettingDeclaresWhenItApplies() {
        // The switch in HarnessgramSettingApply is exhaustive; this pins the ones the owner sees.
        XCTAssertEqual(HarnessgramSettings.Key.appFont.apply, .restart)
        XCTAssertEqual(HarnessgramSettings.Key.theme.apply, .live)
        XCTAssertEqual(HarnessgramSettings.Key.messageFont.apply, .reopenChat)
        XCTAssertEqual(HarnessgramSettings.Key.cockpitTab.apply, .live)
        for key in HarnessgramSettings.Key.allCases {
            XCTAssertFalse(key.apply.rawValue.isEmpty, key.rawValue)
            if key.rawValue.hasSuffix(".chosen") || key.rawValue.hasSuffix("Chosen") {
                XCTAssertEqual(key.apply, .internalState, key.rawValue)
            }
        }
    }

    func testOnlyARestartSettingChangedSinceLaunchWaitsForARestart() {
        self.withDefaults { defaults in
            let settings = HarnessgramSettings(defaults: defaults)
            settings.rememberLaunchValues()
            XCTAssertFalse(settings.waitsForRestart)
            settings.theme = .openSky
            XCTAssertFalse(settings.waitsForRestart, "a live setting never waits")
            settings.appFont = .secularOne
            XCTAssertTrue(settings.waitsForRestart(.appFont))
            XCTAssertTrue(settings.waitsForRestart)
            settings.appFont = .system
            XCTAssertFalse(settings.waitsForRestart(.appFont), "back to the launch font: nothing waits")
        }
    }
}
