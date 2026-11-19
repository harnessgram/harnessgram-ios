import Foundation
import UIKit
import HarnessgramCockpitKit
#if canImport(ActivityKit)
import ActivityKit
#endif

/// Starts, updates and ends the agent task Live Activities from the Cockpit's progress cards while the
/// app runs. Each activity is requested with a push token; the token (and the activity's end) is queued here and
/// sent to the bridge by HarnessgramCockpitSync, so the bridge can update the lock screen while the app is closed. Up to three at once, one per
/// unfinished card or an overflow summary, never a stale one (HarnessgramTaskActivityPlan.choose), the
/// most recently updated in front. A card that finished or went away ends its activity with its
/// last state.
public final class HarnessgramLiveActivityController {
    public static let shared = HarnessgramLiveActivityController()

    private var lastShown: [String: HarnessgramTaskState] = [:]
    /// The card that was in front after the last sync.
    private var lastTop: String?
    /// Bumped by `endAll` and every account change (main queue): a running update loop stops at its next step, so no
    /// activity of the old account is requested after a logout or a switch.
    private var generation: UInt64 = 0

    /// A push token change for one card, waiting to reach the bridge.
    public enum TokenChange: Equatable {
        case token(Data)
        case ended
        /// Why the card's activity has no push token (an allow-listed HarnessgramLiveActivityTokenRule code).
        case problem(String)
    }

    /// Token changes not yet sent, by card id (main queue). The newest change for a card replaces an older one.
    private var pendingTokens: [String: TokenChange] = [:]
    /// Activities whose token updates are already observed (main queue).
    private var observed: Set<String> = []
    /// Called on main when a new token change is queued (HarnessgramCockpitSync sends it).
    public var onTokenChange: (() -> Void)?
    /// When this run first saw each activity, by activity id (main queue): the token grace starts there.
    private var firstSeen: [String: Date] = [:]
    /// Cards whose missing token was already reported in this run (main queue).
    private var reportedMissing: Set<String> = []
    private static let retriedKey = "HarnessgramLiveActivityTokenRetried"

    /// Card ids already requested again for a push token, or whose token request failed: never again (persisted).
    private var retried: [String] {
        return UserDefaults.standard.stringArray(forKey: HarnessgramLiveActivityController.retriedKey) ?? []
    }

    private func rememberRetried(_ cardId: String) {
        UserDefaults.standard.set(HarnessgramLiveActivityTokenRule.remember(cardId, in: self.retried), forKey: HarnessgramLiveActivityController.retriedKey)
    }

    // MARK: APNs diagnosis

    /// The remote-notification registration as this run saw it (main queue), reported when a card has no token.
    private(set) var apnsState: HarnessgramLiveActivityTokenRule.ApnsState = .unknown
    /// unregisterForRemoteNotifications calls this run (main queue).
    private(set) var apnsUnregisterCalls = 0

    public func noteApnsRegistered() {
        assert(Thread.isMainThread)
        self.apnsState = .registered
    }

    public func noteApnsFailed(_ error: Error) {
        assert(Thread.isMainThread)
        self.apnsState = .failed(code: (error as NSError).code)
    }

    /// Telegram's server said TOKEN_WAS_INVALIDATED (Harnessgram keeps its APNs registration; see AppDelegate).
    public func noteApnsInvalidatedByServer() {
        assert(Thread.isMainThread)
        self.apnsState = .invalidatedByServer
    }

    public func noteApnsUnregistered() {
        assert(Thread.isMainThread)
        self.apnsUnregisterCalls += 1
    }

    /// Development-signed builds get sandbox push tokens.
    public static var sandboxTokens: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    /// Takes every queued token change (main queue).
    public func takePendingTokens() -> [String: TokenChange] {
        assert(Thread.isMainThread)
        let changes = self.pendingTokens
        self.pendingTokens = [:]
        return changes
    }

    /// Puts back changes the bridge did not take, unless a newer change for the same card arrived meanwhile.
    public func requeue(_ changes: [String: TokenChange]) {
        assert(Thread.isMainThread)
        for (cardId, change) in changes where self.pendingTokens[cardId] == nil {
            self.pendingTokens[cardId] = change
        }
    }

    private func queue(_ cardId: String, _ change: TokenChange) {
        assert(Thread.isMainThread)
        self.pendingTokens[cardId] = change
        self.onTokenChange?()
    }

    /// A problem waits behind a token or an end still unsent for the same card (HarnessgramLiveActivityTokenRule.queuesProblem).
    private func queueProblem(_ cardId: String, _ code: String) {
        let pending: HarnessgramLiveActivityTokenRule.PendingKind?
        switch self.pendingTokens[cardId] {
        case .token?:
            pending = .token
        case .ended?:
            pending = .ended
        case .problem?:
            pending = .problem
        case nil:
            pending = nil
        }
        if HarnessgramLiveActivityTokenRule.queuesProblem(over: pending) {
            self.queue(cardId, .problem(code))
        }
    }

    /// ActivityKit starts an activity only while the app is in the foreground.
    private static var isAppActive: Bool {
        return UIApplication.shared.applicationState == .active
    }

    #if canImport(ActivityKit)
    /// The card's activity still on the lock screen, read at the moment of asking.
    @available(iOS 16.2, *)
    private func liveActivity(cardId: String) -> Activity<HarnessgramTaskActivityAttributes>? {
        return Activity<HarnessgramTaskActivityAttributes>.activities.first(where: { $0.attributes.cardId == cardId && HarnessgramLiveActivityController.isLive($0) })
    }

    /// Active or stale: still on the lock screen. Ended and dismissed activities linger in `activities` for a while.
    @available(iOS 16.2, *)
    static func isLive(_ activity: Activity<HarnessgramTaskActivityAttributes>) -> Bool {
        return HarnessgramTaskActivityPlan.isLive(activity.activityState)
    }

    @available(iOS 16.2, *)
    private func observe(_ activity: Activity<HarnessgramTaskActivityAttributes>) {
        // The overflow summary is local to the app: the bridge has no card for it.
        guard activity.attributes.cardId != HarnessgramTaskActivityPlan.summaryCardId else {
            return
        }
        if self.firstSeen[activity.id] == nil {
            self.firstSeen[activity.id] = Date()
        }
        guard !self.observed.contains(activity.id) else {
            return
        }
        self.observed.insert(activity.id)
        let cardId = activity.attributes.cardId
        // The token it already has: pushTokenUpdates may not repeat it for an activity from before a relaunch, nor
        // to a second loop after an account event dropped the first one's token.
        if let token = activity.pushToken {
            self.queue(cardId, .token(token))
        }
        let generation = self.generation
        Task { @MainActor [weak self] in
            for await token in activity.pushTokenUpdates {
                guard let self, self.generation == generation else {
                    return
                }
                self.queue(cardId, .token(token))
            }
        }
    }
    #endif

    /// An account change has started (before the store has caught up): pending update loops stop requesting activities.
    public func invalidatePendingUpdates() {
        assert(Thread.isMainThread)
        self.generation &+= 1
        self.observed = []  // the token loops stop with the generation; the next sync observes the activities again
    }

    #if canImport(ActivityKit)
    /// ActivityKit refused because the app is not in the foreground.
    @available(iOS 16.2, *)
    static func isVisibilityRefusal(_ error: Error) -> Bool {
        if case .visibility? = error as? ActivityAuthorizationError {
            return true
        }
        return false
    }

    @available(iOS 16.2, *)
    static func requestFailedCode(_ error: Error) -> String {
        let ns = error as NSError
        let caseName = (error as? ActivityAuthorizationError).map { String(describing: $0) }
        return HarnessgramLiveActivityTokenRule.requestFailed(caseName: caseName, domain: ns.domain, code: ns.code)
    }
    #endif

    /// - Parameter waiting: what waits for the owner (the overflow summary's first row); nil leaves it out.
    ///   - summaryRows: the bridge's switch for the overflow summary's rows (on unless switched off).
    public func sync(progress: [HarnessgramCockpitSnapshot.Progress], waiting: HarnessgramTaskActivityPlan.Waiting? = nil, summaryRows: Bool = true) {
        #if canImport(ActivityKit)
        guard #available(iOS 16.2, *) else {
            return
        }
        assert(Thread.isMainThread)
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            return
        }
        let plan = HarnessgramTaskActivityPlan.choose(progress, waiting: waiting, summaryRows: summaryRows)
        let planned = Set(plan.map { $0.cardId })
        let finishedStates = Dictionary(progress.filter { $0.finished }.map { ($0.id, HarnessgramTaskState(progress: $0)) }, uniquingKeysWith: { first, _ in first })
        let now = Date()
        /// Live cards whose activity never got a push token: requested again with one, the old ended after (once per card).
        var replace: Set<String> = []
        let appActive = HarnessgramLiveActivityController.isAppActive

        for activity in Activity<HarnessgramTaskActivityAttributes>.activities {
            // An ended (or dismissed) activity stays listed until iOS removes it; it was ended (and the bridge told)
            // once already, and it never stands in for a card that comes back.
            guard HarnessgramLiveActivityController.isLive(activity) else {
                continue
            }
            let cardId = activity.attributes.cardId
            guard !cardId.hasPrefix(HarnessgramSampleStore.activityIDPrefix) else { continue }
            if planned.contains(cardId) {
                self.observe(activity)  // also activities from before a relaunch
                let hasToken = activity.pushToken != nil
                let seen = self.firstSeen[activity.id]
                if appActive, HarnessgramLiveActivityTokenRule.shouldReplace(cardId: cardId, hasToken: hasToken, firstSeen: seen, now: now, retried: self.retried) {
                    // Remembered as retried only once the new activity exists (in the update loop below).
                    replace.insert(cardId)
                    self.lastShown[cardId] = nil  // so the plan pushes it again, in its lock-screen order
                } else if HarnessgramLiveActivityTokenRule.shouldReportMissing(cardId: cardId, hasToken: hasToken, firstSeen: seen, now: now, retried: self.retried, reported: self.reportedMissing) {
                    self.reportedMissing.insert(cardId)
                    // The APNs state says more than "no token": the bridge logs it (request-failed:apns-...).
                    self.queueProblem(cardId, HarnessgramLiveActivityTokenRule.apnsProblem(state: self.apnsState, unregisterCalls: self.apnsUnregisterCalls))
                }
                continue
            }
            let final = finishedStates[cardId] ?? self.lastShown[cardId] ?? activity.content.state
            self.lastShown[cardId] = nil
            self.observed.remove(activity.id)
            self.firstSeen[activity.id] = nil
            if cardId != HarnessgramTaskActivityPlan.summaryCardId {
                self.queue(cardId, .ended)
            }
            Task {
                await activity.end(ActivityContent(state: final, staleDate: nil), dismissalPolicy: .default)
            }
        }

        let pushes = HarnessgramTaskActivityPlan.pushes(plan, lastShown: self.lastShown, lastTop: self.lastTop)
        self.lastTop = plan.first?.cardId
        if pushes.isEmpty {
            return
        }
        for item in pushes {
            self.lastShown[item.cardId] = item.state
        }
        let staleDate = Date().addingTimeInterval(30 * 60)
        // iOS decides the final order of the activities on the lock screen: it puts the most recently updated one
        // first. So the updates run one after another in a single task, oldest card first, and the newest card's
        // update lands last (HarnessgramTaskActivityPlan.pushes); the Dynamic Island shows that one too.
        let generation = self.generation
        let replacing = replace
        Task { @MainActor [weak self] in
            for item in pushes {
                // Checked before every request and after every await: endAll or an account change stops the loop.
                guard let self, self.generation == generation else {
                    return
                }
                let content = ActivityContent(state: item.state, staleDate: staleDate)
                // Read now, after every earlier await: another sync's loop may have started this card's activity, and
                // the old activity's token may have arrived meanwhile. One card never gets two activities.
                let existing = self.liveActivity(cardId: item.cardId)
                let action = HarnessgramLiveActivityTokenRule.loopAction(cardId: item.cardId, live: existing != nil, liveHasToken: existing?.pushToken != nil, markedForReplace: replacing.contains(item.cardId), appActive: HarnessgramLiveActivityController.isAppActive)
                let attributes = HarnessgramTaskActivityAttributes(cardId: item.cardId)
                switch action {
                case .update:
                    if let activity = existing {
                        await activity.update(content)
                        guard self.generation == generation else {
                            return
                        }
                    }
                case .wait:
                    // Not in the foreground: ActivityKit would refuse. The next foreground sync pushes it again.
                    self.lastShown[item.cardId] = nil
                case .replace:
                    guard let old = existing else {
                        continue
                    }
                    // The new activity first (no await between the check above and this request); the old one ends only
                    // once the new one exists, so a refusal never leaves the card without an activity.
                    let steps: [HarnessgramLiveActivityTokenRule.ReplaceStep]
                    var failure: Error?
                    do {
                        let activity = try Activity<HarnessgramTaskActivityAttributes>.request(attributes: attributes, content: content, pushType: .token)
                        self.observe(activity)
                        steps = HarnessgramLiveActivityTokenRule.replaceSteps(requestSucceeded: true)
                    } catch {
                        failure = error
                        steps = HarnessgramLiveActivityTokenRule.replaceSteps(requestSucceeded: false, refusedForVisibility: HarnessgramLiveActivityController.isVisibilityRefusal(error))
                    }
                    if steps.contains(.rememberRetried) {
                        self.rememberRetried(item.cardId)
                    }
                    if steps.contains(.reportProblem), let failure, !self.reportedMissing.contains(item.cardId) {
                        self.reportedMissing.insert(item.cardId)
                        self.queueProblem(item.cardId, HarnessgramLiveActivityController.requestFailedCode(failure))
                    }
                    if steps.contains(.endOld) {
                        // The bridge never had the old activity's token, so it is not told.
                        self.observed.remove(old.id)
                        self.firstSeen[old.id] = nil
                        await old.end(nil, dismissalPolicy: .immediate)
                        guard self.generation == generation else {
                            return
                        }
                    } else {
                        // The old activity stays and keeps the latest content while the app runs.
                        await old.update(content)
                        guard self.generation == generation else {
                            return
                        }
                    }
                case .request:
                    if item.cardId == HarnessgramTaskActivityPlan.summaryCardId {
                        // The overflow summary is local to the app (the bridge has no card for it): no push token.
                        if (try? Activity<HarnessgramTaskActivityAttributes>.request(attributes: attributes, content: content, pushType: nil)) == nil {
                            self.lastShown[item.cardId] = nil
                        }
                    } else {
                        do {
                            let activity = try Activity<HarnessgramTaskActivityAttributes>.request(attributes: attributes, content: content, pushType: .token)
                            self.observe(activity)
                        } catch {
                            if HarnessgramLiveActivityController.isVisibilityRefusal(error) {
                                // Left the foreground meanwhile: nothing is recorded; the next foreground sync tries again.
                                self.lastShown[item.cardId] = nil
                                continue
                            }
                            // Said once to the bridge (no silent fallback), and never requested again for this card.
                            self.rememberRetried(item.cardId)
                            if !self.reportedMissing.contains(item.cardId) {
                                self.reportedMissing.insert(item.cardId)
                                self.queueProblem(item.cardId, HarnessgramLiveActivityController.requestFailedCode(error))
                            }
                            if (try? Activity<HarnessgramTaskActivityAttributes>.request(attributes: attributes, content: content, pushType: nil)) == nil {
                                // Without a token the activity still shows and updates while the app runs.
                                self.lastShown[item.cardId] = nil
                            }
                        }
                    }
                }
            }
        }
        #endif
    }

    /// Logout or an account switch (build 15): every task Live Activity ends and leaves the lock screen at once,
    /// and nothing of the old account is shown again (pending refreshes of the old session are dropped by the store).
    public func endAll() {
        #if canImport(ActivityKit)
        guard #available(iOS 16.2, *) else {
            return
        }
        self.generation &+= 1
        self.lastShown = [:]
        self.lastTop = nil
        // The old account's bridge is not told: its tokens stop working once the activities end (APNs answers 410).
        self.pendingTokens = [:]
        self.observed = []
        self.firstSeen = [:]
        self.reportedMissing = []
        for activity in Activity<HarnessgramTaskActivityAttributes>.activities where !activity.attributes.cardId.hasPrefix(HarnessgramSampleStore.activityIDPrefix) {
            Task {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
        #endif
    }

    /// Simulator only: shows a made-up running task so the Live Activity can be checked without a
    /// Cockpit (launch with HARNESSGRAM_DEMO_LIVE_ACTIVITY=1).
    public func startDemoIfRequested() {
        #if targetEnvironment(simulator)
        guard ProcessInfo.processInfo.environment["HARNESSGRAM_DEMO_LIVE_ACTIVITY"] == "1" else {
            return
        }
        // The simulator demo has no logged-in account: a demo account id stands in, only when none is active.
        if HarnessgramCockpitStore.shared.activeAccount == nil {
            HarnessgramCockpitStore.shared.setActiveAccount(1)
        }
        HarnessgramCockpitStore.shared.saveSnapshot(HarnessgramCockpitSnapshot.sample.withNotice(nil))
        self.sync(progress: HarnessgramCockpitSnapshot.sample.progress, waiting: HarnessgramTaskActivityPlan.Waiting(snapshot: HarnessgramCockpitSnapshot.sample))
        #endif
    }
}
