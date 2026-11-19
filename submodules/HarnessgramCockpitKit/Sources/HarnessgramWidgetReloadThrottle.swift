import Foundation
import HarnessgramSettings

/// Near-real-time widgets: the Notification Service Extension asks WidgetKit to reload the Cockpit widgets when a bridge
/// notification arrives, at most once per widget kind every five minutes, because iOS gives each widget a small daily
/// reload budget. The widgets' own 15-minute timeline stays the fallback. The last reload time per kind lives in the app
/// group's defaults so every extension process shares it.
public struct HarnessgramWidgetReloadThrottle {
    /// The Cockpit widget kinds a bridge notification refreshes (the values of HarnessgramTodayWidget.kind and
    /// HarnessgramWidgetKind.waiting; kept here because the extension does not link the widget UI module).
    public static let bridgeWidgetKinds = ["HarnessgramToday", "HarnessgramWaiting"]
    public static let minimumInterval: TimeInterval = 5 * 60
    static let keyPrefix = "HarnessgramCockpit.widgetReload."

    private let defaults: UserDefaults
    private let now: () -> Date
    private let interval: TimeInterval

    public init(defaults: UserDefaults = HarnessgramSettings.appGroupDefaults(), now: @escaping () -> Date = Date.init, interval: TimeInterval = HarnessgramWidgetReloadThrottle.minimumInterval) {
        self.defaults = defaults
        self.now = now
        self.interval = interval
    }

    /// True (and the time is recorded) when this kind may reload now; false while the last reload is younger than the
    /// interval. A recorded time in the future (clock moved back) counts as stale, so a wrong clock never blocks for long.
    public func claim(kind: String) -> Bool {
        let key = HarnessgramWidgetReloadThrottle.keyPrefix + kind
        let current = self.now()
        if let last = self.defaults.object(forKey: key) as? Date {
            let age = current.timeIntervalSince(last)
            if age >= 0 && age < self.interval {
                return false
            }
        }
        self.defaults.set(current, forKey: key)
        return true
    }

    /// The kinds to reload now for one bridge notification (each claimed, in order).
    public func claimBridgeKinds() -> [String] {
        return HarnessgramWidgetReloadThrottle.bridgeWidgetKinds.filter { self.claim(kind: $0) }
    }
}
