import Foundation

/// When a task Live Activity that should carry a push token gets a new one, and how the app tells the bridge why a
/// token is missing (owner report: the bridge never received a token, so the cards only moved while the app ran).
///
/// An activity has no token when an older build (or the old silent fallback) requested it without push, or when the
/// token request itself failed. Such an activity used to be updated forever and never requested again. Now a live,
/// non-summary activity with no token after `grace` is ended and requested once more with a token, at most once per
/// card id (persisted, so it never loops across launches).
public enum HarnessgramLiveActivityTokenRule {
    /// How long a newly seen activity may wait for its token before it counts as missing.
    public static let grace: TimeInterval = 30
    /// The persisted list of card ids already requested again keeps only this many (newest last).
    public static let maxRetried = 64

    public static let noTokenAfterGrace = "no-token-after-grace"
    // The bridge also accepts "push-disabled", which the app never sends: iOS gives an app no per-activity
    // "push is off" signal (with Live Activities off, sync starts none and there is no card to report on).
    static let requestFailedPrefix = "request-failed"
    static let maxDetail = 64

    /// Whether this live activity is ended and requested again with a push token now.
    /// - Parameters:
    ///   - firstSeen: when this run first saw the activity (nil: not seen yet, so the grace has not started).
    ///   - retried: card ids already requested again (or whose token request failed) — never a second time.
    public static func shouldReplace(cardId: String, hasToken: Bool, firstSeen: Date?, now: Date, retried: [String]) -> Bool {
        guard cardId != HarnessgramTaskActivityPlan.summaryCardId, !hasToken, let firstSeen, !retried.contains(cardId) else {
            return false
        }
        return now.timeIntervalSince(firstSeen) >= grace
    }

    /// Whether the missing token is reported now: the activity was already requested again (or its request failed)
    /// and still has no token after the grace. Reported once per card and run (`reported`).
    public static func shouldReportMissing(cardId: String, hasToken: Bool, firstSeen: Date?, now: Date, retried: [String], reported: Set<String>) -> Bool {
        guard cardId != HarnessgramTaskActivityPlan.summaryCardId, !hasToken, let firstSeen, retried.contains(cardId), !reported.contains(cardId) else {
            return false
        }
        return now.timeIntervalSince(firstSeen) >= grace
    }

    /// The retried list with `cardId` added once, oldest dropped beyond `maxRetried`.
    public static func remember(_ cardId: String, in retried: [String]) -> [String] {
        var out = retried.filter { $0 != cardId }
        out.append(cardId)
        if out.count > maxRetried {
            out.removeFirst(out.count - maxRetried)
        }
        return out
    }

    /// `request-failed:<detail>`: the ActivityAuthorizationError case name and code when there is one, otherwise the
    /// error's domain and code. Only [A-Za-z0-9._-] are kept and the detail is at most 64 characters (its end, which
    /// carries the code), so it always passes the bridge's allow-list.
    public static func requestFailed(caseName: String?, domain: String, code: Int) -> String {
        let raw: String
        if let caseName, !caseName.isEmpty {
            raw = "\(caseName).\(code)"
        } else {
            raw = "\(domain).\(code)"
        }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-")
        var scalars = String.UnicodeScalarView()
        scalars.append(contentsOf: raw.unicodeScalars.filter { allowed.contains($0) })
        let kept = String(String(scalars).suffix(maxDetail))
        return kept.isEmpty ? requestFailedPrefix : "\(requestFailedPrefix):\(kept)"
    }

    /// The app's remote-notification registration as this run saw it (AppDelegate callbacks). Live Activity push
    /// tokens come through the same APNs registration, so a card without a token reports this state.
    public enum ApnsState: Equatable, Sendable {
        /// No callback yet in this run.
        case unknown
        /// didRegisterForRemoteNotificationsWithDeviceToken.
        case registered
        /// didFailToRegisterForRemoteNotificationsWithError, with the error's code.
        case failed(code: Int)
        /// Telegram's server answered TOKEN_WAS_INVALIDATED for the device token (its push cannot reach this bundle
        /// id); Harnessgram no longer unregisters for it.
        case invalidatedByServer
    }

    /// `request-failed:apns-<state>.unreg<n>` (n: unregisterForRemoteNotifications calls this run), sent instead of
    /// no-token-after-grace when a card passes the grace without a token. Always inside the bridge's allow-list.
    public static func apnsProblem(state: ApnsState, unregisterCalls: Int) -> String {
        let name: String
        switch state {
        case .unknown:
            name = "apns-unknown"
        case .registered:
            name = "apns-registered"
        case let .failed(code):
            name = "apns-fail.\(code)"
        case .invalidatedByServer:
            name = "apns-invalidated"
        }
        let detail = "\(name).unreg\(max(0, unregisterCalls))"
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-")
        var scalars = String.UnicodeScalarView()
        scalars.append(contentsOf: detail.unicodeScalars.filter { allowed.contains($0) })
        return "\(requestFailedPrefix):\(String(String(scalars).prefix(maxDetail)))"
    }

    /// The bridge's allow-list (src/ctb/panel.py LA_PROBLEM).
    public static func isProblemCode(_ code: String) -> Bool {
        if code == noTokenAfterGrace || code == requestFailedPrefix {
            return true
        }
        let prefix = requestFailedPrefix + ":"
        guard code.hasPrefix(prefix) else {
            return false
        }
        let detail = code.dropFirst(prefix.count)
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-")
        return (1 ... maxDetail).contains(detail.count) && detail.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    // MARK: The update loop

    /// What the update loop does for one planned card.
    public enum LoopAction: Equatable, Sendable {
        /// Update the live activity in place.
        case update
        /// Request a new activity with a push token first; end the old one only if that succeeded (`replaceSteps`).
        case replace
        /// No live activity: request one (with a push token; the summary without).
        case request
        /// Nothing now: ActivityKit refuses to start an activity while the app is not in the foreground
        /// (ActivityAuthorizationError.visibility). The card is pushed again by the next foreground sync.
        case wait
    }

    /// - Parameters:
    ///   - live: whether the card has a live activity (checked again after every await, so one card never gets two).
    ///   - liveHasToken: that activity's push token, read right before acting (it may have arrived meanwhile).
    ///   - markedForReplace: `shouldReplace` chose the card for a new activity in this sync.
    ///   - appActive: the app is in the foreground (UIApplication.applicationState == .active).
    public static func loopAction(cardId: String, live: Bool, liveHasToken: Bool, markedForReplace: Bool, appActive: Bool) -> LoopAction {
        if live {
            // The app-local overflow summary is never replaced (it has no token by design), nor is an activity whose
            // token arrived, nor anything while the app is not in the foreground.
            guard cardId != HarnessgramTaskActivityPlan.summaryCardId, markedForReplace, !liveHasToken, appActive else {
                return .update
            }
            return .replace
        }
        return appActive ? .request : .wait
    }

    /// One step of replacing an activity that has no push token.
    public enum ReplaceStep: Equatable, Sendable {
        /// Request the new activity with a push token (always first: the old one stays until this succeeded).
        case requestWithToken
        /// End the old activity at once (only after the new one exists).
        case endOld
        /// Persist the card as requested again (never twice).
        case rememberRetried
        /// Tell the bridge why there is no token (once per card and run).
        case reportProblem
    }

    /// The order of a replacement. The new activity is requested first; only when it exists does the old one end and
    /// the card count as retried. A visibility refusal (the app left the foreground meanwhile) changes nothing: the
    /// old card stays and the next foreground sync tries again. Any other refusal keeps the old card, is reported and
    /// is not retried (no loop).
    public static func replaceSteps(requestSucceeded: Bool, refusedForVisibility: Bool = false) -> [ReplaceStep] {
        if requestSucceeded {
            return [.requestWithToken, .endOld, .rememberRetried]
        }
        if refusedForVisibility {
            return [.requestWithToken]
        }
        return [.requestWithToken, .rememberRetried, .reportProblem]
    }

    /// What already waits for a card to reach the bridge.
    public enum PendingKind: Equatable, Sendable {
        case token
        case ended
        case problem
    }

    /// A problem never replaces a token or an end still waiting to be sent for the same card (the bridge needs those
    /// more); it is queued only when nothing, or an older problem, waits.
    public static func queuesProblem(over pending: PendingKind?) -> Bool {
        return pending == nil || pending == .problem
    }
}
