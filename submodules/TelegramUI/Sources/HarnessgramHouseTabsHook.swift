import Foundation
import UIKit
import Display
import AccountContext
import HarnessgramSettings
import HarnessgramHouseCore
import HarnessgramHouseUI
import HarnessgramSettingsUI

/// Harnessgram House (plan step 0 hook): the tab list of the root tab bar. TelegramRootController calls this with the
/// tabs Telegram built, in `addRootControllers` and `updateRootControllers`, and uses what it returns. Nothing changes
/// until a lane fills it in: step 2 adds the Home tab (behind `.homeTab`) and step 6 the radio tab (`.radioTab`), and
/// each returns `controllers` untouched while its switch is off. Lane A owns the body.
///
/// Build 23: the Cockpit tab (`HarnessgramSettings.cockpitTab`, on by default) right after Chats, and the optional floating
/// Cockpit button over the chat list (`cockpitFloatingButton`, off by default; the button hides itself while it is off).
/// The native Cockpit (`HouseFeature.nativeCockpit`, off by default) takes the tab's place while its switch is on.
func harnessgramHouseTabs(_ controllers: [ViewController], context: AccountContext) -> [ViewController] {
    let cockpit = HarnessgramCockpitTabCache.controller(context: context)
    let arranged = HarnessgramCockpitTabPlacement.arrange(controllers, cockpit: cockpit, include: HarnessgramCockpitTabPlacement.isIncluded(), isChats: { $0 is ChatListController }, isCockpit: { harnessgramIsCockpitTab($0) })
    if let chatList = controllers.first(where: { $0 is ChatListController }) {
        harnessgramInstallCockpitFloatingButton(chatList: chatList, context: context)
    }
    return arranged
}

/// Either Cockpit tab: the tower page or the native Cockpit.
private func harnessgramIsCockpitTab(_ controller: ViewController) -> Bool {
    return isHouseCockpitTabController(controller) || isNativeCockpitTabController(controller)
}

/// The Cockpit screen the switches ask for now: the native Cockpit while its switch is on, otherwise the tower page.
private func harnessgramMakeCockpitScreen(context: AccountContext) -> ViewController {
    if HarnessgramSettings.shared.houseFeature(.nativeCockpit) {
        return makeNativeCockpitTabController(context: context)
    }
    return makeHouseCockpitTabController(context: context, openWaitingList: { [weak context] in
        if let context {
            openHouseWaitingList(context: context)
        }
    })
}

/// One Cockpit tab per account context and look: the tab list is rebuilt when a tab switch changes, and the same screen
/// comes back; turning the native Cockpit on or off builds the other screen.
private enum HarnessgramCockpitTabCache {
    private static weak var context: AccountContext?
    private static var cached: ViewController?
    private static var cachedNative = false

    static func controller(context: AccountContext) -> ViewController {
        let native = HarnessgramSettings.shared.houseFeature(.nativeCockpit)
        if let cached = HarnessgramCockpitTabCache.cached, HarnessgramCockpitTabCache.context === context, HarnessgramCockpitTabCache.cachedNative == native {
            return cached
        }
        let controller = harnessgramMakeCockpitScreen(context: context)
        HarnessgramCockpitTabCache.context = context
        HarnessgramCockpitTabCache.cached = controller
        HarnessgramCockpitTabCache.cachedNative = native
        return controller
    }
}

/// Opens the Cockpit: its tab when the tab is on, otherwise the same screen pushed over the chats.
func harnessgramOpenCockpit(context: AccountContext) {
    guard let root = context.sharedContext.mainWindow?.viewController as? TelegramRootController else {
        return
    }
    if let tabs = root.rootTabController, let index = tabs.controllers.firstIndex(where: { harnessgramIsCockpitTab($0) }) {
        root.popToRoot(animated: true)
        tabs.selectedIndex = index
    } else {
        root.pushViewController(harnessgramMakeCockpitScreen(context: context))
    }
}

/// Puts the floating button's layer over the chat list's view once the chat list has loaded (it hides itself while its
/// switch is off). Tries again shortly when the chat list is not loaded yet.
private func harnessgramInstallCockpitFloatingButton(chatList: ViewController, context: AccountContext, attempt: Int = 0) {
    DispatchQueue.main.async { [weak chatList, weak context] in
        guard let chatList, let context else {
            return
        }
        guard chatList.isNodeLoaded else {
            if attempt < 20 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: { [weak chatList, weak context] in
                    if let chatList, let context {
                        harnessgramInstallCockpitFloatingButton(chatList: chatList, context: context, attempt: attempt + 1)
                    }
                })
            }
            return
        }
        let host = chatList.displayNode.view
        if host.subviews.contains(where: { $0 is HouseCockpitFloatingLayer }) {
            return
        }
        let layer = HouseCockpitFloatingLayer(insets: { [weak chatList] in
            guard let chatList, let layout = chatList.currentlyAppliedLayout else {
                return .zero
            }
            let top = chatList.navigationLayout(layout: layout).navigationFrame.maxY
            return UIEdgeInsets(top: top, left: 0.0, bottom: max(layout.intrinsicInsets.bottom, layout.safeInsets.bottom), right: 0.0)
        }, open: { [weak context] in
            if let context {
                harnessgramOpenCockpit(context: context)
            }
        })
        layer.setAccentColor(context.sharedContext.currentPresentationData.with { $0 }.theme.list.itemAccentColor)
        layer.frame = host.bounds
        host.addSubview(layer)
    }
}

/// Calls `update` when a switch that changes the tab list is turned on or off (Home tab, radio tab, Cockpit tab, native
/// Cockpit), so the tab bar
/// follows at once, as for the calls tab. Hold the returned object for as long as the observation should last.
func harnessgramHouseObserveTabs(_ update: @escaping () -> Void) -> HarnessgramHouseTabsObserver {
    return HarnessgramHouseTabsObserver(update: update)
}

final class HarnessgramHouseTabsObserver {
    private var observer: NSObjectProtocol?
    private var lastState: [Bool]

    init(update: @escaping () -> Void) {
        let state: () -> [Bool] = {
            return [HarnessgramSettings.shared.houseFeature(.homeTab), HarnessgramSettings.shared.houseFeature(.radioTab), HarnessgramSettings.shared.cockpitTab, HarnessgramSettings.shared.houseFeature(.nativeCockpit)]
        }
        self.lastState = state()
        self.observer = NotificationCenter.default.addObserver(forName: HarnessgramSettings.didChangeNotification, object: nil, queue: .main, using: { [weak self] _ in
            guard let self else {
                return
            }
            let current = state()
            if current != self.lastState {
                self.lastState = current
                update()
            }
        })
    }

    deinit {
        if let observer = self.observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}
