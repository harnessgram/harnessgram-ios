import Foundation
import WatchConnectivity

/// The approved-chats list for the watch app (Telegram/WatchApp, package HarnessgramWatchPolicy). The wire format must
/// stay identical to `HarnessgramWatchAllowlist` there: the same field names, JSONEncoder's default date encoding, and the
/// application-context key below. The watch shows nothing without a current list for its own account.
public struct HarnessgramWatchAllowlistPayload: Codable, Equatable {
    public static let currentVersion = 1
    public static let contextKey = "harnessgram.allowlist.v1"
    /// At most this many chats go to the watch (the newest of the chat list).
    public static let maxChats = 200

    public let version: Int
    public let accountUserId: Int64
    public let allowedChatIds: [Int64]
    public let textOnlyChatIds: [Int64]
    public let issuedAt: Date

    public init(accountUserId: Int64, allowedChatIds: [Int64], textOnlyChatIds: [Int64], issuedAt: Date) {
        self.version = HarnessgramWatchAllowlistPayload.currentVersion
        self.accountUserId = accountUserId
        self.allowedChatIds = Array(allowedChatIds.prefix(HarnessgramWatchAllowlistPayload.maxChats))
        let allowed = Set(self.allowedChatIds)
        self.textOnlyChatIds = textOnlyChatIds.filter { allowed.contains($0) }
        self.issuedAt = issuedAt
    }

    /// Nothing allowed (no account, or more than one logged-in account): the watch shows its "open the iPhone" message.
    public static func denyAll(issuedAt: Date) -> HarnessgramWatchAllowlistPayload {
        return HarnessgramWatchAllowlistPayload(accountUserId: 0, allowedChatIds: [], textOnlyChatIds: [], issuedAt: issuedAt)
    }

    public func applicationContext() throws -> [String: Any] {
        return [HarnessgramWatchAllowlistPayload.contextKey: try JSONEncoder().encode(self)]
    }

    /// Same chats and account (the time is not compared), so an unchanged list is not sent again.
    public func sameChats(as other: HarnessgramWatchAllowlistPayload) -> Bool {
        return self.accountUserId == other.accountUserId && self.allowedChatIds == other.allowedChatIds && self.textOnlyChatIds == other.textOnlyChatIds
    }
}

/// TDLib's chat id for a Telegram peer (what the watch app's TDLib client sees).
public enum HarnessgramWatchChatId {
    public enum Kind {
        case user
        case basicGroup
        case channel
        /// Never sent: secret chats live on one device only.
        case secretChat
    }

    public static func tdlib(kind: Kind, id: Int64) -> Int64? {
        guard id > 0 else {
            return nil
        }
        switch kind {
        case .user:
            return id
        case .basicGroup:
            return -id
        case .channel:
            return -(1_000_000_000_000 + id)
        case .secretChat:
            return nil
        }
    }
}

/// Sends the list to the paired watch. Main queue. An unchanged list is re-sent only once a day (so its issued time stays
/// inside the watch's seven-day window).
public final class HarnessgramWatchLink: NSObject, WCSessionDelegate {
    public static let shared = HarnessgramWatchLink()
    static let resendInterval: TimeInterval = 24 * 60 * 60

    private var pending: HarnessgramWatchAllowlistPayload?
    private var lastSent: HarnessgramWatchAllowlistPayload?
    private var activated = false

    public func publish(_ payload: HarnessgramWatchAllowlistPayload) {
        assert(Thread.isMainThread)
        guard WCSession.isSupported() else {
            return
        }
        if let lastSent, lastSent.sameChats(as: payload), payload.issuedAt.timeIntervalSince(lastSent.issuedAt) < HarnessgramWatchLink.resendInterval {
            return
        }
        self.pending = payload
        let session = WCSession.default
        if !self.activated {
            self.activated = true
            session.delegate = self
            session.activate()
            return
        }
        self.flush()
    }

    private func flush() {
        let session = WCSession.default
        guard let payload = self.pending, session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else {
            return
        }
        do {
            try session.updateApplicationContext(try payload.applicationContext())
            self.lastSent = payload
            self.pending = nil
        } catch {
        }
    }

    public func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async {
            self.flush()
        }
    }

    public func sessionDidBecomeInactive(_ session: WCSession) {
    }

    public func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    public func sessionWatchStateDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            self.flush()
        }
    }
}
