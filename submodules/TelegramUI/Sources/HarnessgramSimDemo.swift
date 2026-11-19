import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import AccountContext
import HarnessgramSettings
import HarnessgramSettingsUI
import HarnessgramCockpitSync
import HarnessgramHouseUI

#if targetEnvironment(simulator)
/// Simulator only: drives the House screens for the logged-in screenshot gate (no taps needed). Launch with
/// HARNESSGRAM_DEMO_STEP = theme | radio | knock (knock also needs HARNESSGRAM_DEMO_HOUSE=1). Made-up data only;
/// a device build compiles it out. Build 23: HARNESSGRAM_DEMO_THEME = a Harnessgram theme's raw value (cockpitNight,
/// runwayDawn, openSky, instruments) with the steps theme-chatlist and theme-chat, for the contrast review; and the
/// step cockpit opens the Cockpit tab with the demo feed; cockpit-tower (with HARNESSGRAM_DEMO_HOUSE=1) opens it with
/// the House demo's flights, for the wide layout.
final class HarnessgramSimDemo {
    static let shared = HarnessgramSimDemo()

    private var started = false
    private var source: DemoRadio?

    private final class DemoRadio: HarnessgramNowPlayingSource {
        var isActive: Bool { true }
        var isPlaying: Bool { true }
        var liveTitle: String? { "שיעור הבוקר בשידור חי" }
        func togglePlayPause() {}
        func close() {}
        func open() {}
    }

    private static func scroll(_ view: UIView, by offset: CGFloat) {
        if let scrollView = view as? UIScrollView, scrollView.contentSize.height > scrollView.bounds.height {
            let maxOffset = scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom
            scrollView.setContentOffset(CGPoint(x: 0.0, y: min(offset, maxOffset)), animated: false)
            return
        }
        for subview in view.subviews {
            HarnessgramSimDemo.scroll(subview, by: offset)
        }
    }

    func start(context: AccountContext, navigationController: NavigationController) {
        guard !self.started, let step = ProcessInfo.processInfo.environment["HARNESSGRAM_DEMO_STEP"] else {
            return
        }
        self.started = true
        NSLog("[HarnessgramSimDemo] start \(step)")
        // HARNESSGRAM_DEMO_ORIENTATION=landscape turns an iPad simulator sideways (simctl cannot rotate a device).
        if ProcessInfo.processInfo.environment["HARNESSGRAM_DEMO_ORIENTATION"] == "landscape", #available(iOS 16.0, *) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
                    scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeRight), errorHandler: { error in
                        NSLog("[HarnessgramSimDemo] rotate failed: \(error)")
                    })
                }
            }
        }
        if let raw = ProcessInfo.processInfo.environment["HARNESSGRAM_DEMO_THEME"], let theme = HarnessgramSettings.Theme(rawValue: raw) {
            HarnessgramSettings.shared.theme = theme
            NSLog("[HarnessgramSimDemo] theme \(raw)")
        }
        switch step {
        case "theme-chatlist":
            break
        case "theme-chat":
            // The demo bridge bot's chat (HarnessgramDemoSeed's made-up bot, user 990000002).
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                let peerId = EnginePeer.Id(namespace: Namespaces.Peer.CloudUser, id: EnginePeer.Id.Id._internalFromInt64Value(990000002))
                let _ = (context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: peerId))
                |> deliverOnMainQueue).start(next: { peer in
                    guard let peer else {
                        NSLog("[HarnessgramSimDemo] theme-chat: no demo chat")
                        return
                    }
                    context.sharedContext.navigateToChatController(NavigateToChatControllerParams(navigationController: navigationController, context: context, chatLocation: .peer(peer)))
                    NSLog("[HarnessgramSimDemo] theme-chat open")
                })
            }
        case "cockpit":
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                HarnessgramCockpitSync.shared.demoConnect(context: context)
                harnessgramOpenCockpit(context: context)
                NSLog("[HarnessgramSimDemo] cockpit open")
            }
        case "cockpit-tower":
            // The Cockpit tab with the House demo feed (needs HARNESSGRAM_DEMO_HOUSE=1): on an iPad or the unfolded
            // phone the tower list with the first task's desk beside it, on a phone the phone tower
            // (HARNESSGRAM_DEMO_TOWER_PHONE=off: the phone list).
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                HarnessgramCockpitSync.shared.demoConnect(context: context)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    HarnessgramCockpitSync.shared.startHouseDemoIfRequested()
                    harnessgramOpenCockpit(context: context)
                    NSLog("[HarnessgramSimDemo] cockpit-tower open")
                    // HARNESSGRAM_DEMO_SCROLL_END=1: the end of the list (the full Cockpit button), for the button check;
                    // HARNESSGRAM_DEMO_SCROLL_TO=<points>: that far down (the middle of a long list).
                    let environment = ProcessInfo.processInfo.environment
                    let offset: CGFloat? = environment["HARNESSGRAM_DEMO_SCROLL_END"] == "1" ? 100000.0 : environment["HARNESSGRAM_DEMO_SCROLL_TO"].flatMap { Double($0) }.map { CGFloat($0) }
                    if let offset {
                        for delay in [3.0, 4.5] {
                            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                                if let view = navigationController.topViewController?.view {
                                    HarnessgramSimDemo.scroll(view, by: offset)
                                }
                            }
                        }
                    }
                }
            }
        case "native-cockpit", "native-decisions", "native-decision":
            // The native Cockpit with the House demo feed (needs HARNESSGRAM_DEMO_HOUSE=1 and its switch on): its home,
            // the decisions list, or the first decision's page.
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                HarnessgramCockpitSync.shared.demoConnect(context: context)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    HarnessgramCockpitSync.shared.startHouseDemoIfRequested()
                    harnessgramOpenCockpit(context: context)
                    NSLog("[HarnessgramSimDemo] \(step) open")
                    guard step != "native-cockpit" else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        let root = context.sharedContext.mainWindow?.viewController as? TelegramRootController
                        if let tab = root?.rootTabController?.controllers.first(where: { isNativeCockpitTabController($0) }) {
                            nativeCockpitDemoOpen(tab, page: step == "native-decision" ? "decision" : "decisions")
                        }
                    }
                }
            }
        case "theme":
            // The launcher stores the theme switch off; it turns on while the app runs, as from Settings.
            DispatchQueue.main.asyncAfter(deadline: .now() + 8.0) {
                HarnessgramSettings.shared.setHouseFeature(.theme, true)
                NSLog("[HarnessgramSimDemo] theme on")
            }
        case "radio":
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
                let source = DemoRadio()
                self.source = source
                HarnessgramNowPlaying.register(source)
                HarnessgramNowPlaying.notifyChanged()
                navigationController.pushViewController(harnessgramRadioController(context: context))
                NSLog("[HarnessgramSimDemo] radio open")
            }
        case "radio-bar":
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                let source = DemoRadio()
                self.source = source
                HarnessgramNowPlaying.register(source)
                HarnessgramNowPlaying.notifyChanged()
                NSLog("[HarnessgramSimDemo] radio bar")
            }
        case "settings", "pairing-connected", "pairing-failed":
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                if step == "pairing-connected" {
                    HarnessgramCockpitSync.shared.demoConnect(context: context)
                }
                navigationController.pushViewController(harnessgramSettingsController(context: context))
                if step != "settings" {
                    // The pairing row is below the first screen: scroll the list down to it.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
                        if let view = navigationController.topViewController?.view {
                            HarnessgramSimDemo.scroll(view, by: 520.0)
                        }
                    }
                }
                NSLog("[HarnessgramSimDemo] \(step) open")
            }
        case "house-defaults":
            // Settings > Harnessgram scrolled to "תצוגה מקדימה: הבית" (the launcher clears the owner's choices first).
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                navigationController.pushViewController(harnessgramSettingsController(context: context))
                // Three passes: the list grows as it scrolls, so a later pass reaches the end.
                for delay in [3.0, 4.5, 6.0] {
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                        if let view = navigationController.topViewController?.view {
                            HarnessgramSimDemo.scroll(view, by: 100000.0)
                        }
                    }
                }
                NSLog("[HarnessgramSimDemo] \(step) open")
            }
        case "additions":
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                navigationController.pushViewController(harnessgramAdditionsController(context: context, openWidgets: {}))
                NSLog("[HarnessgramSimDemo] additions open")
            }
        case "filter":
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                navigationController.pushViewController(harnessgramFilterController(context: context))
                NSLog("[HarnessgramSimDemo] filter open")
            }
        case "knock":
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
                // A clean slate: a session for the demo account, and no decision already marked as knocked.
                HarnessgramCockpitSync.shared.demoActivate(context: context)
                UserDefaults.standard.removeObject(forKey: "HarnessgramHouse.knocked." + String(context.account.peerId.id._internalGetInt64Value()))
                HouseKnockCenter.shared.poke(context: context, message: HouseKnockMessage(key: "demo:1", text: "למזג את תיקון ההתחברות?", chatTitle: "גשר", openRoomLink: nil))
                HarnessgramCockpitSync.shared.startHouseDemoIfRequested()
                NSLog("[HarnessgramSimDemo] knock")
            }
        default:
            break
        }
    }
}
#endif
