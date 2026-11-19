import Foundation
import Display
import AccountContext
import HarnessgramHouseCore

/// The waiting list as a Telegram screen: a normal navigation screen (Telegram's bar, title and back button) with the House
/// list inside. The Home doorway opens it while `.waitingList` is on; with the switch off the doorway opens the bridge
/// bot's chat instead (Home's own fallback).
public func makeHouseWaitingListController(context: AccountContext) -> ViewController {
    let model = HouseWaitingModel(context: context)
    return HouseHostingController(context: context, title: HouseKnockStrings.t(.waitingTitle), hidesNavigationBar: false, content: HouseWaitingView(model: model))
}

/// Pushes the waiting list on the root navigation stack (the knock sheet's "and N more" line and the Home doorway use it).
public func openHouseWaitingList(context: AccountContext) {
    guard let navigationController = context.sharedContext.mainWindow?.viewController as? NavigationController else {
        return
    }
    navigationController.pushViewController(makeHouseWaitingListController(context: context))
}
