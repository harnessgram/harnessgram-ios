import Foundation
import UIKit
import SwiftSignalKit
import Display
import AccountContext
import HarnessgramSettings
import HarnessgramCockpitKit
import HarnessgramCockpitSync
import HarnessgramHouseCore

/// The Cockpit tab's data (build 23): the snapshot the widgets already use, through `HarnessgramCockpitTabViewModel`.
/// The decision rows answer through `HouseDecisionActions` (the same Face ID rule as the widgets, the knock sheet and
/// the waiting list). Used from the main queue only.
final class HouseCockpitTabModel: ObservableObject {
    enum RowState: Equatable {
        case sending
        case failed(String)
    }

    @Published private(set) var tab: HarnessgramCockpitTabViewModel
    @Published private(set) var rowStates: [String: RowState] = [:]
    @Published private(set) var pairing = false
    @Published private(set) var pairMessage: String?
    @Published private(set) var openingCockpit = false
    /// The wide layout (iPad, Split View, the unfolded phone): Telegram's layout has the regular width class, so the
    /// tab is the list column and the task desk opens in the detail column beside it.
    @Published private(set) var isRegularWidth = false
    /// The task on the desk. Kept here, not in the view, so rotation, resizing and the width class changing back and
    /// forth never lose it; resolved again after every refresh (`HarnessgramCockpitDesk.resolvedSelection`).
    @Published private(set) var selectedTaskId: String?
    /// The status bar's height (the phone tower draws the night sky under it, over the scrolled content).
    @Published private(set) var statusBarHeight: CGFloat = 0.0
    /// The desk is on screen and shows the radio, so the tower list leaves it out.
    @Published var deskShowsRadio = false
    private lazy var deskNavigation = HouseCockpitDeskNavigation(navigation: { [weak self] in
        self?.navigation
    })

    /// nil only in a preview model (`init(preview:)`): snapshots of the tab, nothing is sent or opened.
    let context: AccountContext?
    let actions: HouseDecisionActions?
    weak var controller: ViewController? {
        didSet {
            self.updateBadge()
        }
    }
    /// Set by the host: the waiting list screen (HarnessgramHouseUI), or nil to open the full Cockpit instead.
    var openWaitingListScreen: (() -> Void)?
    private var pollDisposable: Disposable?
    private var observers: [NSObjectProtocol] = []
    /// On view (between `start` and `stop`).
    private var isVisible = false
    /// When the tab started waiting for the first snapshot on view (appeared, or the owner asked to retry).
    private var loadingSince: Date?
    private var loadingTimer: SwiftSignalKit.Timer?

    init(context: AccountContext) {
        self.context = context
        self.actions = HouseDecisionActions(context: context)
        self.tab = HouseCockpitTabModel.current(loadingSince: nil)
        let center = NotificationCenter.default
        for name in [HarnessgramCockpitSync.snapshotDidChangeNotification, HarnessgramCockpitSync.refreshStatusDidChangeNotification, HarnessgramSettings.didChangeNotification, UIApplication.didBecomeActiveNotification] {
            self.observers.append(center.addObserver(forName: name, object: nil, queue: .main, using: { [weak self] _ in
                self?.reload()
            }))
        }
    }

    /// A still model for snapshot renders of the tab (light and dark): the given state, no account, no polling, and
    /// every action does nothing.
    init(preview tab: HarnessgramCockpitTabViewModel, isRegularWidth: Bool = false, statusBarHeight: CGFloat = 0.0) {
        self.context = nil
        self.actions = nil
        self.tab = tab
        self.isRegularWidth = isRegularWidth
        self.statusBarHeight = statusBarHeight
    }

    deinit {
        self.pollDisposable?.dispose()
        self.loadingTimer?.invalidate()
        for observer in self.observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    static func current(loadingSince: Date?) -> HarnessgramCockpitTabViewModel {
        let sync = HarnessgramCockpitSync.shared
        let state = sync.viewState
        let memory = HarnessgramCockpitLookMemory.shared
        if let snapshot = state?.snapshot {
            // Kept for the pages without a snapshot and the next cold launch (the off switch reaches them too).
            memory.remember(towerPhone: HarnessgramCockpitSnapshot.towerPhoneOn(snapshot))
        }
        return HarnessgramCockpitTabViewModel.make(snapshot: state?.snapshot, openDecisions: state?.openDecisions, isPaired: sync.isConnected, isPaused: sync.isPaused, failure: sync.lastRefreshFailure, loadingSince: loadingSince, now: Date(), rememberedTowerPhone: memory.towerPhone)
    }

    func reload() {
        if self.context == nil {
            // A preview keeps the state it was given.
            return
        }
        // The connection can arrive after the tab appeared (the shared files are read in the background): polling
        // starts then, not only when the tab appears already connected.
        self.ensurePolling()
        let updated = HouseCockpitTabModel.current(loadingSince: self.loadingSince)
        if updated != self.tab {
            self.tab = updated
        }
        let selected = HarnessgramCockpitDesk.resolvedSelection(self.selectedTaskId, tasks: updated.tasks)
        if selected != self.selectedTaskId {
            self.selectedTaskId = selected
        }
        self.showDeskIfDetailIsEmpty()
        self.applyListStyle()
        if !self.tab.wideCockpit {
            // The bridge switched the wide look off: the phone list everywhere, and no desk beside it.
            self.removeDesk()
        }
        self.scheduleLoadingTimeout()
        let open = Set(updated.decisions.map { $0.id })
        self.rowStates = self.rowStates.filter { open.contains($0.key) }
        self.updateBadge()
    }

    private func ensurePolling() {
        guard let context = self.context, self.isVisible, self.pollDisposable == nil, HarnessgramCockpitSync.shared.isConnected else {
            return
        }
        self.pollDisposable = HarnessgramCockpitSync.shared.pollWhileVisible(context: context)
    }

    /// While the tab waits on view, looks again when the time limit runs out, so it never spins forever.
    private func scheduleLoadingTimeout() {
        self.loadingTimer?.invalidate()
        self.loadingTimer = nil
        guard self.isVisible, case .loading = self.tab.state, let deadline = HarnessgramCockpitTabViewModel.loadingDeadline(loadingSince: self.loadingSince) else {
            return
        }
        let timer = SwiftSignalKit.Timer(timeout: max(0.1, deadline.timeIntervalSinceNow), repeat: false, completion: { [weak self] in
            self?.loadingTimer = nil
            self?.reload()
        }, queue: Queue.mainQueue())
        self.loadingTimer = timer
        timer.start()
    }

    /// The tab's red badge (Telegram's own tab-bar badge, as on Chats): what waits in the Cockpit, none at 0.
    private func updateBadge() {
        guard self.context != nil else { return }
        let text = HarnessgramCockpitWaiting.badgeText(HarnessgramCockpitWaiting.count(state: HarnessgramCockpitSync.shared.viewState))
        if let controller = self.controller, controller.tabBarItem.badgeValue != text {
            controller.tabBarItem.badgeValue = text
        }
    }

    // MARK: The wide layout

    var listStyle: HarnessgramCockpitDesk.ListStyle {
        return HarnessgramCockpitDesk.listStyle(isRegularWidth: self.isRegularWidth, state: self.tab.state, wideCockpit: self.tab.wideCockpit, towerPhone: self.tab.towerPhone)
    }

    /// Set by the host: the page's chrome for a look (the phone tower hides the navigation bar and darkens the page).
    var listStyleChanged: ((HarnessgramCockpitDesk.ListStyle) -> Void)?
    private var appliedListStyle: HarnessgramCockpitDesk.ListStyle?

    /// Tells the host when the look changed (the switch, the width class or the state). Only on a change, so the
    /// layout it requests never loops back here.
    func applyListStyle() {
        guard self.context != nil else { return }
        let style = self.listStyle
        guard style != self.appliedListStyle else {
            return
        }
        self.appliedListStyle = style
        self.listStyleChanged?(style)
    }

    var selectedTask: HarnessgramCockpitTabViewModel.Task? {
        guard let id = self.selectedTaskId else {
            return nil
        }
        return self.tab.tasks.first(where: { $0.id == id })
    }

    /// Before the first layout: the width class of the window the tab will open in, so the first look applied is the
    /// right one (an iPad never draws one frame of the phone tower without its navigation bar).
    private var hasLaidOut = false

    func seedWidthClass(windowSize: CGSize?) {
        guard self.context != nil, let windowSize, windowSize.width > 0.0, windowSize.height > 0.0 else {
            return
        }
        self.isRegularWidth = HarnessgramCockpitDesk.isRegularWidth(windowSize: windowSize)
    }

    /// The tab's layout changed (rotation, Split View, Stage Manager, folding): the regular width class shows the
    /// tower list with the desk beside it; going back to compact takes the desk away (the phone list opens a task's
    /// room directly), so the list is what remains on screen.
    func updateLayout(_ layout: ContainerViewLayout) {
        guard self.context != nil else { return }
        let statusBarHeight = max(layout.statusBarHeight ?? 0.0, layout.safeInsets.top)
        if statusBarHeight != self.statusBarHeight {
            self.statusBarHeight = statusBarHeight
        }
        let isRegularWidth = layout.metrics.widthClass == .regular
        // The first layout always runs (the width class may have been seeded already, see seedWidthClass).
        guard isRegularWidth != self.isRegularWidth || !self.hasLaidOut else {
            return
        }
        self.hasLaidOut = true
        self.isRegularWidth = isRegularWidth
        self.deskNavigation.updateLayout(layout, showIfEmpty: { [weak self] in
            self?.showDeskIfDetailIsEmpty()
        })
        // Inside the screen's own layout pass: the chrome change (it lays the screen out again) waits for the next turn.
        DispatchQueue.main.async { [weak self] in
            self?.applyListStyle()
        }
    }

    private func removeDesk() {
        guard self.context != nil else { return }
        self.deskNavigation.removeDesk()
    }

    /// A flight strip: on the desk beside the list (replacing what the detail column showed).
    func select(_ task: HarnessgramCockpitTabViewModel.Task) {
        guard self.context != nil else { return }
        self.selectedTaskId = task.id
        self.showDesk(replacingDetail: true)
    }

    /// The arrow keys on the tower list.
    func moveSelection(by delta: Int) {
        guard self.context != nil else { return }
        guard let next = HarnessgramCockpitDesk.movedSelection(self.selectedTaskId, by: delta, tasks: self.tab.tasks), next != self.selectedTaskId else {
            return
        }
        self.selectedTaskId = next
        self.showDesk(replacingDetail: false)
    }

    private var navigation: NavigationController? {
        guard self.context != nil else { return nil }
        return self.controller?.navigationController as? NavigationController
    }

    /// The tab is on view in the wide layout and the detail column shows nothing yet: the desk with the first task.
    private func showDeskIfDetailIsEmpty() {
        guard self.isVisible, self.listStyle == .tower, let navigation = self.navigation, navigation.viewControllers.count == 1 else {
            return
        }
        self.showDesk(replacingDetail: false)
    }

    private func showDesk(replacingDetail: Bool) {
        guard self.listStyle == .tower, let navigation = self.navigation, let context = self.context else {
            return
        }
        self.deskNavigation.showDesk(in: navigation, replacingDetail: replacingDetail, makeDesk: {
            makeHouseCockpitDeskController(context: context, model: self)
        })
    }

    /// On view: refresh now and every 45 seconds (the House Home's rule), as soon as the widgets are connected.
    func start() {
        guard self.context != nil else { return }
        self.isVisible = true
        self.loadingSince = Date()
        self.reload()
    }

    func stop() {
        guard self.context != nil else { return }
        self.isVisible = false
        self.loadingSince = nil
        self.loadingTimer?.invalidate()
        self.loadingTimer = nil
        self.pollDisposable?.dispose()
        self.pollDisposable = nil
    }

    /// The error state's button: forgets the last failure, waits afresh and asks the Cockpit now.
    func retry() {
        guard let context = self.context else { return }
        HarnessgramCockpitSync.shared.clearRefreshFailure()
        self.loadingSince = Date()
        self.reload()
        if HarnessgramCockpitSync.shared.isConnected {
            HarnessgramCockpitSync.shared.refresh(context: context, force: true)
        }
    }

    /// Pull to refresh: asks the Cockpit now and waits for the new snapshot, at most a few seconds.
    func refreshAndWait() async {
        guard let context = self.context else { return }
        guard HarnessgramCockpitSync.shared.isConnected else {
            self.reload()
            return
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let waiter = HouseCockpitRefreshWaiter(continuation: continuation)
            waiter.token = NotificationCenter.default.addObserver(forName: HarnessgramCockpitSync.snapshotDidChangeNotification, object: nil, queue: .main, using: { _ in
                waiter.finish()
            })
            // A failed read ends the wait too: the error state shows why at once.
            waiter.failureToken = NotificationCenter.default.addObserver(forName: HarnessgramCockpitSync.refreshStatusDidChangeNotification, object: nil, queue: .main, using: { _ in
                if HarnessgramCockpitSync.shared.lastRefreshFailure != nil {
                    waiter.finish()
                }
            })
            DispatchQueue.main.asyncAfter(deadline: .now() + 6.0, execute: {
                waiter.finish()
            })
            HarnessgramCockpitSync.shared.refresh(context: context, force: true)
        }
        self.reload()
    }

    /// The widgets' one-tap pairing (Face ID first).
    func pair() {
        guard !self.pairing, let context = self.context else {
            return
        }
        self.pairing = true
        self.pairMessage = nil
        HarnessgramCockpitSync.shared.pair(context: context, completion: { [weak self] result in
            guard let self else {
                return
            }
            self.pairing = false
            switch result {
            case .connected:
                self.pairMessage = nil
            case .needsOneAccount:
                self.pairMessage = HarnessgramWidgetStrings.pairNeedsOneAccount
            case let .failed(reason):
                self.pairMessage = reason.text
            case .notConfirmed:
                self.pairMessage = nil
            }
            self.reload()
        })
    }

    func openFullCockpit() {
        guard !self.openingCockpit, let controller = self.controller, let context = self.context else {
            return
        }
        self.openingCockpit = true
        HouseCockpitOpener.open(context: context, parentController: controller, completion: { [weak self] _ in
            self?.openingCockpit = false
        })
    }

    func plan(for decision: HarnessgramCockpitSnapshot.Decision) -> HouseWaitingRowPlan {
        return self.actions?.plan(for: decision) ?? HouseWaitingRowPlan.make(decision: decision, credential: nil, now: Date())
    }

    /// A plain yes/no decision, answered in place.
    func answer(_ decision: HarnessgramCockpitSnapshot.Decision, _ choice: HarnessgramCockpitLinks.Choice) {
        guard self.rowStates[decision.id] != .sending, let actions = self.actions else {
            return
        }
        self.rowStates[decision.id] = .sending
        actions.answer(decision: decision, choice: choice, completion: { [weak self] outcome in
            guard let self else {
                return
            }
            switch outcome {
            case .sent, .gone:
                self.rowStates[decision.id] = nil
                self.reload()
            case .notConfirmed:
                self.rowStates[decision.id] = nil
            case .unavailable:
                self.rowStates[decision.id] = .failed(HouseCockpitStrings.sendFailed)
            }
        })
    }

    /// A sensitive decision: the widgets' app flow, which asks for Face ID before anything is sent.
    func approveWithFaceID(_ decision: HarnessgramCockpitSnapshot.Decision) {
        self.actions?.openAppFlow(decision: decision, choice: nil)
    }

    func openRoom(_ decision: HarnessgramCockpitSnapshot.Decision) {
        self.actions?.openRoom(topicURL: decision.topicURL)
    }

    func canOpenRoom(_ decision: HarnessgramCockpitSnapshot.Decision) -> Bool {
        return HarnessgramCockpitLinks.appURL(forTopicURL: decision.topicURL) != nil
    }

    func openTask(_ task: HarnessgramCockpitTabViewModel.Task) {
        self.actions?.openRoom(topicURL: task.topicURL)
    }

    func canOpenTask(_ task: HarnessgramCockpitTabViewModel.Task) -> Bool {
        return HarnessgramCockpitLinks.appURL(forTopicURL: task.topicURL) != nil
    }

    func openWaitingList() {
        guard self.context != nil else { return }
        if HarnessgramSettings.shared.houseFeature(.waitingList), let open = self.openWaitingListScreen {
            open()
        } else {
            self.openFullCockpit()
        }
    }

    func openRadio() {
        guard let context = self.context else {
            return
        }
        (self.controller?.navigationController as? NavigationController)?.pushViewController(harnessgramRadioController(context: context))
    }

    func toggleRadio() {
        guard let context = self.context else { return }
        let radio = HarnessgramRadioPlayer.shared
        if radio.hasListenLink {
            radio.toggle(context: context)
        } else {
            self.openRadio()
        }
    }
}

/// Resumes the pull-to-refresh wait exactly once (the new snapshot or the time limit, whichever comes first).
private final class HouseCockpitRefreshWaiter: @unchecked Sendable {
    private var continuation: CheckedContinuation<Void, Never>?
    var token: NSObjectProtocol?
    var failureToken: NSObjectProtocol?

    init(continuation: CheckedContinuation<Void, Never>) {
        self.continuation = continuation
    }

    func finish() {
        assert(Thread.isMainThread)
        if let token = self.token {
            NotificationCenter.default.removeObserver(token)
            self.token = nil
        }
        if let token = self.failureToken {
            NotificationCenter.default.removeObserver(token)
            self.failureToken = nil
        }
        self.continuation?.resume()
        self.continuation = nil
    }
}
