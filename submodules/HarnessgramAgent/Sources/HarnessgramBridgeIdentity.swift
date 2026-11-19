import Foundation
import HarnessgramSettings

/// Who the Harnessgram bridge is, by its immutable Telegram user id (a username can be reassigned to another bot).
///
/// Build 15 (review P1): the id is never taken from the username (no trust on first use). It is pinned only from the
/// bridge's own authenticated Cockpit panel response (`bot_id`, from the bridge's getMe), which reaches the app over the
/// configured private bridge address with the user's Telegram-signed login. Until that happens the bridge has no privileges at all:
/// its decision widgets stay hidden and its buttons get no marker exemption (they ask for Face ID). If the panel later
/// names a different id, every privilege stops until the owner confirms the new bot in Settings > Harnessgram (Face ID).
public final class HarnessgramBridgeIdentity {
    public static let shared = HarnessgramBridgeIdentity(settings: .shared)

    public enum State: Equatable {
        /// Not resolved yet: no bot has bridge privileges.
        case unknown
        case pinned(Int64)
        /// The username now points at `seen`; nothing has bridge privileges until the owner confirms it.
        case changed(pinned: Int64, seen: Int64)
    }

    private let settings: HarnessgramSettings
    private let lock = NSLock()

    public init(settings: HarnessgramSettings) {
        self.settings = settings
    }

    public var state: State {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.stateLocked()
    }

    /// The only trusted origin of a pin: the bridge's own panel.
    public static let panelSource = "panel"

    private func stateLocked() -> State {
        guard let pinned = self.settings.bridgeBotId else {
            return .unknown
        }
        guard self.settings.bridgeBotIdSource == HarnessgramBridgeIdentity.panelSource else {
            // A pin from builds 13-14 (taken from the username) is not trusted: it is dropped, and the bridge has no
            // privileges until its panel names it.
            self.settings.bridgeBotId = nil
            self.settings.bridgeBotPendingId = nil
            return .unknown
        }
        if let pending = self.settings.bridgeBotPendingId, pending != pinned {
            return .changed(pinned: pinned, seen: pending)
        }
        return .pinned(pinned)
    }

    /// The bridge's panel reported its bot id. The first report pins it; the same id changes nothing (and clears a
    /// stale change); a different id is held as a change that needs the owner.
    public func observePanel(botId: Int64) {
        guard botId > 0 else {
            return
        }
        self.lock.lock()
        defer { self.lock.unlock() }
        switch self.stateLocked() {
        case .unknown:
            self.settings.bridgeBotId = botId
            self.settings.bridgeBotIdSource = HarnessgramBridgeIdentity.panelSource
            self.settings.bridgeBotPendingId = nil
        case let .pinned(pinned):
            if pinned != botId {
                self.settings.bridgeBotPendingId = botId
            }
        case let .changed(pinned, _):
            self.settings.bridgeBotPendingId = pinned == botId ? nil : botId
        }
    }

    /// Whether the Cockpit login may go to this bot: any bot before a pin exists (the login's private-origin check
    /// still applies), only the pinned bot once one does, and none while a change waits for the owner.
    public func mayLogIn(userId: Int64) -> Bool {
        switch self.state {
        case .unknown:
            return true
        case let .pinned(pinned):
            return pinned == userId
        case .changed:
            return false
        }
    }

    /// The owner confirmed the bot the username now resolves to (the caller asks for Face ID first).
    public func confirmChangedBot() {
        self.lock.lock()
        defer { self.lock.unlock() }
        if case let .changed(_, seen) = self.stateLocked() {
            self.settings.bridgeBotId = seen
            self.settings.bridgeBotIdSource = HarnessgramBridgeIdentity.panelSource
            self.settings.bridgeBotPendingId = nil
        }
    }

    /// True only for the pinned bridge bot, and never while a change waits for the owner.
    public func isBridge(userId: Int64?) -> Bool {
        guard let userId else {
            return false
        }
        if case let .pinned(pinned) = self.state {
            return pinned == userId
        }
        return false
    }
}
