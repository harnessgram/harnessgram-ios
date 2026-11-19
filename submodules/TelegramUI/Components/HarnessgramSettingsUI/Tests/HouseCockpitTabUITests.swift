import XCTest
@testable import HarnessgramSettingsUI
import HarnessgramSettings

/// Build 23: the Cockpit tab's section headers carry their counts, and its copy stays Hebrew only.
final class HouseCockpitTabUITests: XCTestCase {
    func testSectionHeadersShowTheirCountAndNoCountAtZero() {
        XCTAssertEqual(HouseCockpitStrings.header(HouseCockpitStrings.decisionsHeader, count: 2), "אישורי המראה · 2")
        XCTAssertEqual(HouseCockpitStrings.header(HouseCockpitStrings.tasksHeader, count: 0), "לוח טיסה")
    }

    func testTheCopyHasNoLatinLetters() {
        let lines = [HouseCockpitStrings.tabTitle, HouseCockpitStrings.decisionsHeader, HouseCockpitStrings.tasksHeader, HouseCockpitStrings.radioHeader, HouseCockpitStrings.fullCockpit, HouseCockpitStrings.notPairedTitle, HouseCockpitStrings.notPairedDetail, HouseCockpitStrings.pausedDetail, HouseCockpitStrings.emptyTitle, HouseCockpitStrings.emptyDetail, HouseCockpitStrings.waitingRow, HouseCockpitStrings.waitingRowDetail, HouseCockpitStrings.floatingButton, HouseCockpitStrings.floatingButtonHint, HouseCockpitStrings.taskLanded, HouseCockpitStrings.sendFailed]
        for line in lines + [HouseCockpitStrings.originalText, HouseCockpitStrings.originalYes, HouseCockpitStrings.originalNo, HouseCockpitStrings.loading, HouseCockpitStrings.unavailableTitle, HouseCockpitStrings.unavailableNoAnswer, HouseCockpitStrings.retry, HouseCockpitStrings.phoneOverview, HouseCockpitStrings.phoneFeet, HouseCockpitStrings.phoneNoFlight, HouseCockpitStrings.phoneLeadFlight, HouseCockpitStrings.phoneOpenRoomHint, HouseCockpitStrings.phoneFlying(1), HouseCockpitStrings.phoneFlying(3), HouseCockpitStrings.phoneMoreAgents(1), HouseCockpitStrings.phoneMoreAgents(4)] {
            XCTAssertNil(line.range(of: "[A-Za-z]", options: .regularExpression), line)
        }
    }

    func testThePhoneTowerStepLine() {
        XCTAssertEqual(HouseCockpitStrings.phoneStepLine(position: (3, 5), step: "בדיקות", finished: false), "שלב 3 מתוך 5 · בדיקות")
        XCTAssertEqual(HouseCockpitStrings.phoneStepLine(position: nil, step: "בדיקות", finished: false), "בדיקות")
        XCTAssertEqual(HouseCockpitStrings.phoneStepLine(position: nil, step: "", finished: false), "")
        XCTAssertEqual(HouseCockpitStrings.phoneStepLine(position: (5, 5), step: "העלאה", finished: true), HouseCockpitStrings.taskLanded)
    }

    func testTheAdditionsPageListsBothCockpitSwitchesWithTheirDefaults() {
        XCTAssertTrue(HarnessgramAddition.allCases.contains(.cockpitTab))
        XCTAssertTrue(HarnessgramAddition.allCases.contains(.cockpitFloatingButton))
        let suite = "HouseCockpitTabUITests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let state = HarnessgramAdditionsState.current(settings: HarnessgramSettings(defaults: defaults), filter: .shared, widgetsConnected: false)
        XCTAssertEqual(state.row(.cockpitTab), .toggle(true))
        XCTAssertEqual(state.row(.cockpitFloatingButton), .toggle(false))
    }
}
