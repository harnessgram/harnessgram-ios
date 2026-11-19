import Foundation

/// What waits for the owner in the Cockpit (build 23), one number for every place that shows it: the Cockpit tab's
/// badge, the floating button, and the app icon. The same sources as the widgets: the open decisions (the full list
/// when the app has it, else the widget snapshot's count, which is never smaller than its own lines) plus the owner's
/// open reminders. The waiting list is the open decisions, so it is not counted twice. The bridge's snapshot does not
/// carry reminders yet; they count as 0 until it does.
public enum HarnessgramCockpitWaiting {
    public static func count(snapshot: HarnessgramCockpitSnapshot?, openDecisions: [HarnessgramCockpitSnapshot.Decision]?, reminders: Int = 0, isConnected: Bool) -> Int {
        guard isConnected else {
            return 0
        }
        let decisions = max(snapshot?.waitingCount ?? 0, snapshot?.decisions.count ?? 0, openDecisions?.count ?? 0)
        return max(0, decisions) + max(0, reminders)
    }

    public static func count(state: HarnessgramCockpitStore.ViewState?, reminders: Int = 0) -> Int {
        guard let state else { return 0 }
        return self.count(snapshot: state.snapshot, openDecisions: state.openDecisions, reminders: reminders, isConnected: !state.isPaused && state.session != nil && state.hasLogin)
    }

    /// The badge's text: nil at 0 (no badge), the number otherwise, "99+" above 99.
    public static func badgeText(_ count: Int) -> String? {
        guard count > 0 else {
            return nil
        }
        return count > 99 ? "99+" : "\(count)"
    }

    /// The app icon's number: Telegram's own unread count, plus what waits in the Cockpit while the owner keeps the
    /// "סימון על סמל האפליקציה" switch on.
    public static func appBadge(telegramUnread: Int, waiting: Int, include: Bool) -> Int {
        return max(0, telegramUnread) + (include ? max(0, waiting) : 0)
    }

    /// The count from what this device stored last.
    public static func current(store: HarnessgramCockpitStore = .shared) -> Int {
        return self.count(state: store.viewState())
    }
}
