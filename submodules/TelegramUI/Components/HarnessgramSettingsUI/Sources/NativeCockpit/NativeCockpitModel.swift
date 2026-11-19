import Foundation
import UIKit
import SwiftUI
import SwiftSignalKit
import Display
import TelegramPresentationData
import AccountContext
import HarnessgramSettings
import HarnessgramCockpitKit
import HarnessgramCockpitSync

/// The presentation theme's list colours, for the native Cockpit's pages (light and dark follow the theme).
struct NativeCockpitPalette: Equatable {
    var page: UIColor
    var row: UIColor
    var primary: UIColor
    var secondary: UIColor
    var accent: UIColor
    var destructive: UIColor
    var constructive: UIColor
    var separator: UIColor

    init(theme: PresentationTheme) {
        self.page = theme.list.blocksBackgroundColor
        self.row = theme.list.itemBlocksBackgroundColor
        self.primary = theme.list.itemPrimaryTextColor
        self.secondary = theme.list.itemSecondaryTextColor
        self.accent = theme.list.itemAccentColor
        self.destructive = theme.list.itemDestructiveColor
        self.constructive = theme.list.itemDisclosureActions.constructive.fillColor
        self.separator = theme.list.itemBlocksSeparatorColor
    }
}

/// The native Cockpit's data and actions (main queue). One model serves the home, the decisions list and a decision's
/// page, so the reads go on while any of them is on screen and stop when none is.
@MainActor
final class NativeCockpitModel: ObservableObject {
    /// Answering decisions from the native Cockpit stays off until the review fixes land (duplicate decision ids,
    /// one answer per decision across screens, Face ID only, multi-option decisions). The screens list and open the
    /// decisions read-only; the Mini App keeps answering them.
    static let answersAvailable = false

    private static var answerGuard = HarnessgramAnswerGuard(defaults: .standard, now: Date())
    private static var guardedStates: [String: NativeDecisionAnswerState] = [:]
    private static let answerGuardDidChange = Notification.Name("HarnessgramNativeCockpitAnswerGuardDidChange")

    static var answeringAllowed: Bool {
        return NativeCockpitModel.answersAvailable && HarnessgramSettings.shared.houseFeature(.nativeDecisions)
    }

    private static var canAnswerHere: Bool {
        return self.answeringAllowed && HarnessgramSettings.shared.houseFeature(.nativeCockpit)
    }

    @Published private(set) var home: NativeCockpitHome
    @Published private(set) var decisions: [HarnessgramCockpitScreen.Decision] = []
    @Published private(set) var deliveries: [HarnessgramCockpitScreen.Delivery] = []
    @Published private(set) var answerOn: Bool
    @Published private(set) var answers: [String: NativeDecisionAnswerState] = [:]
    @Published private(set) var palette: NativeCockpitPalette
    @Published private(set) var pairing = false
    @Published private(set) var pairMessage: String?
    @Published var notes: [String: String] = [:]

    #if targetEnvironment(simulator)
    /// Simulator demo only: the tab's models, so the demo can open its pages (nativeCockpitDemoOpen).
    static var demoModels: [NativeCockpitModel] = []
    #endif

    /// nil in a preview model: everything shows, nothing is sent or opened.
    let context: AccountContext?
    weak var controller: ViewController? {
        didSet {
            self.updateBadge()
        }
    }
    /// The decisions answered from this page stay visible with their result until the page closes, even after the
    /// bridge dropped them from its list.
    private var answered: [String: HarnessgramCockpitScreen.Decision] = [:]
    private var observers: [NSObjectProtocol] = []
    private var presentationDisposable: Disposable?
    private var pollDisposable: Disposable?
    private var visibleScreens = 0
    private var stopTimer: SwiftSignalKit.Timer?

    init(context: AccountContext) {
        self.context = context
        self.palette = NativeCockpitPalette(theme: context.sharedContext.currentPresentationData.with { $0 }.theme)
        self.answerOn = NativeCockpitModel.canAnswerHere
        self.home = .loading
        self.reload()
        let center = NotificationCenter.default
        for name in [HarnessgramCockpitSync.snapshotDidChangeNotification, HarnessgramCockpitSync.refreshStatusDidChangeNotification, HarnessgramSettings.didChangeNotification, UIApplication.didBecomeActiveNotification] {
            self.observers.append(center.addObserver(forName: name, object: nil, queue: .main, using: { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.reload()
                }
            }))
        }
        self.observers.append(center.addObserver(forName: Self.answerGuardDidChange, object: nil, queue: .main, using: { [weak self] _ in
            MainActor.assumeIsolated {
                self?.objectWillChange.send()
            }
        }))
        self.presentationDisposable = (context.sharedContext.presentationData |> deliverOnMainQueue).start(next: { [weak self] presentationData in
            guard let self else { return }
            let palette = NativeCockpitPalette(theme: presentationData.theme)
            if palette != self.palette {
                self.palette = palette
            }
        })
    }

    /// A still model for screenshots and tests.
    init(preview home: NativeCockpitHome, decisions: [HarnessgramCockpitScreen.Decision], answerOn: Bool, answers: [String: NativeDecisionAnswerState] = [:], theme: PresentationTheme) {
        self.context = nil
        self.home = home
        self.decisions = decisions
        self.answerOn = answerOn
        self.answers = answers
        self.palette = NativeCockpitPalette(theme: theme)
    }

    deinit {
        self.pollDisposable?.dispose()
        self.presentationDisposable?.dispose()
        self.stopTimer?.invalidate()
        for observer in self.observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func reload() {
        guard self.context != nil else { return }
        let sync = HarnessgramCockpitSync.shared
        let screen = sync.screen
        let now = Date()
        let retryIn = sync.pollSchedule.notBefore.map { max(0.0, $0.timeIntervalSince(now)) }
        let home = NativeCockpitHome.make(screen: screen, isConnected: sync.isConnected, isPaused: sync.isPaused, failure: sync.lastRefreshFailure, retryIn: retryIn, now: now)
        if home != self.home {
            self.home = home
        }
        let open = screen?.decisions ?? []
        let openIds = Set(open.map { $0.id })
        // An answered decision stays on its page with the result; the list shows only what is still open.
        let kept = self.answered.values.filter { !openIds.contains($0.id) }
        let decisions = open + kept.sorted { $0.id < $1.id }
        if decisions != self.decisions {
            self.decisions = decisions
        }
        let deliveries = screen?.deliveries ?? []
        if deliveries != self.deliveries {
            self.deliveries = deliveries
        }
        let answerOn = NativeCockpitModel.canAnswerHere
        if answerOn != self.answerOn {
            self.answerOn = answerOn
        }
        self.ensurePolling()
        self.updateBadge()
    }

    var openDecisions: [HarnessgramCockpitScreen.Decision] {
        return self.decisions.filter { self.answered[$0.id] == nil }
    }

    func decision(id: String) -> HarnessgramCockpitScreen.Decision? {
        return self.decisions.first(where: { $0.id == id })
    }

    func delivery(key: String) -> HarnessgramCockpitScreen.Delivery? {
        return self.deliveries.first(where: { $0.key == key })
    }

    // MARK: Reads only while on screen

    func appeared() {
        guard self.context != nil else { return }
        self.visibleScreens += 1
        self.stopTimer?.invalidate()
        self.stopTimer = nil
        self.reload()
    }

    /// A push from one page to the next disappears the old page around the time the new one appears: the reads stop only
    /// when no page came back within a moment.
    func disappeared() {
        guard self.context != nil else { return }
        self.visibleScreens = max(0, self.visibleScreens - 1)
        guard self.visibleScreens == 0 else { return }
        self.stopTimer?.invalidate()
        let timer = SwiftSignalKit.Timer(timeout: 0.6, repeat: false, completion: { [weak self] in
            guard let self, self.visibleScreens == 0 else { return }
            self.pollDisposable?.dispose()
            self.pollDisposable = nil
            self.answered = [:]
            self.answers = [:]
            self.notes = [:]
        }, queue: Queue.mainQueue())
        self.stopTimer = timer
        timer.start()
    }

    private func ensurePolling() {
        guard let context = self.context, self.visibleScreens > 0, self.pollDisposable == nil, HarnessgramCockpitSync.shared.isConnected else {
            return
        }
        self.pollDisposable = HarnessgramCockpitSync.shared.pollWhileVisible(context: context, interval: HarnessgramCockpitPollSchedule.defaultBase)
    }

    private func updateBadge() {
        guard self.context != nil, let controller = self.controller else { return }
        let text = HarnessgramCockpitWaiting.badgeText(HarnessgramCockpitWaiting.count(state: HarnessgramCockpitSync.shared.viewState))
        if controller.tabBarItem.badgeValue != text {
            controller.tabBarItem.badgeValue = text
        }
    }

    // MARK: Actions

    /// Pull to refresh (SwiftUI calls it off the main queue; the sync is main-queue only).
    @MainActor
    func refresh() async {
        guard let context = self.context else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            HarnessgramCockpitSync.shared.refresh(context: context, force: true, completion: {
                continuation.resume()
            })
        }
        self.reload()
    }

    func retry() {
        guard let context = self.context else { return }
        HarnessgramCockpitSync.shared.clearRefreshFailure()
        HarnessgramCockpitSync.shared.refresh(context: context, force: true)
        self.reload()
    }

    func pair() {
        guard let context = self.context, !self.pairing else { return }
        self.pairing = true
        self.pairMessage = nil
        HarnessgramCockpitSync.shared.pair(context: context, completion: { [weak self] result in
            guard let self else { return }
            self.pairing = false
            switch result {
            case .connected, .notConfirmed:
                self.pairMessage = nil
            case .needsOneAccount:
                self.pairMessage = HarnessgramWidgetStrings.pairNeedsOneAccount
            case let .failed(reason):
                self.pairMessage = reason.text
            }
            self.reload()
        })
    }

    func openFullCockpit() {
        guard let context = self.context, let controller = self.topController else { return }
        HouseCockpitOpener.open(context: context, parentController: controller, completion: { _ in })
    }

    func openTopic(_ decision: HarnessgramCockpitScreen.Decision) {
        guard let context = self.context else { return }
        HouseDecisionActions(context: context).openRoom(topicURL: decision.base.topicURL)
    }

    func canOpenTopic(_ decision: HarnessgramCockpitScreen.Decision) -> Bool {
        return HarnessgramCockpitLinks.appURL(forTopicURL: decision.base.topicURL) != nil
    }

    func showDecisions() {
        guard let context = self.context else { return }
        self.push(makeNativeDecisionsController(context: context, model: self))
    }

    func openDecision(_ decision: HarnessgramCockpitScreen.Decision) {
        guard let context = self.context else { return }
        self.push(makeNativeDecisionController(context: context, model: self, id: decision.id))
    }

    private var topController: ViewController? {
        return ((self.controller?.navigationController as? NavigationController)?.topViewController as? ViewController) ?? self.controller
    }

    private func push(_ controller: ViewController) {
        (self.controller?.navigationController as? NavigationController)?.pushViewController(controller)
    }

    /// The owner's yes or no. Face ID first for a decision that is not explicitly routine (in the sync).
    func answer(_ decision: HarnessgramCockpitScreen.Decision, _ choice: HarnessgramCockpitLinks.Choice) {
        guard let context = self.context, self.answerOn, Self.canAnswerHere, decision.answerableHere else { return }
        let key = HarnessgramAnswerGuard.key(account: context.account.peerId.toInt64(), decisionId: decision.id)
        let stillOpen = self.openDecisions.contains(where: { $0.id == decision.id })
        let hasDelivery = self.deliveries.contains(where: { $0.id == decision.id })
        guard Self.answerGuard.begin(key, now: Date(), stillOpen: stillOpen, hasDelivery: hasDelivery) else { return }
        let note = self.notes[decision.id] ?? ""
        self.answers[decision.id] = nil
        Self.guardedStates[key] = .sending(choice)
        NotificationCenter.default.post(name: Self.answerGuardDidChange, object: nil)
        HarnessgramCockpitSync.shared.answerFromNativeCockpit(
            context: context,
            decision: decision,
            choice: choice,
            note: note,
            reason: NativeCockpitStrings.t(.faceIDReason),
            stillAllowed: { Self.answeringAllowed },
            willSend: {
                Self.answerGuard.markSending(key, now: Date())
                Self.answerGuard.saveUncertain(to: .standard)
            },
            completion: { [weak self] result in
                Self.answerGuard.finish(key, result: result, now: Date())
                Self.answerGuard.saveUncertain(to: .standard)
                Self.guardedStates[key] = result.guardOutcome == .done ? .finished(result, choice: choice) : nil
                if let self {
                    self.answers[decision.id] = result == .failed ? nil : .finished(result, choice: choice)
                    if result.guardOutcome == .done {
                        self.answered[decision.id] = decision
                    }
                    self.reload()
                }
                NotificationCenter.default.post(name: Self.answerGuardDidChange, object: nil)
            }
        )
    }

    func answerState(_ decision: HarnessgramCockpitScreen.Decision) -> NativeDecisionAnswerState {
        if let key = self.answerKey(decision), let state = Self.guardedStates[key] {
            return state
        }
        return self.answers[decision.id] ?? .idle
    }

    func timedAnswerBlock(_ decision: HarnessgramCockpitScreen.Decision) -> HarnessgramAnswerGuard.TimedBlock? {
        guard let key = self.answerKey(decision) else { return nil }
        return Self.answerGuard.timedBlock(key, now: Date())
    }

    private func answerKey(_ decision: HarnessgramCockpitScreen.Decision) -> String? {
        guard let context = self.context else { return nil }
        return HarnessgramAnswerGuard.key(account: context.account.peerId.toInt64(), decisionId: decision.id)
    }

    // MARK: Comments (rich decisions): the owner's own words, approving nothing

    @Published private(set) var commentStates: [String: NativeCommentState] = [:]
    private var commentDrafts: [String: String] = [:]

    func commentBinding(_ id: String) -> Binding<String> {
        return Binding(get: { [weak self] in
            self?.commentDrafts[id] ?? ""
        }, set: { [weak self] value in
            self?.commentDrafts[id] = String(value.prefix(HarnessgramDecisionComment.limit))
        })
    }

    func commentState(_ decision: HarnessgramCockpitScreen.Decision) -> NativeCommentState {
        return self.commentStates[decision.id] ?? .idle
    }

    func sendComment(_ decision: HarnessgramCockpitScreen.Decision) {
        guard let context = self.context, decision.extras.commentAllowed else { return }
        if case .sending = self.commentStates[decision.id] {
            return
        }
        let text = self.commentDrafts[decision.id] ?? ""
        guard HarnessgramDecisionComment.body(id: decision.id, text: text) != nil else { return }
        self.commentStates[decision.id] = .sending
        HarnessgramCockpitSync.shared.commentFromNativeCockpit(context: context, decision: decision, text: text, reason: NativeCockpitStrings.t(.commentFaceIDReason), completion: { [weak self] result in
            guard let self else { return }
            self.commentStates[decision.id] = .finished(result)
            if result == .sent {
                self.commentDrafts[decision.id] = ""
            }
        })
    }

    func noteBinding(_ id: String) -> Binding<String> {
        return Binding(get: { [weak self] in
            self?.notes[id] ?? ""
        }, set: { [weak self] value in
            guard let self else { return }
            // A rich decision takes the bridge's longer note; nothing the owner typed is cut below that.
            let limit = self.decision(id: id).map { HarnessgramDecisionAnswer.noteLimit(for: $0) } ?? HarnessgramDecisionAnswer.richNoteLimit
            self.notes[id] = String(value.prefix(limit))
        })
    }
}

/// A comment's state on its decision page.
enum NativeCommentState: Equatable {
    case idle
    case sending
    case finished(HarnessgramDecisionComment.Result)

    var line: String? {
        switch self {
        case .idle:
            return nil
        case .sending:
            return NativeCockpitStrings.t(.commentSending)
        case let .finished(result):
            switch result {
            case .sent: return NativeCockpitStrings.t(.commentSent)
            case .closed: return NativeCockpitStrings.t(.resultClosed)
            case .refused: return NativeCockpitStrings.t(.commentRefused)
            case .notConfirmed: return NativeCockpitStrings.t(.resultNotConfirmed)
            case .loginExpired: return NativeCockpitStrings.t(.resultLoginExpired)
            case .busy: return NativeCockpitStrings.t(.resultBusy)
            case .failed: return NativeCockpitStrings.t(.commentUncertain)
            }
        }
    }
}
