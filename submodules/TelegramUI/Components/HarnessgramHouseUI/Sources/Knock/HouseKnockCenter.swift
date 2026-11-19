import Foundation
import UIKit
import AccountContext
import HarnessgramSettings
import HarnessgramCockpitKit
import HarnessgramCockpitSync
import HarnessgramHouseCore
import HarnessgramSettingsUI

/// A bridge message that may knock, as the in-app notification hook read it (the hook is the one place that looks at
/// Telegram's message types; `HouseKnockRule` decides whether it may knock).
public struct HouseKnockMessage: Equatable, Sendable {
    /// One key per message (`peer:namespace:id`), so the same message never knocks twice.
    public var key: String
    public var text: String
    /// The chat's title: the project group, or the bridge bot's name.
    public var chatTitle: String
    /// `tg://...` link to the topic (or the bot's chat) the message is in.
    public var openRoomLink: String?

    public init(key: String, text: String, chatTitle: String, openRoomLink: String?) {
        self.key = key
        self.text = text
        self.chatTitle = chatTitle
        self.openRoomLink = openRoomLink
    }
}

/// The knock (House step 3). The in-app notification hook calls `poke` for a bridge message that asks a question. The
/// center forces a Cockpit refresh, compares the open decisions with the ledger of decisions that already knocked, and
/// shows one sheet for each new one (at most three per poke, one at a time). A decision knocks once, also across
/// relaunches; "later" leaves it in the list and the doorway.
///
/// Telegram's banner is held back by the hook for such a message. If the Cockpit does not list a new decision within
/// 2.5 seconds (not paired, or the refresh is slow), the sheet shows the bridge's own message with "open the room",
/// so the question is never lost. All of this runs on the main queue; `@unchecked Sendable` only so the notification
/// and timer closures may capture it.
public final class HouseKnockCenter: @unchecked Sendable {
    public static let shared = HouseKnockCenter()

    /// How long the center waits for the Cockpit before it shows the bridge's message itself.
    static let fallbackDelay: TimeInterval = 2.5
    /// How long a poke can still turn into a decision's knock (a slow refresh).
    static let pokeWindow: TimeInterval = 20.0

    private struct Poke {
        var message: HouseKnockMessage
        var deadline: Date
    }

    private weak var context: AccountContext?
    private var pending: [Poke] = []
    private var queue: [HouseKnockItem] = []
    /// Ids of the items in the queue or on screen: a second evaluation never queues them again.
    private var activeIds = Set<String>()
    private var shownMessageKeys: [String] = []
    private weak var presenting: HouseKnockSheetController?
    private var observer: NSObjectProtocol?
    private var ledger: HouseKnockLedger?
    private var ledgerAccount: Int64?

    private init() {
    }

    /// A bridge message that asks a question arrived while the owner is not in that chat.
    public func poke(context: AccountContext, message: HouseKnockMessage) {
        assert(Thread.isMainThread)
        guard HarnessgramSettings.shared.houseFeature(.knock), UIApplication.shared.applicationState == .active else {
            return
        }
        self.context = context
        if self.shownMessageKeys.contains(message.key) || self.pending.contains(where: { $0.message.key == message.key }) {
            return
        }
        self.installObserver()
        self.pending.append(Poke(message: message, deadline: Date().addingTimeInterval(HouseKnockCenter.pokeWindow)))
        HarnessgramCockpitSync.shared.refresh(context: context, force: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + HouseKnockCenter.fallbackDelay) { [weak self] in
            self?.showMessageIfStillPending(key: message.key)
        }
    }

    private func installObserver() {
        guard self.observer == nil else {
            return
        }
        self.observer = NotificationCenter.default.addObserver(forName: HarnessgramCockpitSync.snapshotDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.evaluate()
        }
    }

    private func ledger(for context: AccountContext) -> HouseKnockLedger {
        let accountId = context.account.peerId.id._internalGetInt64Value()
        if let ledger = self.ledger, self.ledgerAccount == accountId {
            return ledger
        }
        let ledger = HouseKnockLedger(storage: HouseKnockUserDefaultsStorage(accountId: accountId))
        self.ledger = ledger
        self.ledgerAccount = accountId
        return ledger
    }

    /// The Cockpit has new data: any open poke that finds a decision that never knocked turns into its sheet.
    private func evaluate() {
        assert(Thread.isMainThread)
        let now = Date()
        self.pending.removeAll(where: { $0.deadline < now })
        guard !self.pending.isEmpty, let context = self.context, let open = HarnessgramCockpitSync.shared.viewState?.openDecisions else {
            return
        }
        let ledger = self.ledger(for: context)
        let new = ledger.newDecisions(open: open).filter { !self.activeIds.contains("d:" + $0.id) }
        guard !new.isEmpty else {
            return
        }
        self.pending.removeAll()
        let batch = HouseKnockQueue.batch(from: new)
        for decision in batch.skipped {
            // Beyond the cap: seen, not knocked; it waits in the list.
            ledger.markKnocked(decision.id)
        }
        var items: [HouseKnockItem] = []
        for (index, decision) in batch.show.enumerated() {
            let more = (batch.show.count - 1 - index) + batch.skipped.count
            items.append(HouseKnockItem(decision: decision, moreWaiting: more))
        }
        for item in items {
            self.activeIds.insert(item.id)
        }
        self.queue.insert(contentsOf: items, at: 0)
        self.presentNextIfIdle()
    }

    /// The Cockpit listed nothing new: the bridge's own message knocks, with "open the room" only.
    private func showMessageIfStillPending(key: String) {
        assert(Thread.isMainThread)
        guard let poke = self.pending.first(where: { $0.message.key == key }), !self.shownMessageKeys.contains(key) else {
            return
        }
        self.shownMessageKeys.append(key)
        if self.shownMessageKeys.count > 60 {
            self.shownMessageKeys.removeFirst(self.shownMessageKeys.count - 60)
        }
        let message = poke.message
        let question = HouseKnockText.questionLine(fromMessageText: message.text) ?? HouseKnockStrings.t(.roomQuestionFallback)
        let title = message.chatTitle.isEmpty ? HouseKnockText.roomFallback : message.chatTitle
        let item = HouseKnockItem(source: .message(key: message.key), question: question, roomTitle: title, openRoomLink: message.openRoomLink)
        self.activeIds.insert(item.id)
        self.queue.append(item)
        self.presentNextIfIdle()
    }

    private func presentNextIfIdle() {
        assert(Thread.isMainThread)
        guard self.presenting == nil, !self.queue.isEmpty, let context = self.context, UIApplication.shared.applicationState == .active else {
            return
        }
        let item = self.queue.removeFirst()
        let actions = HouseDecisionActions(context: context)
        let plan = item.decision.map { actions.plan(for: $0) }
        if let decision = item.decision {
            self.ledger(for: context).markKnocked(decision.id)
        }
        let model = HouseKnockSheetModel(item: item, plan: plan)
        if item.moreWaiting > 0, HarnessgramSettings.shared.houseFeature(.waitingList) {
            model.onOpenWaitingList = {
                openHouseWaitingList(context: context)
            }
        }
        let controller = HouseKnockSheetController(model: model)
        controller.onDismissed = { [weak self] how in
            self?.sheetEnded(item: item, how: how, actions: actions, plan: plan)
        }
        self.presenting = controller
        context.sharedContext.presentGlobalController(controller, nil)
    }

    private func sheetEnded(item: HouseKnockItem, how: HouseKnockSheetController.Dismissal, actions: HouseDecisionActions, plan: HouseWaitingRowPlan?) {
        assert(Thread.isMainThread)
        self.presenting = nil
        self.activeIds.remove(item.id)
        switch how {
        case .later, .openWaitingList:
            break
        case .openRoom:
            if let link = item.openRoomLink {
                actions.open(url: link)
            }
        case .approve:
            self.approve(item: item, actions: actions, plan: plan)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.presentNextIfIdle()
        }
    }

    /// Approve: a sensitive decision opens the app flow (its alert and Face ID come first, as for a widget); a plain one is
    /// answered right away, and if that cannot be done the app flow takes over with the same answer.
    private func approve(item: HouseKnockItem, actions: HouseDecisionActions, plan: HouseWaitingRowPlan?) {
        guard let decision = item.decision, let plan else {
            return
        }
        switch plan.style {
        case .approveWithFaceID:
            actions.openAppFlow(decision: decision, choice: nil)
        case .answerInPlace, .answerViaApp:
            actions.answer(decision: decision, choice: .yes, completion: { outcome in
                if outcome == .unavailable {
                    actions.openAppFlow(decision: decision, choice: .yes)
                }
            })
        case .chooseInRoom:
            if let link = item.openRoomLink {
                actions.open(url: link)
            }
        }
    }
}
