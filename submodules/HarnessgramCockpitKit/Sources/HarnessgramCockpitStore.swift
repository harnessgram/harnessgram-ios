import Foundation
import Darwin
import os

/// The app group folder the app and the widget extension share: the last snapshot and the Cockpit login.
/// The snapshot is readable after the first unlock (so the lock screen widget can show the count); the
/// login uses complete protection, so it cannot be read at all while the phone is locked: no widget
/// button can answer from a locked phone even if iOS were to run it.
///
/// Build 15 (review P1/P2, one design): an account session = the active account plus a random epoch that changes on
/// every real account change and on logout. Every asynchronous result (a login, a refresh, a widget timeline, a widget
/// answer) captures the session at its start and is dropped if the session changed meanwhile; nothing but a real
/// account change (`setActiveAccount`) can change it.
///
/// Build 14 (review P1/P2):
/// - Everything is kept per Telegram account (`accounts/<account peer id>/`) and only the active account's
///   files are read. The app sets the active account whenever it changes; logging out (nil) or switching
///   removes every other account's snapshot and login, so a widget can never answer with an earlier
///   account's login.
/// - Every change goes through one cross-process lock (`flock` on a file in the folder), so the app and
///   the widget extension never overwrite each other's update. An answered decision is remembered for a
///   while and never comes back from an older snapshot.
public final class HarnessgramCockpitStore {
    public static let shared = HarnessgramCockpitStore(
        directory: HarnessgramCockpitStore.appGroupDirectory(),
        now: Date.init,
        requiresBackground: Bundle.main.bundleURL.pathExtension != "appex"
    )

    static let folderName = "harnessgram-cockpit"
    static let accountsFolderName = "accounts"
    static let activeAccountName = "active-account.json"
    static let snapshotName = "snapshot.json"
    static let credentialName = "login.json"
    static let answeredName = "answered.json"
    /// The app's full list of open decisions (the widget snapshot keeps only `HarnessgramCockpitSnapshot.maxDecisions`).
    /// Only the app reads and writes it; it is removed with the rest of an account's files.
    static let openDecisionsName = "open-decisions.json"
    static let lockName = ".lock"
    static let pausedName = "paused"
    static let chatWidgetShownName = "chat-widget-shown.json"
    /// How long an answered decision stays out of later snapshots (the bridge drops it well within this).
    public static let answeredMemory: TimeInterval = 15 * 60
    /// Storage never waits indefinitely for another app-group client. UI callers must still use a background queue.
    static let lockTimeout: TimeInterval = 0.05
    static let lockRetryNanoseconds: UInt64 = 1_000_000
    private static let lockLogger = Logger(subsystem: "HarnessgramCockpitKit", category: "StoreLock")

    private struct ActiveAccount: Codable {
        var accountId: Int64
        var epoch: String?
    }

    /// The active account and the epoch of its current session.
    public struct Session: Equatable, Sendable {
        public let accountId: Int64
        public let epoch: String

        public init(accountId: Int64, epoch: String) {
            self.accountId = accountId
            self.epoch = epoch
        }
    }

    /// One atomic read of everything a widget answer needs: the session, its snapshot and its login.
    public struct AnswerContext {
        public let session: Session
        public let snapshot: HarnessgramCockpitSnapshot
        public let credential: HarnessgramCockpitCredential?
    }

    /// One read for app UI. Call this away from the main thread and publish the value in memory.
    public struct ViewState: Sendable, Equatable {
        public let session: Session?
        public let isPaused: Bool
        public let hasLogin: Bool
        public let credentialCanAnswer: Bool
        public let bridgeOrigin: String?
        public let snapshot: HarnessgramCockpitSnapshot?
        public let openDecisions: [HarnessgramCockpitSnapshot.Decision]?

        public init(session: Session?, isPaused: Bool, hasLogin: Bool, credentialCanAnswer: Bool = false, bridgeOrigin: String? = nil, snapshot: HarnessgramCockpitSnapshot?, openDecisions: [HarnessgramCockpitSnapshot.Decision]?) {
            self.session = session
            self.isPaused = isPaused
            self.hasLogin = hasLogin
            self.credentialCanAnswer = credentialCanAnswer
            self.bridgeOrigin = bridgeOrigin
            self.snapshot = snapshot
            self.openDecisions = openDecisions
        }
    }

    /// A store call that says whether it ran. `lockUnavailable`: the lock (or, for a write, the write itself) was not
    /// available, so nothing is known. It never means "logged out", "paused", "no decisions" or "nothing saved".
    public enum MutationResult<Value> {
        case completed(Value)
        case lockUnavailable

        /// The value when the call ran; nil when the lock was unavailable.
        public var completedValue: Value? {
            if case let .completed(value) = self {
                return value
            }
            return nil
        }
    }

    /// `retrying` for a background thread that may block briefly (never the main thread).
    public static func retryingBlocking<T>(attempts: Int = 4, initialDelay: TimeInterval = 0.05, _ operation: () -> MutationResult<T>) -> MutationResult<T> {
        var delay = initialDelay
        for attempt in 0 ..< max(1, attempts) {
            let result = operation()
            if case .completed = result {
                return result
            }
            if attempt + 1 < attempts {
                usleep(UInt32(delay * 1_000_000))
                delay *= 2
            }
        }
        return .lockUnavailable
    }

    /// Runs `operation` up to `attempts` times while it reports `lockUnavailable`, waiting a little longer each time
    /// (off the calling actor's thread). For extension and background callers; app UI goes through its storage queue.
    public static func retrying<T>(attempts: Int = 4, initialDelay: TimeInterval = 0.05, _ operation: () -> MutationResult<T>) async -> MutationResult<T> {
        var delay = initialDelay
        for attempt in 0 ..< max(1, attempts) {
            let result = operation()
            if case .completed = result {
                return result
            }
            if attempt + 1 < attempts {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                delay *= 2
            }
        }
        return .lockUnavailable
    }

    private let directory: URL?
    private let threadLock = NSLock()
    /// Answers the bridge accepted that could not be written yet (busy lock or failed write). Kept for this process's
    /// lifetime, applied by every later read of the answered list and written by the next successful locked write.
    private let pendingLock = NSLock()
    private var pendingAnswered: [String: (session: Session?, at: Date)] = [:]
    private let now: () -> Date
    private let requiresBackground: Bool

    /// Isolated stores (including tests) retain the synchronous API; app UI uses the shared background-only store.
    public convenience init(directory: URL?, now: @escaping () -> Date = Date.init) {
        self.init(directory: directory, now: now, requiresBackground: false)
    }

    private init(directory: URL?, now: @escaping () -> Date, requiresBackground: Bool) {
        self.directory = directory
        self.now = now
        self.requiresBackground = requiresBackground
    }

    /// `group.<base bundle id>/harnessgram-cockpit`; an extension drops its own last bundle id component
    /// (the HarnessgramSettings rule).
    public static func appGroupDirectory() -> URL? {
        guard var id = Bundle.main.bundleIdentifier else {
            return nil
        }
        if Bundle.main.bundleURL.pathExtension == "appex", let dot = id.range(of: ".", options: .backwards) {
            id = String(id[..<dot.lowerBound])
        }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group." + id)?.appendingPathComponent(folderName, isDirectory: true)
    }

    // MARK: Account

    /// The Telegram account the widgets act for, or nil (logged out: nothing is shown or answered).
    public var activeAccount: Int64? {
        return self.session?.accountId
    }

    /// The current session, or nil when logged out.
    public var session: Session? {
        return self.locked(failure: nil) {
            return self.sessionLocked()
        }
    }

    /// The current session (nil: logged out or paused), or `lockUnavailable` when that could not be read.
    public func sessionChecked() -> MutationResult<Session?> {
        return self.lockedChecked { () -> Session? in
            return self.sessionLocked()
        }
    }

    /// Whether `session` is still the current one (an async result checks this before it is used). A lock timeout
    /// reads as false here (fail closed); callers that must tell the two apart use `isCurrentChecked`.
    public func isCurrent(_ session: Session) -> Bool {
        return self.session == session
    }

    public func isCurrentChecked(_ session: Session) -> MutationResult<Bool> {
        return self.lockedChecked { () -> Bool in
            return self.sessionLocked() == session
        }
    }

    /// Build 16: the Cockpit, the widgets and the Live Activity work only while exactly one Telegram account is logged
    /// in. A second login, a switch or a logout pauses them: everything is wiped and nothing starts again until the
    /// owner re-pairs (`resume`). No restore logic.
    public var isPaused: Bool {
        return self.isPausedChecked().completedValue ?? false
    }

    /// `isPaused`, or `lockUnavailable` (which never means "not paused").
    public func isPausedChecked() -> MutationResult<Bool> {
        return self.lockedChecked { () -> Bool in
            guard let directory = self.directory else {
                return false
            }
            return FileManager.default.fileExists(atPath: directory.appendingPathComponent(HarnessgramCockpitStore.pausedName, isDirectory: false).path)
        }
    }

    /// Wipes every account's files, the session and the build 13 files, and stays off until `resume`.
    public func pause() {
        _ = self.pauseChecked()
    }

    @discardableResult
    public func pauseChecked() -> Bool {
        return self.locked(failure: false) {
            guard let directory = self.directory else {
                return false
            }
            let pausedURL = directory.appendingPathComponent(HarnessgramCockpitStore.pausedName, isDirectory: false)
            guard (try? Data().write(to: pausedURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])) != nil else { return false }
            let removedLegacy = self.removeLegacyFilesChecked()
            let removedAccounts = self.removeIfPresent(directory.appendingPathComponent(HarnessgramCockpitStore.accountsFolderName, isDirectory: true))
            let removedActive = self.removeIfPresent(directory.appendingPathComponent(HarnessgramCockpitStore.activeAccountName, isDirectory: false))
            return removedLegacy && removedAccounts && removedActive
        }
    }

    /// The owner re-paired with exactly one account logged in: a fresh session for it.
    @discardableResult
    public func resume(accountId: Int64) -> Session? {
        return self.locked(failure: nil) {
            guard let directory = self.directory else { return nil }
            let pausedURL = directory.appendingPathComponent(HarnessgramCockpitStore.pausedName, isDirectory: false)
            if !FileManager.default.fileExists(atPath: pausedURL.path) {
                guard (try? Data().write(to: pausedURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])) != nil else { return nil }
            }
            guard self.removeLegacyFilesChecked(),
                  self.removeIfPresent(directory.appendingPathComponent(HarnessgramCockpitStore.accountsFolderName, isDirectory: true)),
                  self.removeIfPresent(directory.appendingPathComponent(HarnessgramCockpitStore.activeAccountName, isDirectory: false)) else { return nil }
            let session = Session(accountId: accountId, epoch: UUID().uuidString)
            let activeURL = directory.appendingPathComponent(HarnessgramCockpitStore.activeAccountName, isDirectory: false)
            guard self.writeLocked(ActiveAccount(accountId: accountId, epoch: session.epoch), to: activeURL, protection: .completeFileProtectionUntilFirstUserAuthentication),
                  self.removeIfPresent(pausedURL) else { return nil }
            return session
        }
    }

    /// Only a real account change calls this (the app's account and login events; nil when logged out).
    /// While paused it does nothing and returns nil. The same
    /// account keeps its session; another account, or logout, starts a new epoch and removes every other account's
    /// files and the build 13 files at the folder's root.
    @discardableResult
    public func setActiveAccount(_ accountId: Int64?) -> Session? {
        switch self.setActiveAccountChecked(accountId) {
        case let .completed(session): return session
        case .lockUnavailable: return nil
        }
    }

    public func setActiveAccountChecked(_ accountId: Int64?) -> MutationResult<Session?> {
        return self.locked(failure: .lockUnavailable) {
            let result = self.setActiveAccountLocked(accountId)
            if case .lockUnavailable = result, let directory = self.directory {
                let pausedURL = directory.appendingPathComponent(HarnessgramCockpitStore.pausedName, isDirectory: false)
                _ = try? Data().write(to: pausedURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            }
            return result
        }
    }

    private func setActiveAccountLocked(_ accountId: Int64?) -> MutationResult<Session?> {
        guard let directory = self.directory else { return .completed(nil) }
        guard self.removeLegacyFilesChecked() else { return .lockUnavailable }
        if FileManager.default.fileExists(atPath: directory.appendingPathComponent(HarnessgramCockpitStore.pausedName, isDirectory: false).path) {
            return .completed(nil)
        }
        if let accountId, let current = self.sessionLocked(), current.accountId == accountId {
            return .completed(current)
        }
        let accounts = directory.appendingPathComponent(HarnessgramCockpitStore.accountsFolderName, isDirectory: true)
        let accountNames: [String]
        if FileManager.default.fileExists(atPath: accounts.path) {
            do {
                accountNames = try FileManager.default.contentsOfDirectory(atPath: accounts.path)
            } catch {
                return .lockUnavailable
            }
        } else {
            accountNames = []
        }
        for name in accountNames {
            guard self.removeIfPresent(accounts.appendingPathComponent(name, isDirectory: true)) else { return .lockUnavailable }
        }
        let activeURL = directory.appendingPathComponent(HarnessgramCockpitStore.activeAccountName, isDirectory: false)
        guard let accountId else {
            return self.removeIfPresent(activeURL) ? .completed(nil) : .lockUnavailable
        }
        let session = Session(accountId: accountId, epoch: UUID().uuidString)
        guard self.writeLocked(ActiveAccount(accountId: accountId, epoch: session.epoch), to: activeURL, protection: .completeFileProtectionUntilFirstUserAuthentication) else {
            return .lockUnavailable
        }
        return .completed(session)
    }

    /// Removes the build 13 files (`login.json`, `snapshot.json` directly in the folder).
    public func removeLegacyFiles() {
        self.locked(failure: ()) {
            self.removeLegacyFilesLocked()
        }
    }

    /// Paired with the bridge for the current session: a login was saved (checked by its presence, so it also works
    /// while the phone is locked and the login itself cannot be read).
    public var hasLogin: Bool {
        return self.hasLoginChecked().completedValue ?? false
    }

    /// `hasLogin`, or `lockUnavailable` (which never means "not paired").
    public func hasLoginChecked() -> MutationResult<Bool> {
        return self.lockedChecked { () -> Bool in
            guard let url = self.accountFileLocked(HarnessgramCockpitStore.credentialName, session: nil) else {
                return false
            }
            return FileManager.default.fileExists(atPath: url.path)
        }
    }

    /// The widget answer's context in one read under the lock. nil both when there is none and when the lock was
    /// unavailable; a caller that shows state uses `answerContextChecked` to tell them apart.
    public func answerContext() -> AnswerContext? {
        return self.answerContextChecked().completedValue ?? nil
    }

    /// `.completed(nil)`: no session or no snapshot. `.lockUnavailable`: unknown, keep what is shown and retry.
    public func answerContextChecked() -> MutationResult<AnswerContext?> {
        return self.lockedChecked { () -> AnswerContext? in
            guard let session = self.sessionLocked(), let snapshotURL = self.accountFileLocked(HarnessgramCockpitStore.snapshotName, session: session), var snapshot: HarnessgramCockpitSnapshot = self.readLocked(snapshotURL) else {
                return nil
            }
            // Answered decisions stay out of reads too, including answers whose save is still pending.
            for id in self.answeredLocked(session: session).keys {
                snapshot = snapshot.removingDecision(id)
            }
            var credential: HarnessgramCockpitCredential?
            if let url = self.accountFileLocked(HarnessgramCockpitStore.credentialName, session: session), let value: HarnessgramCockpitCredential = self.readLocked(url), value.originURL != nil {
                credential = value
            }
            return AnswerContext(session: session, snapshot: snapshot, credential: credential)
        }
    }

    /// A consistent UI snapshot under the same app/widget lock. Lock failure returns nil and never reads unlocked.
    public func viewState() -> ViewState? {
        return self.locked(failure: nil) {
            let session = self.sessionLocked()
            let pausedURL = self.directory?.appendingPathComponent(HarnessgramCockpitStore.pausedName, isDirectory: false)
            let isPaused = pausedURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
            let hasLogin = self.accountFileLocked(HarnessgramCockpitStore.credentialName, session: nil).map { FileManager.default.fileExists(atPath: $0.path) } ?? false
            let snapshotURL = self.accountFileLocked(HarnessgramCockpitStore.snapshotName, session: nil)
            let openURL = self.accountFileLocked(HarnessgramCockpitStore.openDecisionsName, session: nil)
            let snapshot: HarnessgramCockpitSnapshot? = snapshotURL.flatMap { self.readLocked($0) }
            let openDecisions: [HarnessgramCockpitSnapshot.Decision]? = openURL.flatMap { self.readLocked($0) }
            let credentialURL = self.accountFileLocked(HarnessgramCockpitStore.credentialName, session: nil)
            let credential: HarnessgramCockpitCredential? = credentialURL.flatMap { self.readLocked($0) }
            return ViewState(session: session, isPaused: isPaused, hasLogin: hasLogin, credentialCanAnswer: credential?.canAnswer(now: self.now()) ?? false, bridgeOrigin: isPaused ? nil : credential?.originURL?.absoluteString, snapshot: snapshot, openDecisions: openDecisions)
        }
    }

    // MARK: Snapshot

    public func loadSnapshot(forSession session: Session? = nil) -> HarnessgramCockpitSnapshot? {
        return self.locked(failure: nil) {
            guard let url = self.accountFileLocked(HarnessgramCockpitStore.snapshotName, session: session) else {
                return nil
            }
            return self.readLocked(url)
        }
    }

    /// A snapshot fetched in `session` (nil: whichever session is current). Refused when that session is no longer the
    /// current one. Decisions answered meanwhile stay out.
    @discardableResult
    public func saveSnapshot(_ snapshot: HarnessgramCockpitSnapshot, forSession session: Session? = nil) -> Bool {
        return self.locked(failure: false) {
            self.flushPendingAnsweredLocked()
            guard let url = self.accountFileLocked(HarnessgramCockpitStore.snapshotName, session: session) else {
                return false
            }
            let answered = self.answeredLocked(session: session)
            var filtered = snapshot
            for id in answered.keys {
                filtered = filtered.removingDecision(id)
            }
            return self.writeLocked(filtered, to: url, protection: .completeFileProtectionUntilFirstUserAuthentication)
        }
    }

    /// One refresh's result, written in one step under the lock: the snapshot and (when given) the app's full list of
    /// open decisions, so a stale list can never outlive a newer snapshot. If the list cannot be written it is removed
    /// (readers then fall back to the snapshot). `.completed(stored)` is the stored (filtered) snapshot, or nil when
    /// `session` is no longer current or the snapshot write failed; `.lockUnavailable`: nothing was read or written.
    public func storeSnapshot(_ snapshot: HarnessgramCockpitSnapshot, openDecisions: [HarnessgramCockpitSnapshot.Decision]?, forSession session: Session? = nil) -> MutationResult<HarnessgramCockpitSnapshot?> {
        return self.lockedChecked { () -> HarnessgramCockpitSnapshot? in
            self.flushPendingAnsweredLocked()
            guard let url = self.accountFileLocked(HarnessgramCockpitStore.snapshotName, session: session) else {
                return nil
            }
            let answered = self.answeredLocked(session: session)
            var filtered = snapshot
            for id in answered.keys {
                filtered = filtered.removingDecision(id)
            }
            guard self.writeLocked(filtered, to: url, protection: .completeFileProtectionUntilFirstUserAuthentication) else {
                return nil
            }
            if let openDecisions, let openURL = self.accountFileLocked(HarnessgramCockpitStore.openDecisionsName, session: session) {
                if !self.writeLocked(openDecisions.filter { answered[$0.id] == nil }, to: openURL, protection: .completeFileProtectionUntilFirstUserAuthentication) {
                    _ = self.removeIfPresent(openURL)
                }
            }
            return filtered
        }
    }

    /// Reads, changes and writes the snapshot as one step under the cross-process lock, only while `session` (nil:
    /// whichever is current) is current. Returns the stored result, or nil.
    @discardableResult
    public func updateSnapshot(forSession session: Session? = nil, _ transform: (HarnessgramCockpitSnapshot) -> HarnessgramCockpitSnapshot) -> HarnessgramCockpitSnapshot? {
        return self.locked(failure: nil) {
            self.flushPendingAnsweredLocked()
            guard let url = self.accountFileLocked(HarnessgramCockpitStore.snapshotName, session: session), let current: HarnessgramCockpitSnapshot = self.readLocked(url) else {
                return nil
            }
            let updated = transform(current)
            return self.writeLocked(updated, to: url, protection: .completeFileProtectionUntilFirstUserAuthentication) ? updated : nil
        }
    }

    /// The decision was answered (or closed) in `session`: it leaves the snapshot now and stays out of older ones.
    @discardableResult
    public func markAnswered(_ id: String, forSession session: Session? = nil) -> HarnessgramCockpitSnapshot? {
        return self.markAnsweredChecked(id, forSession: session).completedValue ?? nil
    }

    /// `markAnswered` that says whether the answer was remembered: `.lockUnavailable` when the lock or the answered
    /// list's write was unavailable (retry; keep the decision hidden meanwhile). `.completed` once it is remembered, or
    /// when `session` is no longer current (nothing to keep).
    public func markAnsweredChecked(_ id: String, forSession session: Session? = nil) -> MutationResult<HarnessgramCockpitSnapshot?> {
        let answeredAt = self.now()
        let result: MutationResult<MutationResult<HarnessgramCockpitSnapshot?>> = self.lockedChecked { () -> MutationResult<HarnessgramCockpitSnapshot?> in
            self.flushPendingAnsweredLocked()
            guard let answeredURL = self.accountFileLocked(HarnessgramCockpitStore.answeredName, session: session) else {
                return .completed(nil)
            }
            var answered = self.answeredLocked(session: session)
            answered[id] = answeredAt
            guard self.writeLocked(answered, to: answeredURL, protection: .completeFileProtectionUntilFirstUserAuthentication) else {
                return .lockUnavailable
            }
            self.setPendingAnswered(id, nil)
            return .completed(self.removeAnsweredLocked(id, session: session))
        }
        let outcome: MutationResult<HarnessgramCockpitSnapshot?>
        switch result {
        case let .completed(inner): outcome = inner
        case .lockUnavailable: outcome = .lockUnavailable
        }
        if case .lockUnavailable = outcome {
            // Never forgotten while this process lives: the next successful locked write stores it.
            self.setPendingAnswered(id, (session: session, at: answeredAt))
        }
        return outcome
    }

    private func setPendingAnswered(_ id: String, _ entry: (session: Session?, at: Date)?) {
        self.pendingLock.lock()
        self.pendingAnswered[id] = entry
        self.pendingLock.unlock()
    }

    private func pendingAnsweredSnapshot() -> [String: (session: Session?, at: Date)] {
        self.pendingLock.lock()
        defer { self.pendingLock.unlock() }
        let now = self.now()
        self.pendingAnswered = self.pendingAnswered.filter { now.timeIntervalSince($0.value.at) < HarnessgramCockpitStore.answeredMemory }
        return self.pendingAnswered
    }

    /// Writes the pending answers that belong to the current session (others are dropped with their session).
    private func flushPendingAnsweredLocked() {
        for (id, entry) in self.pendingAnsweredSnapshot() {
            guard let answeredURL = self.accountFileLocked(HarnessgramCockpitStore.answeredName, session: entry.session) else {
                self.setPendingAnswered(id, nil)
                continue
            }
            var answered = self.answeredLocked(session: entry.session)
            answered[id] = entry.at
            if self.writeLocked(answered, to: answeredURL, protection: .completeFileProtectionUntilFirstUserAuthentication) {
                self.setPendingAnswered(id, nil)
                _ = self.removeAnsweredLocked(id, session: entry.session)
            }
        }
    }

    /// Takes an answered decision out of the open list and the snapshot; returns the stored snapshot, or nil.
    private func removeAnsweredLocked(_ id: String, session: Session?) -> HarnessgramCockpitSnapshot? {
        if let openURL = self.accountFileLocked(HarnessgramCockpitStore.openDecisionsName, session: session), let open: [HarnessgramCockpitSnapshot.Decision] = self.readLocked(openURL) {
            _ = self.writeLocked(open.filter { $0.id != id }, to: openURL, protection: .completeFileProtectionUntilFirstUserAuthentication)
        }
        guard let url = self.accountFileLocked(HarnessgramCockpitStore.snapshotName, session: session), let current: HarnessgramCockpitSnapshot = self.readLocked(url) else {
            return nil
        }
        let updated = current.removingDecision(id)
        return self.writeLocked(updated, to: url, protection: .completeFileProtectionUntilFirstUserAuthentication) ? updated : nil
    }

    // MARK: Open decisions (app only)

    /// Every open decision as of the last refresh, uncapped; nil when none was saved for the active account.
    public func loadOpenDecisions() -> [HarnessgramCockpitSnapshot.Decision]? {
        return self.locked(failure: nil) {
            guard let url = self.accountFileLocked(HarnessgramCockpitStore.openDecisionsName, session: nil) else {
                return nil
            }
            return self.readLocked(url)
        }
    }

    /// The full list fetched in `session` (nil: whichever is current). Refused when that session is no longer the
    /// current one. Decisions answered meanwhile stay out, as in `saveSnapshot`.
    @discardableResult
    public func saveOpenDecisions(_ decisions: [HarnessgramCockpitSnapshot.Decision], forSession session: Session? = nil) -> Bool {
        return self.locked(failure: false) {
            self.flushPendingAnsweredLocked()
            guard let url = self.accountFileLocked(HarnessgramCockpitStore.openDecisionsName, session: session) else {
                return false
            }
            let answered = self.answeredLocked(session: session)
            return self.writeLocked(decisions.filter { answered[$0.id] == nil }, to: url, protection: .completeFileProtectionUntilFirstUserAuthentication)
        }
    }

    // MARK: Chat-list widget (build 18)

    /// The chats Telegram's chat-list widget actually shows, defaults included, by account record id, so the app tracks
    /// them for new messages. Kept with the current session: wiped on pause, switch or logout.
    @discardableResult
    public func saveChatWidgetShown(_ shown: [Int64: [Int64]], forSession session: Session) -> Bool {
        return self.locked(failure: false) {
            guard let url = self.accountFileLocked(HarnessgramCockpitStore.chatWidgetShownName, session: session) else {
                return false
            }
            let encoded = Dictionary(uniqueKeysWithValues: shown.map { (String($0.key), $0.value) })
            return self.writeLocked(encoded, to: url, protection: .completeFileProtectionUntilFirstUserAuthentication)
        }
    }

    public func loadChatWidgetShown() -> [Int64: [Int64]] {
        return self.loadChatWidgetShownChecked().completedValue ?? [:]
    }

    /// `loadChatWidgetShown`, or `lockUnavailable` (which never means "no chats shown").
    public func loadChatWidgetShownChecked() -> MutationResult<[Int64: [Int64]]> {
        return self.lockedChecked { () -> [Int64: [Int64]] in
            guard let url = self.accountFileLocked(HarnessgramCockpitStore.chatWidgetShownName, session: nil), let stored: [String: [Int64]] = self.readLocked(url) else {
                return [:]
            }
            var result: [Int64: [Int64]] = [:]
            for (key, value) in stored {
                if let id = Int64(key) {
                    result[id] = value
                }
            }
            return result
        }
    }

    // MARK: Login

    /// nil while the phone is locked (complete protection), when none was saved for the active account, or when
    /// it is unusable.
    public func loadCredential(forSession session: Session? = nil) -> HarnessgramCockpitCredential? {
        return self.locked(failure: nil) {
            guard let url = self.accountFileLocked(HarnessgramCockpitStore.credentialName, session: session), let credential: HarnessgramCockpitCredential = self.readLocked(url), credential.originURL != nil else {
                return nil
            }
            return credential
        }
    }

    /// A login minted in `session` (nil: whichever is current). Refused when that session is no longer current.
    @discardableResult
    public func saveCredential(_ credential: HarnessgramCockpitCredential, forSession session: Session? = nil) -> Bool {
        guard credential.originURL != nil else {
            return false
        }
        return self.locked(failure: false) {
            guard let url = self.accountFileLocked(HarnessgramCockpitStore.credentialName, session: session) else {
                return false
            }
            return self.writeLocked(credential, to: url, protection: .completeFileProtection)
        }
    }

    /// The bridge refused it, or the owner signed out: the widgets fall back to opening the app.
    /// When a rejected login is supplied, leave in place any login saved while the request was pending.
    public func forgetCredential(forSession session: Session? = nil, matching credential: HarnessgramCockpitCredential? = nil) {
        self.locked(failure: ()) {
            guard let url = self.accountFileLocked(HarnessgramCockpitStore.credentialName, session: session) else {
                return
            }
            if let credential {
                let stored: HarnessgramCockpitCredential? = self.readLocked(url)
                guard stored == credential else { return }
            }
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: Locked helpers

    /// One step at a time, across threads (NSLock) and across the app and its extensions (flock).
    private func locked<T>(failure: T, _ body: () -> T) -> T {
        // A missed app UI caller must not reintroduce a camera-wide freeze. Extension providers
        // and isolated test stores keep their existing synchronous contract.
        guard !self.requiresBackground || !Thread.isMainThread else {
            HarnessgramCockpitStore.lockLogger.error("Cockpit store main-thread access skipped")
            return failure
        }
        let started = DispatchTime.now().uptimeNanoseconds
        let timeout = UInt64(HarnessgramCockpitStore.lockTimeout * 1_000_000_000)
        let retryMicros = UInt32(HarnessgramCockpitStore.lockRetryNanoseconds / 1_000)
        var threadContended = false
        while !self.threadLock.try() {
            threadContended = true
            guard DispatchTime.now().uptimeNanoseconds &- started < timeout else {
                let waitedMS = Double(DispatchTime.now().uptimeNanoseconds &- started) / 1_000_000
                HarnessgramCockpitStore.lockLogger.error("Cockpit store thread lock timed out after \(waitedMS, privacy: .public)ms; operation skipped")
                return failure
            }
            usleep(retryMicros)
        }
        defer { self.threadLock.unlock() }
        let threadWaitMS = Double(DispatchTime.now().uptimeNanoseconds &- started) / 1_000_000
        guard let directory = self.directory else {
            return failure
        }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        } catch {
            HarnessgramCockpitStore.lockLogger.error("Cockpit store directory unavailable; operation skipped")
            return failure
        }
        let fd = open(directory.appendingPathComponent(HarnessgramCockpitStore.lockName, isDirectory: false).path, O_CREAT | O_RDWR, 0o600)
        guard fd >= 0 else {
            HarnessgramCockpitStore.lockLogger.error("Cockpit store lock file unavailable; operation skipped")
            return failure
        }
        let flockStarted = DispatchTime.now().uptimeNanoseconds
        var fileContended = false
        while flock(fd, LOCK_EX | LOCK_NB) != 0 {
            fileContended = true
            if errno != EWOULDBLOCK && errno != EAGAIN && errno != EINTR {
                close(fd)
                HarnessgramCockpitStore.lockLogger.error("Cockpit store lock acquisition failed; operation skipped")
                return failure
            }
            guard DispatchTime.now().uptimeNanoseconds &- started < timeout else {
                close(fd)
                let waitedMS = Double(DispatchTime.now().uptimeNanoseconds &- started) / 1_000_000
                HarnessgramCockpitStore.lockLogger.error("Cockpit store file lock timed out after \(waitedMS, privacy: .public)ms; operation skipped")
                return failure
            }
            usleep(retryMicros)
        }
        let fileWaitMS = Double(DispatchTime.now().uptimeNanoseconds &- flockStarted) / 1_000_000
        if threadContended || fileContended {
            HarnessgramCockpitStore.lockLogger.info("Cockpit store lock wait: thread=\(threadWaitMS, privacy: .public)ms file=\(fileWaitMS, privacy: .public)ms")
        }
        defer {
            flock(fd, LOCK_UN)
            close(fd)
        }
        return body()
    }

    /// `locked` that reports a lock it could not take as `lockUnavailable` instead of a made-up value.
    private func lockedChecked<T>(_ body: () -> T) -> MutationResult<T> {
        return self.locked(failure: MutationResult<T>.lockUnavailable) {
            return .completed(body())
        }
    }

    private func sessionLocked() -> Session? {
        guard let directory = self.directory else {
            return nil
        }
        if FileManager.default.fileExists(atPath: directory.appendingPathComponent(HarnessgramCockpitStore.pausedName, isDirectory: false).path) {
            return nil
        }
        let active: ActiveAccount? = self.readLocked(directory.appendingPathComponent(HarnessgramCockpitStore.activeAccountName, isDirectory: false))
        guard let active else {
            return nil
        }
        // A build 14 file has no epoch: it reads as a session of its own until the next real account change.
        return Session(accountId: active.accountId, epoch: active.epoch ?? "build14")
    }

    private func removeLegacyFilesLocked() {
        guard let directory = self.directory else {
            return
        }
        for name in [HarnessgramCockpitStore.credentialName, HarnessgramCockpitStore.snapshotName] {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name, isDirectory: false))
        }
    }

    private func removeLegacyFilesChecked() -> Bool {
        guard let directory = self.directory else { return false }
        return [HarnessgramCockpitStore.credentialName, HarnessgramCockpitStore.snapshotName].allSatisfy { name in
            self.removeIfPresent(directory.appendingPathComponent(name, isDirectory: false))
        }
    }

    private func removeIfPresent(_ url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return true }
        do {
            try FileManager.default.removeItem(at: url)
            return true
        } catch {
            return false
        }
    }

    /// The current session's file; nil without a session, or when `session` is given and is not the current one.
    private func accountFileLocked(_ name: String, session: Session?) -> URL? {
        guard let directory = self.directory, let current = self.sessionLocked() else {
            return nil
        }
        if let session, session != current {
            return nil
        }
        return directory
            .appendingPathComponent(HarnessgramCockpitStore.accountsFolderName, isDirectory: true)
            .appendingPathComponent(String(current.accountId), isDirectory: true)
            .appendingPathComponent(name, isDirectory: false)
    }

    /// Answered decisions still remembered (older ones are dropped).
    private func answeredLocked(session: Session?) -> [String: Date] {
        guard let url = self.accountFileLocked(HarnessgramCockpitStore.answeredName, session: session) else {
            return [:]
        }
        var answered: [String: Date] = self.readLocked(url) ?? [:]
        // Answers not written yet still count (only those of the current session).
        let current = self.sessionLocked()
        for (id, entry) in self.pendingAnsweredSnapshot() where entry.session == nil || entry.session == current {
            answered[id] = answered[id] ?? entry.at
        }
        let now = self.now()
        return answered.filter { now.timeIntervalSince($0.value) < HarnessgramCockpitStore.answeredMemory }
    }

    private func readLocked<T: Decodable>(_ url: URL) -> T? {
        guard let data = try? Data(contentsOf: url), data.count <= 1_000_000 else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(T.self, from: data)
    }

    private func writeLocked<T: Encodable>(_ value: T, to url: URL, protection: Data.WritingOptions) -> Bool {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        guard let data = try? encoder.encode(value) else {
            return false
        }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
            try data.write(to: url, options: [.atomic, protection])
            return true
        } catch {
            return false
        }
    }
}

extension HarnessgramCockpitStore.MutationResult: Sendable where Value: Sendable {}

extension HarnessgramCockpitStore.MutationResult: Equatable where Value: Equatable {}

/// Build 16: what an account event does to the Cockpit, the widgets and the Live Activity (pure, tested).
public enum HarnessgramAccountRule {
    public enum Action: Equatable {
        case none
        /// Exactly one account and nothing set up yet: its session starts (the first pairing).
        case start(Int64)
        /// A second login, a switch or a logout: wipe, end the Live Activities, stay off until re-paired.
        case pause
    }

    /// Carries a detected switch across asynchronous account events until pause is written successfully.
    public static func requiresPause(previousPrimary: Int64?, previousLoggedInCount: Int, primary: Int64?, loggedInCount: Int, alreadyPending: Bool) -> Bool {
        if alreadyPending || loggedInCount >= 2 {
            return true
        }
        return previousLoggedInCount > 0 && (loggedInCount == 0 || primary != previousPrimary)
    }

    /// - Parameters:
    ///   - primary: the active account, if any.
    ///   - loggedInCount: logged-in accounts (an add-account flow that has not completed a login does not count).
    public static func action(primary: Int64?, loggedInCount: Int, session: HarnessgramCockpitStore.Session?, isPaused: Bool) -> Action {
        if isPaused {
            return .none
        }
        if loggedInCount >= 2 {
            return .pause
        }
        guard loggedInCount == 1, let primary else {
            return session == nil ? .none : .pause
        }
        guard let session else {
            return .start(primary)
        }
        return session.accountId == primary ? .none : .pause
    }
}

/// Build 18: Telegram's chat-list widget follows the single-account rule of build 16: it shows chats only while the
/// Cockpit is not paused and its session belongs to the account the widget reads.
public enum HarnessgramChatWidgetGate {
    public static func isEnabled(session: HarnessgramCockpitStore.Session?, isPaused: Bool, accountPeerId: Int64) -> Bool {
        guard !isPaused, let session else {
            return false
        }
        return session.accountId == accountPeerId
    }
}

