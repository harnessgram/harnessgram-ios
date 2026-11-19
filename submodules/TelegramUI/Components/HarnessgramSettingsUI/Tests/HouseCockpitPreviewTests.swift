import XCTest
import Display
import HarnessgramCockpitKit
import HarnessgramHouseCore
@testable import HarnessgramCockpitSync
@testable import HarnessgramSettings
@testable import HarnessgramSettingsUI

final class HouseCockpitPreviewTests: XCTestCase {
    @MainActor
    func testPreviewActionsLeaveHostCallbacksAndLiveRefreshFailureUntouched() async throws {
        let sync = HarnessgramCockpitSync.shared
        let previousFailure = sync.lastRefreshFailure
        let settings = HarnessgramSettings.shared
        let keys = [HarnessgramSettings.Key.houseWaitingList, .houseWaitingListChosen]
        let previousSettings = keys.map { settings.defaults.object(forKey: $0.rawValue) }
        defer {
            for (key, value) in zip(keys, previousSettings) {
                settings.defaults.set(value, forKey: key.rawValue)
            }
            sync.setRefreshFailure(previousFailure)
        }
        settings.setHouseFeature(.waitingList, true)
        sync.setRefreshFailure(.panelUnreachable)
        let noRefreshChange = self.expectation(description: "Preview must not post a live refresh change")
        noRefreshChange.isInverted = true
        let observer = NotificationCenter.default.addObserver(forName: HarnessgramCockpitSync.refreshStatusDidChangeNotification, object: nil, queue: .main) { _ in
            noRefreshChange.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        let tab = HarnessgramCockpitTabViewModel.make(snapshot: .houseDemo, openDecisions: nil, isPaired: true, isPaused: false)
        let model = HouseCockpitTabModel(preview: tab)
        var callbackCount = 0
        model.openWaitingListScreen = { callbackCount += 1 }
        model.listStyleChanged = { _ in callbackCount += 1 }
        let controller = ViewController(navigationBarPresentationData: nil)
        controller.tabBarItem.badgeValue = "preview"
        model.controller = controller

        model.openWaitingList()
        model.retry()
        model.applyListStyle()
        model.start()
        model.reload()
        await model.refreshAndWait()
        model.pair()
        model.openFullCockpit()
        model.openRadio()
        model.toggleRadio()
        let decision = try XCTUnwrap(tab.decisions.first)
        model.answer(decision, .yes)
        model.approveWithFaceID(decision)
        model.openRoom(decision)
        let task = try XCTUnwrap(tab.tasks.first)
        model.openTask(task)
        model.select(task)
        model.moveSelection(by: 1)
        model.stop()

        XCTAssertEqual(callbackCount, 0)
        XCTAssertEqual(sync.lastRefreshFailure, .panelUnreachable)
        XCTAssertEqual(controller.tabBarItem.badgeValue, "preview")
        XCTAssertEqual(model.tab, tab)
        XCTAssertNil(model.selectedTaskId)
        XCTAssertTrue(model.rowStates.isEmpty)
        XCTAssertFalse(model.pairing)
        XCTAssertFalse(model.openingCockpit)
        await fulfillment(of: [noRefreshChange], timeout: 0.05)
    }
}
