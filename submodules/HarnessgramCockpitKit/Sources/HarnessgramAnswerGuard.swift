import Foundation

/// One answer in flight or completed per decision. An answer with an unknown outcome is blocked for up to a day,
/// including across app launches. A stale list with no delivery receipt is insufficient evidence to retry sooner.
public struct HarnessgramAnswerGuard: Equatable {
    public static let uncertainHold: TimeInterval = 24 * 60 * 60
    private static let maxUncertainEntries = 64
    private static let defaultsKey = "Harnessgram.nativeCockpit.uncertainAnswers"

    public enum Outcome: Equatable {
        case done
        case notSent
        case uncertain
    }

    public enum TimedBlock: Equatable {
        case busy(until: Date)
        case uncertain(until: Date)

        public var until: Date {
            switch self {
            case let .busy(until), let .uncertain(until):
                return until
            }
        }
    }

    private var inFlight: Set<String> = []
    private var done: Set<String> = []
    private var busyUntil: [String: Date] = [:]
    private var uncertainSince: [String: Date] = [:]

    public init() {
    }

    /// Only ambiguous sends survive a launch. Never store the login, decision text, or answer.
    public init(defaults: UserDefaults, now: Date) {
        self.uncertainSince = defaults.dictionary(forKey: Self.defaultsKey)?.compactMapValues { $0 as? Date } ?? [:]
        self.pruneUncertain(now: now)
    }

    public func saveUncertain(to defaults: UserDefaults) {
        defaults.set(self.uncertainSince, forKey: Self.defaultsKey)
    }

    public static func key(account: Int64, decisionId: String) -> String {
        return "\(account)|\(decisionId)"
    }

    /// True when the app can start work on this answer, including any owner confirmation.
    public mutating func begin(_ key: String, now: Date, stillOpen: Bool, hasDelivery: Bool) -> Bool {
        self.pruneUncertain(now: now)
        self.busyUntil = self.busyUntil.filter { $0.value > now }
        guard stillOpen, !hasDelivery, !self.inFlight.contains(key), !self.done.contains(key), self.timedBlock(key, now: now) == nil else {
            return false
        }
        self.inFlight.insert(key)
        return true
    }

    /// Reserve the uncertainty block before starting the request so a quit before the reply is conservative too.
    public mutating func markSending(_ key: String, now: Date) {
        self.uncertainSince[key] = now
        self.pruneUncertain(now: now)
    }

    public mutating func finish(_ key: String, result: HarnessgramDecisionAnswer.Result, now: Date) {
        self.inFlight.remove(key)
        self.uncertainSince[key] = nil
        switch result.guardOutcome {
        case .done:
            self.done.insert(key)
        case .notSent:
            if case let .busy(retryAfter?) = result, retryAfter.isFinite, retryAfter > 0 {
                self.busyUntil[key] = now.addingTimeInterval(retryAfter)
            }
        case .uncertain:
            self.markSending(key, now: now)
        }
    }

    public func timedBlock(_ key: String, now: Date) -> TimedBlock? {
        if !self.inFlight.contains(key), let since = self.uncertainSince[key] {
            let until = since.addingTimeInterval(Self.uncertainHold)
            if now < until {
                return .uncertain(until: until)
            }
        }
        if let until = self.busyUntil[key], now < until {
            return .busy(until: until)
        }
        return nil
    }

    private mutating func pruneUncertain(now: Date) {
        self.uncertainSince = self.uncertainSince.filter { now.timeIntervalSince($0.value) < Self.uncertainHold }
        if self.uncertainSince.count > Self.maxUncertainEntries {
            let newest = self.uncertainSince.sorted { lhs, rhs in
                lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value > rhs.value
            }.prefix(Self.maxUncertainEntries)
            self.uncertainSince = Dictionary(uniqueKeysWithValues: newest.map { ($0.key, $0.value) })
        }
    }

    /// An answer login must use the HTTPS host and port that served the displayed decision.
    public static func sameOrigin(shown: URL?, minted: URL?) -> Bool {
        guard let shown, let minted, shown.scheme?.lowercased() == "https", minted.scheme?.lowercased() == "https",
              let host = shown.host?.lowercased(), !host.isEmpty else {
            return false
        }
        return host == minted.host?.lowercased() && (shown.port ?? 443) == (minted.port ?? 443)
    }

    public func isBlocked(_ key: String, now: Date) -> Bool {
        return self.inFlight.contains(key) || self.done.contains(key) || self.timedBlock(key, now: now) != nil
    }
}

extension HarnessgramDecisionAnswer.Result {
    public var guardOutcome: HarnessgramAnswerGuard.Outcome {
        switch self {
        case .sent, .alreadyClosed:
            return .done
        case .notConfirmed, .cancelledLocally, .loginExpired, .busy, .notAllowed:
            return .notSent
        case .failed:
            return .uncertain
        }
    }
}
