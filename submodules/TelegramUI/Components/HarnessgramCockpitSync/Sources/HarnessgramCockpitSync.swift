import Foundation
import SwiftSignalKit
import TelegramCore
@preconcurrency import AccountContext
import WidgetKit
@preconcurrency import HarnessgramCockpitKit
import HarnessgramAgent
import HarnessgramSettings

/// Keeps the widgets and the agent Live Activity current while the app runs.
///
/// The Cockpit takes only a signed Mini App login (initData). This app is the owner's Telegram client,
/// so it asks Telegram for the Cockpit bot's web app exactly as opening the Cockpit does, and keeps the
/// login it gets for the widget extension (HarnessgramCockpitStore: complete file protection). The login
/// goes only to the bot menu button's HTTPS origin authorized by the local pairing configuration.
/// `@unchecked Sendable`: its mutable state (`lastRefresh`, `refreshing`) is only read and written on the main
/// queue; background work captures it only to hop back there.
public final class HarnessgramCockpitSync: @unchecked Sendable {
    public static let shared = HarnessgramCockpitSync()

    /// The bridge bot is selected by local build configuration. Privileges depend on the authenticated panel's
    /// immutable bot id (HarnessgramBridgeIdentity), never on the configurable username alone.
    static let minimumInterval: TimeInterval = 60

    /// Posted on the main queue after a refresh stored a new snapshot (and the full list of open decisions), after an
    /// answer, and after the demo feed: the House screens redraw from `HarnessgramCockpitStore` when they hear it.
    public static let snapshotDidChangeNotification = Notification.Name("HarnessgramCockpitSnapshotDidChange")

    /// Posted on the main queue when a read for the UI failed, or when the last failure is cleared (a read stored a
    /// snapshot, or the account changed). Screens show `lastRefreshFailure` instead of waiting forever.
    public static let refreshStatusDidChangeNotification = Notification.Name("HarnessgramCockpitRefreshStatusDidChange")

    public enum AnswerResult: Equatable, Sendable {
        case sent
        /// Answered meanwhile, or it no longer waits on the owner.
        case gone
        /// Face ID or the passcode was not confirmed: nothing was sent.
        case notConfirmed
        case unavailable
    }

    private let store: HarnessgramCockpitStore
    private let client: HarnessgramCockpitClient
    private let storageQueue = DispatchQueue(label: "HarnessgramCockpitSync.storage", qos: .utility)
    private let mintDisposables = DisposableSet()
    /// Main-queue copy for UI consumers. UI never reads the shared files or waits for their lock.
    private var latestViewState: HarnessgramCockpitStore.ViewState?
    private var viewStateRefreshPending = false
    private var viewStateRefreshNeedsAnother = false
    private var uiGeneration: UInt64 = 0
    private let storageGeneration = Atomic<UInt64>(value: 0)
    private var storeStateSuppressed = false
    /// Decisions answered from this app, hidden from the UI copy even while the shared files are busy and the answer
    /// is not remembered there yet (main queue; cleared on every account change).
    private var locallyAnswered: [String: Date] = [:]
    private var viewStateLockRetries = 0
    private var lastRefresh: Date?
    private var refreshing = false
    /// Why the last read failed (main queue). nil once a read stored a snapshot, after an account change, and while a
    /// retry the owner asked for runs (`clearRefreshFailure`).
    public private(set) var lastRefreshFailure: HarnessgramPairFailure?
    /// The native Cockpit's model from the last read (main queue, memory only; dropped on every account change).
    private var latestScreen: HarnessgramCockpitScreen?
    private var latestScreenSession: HarnessgramCockpitStore.Session?
    /// When the next read of a visible screen may go: backoff after failures and the bridge's Retry-After (main queue).
    public private(set) var pollSchedule = HarnessgramCockpitPollSchedule()
    /// The wait a rate-limited read asked for, until its outcome is noted (main queue).
    private var pendingRetryAfter: TimeInterval?

    init(store: HarnessgramCockpitStore = .shared, client: HarnessgramCockpitClient = HarnessgramCockpitClient()) {
        self.store = store
        self.client = client
        self.refreshViewState()
        DispatchQueue.main.async { [weak self] in
            HarnessgramLiveActivityController.shared.onTokenChange = { [weak self] in
                self?.sendLiveActivityTokens()
            }
        }
    }

    private var sendingLiveActivityTokens = false
    /// A token change arrived while a send was running: send once more when it ends (main queue).
    private var liveActivityTokensArrived = false

    /// Sends queued Live Activity token changes to the current session's bridge with its stored login (main queue).
    /// A change the bridge could not take yet (offline, old login) is put back and sent after the next read; one it
    /// refused outright is dropped. Nothing is sent once the account changed.
    func sendLiveActivityTokens() {
        assert(Thread.isMainThread)
        guard !self.sendingLiveActivityTokens else {
            self.liveActivityTokensArrived = true
            return
        }
        let changes = HarnessgramLiveActivityController.shared.takePendingTokens()
        guard !changes.isEmpty else {
            return
        }
        self.sendingLiveActivityTokens = true
        self.liveActivityTokensArrived = false
        let generation = self.uiGeneration
        let sandbox = HarnessgramLiveActivityController.sandboxTokens
        Task {
            var retry: [String: HarnessgramLiveActivityController.TokenChange] = [:]
            let session = await self.currentSession()
            var credential: HarnessgramCockpitCredential?
            if let session {
                credential = await self.storeValue({ self.store.loadCredential(forSession: session) })
            }
            for (cardId, change) in changes {
                // Checked before every request: an account change meanwhile must not send this account's tokens on.
                guard let session, let credential, await self.sessionIsCurrent(session), await MainActor.run(body: { self.uiGeneration == generation }) else {
                    retry[cardId] = change
                    continue
                }
                let outcome: HarnessgramCockpitClient.TokenOutcome
                switch change {
                case let .token(value):
                    outcome = await self.client.registerLiveActivityToken(cardId: cardId, token: value, sandbox: sandbox, credential: credential, now: Date())
                case .ended:
                    outcome = await self.client.registerLiveActivityToken(cardId: cardId, token: nil, sandbox: sandbox, credential: credential, now: Date())
                case let .problem(code):
                    // Why the card has no push token: a diagnosis only, the bridge stores nothing.
                    outcome = await self.client.reportLiveActivityProblem(cardId: cardId, problem: code, credential: credential, now: Date())
                }
                if outcome == .retry {
                    retry[cardId] = change
                }
            }
            DispatchQueue.main.async {
                self.sendingLiveActivityTokens = false
                // Changes of an account that is gone are dropped (endAll already cleared the queue).
                if self.uiGeneration == generation, !retry.isEmpty {
                    HarnessgramLiveActivityController.shared.requeue(retry)
                }
                if self.liveActivityTokensArrived {
                    self.liveActivityTokensArrived = false
                    self.sendLiveActivityTokens()
                }
            }
        }
    }

    /// The native Cockpit's screen model, without the decisions answered from this app. Main queue only.
    public var screen: HarnessgramCockpitScreen? {
        assert(Thread.isMainThread)
        guard let screen = self.latestScreen, !self.storeStateSuppressed, self.latestViewState?.isPaused != true else {
            return nil
        }
        let now = Date()
        let hidden = Set(self.locallyAnswered.filter { now.timeIntervalSince($0.value) < HarnessgramCockpitStore.answeredMemory }.keys)
        return screen.removingDecisions(hidden)
    }

    /// Last published app-group state. Read only from the main queue.
    public var viewState: HarnessgramCockpitStore.ViewState? {
        assert(Thread.isMainThread)
        return self.latestViewState
    }

    /// Refreshes the in-memory UI copy without blocking the caller.
    public func refreshViewState() {
        if Thread.isMainThread {
            self.scheduleViewStateRefresh()
        } else {
            DispatchQueue.main.async { [weak self] in self?.scheduleViewStateRefresh() }
        }
    }

    private func scheduleViewStateRefresh() {
        assert(Thread.isMainThread)
        if self.viewStateRefreshPending {
            self.viewStateRefreshNeedsAnother = true
            return
        }
        self.viewStateRefreshPending = true
        let generation = self.uiGeneration
        self.storageQueue.async { [weak self] in
            guard let self else { return }
            let state = self.store.viewState()
            DispatchQueue.main.async {
                self.viewStateRefreshPending = false
                if let state {
                    self.viewStateLockRetries = 0
                    let visible = self.hidingLocallyAnswered(state)
                    if generation == self.uiGeneration, !self.storeStateSuppressed {
                        let changed = self.latestViewState != visible
                        self.latestViewState = visible
                        self.syncLiveActivityFromViewState()
                        if changed {
                            NotificationCenter.default.post(name: HarnessgramCockpitSync.snapshotDidChangeNotification, object: nil)
                        }
                    }
                } else if generation == self.uiGeneration, self.viewStateLockRetries < 3 {
                    // The shared files were busy: the last copy stays, and it is read again shortly.
                    self.viewStateLockRetries += 1
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2 * Double(self.viewStateLockRetries)) {
                        self.scheduleViewStateRefresh()
                    }
                }
                if self.viewStateRefreshNeedsAnother {
                    self.viewStateRefreshNeedsAnother = false
                    self.scheduleViewStateRefresh()
                }
            }
        }
    }

    private func storeValue<T>(_ operation: @escaping () -> T) async -> T {
        await withCheckedContinuation { continuation in
            self.storageQueue.async {
                continuation.resume(returning: operation())
            }
        }
    }

    /// A checked store call on the storage queue; a busy lock is retried a few times (with growing waits off the
    /// queue) and is never read as absent state. Still busy after that: `lockUnavailable`.
    private func storeRetrying<T>(attempts: Int = 4, _ operation: @escaping () -> HarnessgramCockpitStore.MutationResult<T>) async -> HarnessgramCockpitStore.MutationResult<T> {
        var delay: UInt64 = 50_000_000
        for attempt in 0 ..< attempts {
            let result = await self.storeValue(operation)
            if case .completed = result {
                return result
            }
            if attempt + 1 < attempts {
                try? await Task.sleep(nanoseconds: delay)
                delay *= 2
            }
        }
        return .lockUnavailable
    }

    /// A save that returns false for a busy lock as well as a refusal: retried a few times, then false.
    private func storeSaveRetrying(_ operation: @escaping () -> Bool) async -> Bool {
        let result = await self.storeRetrying({ () -> HarnessgramCockpitStore.MutationResult<Bool> in
            return operation() ? .completed(true) : .lockUnavailable
        })
        return result == .completed(true)
    }

    /// The current session; nil when there is none, or when the shared files stayed busy (callers then do nothing).
    private func currentSession() async -> HarnessgramCockpitStore.Session? {
        return await self.storeRetrying({ self.store.sessionChecked() }).completedValue ?? nil
    }

    /// Whether `session` is still current; a busy lock is retried and, if it stays busy, fails closed.
    private func sessionIsCurrent(_ session: HarnessgramCockpitStore.Session) async -> Bool {
        return await self.storeRetrying({ self.store.isCurrentChecked(session) }) == .completed(true)
    }

    /// The UI copy without the decisions answered from this app (main queue).
    private func hidingLocallyAnswered(_ state: HarnessgramCockpitStore.ViewState) -> HarnessgramCockpitStore.ViewState {
        assert(Thread.isMainThread)
        let now = Date()
        self.locallyAnswered = self.locallyAnswered.filter { now.timeIntervalSince($0.value) < HarnessgramCockpitStore.answeredMemory }
        guard !self.locallyAnswered.isEmpty else {
            return state
        }
        var snapshot = state.snapshot
        for id in self.locallyAnswered.keys {
            snapshot = snapshot?.removingDecision(id)
        }
        let openDecisions = state.openDecisions?.filter { self.locallyAnswered[$0.id] == nil }
        return HarnessgramCockpitStore.ViewState(session: state.session, isPaused: state.isPaused, hasLogin: state.hasLogin, credentialCanAnswer: state.credentialCanAnswer, bridgeOrigin: state.bridgeOrigin, snapshot: snapshot, openDecisions: openDecisions)
    }

    private func pauseStoreWithBoundedRetry() -> Bool {
        for attempt in 0 ..< 3 {
            if self.store.pauseChecked() { return true }
            if attempt < 2 { Thread.sleep(forTimeInterval: 0.01) }
        }
        return false
    }

    /// Called when the app becomes active (AppDelegate). At most once a minute unless `force`. It never sets the
    /// active account: only real account events do (`setActiveAccount`); it works within the session it finds.
    /// `completion` runs on the main queue once this call is over (also when it did nothing).
    public func refresh(context: AccountContext, force: Bool = false, completion: (() -> Void)? = nil) {
        assert(Thread.isMainThread)
        guard let visibleState = self.latestViewState, !visibleState.isPaused, visibleState.session?.accountId == HarnessgramCockpitSync.accountId(context) else {
            completion?()
            return
        }
        let now = Date()
        // The bridge's Retry-After holds every read, also one the owner asked for.
        if self.refreshing || !self.pollSchedule.mayRequest(now: now) || (!force && self.lastRefresh.map { now.timeIntervalSince($0) < HarnessgramCockpitSync.minimumInterval } == true) {
            completion?()
            return
        }
        self.refreshing = true
        self.lastRefresh = now
        let generation = self.uiGeneration
        let finished: () -> Void = {
            DispatchQueue.main.async {
                self.refreshing = false
                completion?()
            }
        }
        Task {
            guard let session = await self.currentSession(), session.accountId == HarnessgramCockpitSync.accountId(context) else {
                // The shared files stayed busy (or the session moved on): said, so the screen does not wait forever.
                self.noteRefreshOutcome(.storage, generation: generation)
                finished()
                return
            }
            DispatchQueue.main.async {
                self.mintLogin(context: context, completion: { outcome in
                    Task {
                        let credential: HarnessgramCockpitCredential?
                        let mintFailure: HarnessgramPairFailure?
                        switch outcome {
                        case let .login(value):
                            credential = value
                            mintFailure = nil
                        case let .failed(reason):
                            credential = nil
                            mintFailure = reason
                        }
                        if let credential {
                            _ = await self.storeSaveRetrying { self.store.saveCredential(credential, forSession: session) }
                        }
                        let stored: HarnessgramCockpitCredential?
                        if let credential {
                            stored = credential
                        } else {
                            stored = await self.storeValue { self.store.loadCredential(forSession: session) }
                        }
                        if let mintFailure, stored?.canRead(now: Date()) != true {
                            // No new login and the saved one is too old to read: the mint's step is the real reason
                            // (reading with the old login would only say "unreadable login").
                            self.noteRefreshOutcome(mintFailure, generation: generation)
                        } else {
                            _ = await self.refreshSnapshot(credential: stored, session: session)
                        }
                        finished()
                    }
                })
            }
        }
    }

    /// For a screen that is on view (the House Home): refreshes now and then every `interval` seconds (at least 15)
    /// until the returned disposable is disposed. Each poll reuses the stored login while it is valid, so a quiet screen
    /// does not ask Telegram for a new web login every time; it mints one only when there is none.
    ///
    /// The next read is planned when the last one ended (`pollSchedule`): `interval` while reads succeed, longer after
    /// each failure, and never before the time the bridge asked for with Retry-After.
    public func pollWhileVisible(context: AccountContext, interval: TimeInterval = 45.0) -> Disposable {
        assert(Thread.isMainThread)
        let poller = HarnessgramCockpitVisiblePoller(base: max(15.0, interval))
        poller.read = { [weak self, weak poller] in
            guard let self else { return }
            self.refreshVisible(context: context, completion: {
                poller?.arm(delay: self.pollSchedule.delay(now: Date(), base: poller?.base))
            })
        }
        self.refresh(context: context, force: true, completion: { [weak self, weak poller] in
            guard let self else { return }
            poller?.arm(delay: self.pollSchedule.delay(now: Date(), base: poller?.base))
        })
        return ActionDisposable {
            Queue.mainQueue().async {
                poller.stop()
            }
        }
    }

    private func refreshVisible(context: AccountContext, completion: @escaping () -> Void) {
        assert(Thread.isMainThread)
        guard !self.refreshing, self.pollSchedule.mayRequest(now: Date()), let visibleState = self.latestViewState, !visibleState.isPaused, visibleState.session?.accountId == HarnessgramCockpitSync.accountId(context) else {
            completion()
            return
        }
        self.refreshing = true
        self.lastRefresh = Date()
        Task {
            guard let session = await self.currentSession(), session.accountId == HarnessgramCockpitSync.accountId(context), let credential = await self.storeValue({ self.store.loadCredential(forSession: session) }), credential.canRead(now: Date()) else {
                DispatchQueue.main.async {
                    self.refreshing = false
                    self.refresh(context: context, force: true, completion: completion)
                }
                return
            }
            _ = await self.refreshSnapshot(credential: credential, session: session)
            DispatchQueue.main.async {
                self.refreshing = false
                completion()
            }
        }
    }

    /// Simulator only: a made-up Cockpit for the House screens, so they can be checked without a bridge (launch with
    /// HARNESSGRAM_DEMO_HOUSE=1). Never reads real data and does nothing on a device.
    public func startHouseDemoIfRequested() {
        #if targetEnvironment(simulator)
        guard ProcessInfo.processInfo.environment["HARNESSGRAM_DEMO_HOUSE"] == "1" else {
            return
        }
        // The simulator has no logged-in account: a demo account id stands in, only when none is active.
        Task {
            if await self.storeValue({ self.store.activeAccount }) == nil { _ = await self.storeValue { self.store.setActiveAccount(1) } }
            var demo = HarnessgramCockpitSnapshot.houseDemo
            // HARNESSGRAM_DEMO_TOWER_PHONE=off: the bridge's "towerPhone" switch off (the phone list as before).
            if ProcessInfo.processInfo.environment["HARNESSGRAM_DEMO_TOWER_PHONE"] == "off" {
                demo.appSwitches = HarnessgramCockpitSnapshot.AppSwitches(towerPhone: false)
            }
            _ = await self.storeValue { [demo] in self.store.saveSnapshot(demo) }
            _ = await self.storeValue { self.store.saveOpenDecisions(HarnessgramCockpitSnapshot.houseDemoOpenDecisions) }
            await MainActor.run {
                self.latestScreen = HarnessgramCockpitScreen.houseDemo(now: Date())
                self.latestScreenSession = nil
            }
            self.refreshViewState()
            self.postSnapshotDidChange()
        }
        #endif
    }

    /// Simulator demo only: the "connected" state of the widget pairing row, with a made-up login that is never sent
    /// (the demo has no network). Does nothing on a device.
    public func demoConnect(context: AccountContext) {
        #if targetEnvironment(simulator)
        self.demoActivate(context: context, completion: { [weak self] session in
            guard let self, let session else { return }
            Task {
                _ = await self.storeValue { self.store.saveCredential(HarnessgramCockpitCredential(initData: "demo", origin: "https://demo.private.example.test", authDate: Date(), configuration: HarnessgramLocalConfig(bridgeOrigin: "https://demo.private.example.test")), forSession: session) }
                self.refreshViewState()
            }
        })
        #endif
    }

    /// Simulator demo only: a fresh session for the demo account (resumed if a previous demo step paused it).
    public func demoActivate(context: AccountContext, completion: ((HarnessgramCockpitStore.Session?) -> Void)? = nil) {
        #if targetEnvironment(simulator)
        let accountId = HarnessgramCockpitSync.accountId(context)
        Task {
            let session = await self.storeValue { self.store.isPaused ? self.store.resume(accountId: accountId) : self.store.setActiveAccount(accountId) }
            self.refreshViewState()
            DispatchQueue.main.async { completion?(session) }
        }
        #else
        completion?(nil)
        #endif
    }

    private func postSnapshotDidChange() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: HarnessgramCockpitSync.snapshotDidChangeNotification, object: nil)
        }
    }

    /// Records a read's outcome for the UI (nil: it stored a snapshot), only within the generation it started in.
    private func noteRefreshOutcome(_ failure: HarnessgramPairFailure?, generation: UInt64) {
        DispatchQueue.main.async {
            guard generation == self.uiGeneration else { return }
            if failure == nil {
                self.pollSchedule.noteSuccess()
            } else {
                self.pollSchedule.noteFailure(now: Date(), retryAfter: failure == .panelBusy ? self.pendingRetryAfter : nil)
            }
            self.pendingRetryAfter = nil
            self.setRefreshFailure(failure)
        }
    }

    /// The owner asked to try again: the screen waits for this attempt's outcome instead of showing the last one.
    public func clearRefreshFailure() {
        assert(Thread.isMainThread)
        self.setRefreshFailure(nil)
    }

    func setRefreshFailure(_ failure: HarnessgramPairFailure?) {
        assert(Thread.isMainThread)
        // Every failure is posted, also a repeated one, so a screen waiting on a retry hears that it ended.
        if failure == nil && self.lastRefreshFailure == nil {
            return
        }
        self.lastRefreshFailure = failure
        NotificationCenter.default.post(name: HarnessgramCockpitSync.refreshStatusDidChangeNotification, object: nil)
    }

    /// The Telegram account the Cockpit files belong to (HarnessgramCockpitStore keeps them per account).
    static func accountId(_ context: AccountContext) -> Int64 {
        return context.account.peerId.id._internalGetInt64Value()
    }

    /// The last account event: the active account and how many accounts are logged in.
    private var lastPrimary: Int64?
    private var lastLoggedInCount = 0
    /// A switch/logout must remain a pause even if later account events arrive before storage catches up.
    private var pendingAccountPause = false

    /// The app's account event (AppDelegate, from the logged-in accounts; starting an add-account flow is not one).
    /// Exactly one account: its session starts the first time. A second login, a switch or a logout: everything is
    /// wiped, every Live Activity ends, and nothing starts again until the owner re-pairs (`repair`).
    public func accountsChanged(primary: Int64?, loggedInCount: Int) {
        assert(Thread.isMainThread)
        self.pendingAccountPause = HarnessgramAccountRule.requiresPause(
            previousPrimary: self.lastPrimary,
            previousLoggedInCount: self.lastLoggedInCount,
            primary: primary,
            loggedInCount: loggedInCount,
            alreadyPending: self.pendingAccountPause
        )
        let forcePause = self.pendingAccountPause
        self.lastPrimary = primary
        self.lastLoggedInCount = loggedInCount
        self.lastRefresh = nil
        self.uiGeneration &+= 1
        let generation = self.uiGeneration
        _ = self.storageGeneration.swap(generation)
        self.latestViewState = nil
        self.latestScreen = nil
        self.latestScreenSession = nil
        self.pollSchedule = HarnessgramCockpitPollSchedule()
        self.pendingRetryAfter = nil
        self.locallyAnswered = [:]
        self.setRefreshFailure(nil)
        HarnessgramLiveActivityController.shared.invalidatePendingUpdates()
        self.storeStateSuppressed = true
        NotificationCenter.default.post(name: HarnessgramCockpitSync.snapshotDidChangeNotification, object: nil)
        self.storageQueue.async { [weak self] in
            self?.reconcileAccountEvent(primary: primary, loggedInCount: loggedInCount, generation: generation, attempt: 0, forcePause: forcePause)
        }
    }

    private func reconcileAccountEvent(primary: Int64?, loggedInCount: Int, generation: UInt64, attempt: Int, forcePause: Bool) {
        guard self.storageGeneration.with({ $0 }) == generation else { return }
        guard let prior = self.store.viewState() else {
            self.retryAccountReconciliation(primary: primary, loggedInCount: loggedInCount, generation: generation, attempt: attempt, forcePause: forcePause)
            return
        }
        let action: HarnessgramAccountRule.Action = forcePause ? .pause : HarnessgramAccountRule.action(primary: primary, loggedInCount: loggedInCount, session: prior.session, isPaused: prior.isPaused)
        guard self.storageGeneration.with({ $0 }) == generation else { return }
        var succeeded = true
        switch action {
        case .none: break
        case let .start(accountId):
            if case .lockUnavailable = self.store.setActiveAccountChecked(accountId) { succeeded = false }
        case .pause: succeeded = self.pauseStoreWithBoundedRetry()
        }
        let state = succeeded ? self.store.viewState() : nil
        guard succeeded, state != nil else {
            self.retryAccountReconciliation(primary: primary, loggedInCount: loggedInCount, generation: generation, attempt: attempt, forcePause: forcePause || action == .pause)
            return
        }
        DispatchQueue.main.async {
            guard generation == self.uiGeneration else { return }
            self.storeStateSuppressed = false
            self.latestViewState = state
            if case .pause = action, state?.isPaused == true {
                self.pendingAccountPause = false
            }
            NotificationCenter.default.post(name: HarnessgramCockpitSync.snapshotDidChangeNotification, object: nil)
            if case .pause = action { HarnessgramLiveActivityController.shared.endAll() }
            if action != .none { WidgetCenter.shared.reloadAllTimelines() }
        }
    }

    private func retryAccountReconciliation(primary: Int64?, loggedInCount: Int, generation: UInt64, attempt: Int, forcePause: Bool) {
        let delay = min(2.0, 0.2 * pow(2.0, Double(min(attempt, 4))))
        self.storageQueue.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.storageGeneration.with({ $0 }) == generation else { return }
            self.reconcileAccountEvent(primary: primary, loggedInCount: loggedInCount, generation: generation, attempt: attempt + 1, forcePause: forcePause)
        }
    }

    /// Paused after a second login, a switch or a logout, with exactly one account logged in now: the owner may re-pair.
    public var canRepair: Bool {
        return (self.latestViewState?.isPaused ?? false) && self.lastLoggedInCount == 1 && self.lastPrimary != nil
    }

    public var isPaused: Bool {
        return self.latestViewState?.isPaused ?? false
    }

    /// The widgets are connected to the bridge: a session for the one logged-in account and a saved Cockpit login.
    public var isConnected: Bool {
        guard let state = self.latestViewState else { return false }
        return !state.isPaused && state.session != nil && state.hasLogin
    }

    /// Exactly one Telegram account is logged in (the widgets can be connected).
    public var hasSingleAccount: Bool {
        return self.lastLoggedInCount == 1 && self.lastPrimary != nil
    }

    public enum PairResult {
        case connected
        case needsOneAccount
        case notConfirmed
        /// Which step failed (build 18 fix): the text says what is actually wrong.
        case failed(HarnessgramPairFailure)
    }

    /// Build 18: connects the widgets in one tap (Settings > Harnessgram > Agents, or the unpaired widget's tap): after
    /// Face ID, it starts (or restarts) the session for the one logged-in account and gets a fresh Cockpit login from the
    /// bridge's web app at once, so the widget does not wait for the next refresh. The Cockpit login is the pairing: it is
    /// what the widgets read and answer with (a device token from /api/device-pair is not used).
    public func pair(context: AccountContext, completion: @escaping (PairResult) -> Void) {
        assert(Thread.isMainThread)
        let generation = self.uiGeneration
        let accountId = HarnessgramCockpitSync.accountId(context)
        guard !self.storeStateSuppressed, self.hasSingleAccount, self.lastPrimary == accountId else {
            completion(.needsOneAccount)
            return
        }
        HarnessgramOwnerConfirmation.shared.confirm(reason: HarnessgramWidgetStrings.repairReason, completion: { [weak self] confirmed in
            guard let self else {
                return
            }
            guard confirmed else {
                completion(.notConfirmed)
                return
            }
            guard self.uiGeneration == generation else {
                completion(.needsOneAccount)
                return
            }
            guard !self.storeStateSuppressed, self.hasSingleAccount, self.lastPrimary == accountId else {
                completion(.needsOneAccount)
                return
            }
            Task {
                // A busy store (or a write that failed) is retried; a changed generation stops at once.
                let session: HarnessgramCockpitStore.Session? = await self.storeRetrying { () -> HarnessgramCockpitStore.MutationResult<HarnessgramCockpitStore.Session?> in
                    guard self.storageGeneration.with({ $0 }) == generation else { return .completed(nil) }
                    guard case let .completed(paused) = self.store.isPausedChecked() else { return .lockUnavailable }
                    let started = paused ? self.store.resume(accountId: accountId) : self.store.setActiveAccount(accountId)
                    return started.map { .completed($0) } ?? .lockUnavailable
                }.completedValue ?? nil
                self.refreshViewState()
                guard let session else {
                    DispatchQueue.main.async { completion(.failed(.storage)) }
                    return
                }
                DispatchQueue.main.async { self.lastRefresh = nil }
                DispatchQueue.main.async {
                    self.mintLogin(context: context, completion: { outcome in
                        Task {
                            guard await MainActor.run(body: { self.uiGeneration == generation && self.hasSingleAccount && self.lastPrimary == accountId }) else {
                                DispatchQueue.main.async { completion(.needsOneAccount) }
                                return
                            }
                            guard await self.sessionIsCurrent(session) else {
                                DispatchQueue.main.async { completion(.needsOneAccount) }
                                return
                            }
                            let credential: HarnessgramCockpitCredential
                            switch outcome {
                            case let .failed(reason):
                                DispatchQueue.main.async { completion(.failed(reason)) }
                                return
                            case let .login(value): credential = value
                            }
                            guard await self.storeSaveRetrying({ self.store.saveCredential(credential, forSession: session) }) else {
                                DispatchQueue.main.async { completion(.failed(.storage)) }
                                return
                            }
                            // Connected means the panel read the login once (and named its bot), not only that Telegram signed it.
                            let failure = await self.firstRead(credential: credential, session: session)
                            DispatchQueue.main.async {
                                guard self.uiGeneration == generation else { completion(.needsOneAccount); return }
                                self.refreshViewState()
                                WidgetCenter.shared.reloadAllTimelines()
                                let result = failure.map { PairResult.failed($0) } ?? .connected
                                if case .connected = result {
                                    self.pendingAccountPause = false
                                }
                                completion(result)
                            }
                        }
                    })
                }
            }
        })
    }

    /// One-tap disconnect: everything is wiped, every Live Activity ends, and the widgets wait for a new connection.
    public func disconnect() {
        assert(Thread.isMainThread)
        self.pendingAccountPause = true
        self.lastRefresh = nil
        self.uiGeneration &+= 1
        let generation = self.uiGeneration
        _ = self.storageGeneration.swap(generation)
        self.latestViewState = nil
        self.latestScreen = nil
        self.latestScreenSession = nil
        self.pollSchedule = HarnessgramCockpitPollSchedule()
        self.pendingRetryAfter = nil
        self.locallyAnswered = [:]
        self.setRefreshFailure(nil)
        HarnessgramLiveActivityController.shared.invalidatePendingUpdates()
        self.storeStateSuppressed = true
        NotificationCenter.default.post(name: HarnessgramCockpitSync.snapshotDidChangeNotification, object: nil)
        self.storageQueue.async { [weak self] in
            guard let self, self.storageGeneration.with({ $0 }) == generation else { return }
            self.reconcileAccountEvent(primary: nil, loggedInCount: 0, generation: generation, attempt: 0, forcePause: true)
        }
    }

    /// Kept for the build 16 Settings row: the same as `pair`.
    public func repair(context: AccountContext, completion: @escaping (Bool) -> Void) {
        self.pair(context: context, completion: { result in
            if case .connected = result {
                completion(true)
            } else {
                completion(false)
            }
        })
    }

    @discardableResult
    func refreshSnapshot(credential: HarnessgramCockpitCredential?, session: HarnessgramCockpitStore.Session) async -> HarnessgramCockpitSnapshot? {
        if case let .read(snapshot) = await self.read(credential: credential, session: session) {
            return snapshot
        }
        return nil
    }

    /// The first read after connecting: nil when the panel took the login, otherwise why not.
    func firstRead(credential: HarnessgramCockpitCredential, session: HarnessgramCockpitStore.Session) async -> HarnessgramPairFailure? {
        switch await self.read(credential: credential, session: session) {
        case .read:
            return nil
        case let .failed(reason):
            return reason
        }
    }

    enum ReadOutcome {
        case read(HarnessgramCockpitSnapshot)
        case failed(HarnessgramPairFailure)
    }

    private func read(credential: HarnessgramCockpitCredential?, session: HarnessgramCockpitStore.Session) async -> ReadOutcome {
        // Any account event (switch, logout, disconnect) from here on bumps it on main and ends the Live Activities there.
        let generation = await MainActor.run { self.uiGeneration }
        let outcome = await self.readOnce(credential: credential, session: session, generation: generation)
        // Every read says how it ended, so a screen waiting for the first snapshot shows why it did not come.
        switch outcome {
        case .read:
            self.noteRefreshOutcome(nil, generation: generation)
        case let .failed(reason):
            self.noteRefreshOutcome(reason, generation: generation)
        }
        return outcome
    }

    private func readOnce(credential: HarnessgramCockpitCredential?, session: HarnessgramCockpitStore.Session, generation: UInt64) async -> ReadOutcome {
        let now = Date()
        guard let credential, credential.canRead(now: now) else {
            return .failed(.loginUnreadable)
        }
        do {
            let result = try await self.client.fetch(credential: credential, now: now)
            let fetched = result.snapshot
            // A result of an older session (switch or logout meanwhile) is dropped here.
            // The snapshot and the full open list are stored in one locked step (a list that cannot be written is
            // removed), so a stale list never hides newer decisions; a busy lock is retried, never read as "not saved".
            guard case let .completed(stored) = await self.storeRetrying({ self.store.storeSnapshot(fetched, openDecisions: result.openDecisions, forSession: session) }), let snapshot = stored else {
                return .failed(.storage)
            }
            let screen = result.screen
            await MainActor.run {
                // Only within the account generation the read started in; never written to the shared files.
                if self.uiGeneration == generation, !self.storeStateSuppressed {
                    self.latestScreen = screen
                    self.latestScreenSession = session
                }
            }
            self.refreshViewState()
            self.postSnapshotDidChange()
            if let botId = fetched.botId {
                // The bridge's own authenticated panel names its bot (getMe): the only source that pins it.
                HarnessgramBridgeIdentity.shared.observePanel(botId: botId)
            }
            WidgetCenter.shared.reloadAllTimelines()
            Task {
                guard await self.sessionIsCurrent(session) else { return }
                DispatchQueue.main.async {
                    // Checked again on main: a logout or switch after the store check has bumped the generation and
                    // ended every activity; an old account's activity must not come back after that.
                    guard self.uiGeneration == generation, !self.storeStateSuppressed, self.latestViewState?.isPaused != true else { return }
                    self.sendLiveActivityTokens()  // a fresh read: retry token changes the bridge did not take yet
                }
            }
            return .read(snapshot)
        } catch HarnessgramCockpitClient.FetchError.expired {
            _ = await self.storeValue { self.store.forgetCredential(forSession: session) }
            self.refreshViewState()
            WidgetCenter.shared.reloadAllTimelines()
            return .failed(.panelRefused)
        } catch let HarnessgramCockpitClient.FetchError.rateLimited(retryAfter) {
            await MainActor.run {
                if self.uiGeneration == generation {
                    self.pendingRetryAfter = retryAfter
                }
            }
            return .failed(.panelBusy)
        } catch HarnessgramCockpitClient.FetchError.unreachable {
            return .failed(.panelUnreachable)
        } catch HarnessgramCockpitClient.FetchError.badAnswer {
            return .failed(.panelBadAnswer)
        } catch HarnessgramCockpitClient.FetchError.noCredential {
            return .failed(.webAppElsewhere)
        } catch {
            return .failed(.panelBadAnswer)
        }
    }

    /// Use the same filtered snapshot as the app, including answers not yet persisted to the shared store.
    private func syncLiveActivityFromViewState() {
        assert(Thread.isMainThread)
        guard !self.storeStateSuppressed, let state = self.latestViewState, !state.isPaused, let snapshot = state.snapshot else {
            return
        }
        HarnessgramLiveActivityController.shared.sync(progress: snapshot.progress, waiting: HarnessgramTaskActivityPlan.Waiting(snapshot: snapshot), summaryRows: HarnessgramCockpitSnapshot.summaryRowsOn(snapshot))
    }

    /// A fresh login, or nil (callers that only refresh).
    func mintCredential(context: AccountContext, completion: @escaping (HarnessgramCockpitCredential?) -> Void) {
        self.mintLogin(context: context, completion: { outcome in
            if case let .login(credential) = outcome {
                completion(credential)
            } else {
                completion(nil)
            }
        })
    }

    enum MintOutcome {
        case login(HarnessgramCockpitCredential)
        case failed(HarnessgramPairFailure)
    }

    /// How long Telegram may take for the three steps (resolve, bot info, web app), the home relay included.
    static let mintTimeout: Double = 30.0

    /// A fresh login, the way Telegram opens the bridge's Cockpit: the bot's menu-button web app (as a menu tap does),
    /// else its Main App. The login is kept only when the signed URL matches an HTTPS origin authorized by the local
    /// pairing configuration. Each step that fails says why (HarnessgramPairFailure).
    func mintLogin(context: AccountContext, completion: @escaping (MintOutcome) -> Void) {
        guard !HarnessgramAgentChat.bridgeBotResolveName.isEmpty else {
            completion(.failed(.botNotFound))
            return
        }
        let engine = context.engine
        let fail: (HarnessgramPairFailure) -> Signal<MintOutcome, NoError> = { .single(.failed($0)) }
        let signed: (Signal<RequestWebViewResult, RequestWebViewError>) -> Signal<MintOutcome?, NoError> = { request in
            return request
            |> map { result -> MintOutcome? in
                guard HarnessgramCockpitCredential.origin(ofMenuURL: result.url) != nil else {
                    return .failed(.webAppElsewhere)
                }
                guard let credential = HarnessgramCockpitCredential.from(webAppURL: result.url, menuURL: result.url) else {
                    return .failed(.loginUnreadable)
                }
                return .login(credential)
            }
            |> `catch` { _ -> Signal<MintOutcome?, NoError> in
                return .single(nil)
            }
        }
        let signal: Signal<MintOutcome, NoError> = engine.peers.resolvePeerByName(name: HarnessgramAgentChat.bridgeBotResolveName, referrer: nil)
        |> mapToSignal { result -> Signal<EnginePeer?, NoError> in
            guard case let .result(peer) = result else {
                return .complete()
            }
            return .single(peer)
        }
        |> take(1)
        |> mapToSignal { peer -> Signal<MintOutcome, NoError> in
            guard let peer, case let .user(user) = peer, let botInfo = user.botInfo, HarnessgramAgentChat.isBridgeBot(username: user.addressName) else {
                return fail(.botNotFound)
            }
            // The username is not trusted to name the bridge (build 15): its id is pinned only from the bridge's own
            // panel. Once pinned, the login goes only to that bot; before that, the configured HTTPS origin/network
            // is what keeps it with the user's bridge.
            guard HarnessgramBridgeIdentity.shared.mayLogIn(userId: peer.id.id._internalGetInt64Value()) else {
                return fail(.botChanged)
            }
            let hasMainApp = botInfo.flags.contains(.hasWebApp)
            return engine.peers.fetchAndUpdateCachedPeerData(peerId: peer.id)
            |> take(1)
            |> mapToSignal { _ -> Signal<MintOutcome, NoError> in
                return engine.data.get(TelegramEngine.EngineData.Item.Peer.BotMenu(id: peer.id))
                |> mapToSignal { menu -> Signal<MintOutcome, NoError> in
                    let mainApp: Signal<MintOutcome, NoError> = hasMainApp ? (signed(engine.messages.requestMainWebView(peerId: peer.id, botId: peer.id, source: .generic, themeParams: nil)) |> map { $0 ?? .failed(.loginRefused) }) : fail(.noWebApp)
                    guard let menu, case let .webView(_, url) = menu else {
                        return mainApp
                    }
                    guard HarnessgramCockpitCredential.origin(ofMenuURL: url) != nil else {
                        return hasMainApp ? mainApp : fail(.webAppElsewhere)
                    }
                    // A menu tap: messages.requestWebView from the bot menu. A simple web view with the same URL is
                    // the fallback, then the Main App.
                    return signed(engine.messages.requestWebView(peerId: peer.id, botId: peer.id, url: url, payload: nil, themeParams: nil, fromMenu: true, replyToMessageId: nil, threadId: nil))
                    |> mapToSignal { outcome -> Signal<MintOutcome, NoError> in
                        if let outcome {
                            return .single(outcome)
                        }
                        return signed(engine.messages.requestSimpleWebView(botId: peer.id, url: url, source: .generic, themeParams: nil))
                        |> mapToSignal { outcome -> Signal<MintOutcome, NoError> in
                            if let outcome {
                                return .single(outcome)
                            }
                            return hasMainApp ? mainApp : fail(.loginRefused)
                        }
                    }
                }
            }
        }
        |> timeout(HarnessgramCockpitSync.mintTimeout, queue: Queue.mainQueue(), alternate: .single(.failed(.timedOut)))
        |> deliverOnMainQueue

        // One disposable per request: a decide link while a refresh mints must not cancel the refresh.
        // The completion runs exactly once; a chain that ends without a value found no bot.
        var finished = false
        let finish: (MintOutcome) -> Void = { outcome in
            if !finished {
                finished = true
                completion(outcome)
            }
        }
        let disposable = MetaDisposable()
        self.mintDisposables.add(disposable)
        disposable.set(signal.start(next: { outcome in
            finish(outcome)
        }, completed: { [weak self] in
            finish(.failed(.botNotFound))
            self?.mintDisposables.remove(disposable)
        }))
    }

    /// The decision behind a widget decide link, as the Cockpit has it now (never from the link alone), with the
    /// session it belongs to. Nothing (all nil) when the session changes while the login is minted.
    public func openDecision(context: AccountContext, id: String, completion: @escaping (HarnessgramCockpitSnapshot.Decision?, HarnessgramCockpitCredential?, HarnessgramCockpitStore.Session?) -> Void) {
        assert(Thread.isMainThread)
        guard !self.storeStateSuppressed else { completion(nil, nil, nil); return }
        let generation = self.uiGeneration
        Task {
            guard let session = await self.currentSession(), session.accountId == HarnessgramCockpitSync.accountId(context) else {
                DispatchQueue.main.async { completion(nil, nil, nil) }
                return
            }
            DispatchQueue.main.async {
                self.mintCredential(context: context, completion: { minted in
                    Task {
                        guard await self.sessionIsCurrent(session) else {
                            DispatchQueue.main.async { completion(nil, nil, nil) }
                            return
                        }
                        let credential: HarnessgramCockpitCredential?
                        if let minted {
                            _ = await self.storeSaveRetrying { self.store.saveCredential(minted, forSession: session) }
                            credential = minted
                        } else {
                            credential = await self.storeValue { self.store.loadCredential(forSession: session) }
                        }
                        let snapshot = await self.refreshSnapshot(credential: credential, session: session)
                        let decision = snapshot?.decisions.first(where: { $0.id == id })
                        DispatchQueue.main.async {
                            guard self.uiGeneration == generation, self.latestViewState?.session == session else {
                                completion(nil, nil, nil)
                                return
                            }
                            completion(decision, snapshot == nil ? nil : credential, session)
                        }
                    }
                })
            }
        }
    }

    /// Sends the owner's answer from the app. A sensitive decision first needs Face ID (or the passcode).
    public func answerUsingStoredCredential(context: AccountContext, decision: HarnessgramCockpitSnapshot.Decision, choice: HarnessgramCockpitLinks.Choice, completion: @escaping (AnswerResult) -> Void) {
        assert(Thread.isMainThread)
        guard let visibleState = self.latestViewState, !visibleState.isPaused, visibleState.session?.accountId == HarnessgramCockpitSync.accountId(context) else {
            completion(.unavailable)
            return
        }
        let generation = self.uiGeneration
        Task {
            // A busy store is retried and then reported as unavailable, never as "no session".
            guard case let .completed(session) = await self.storeRetrying({ self.store.sessionChecked() }) else {
                DispatchQueue.main.async { completion(.unavailable) }
                return
            }
            let credential = await self.storeValue { self.store.loadCredential(forSession: session) }
            guard await MainActor.run(body: { generation == self.uiGeneration && self.latestViewState?.session == session }) else {
                DispatchQueue.main.async { completion(.unavailable) }
                return
            }
            if let session, session.accountId == HarnessgramCockpitSync.accountId(context), let credential, credential.canAnswer(now: Date()) {
                DispatchQueue.main.async {
                    self.answer(decision: decision, choice: choice, credential: credential, session: session, completion: completion)
                }
                return
            }
            // openDecision reads and changes main-queue state: it starts on main, and only in the same generation.
            DispatchQueue.main.async {
                guard generation == self.uiGeneration, !self.storeStateSuppressed else {
                    completion(.unavailable)
                    return
                }
                self.openDecision(context: context, id: decision.id, completion: { _, credential, session in
                    guard let credential, let session else {
                        completion(.unavailable)
                        return
                    }
                    self.answer(decision: decision, choice: choice, credential: credential, session: session, completion: completion)
                })
            }
        }
    }

    /// Sends the owner's answer from the app. A sensitive decision first needs Face ID (or the passcode).
    public func answer(decision: HarnessgramCockpitSnapshot.Decision, choice: HarnessgramCockpitLinks.Choice, credential: HarnessgramCockpitCredential, session: HarnessgramCockpitStore.Session, completion: @escaping (AnswerResult) -> Void) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.answer(decision: decision, choice: choice, credential: credential, session: session, completion: completion) }
            return
        }
        let generation = self.uiGeneration
        guard !self.storeStateSuppressed, let state = self.latestViewState, state.session == session, !state.isPaused else {
            completion(.unavailable)
            return
        }
        let send: () -> Void = { [weak self] in
            guard let self else {
                return
            }
            Task {
                guard await MainActor.run(body: {
                    self.uiGeneration == generation && !self.storeStateSuppressed && self.latestViewState?.session == session && self.latestViewState?.isPaused == false
                }) else {
                    DispatchQueue.main.async { completion(.unavailable) }
                    return
                }
                // A switch or logout since the decision was opened (or during Face ID) sends nothing.
                // Checked again inside the task, right before the request opens (build 16).
                guard await self.storeValue({
                    self.storageGeneration.with({ $0 }) == generation && self.store.isCurrent(session)
                }) else {
                    DispatchQueue.main.async {
                        completion(.unavailable)
                    }
                    return
                }
                guard await MainActor.run(body: {
                    self.storageGeneration.with({ $0 }) == generation && !self.storeStateSuppressed && self.latestViewState?.session == session
                }) else {
                    DispatchQueue.main.async { completion(.unavailable) }
                    return
                }
                let outcome = await self.client.answer(id: decision.id, choice: choice, credential: credential, now: Date())
                let result: AnswerResult
                switch outcome {
                case .sent:
                    result = .sent
                case .closed:
                    result = .gone
                case .expired:
                    _ = await self.storeValue { self.store.forgetCredential(forSession: session) }
                    result = .unavailable
                case .failed:
                    result = .unavailable
                }
                if result == .sent || result == .gone {
                    // Hidden in the app at once, then remembered in the shared files; a busy lock is retried (bounded)
                    // and the decision stays hidden here meanwhile, so an older snapshot cannot bring it back.
                    await MainActor.run {
                        guard self.uiGeneration == generation else { return }
                        self.locallyAnswered[decision.id] = Date()
                        if let state = self.latestViewState {
                            self.latestViewState = self.hidingLocallyAnswered(state)
                        }
                        self.syncLiveActivityFromViewState()
                    }
                    // Still busy after the retries: the store keeps it pending and writes it with its next locked write.
                    _ = await self.storeRetrying(attempts: 6, { self.store.markAnsweredChecked(decision.id, forSession: session) })
                    self.refreshViewState()
                    self.postSnapshotDidChange()
                }
                WidgetCenter.shared.reloadAllTimelines()
                DispatchQueue.main.async {
                    completion(result)
                }
            }
        }
        if decision.sensitive {
            HarnessgramOwnerConfirmation.shared.confirm(reason: HarnessgramWidgetStrings.confirmFaceIDReason, completion: { confirmed in
                if confirmed {
                    send()
                } else {
                    completion(.notConfirmed)
                }
            })
        } else {
            send()
        }
    }

    // MARK: The native Cockpit's answers

    /// One picture of a decision for the native Cockpit (rich decisions): the stored login of the current session,
    /// the card-media token, then the image; nil on any failure or once the session changed.
    public func decisionImage(id: String) async -> Data? {
        guard let session = await MainActor.run(body: { self.storeStateSuppressed ? nil : self.latestViewState?.session }) else {
            return nil
        }
        guard let credential = await self.storeValue({ self.store.loadCredential(forSession: session) }) else {
            return nil
        }
        let data = await self.client.cardImage(id: id, credential: credential, now: Date())
        guard await MainActor.run(body: { self.latestViewState?.session == session }) else {
            return nil
        }
        return data
    }

    /// The owner's comment on a decision without deciding (rich decisions): Face ID first (it reaches a live session),
    /// then a login that can answer for the same bridge the decision came from, then `choice: "reply"`. Nothing is
    /// approved; the decision stays open. Main actor in and out.
    @MainActor
    public func commentFromNativeCockpit(context: AccountContext, decision: HarnessgramCockpitScreen.Decision, text: String, reason: String, completion: @escaping @MainActor (HarnessgramDecisionComment.Result) -> Void) {
        let accountId = HarnessgramCockpitSync.accountId(context)
        guard decision.extras.commentAllowed, decision.permissionRequest == nil, HarnessgramDecisionComment.body(id: decision.id, text: text) != nil, let session = self.latestViewState?.session, session.accountId == accountId else {
            completion(.refused)
            return
        }
        let generation = self.uiGeneration
        HarnessgramOwnerConfirmation.shared.confirm(reason: reason, policy: .biometrics, completion: { [weak self] confirmed in
            guard let self else { return }
            guard confirmed else {
                completion(.notConfirmed)
                return
            }
            Task { @MainActor in
                guard let credential = await self.answerCredential(context: context, decision: decision, session: session, generation: generation), self.uiGeneration == generation, self.latestViewState?.session == session else {
                    completion(.loginExpired)
                    return
                }
                let result = await self.client.comment(id: decision.id, text: text, credential: credential, now: Date())
                completion(result)
                self.refresh(context: context, force: true)
            }
        })
    }

    /// A yes or no from the native Cockpit (HarnessgramDecisionAnswer): Face ID first for anything not explicitly
    /// routine, then a login fresh enough to answer (a new one is minted when the stored one is too old), sent only while
    /// the account and its session are still the ones the screen showed. An answer the bridge took, or one it says was
    /// closed already, is hidden at once, as for the widgets' answers; then the Cockpit is read again.
    @MainActor
    public func answerFromNativeCockpit(
        context: AccountContext,
        decision: HarnessgramCockpitScreen.Decision,
        choice: HarnessgramCockpitLinks.Choice,
        note: String,
        reason: String,
        stillAllowed: @escaping @MainActor () -> Bool,
        willSend: @escaping @MainActor () -> Void,
        completion: @escaping @MainActor (HarnessgramDecisionAnswer.Result) -> Void
    ) {
        let accountId = HarnessgramCockpitSync.accountId(context)
        guard stillAllowed(), let session = self.latestViewState?.session, session.accountId == accountId,
              self.canSendNativeAnswer(decision, choice: choice, note: note, session: session, generation: self.uiGeneration) else {
            completion(.cancelledLocally)
            return
        }
        let generation = self.uiGeneration
        Task { @MainActor in
            var sessionConfirmed = false
            let result = await HarnessgramDecisionAnswer.run(
                decision: decision,
                choice: choice,
                note: note,
                reason: reason,
                confirm: { reason in
                    await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                        DispatchQueue.main.async {
                            HarnessgramOwnerConfirmation.shared.confirm(reason: reason, policy: .biometrics, completion: { confirmed in
                                continuation.resume(returning: confirmed)
                            })
                        }
                    }
                },
                credential: {
                    let login = await self.answerCredential(context: context, decision: decision, session: session, generation: generation)
                    sessionConfirmed = await self.sessionIsCurrent(session)
                    return login
                },
                stillAllowed: {
                    sessionConfirmed && stillAllowed() && self.canSendNativeAnswer(decision, choice: choice, note: note, session: session, generation: generation)
                },
                willSend: willSend,
                onLoginRejected: { login in
                    await self.storeValue { self.store.forgetCredential(forSession: session, matching: login) }
                },
                transport: self.client.transport,
                now: { Date() }
            )
            switch result {
            case .sent, .alreadyClosed:
                if self.uiGeneration == generation {
                    self.locallyAnswered[decision.id] = Date()
                    if let state = self.latestViewState {
                        self.latestViewState = self.hidingLocallyAnswered(state)
                    }
                    self.syncLiveActivityFromViewState()
                }
                _ = await self.storeRetrying(attempts: 6, { self.store.markAnsweredChecked(decision.id, forSession: session) })
                self.refreshViewState()
                self.postSnapshotDidChange()
                WidgetCenter.shared.reloadAllTimelines()
            default:
                break
            }

            // Report the actual result even if the account changed after sending; the answer guard still owns it.
            if self.uiGeneration == generation, case let .busy(retryAfter) = result {
                self.pollSchedule.noteFailure(now: Date(), retryAfter: retryAfter)
            }
            completion(result)
            if self.uiGeneration == generation, result != .cancelledLocally {
                self.refresh(context: context, force: true)
            }
        }
    }

    @MainActor
    private func canSendNativeAnswer(_ decision: HarnessgramCockpitScreen.Decision, choice: HarnessgramCockpitLinks.Choice, note: String, session: HarnessgramCockpitStore.Session, generation: UInt64) -> Bool {
        guard HarnessgramSettings.shared.houseFeature(.nativeCockpit), self.uiGeneration == generation,
              !self.storeStateSuppressed, self.hasSingleAccount, self.lastPrimary == session.accountId,
              let state = self.latestViewState, !state.isPaused, state.session == session, self.latestScreenSession == session,
              state.openDecisions?.contains(where: { $0.id == decision.id }) != false else {
            return false
        }
        guard let screen = self.screen, let latest = screen.decision(id: decision.id),
              HarnessgramAnswerGuard.sameOrigin(shown: decision.bridgeOrigin, minted: latest.bridgeOrigin),
              !latest.requiresOwnerCheck || decision.requiresOwnerCheck,
              !screen.deliveries.contains(where: { $0.id == decision.id }) else {
            return false
        }
        return HarnessgramDecisionAnswer.mayAnswer(latest, choice: choice, note: note)
    }

    /// Use the stored login while it can still answer, otherwise ask Telegram for a new one.
    @MainActor
    private func answerCredential(context: AccountContext, decision: HarnessgramCockpitScreen.Decision, session: HarnessgramCockpitStore.Session, generation: UInt64) async -> HarnessgramCockpitCredential? {
        guard self.uiGeneration == generation, await self.sessionIsCurrent(session),
              let stored = await self.storeValue({ self.store.loadCredential(forSession: session) }) else {
            return nil
        }
        if stored.canAnswer(now: Date()) {
            return stored
        }
        guard self.uiGeneration == generation else { return nil }
        let minted: HarnessgramCockpitCredential? = await withCheckedContinuation { continuation in
            self.mintCredential(context: context, completion: { credential in
                continuation.resume(returning: credential)
            })
        }
        if let minted, HarnessgramDecisionAnswer.matchesBridge(minted, for: decision), self.uiGeneration == generation {
            _ = await self.storeSaveRetrying { self.store.saveCredential(minted, forSession: session) }
        }
        return minted
    }
}

/// The timer behind `pollWhileVisible`: one read at a time, the next one armed when the last one ended. Main queue.
final class HarnessgramCockpitVisiblePoller {
    let base: TimeInterval
    var read: (() -> Void)?
    private var timer: SwiftSignalKit.Timer?
    private var stopped = false

    init(base: TimeInterval) {
        self.base = base
    }

    func arm(delay: TimeInterval) {
        assert(Thread.isMainThread)
        guard !self.stopped else {
            return
        }
        self.timer?.invalidate()
        let timer = SwiftSignalKit.Timer(timeout: max(1.0, delay), repeat: false, completion: { [weak self] in
            guard let self, !self.stopped else {
                return
            }
            self.timer = nil
            self.read?()
        }, queue: Queue.mainQueue())
        self.timer = timer
        timer.start()
    }

    func stop() {
        assert(Thread.isMainThread)
        self.stopped = true
        self.timer?.invalidate()
        self.timer = nil
        self.read = nil
    }
}
