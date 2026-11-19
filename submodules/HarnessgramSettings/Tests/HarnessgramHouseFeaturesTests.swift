import XCTest
import HarnessgramSettings

final class HarnessgramHouseFeaturesTests: XCTestCase {
    private func withDefaults(_ body: (UserDefaults) -> Void) {
        let suite = "HarnessgramHouseFeaturesTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        body(defaults)
    }

    /// Owner-first (build 18 fix): every House screen built so far is on for the owner until he turns it off.
    func testTheBuiltHouseScreensAreOnByDefault() {
        // Build 34: the native Cockpit joins (its answering switch, nativeDecisions, stays off).
        let on: Set<HouseFeature> = [.theme, .radioScreen, .knock, .waitingList, .nativeCockpit]
        XCTAssertEqual(HarnessgramSettings.houseDefaultsOn, on)
        self.withDefaults { defaults in
            let settings = HarnessgramSettings(defaults: defaults)
            for feature in HouseFeature.allCases {
                XCTAssertEqual(settings.houseFeature(feature), on.contains(feature), feature.rawValue)
            }
        }
    }

    /// A switch the owner turned off before the defaults turned on stays off.
    func testASwitchTheOwnerTurnedOffStaysOffAfterTheDefaultTurnedOn() {
        self.withDefaults { defaults in
            HarnessgramSettings(defaults: defaults).setHouseFeature(.knock, false)
            let settings = HarnessgramSettings(defaults: defaults)
            XCTAssertFalse(settings.houseFeature(.knock))
            XCTAssertTrue(settings.houseFeature(.theme))
        }
    }

    func testTheOwnersChoiceIsKeptAndSurvivesTheDefaultFlipping() {
        self.withDefaults { defaults in
            let settings = HarnessgramSettings(defaults: defaults)
            settings.setHouseFeature(.homeTab, false)
            settings.setHouseFeature(.knock, true)
            // The default for every screen turns on later: a screen the owner switched off stays off, one he switched on stays on.
            let allOn = Set(HouseFeature.allCases)
            XCTAssertFalse(settings.houseFeature(.homeTab, defaultsOn: allOn))
            XCTAssertTrue(settings.houseFeature(.knock, defaultsOn: allOn))
            // A screen he never chose follows the default.
            XCTAssertTrue(settings.houseFeature(.room, defaultsOn: allOn))
            XCTAssertFalse(settings.houseFeature(.room, defaultsOn: []))
            let reloaded = HarnessgramSettings(defaults: defaults)
            XCTAssertTrue(reloaded.houseFeature(.knock))
            XCTAssertFalse(reloaded.houseFeature(.homeTab, defaultsOn: allOn))
        }
    }

    func testAStoredValueWithoutTheChosenMarkIsIgnored() {
        self.withDefaults { defaults in
            let settings = HarnessgramSettings(defaults: defaults)
            defaults.set(false, forKey: "HarnessgramSettings.house.theme")
            XCTAssertTrue(settings.houseFeature(.theme))
            defaults.set(true, forKey: "HarnessgramSettings.house.room")
            XCTAssertFalse(settings.houseFeature(.room))
            XCTAssertFalse(settings.houseFeature(.theme, defaultsOn: []))
        }
    }

    func testResetFollowsTheDefaultAgain() {
        self.withDefaults { defaults in
            let settings = HarnessgramSettings(defaults: defaults)
            settings.setHouseFeature(.theme, false)
            XCTAssertFalse(settings.houseFeature(.theme))
            settings.resetHouseFeature(.theme)
            XCTAssertTrue(settings.houseFeature(.theme))
        }
    }

    /// The House switches write exactly their own two keys and never any other setting, and none of them can
    /// touch the policy namespace (approvals, media filter) that lives under "Harnessgram.".
    func testHouseSwitchesTouchOnlyTheirOwnKeys() {
        for feature in HouseFeature.allCases {
            self.withDefaults { defaults in
                let before = Set(defaults.dictionaryRepresentation().keys)
                HarnessgramSettings(defaults: defaults).setHouseFeature(feature, true)
                let added = Set(defaults.dictionaryRepresentation().keys).subtracting(before)
                XCTAssertEqual(added, [
                    "HarnessgramSettings.house." + feature.rawValue,
                    "HarnessgramSettings.house." + feature.rawValue + ".chosen",
                ])
            }
        }
        let houseKeys = HarnessgramSettings.Key.allCases.filter { $0.rawValue.hasPrefix("HarnessgramSettings.house.") }
        XCTAssertEqual(houseKeys.count, HouseFeature.allCases.count * 2)
        for key in houseKeys {
            XCTAssertFalse(key.rawValue.hasPrefix("Harnessgram."), key.rawValue)
        }
    }
}
