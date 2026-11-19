import Foundation
import UIKit
import UserNotifications
import HarnessgramSettings
import HarnessgramCockpitKit

/// The app icon's number (build 23): Telegram's own unread count (AppDelegate hands it here instead of setting the
/// icon itself) plus what waits in the Cockpit while "סימון על סמל האפליקציה" is on. It is applied again after every
/// snapshot sync, every switch change and every return to the foreground. UIKit stays on main; storage is read async.
public final class HarnessgramAppBadge {
    public static let shared = HarnessgramAppBadge()

    private var telegramUnread: Int?
    private var applied: Int?
    private var observers: [NSObjectProtocol] = []

    private init() {
        let center = NotificationCenter.default
        for name in [HarnessgramCockpitSync.snapshotDidChangeNotification, HarnessgramSettings.didChangeNotification, UIApplication.willEnterForegroundNotification, UIApplication.didBecomeActiveNotification] {
            self.observers.append(center.addObserver(forName: name, object: nil, queue: .main, using: { [weak self] _ in
                self?.apply()
            }))
        }
    }

    /// Telegram's unread count changed.
    public func setTelegramUnread(_ count: Int) {
        assert(Thread.isMainThread)
        self.telegramUnread = count
        self.apply()
    }

    /// Recomputes and sets the icon's number; nothing before Telegram's own count is known.
    public func apply() {
        assert(Thread.isMainThread)
        guard let telegramUnread = self.telegramUnread else {
            return
        }
        let include = HarnessgramSettings.shared.cockpitAppBadge
        let waiting: Int
        if include {
            HarnessgramCockpitSync.shared.refreshViewState()
            waiting = HarnessgramCockpitWaiting.count(state: HarnessgramCockpitSync.shared.viewState)
        } else {
            waiting = 0
        }
        let total = HarnessgramCockpitWaiting.appBadge(telegramUnread: telegramUnread, waiting: waiting, include: include)
        guard total != self.applied else {
            return
        }
        self.applied = total
        if #available(iOS 16.0, *) {
            UNUserNotificationCenter.current().setBadgeCount(total, withCompletionHandler: nil)
        } else {
            UIApplication.shared.applicationIconBadgeNumber = total
        }
    }
}
