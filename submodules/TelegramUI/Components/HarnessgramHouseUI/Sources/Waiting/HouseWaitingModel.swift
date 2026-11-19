import Foundation
import UIKit
import SwiftSignalKit
import AccountContext
import HarnessgramCockpitKit
import HarnessgramCockpitSync
import HarnessgramHouseCore
import HarnessgramSettingsUI

/// The waiting list's data: every open decision as of the last Cockpit refresh (the app-only full list, not the widget's
/// five), kept current while the screen is on view. The screen's rules (what a row can do) are `HouseWaitingRowPlan`.
/// Used from the main queue only (SwiftUI and the Cockpit's notification both arrive there).
final class HouseWaitingModel: ObservableObject {
    enum RowState: Equatable {
        case sending
        case failed(String)
    }

    @Published private(set) var decisions: [HarnessgramCockpitSnapshot.Decision] = []
    @Published private(set) var rowStates: [String: RowState] = [:]
    @Published private(set) var hasLogin = false

    let actions: HouseDecisionActions
    private let context: AccountContext
    private var pollDisposable: Disposable?
    private var observer: NSObjectProtocol?

    init(context: AccountContext) {
        self.context = context
        self.actions = HouseDecisionActions(context: context)
        self.reload()
    }

    deinit {
        self.stop()
    }

    /// The screen is on view: refresh now and every 45 seconds, and follow every Cockpit change.
    func start() {
        guard self.pollDisposable == nil else {
            return
        }
        self.reload()
        self.pollDisposable = HarnessgramCockpitSync.shared.pollWhileVisible(context: self.context)
        self.observer = NotificationCenter.default.addObserver(forName: HarnessgramCockpitSync.snapshotDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.reload()
        }
    }

    func stop() {
        self.pollDisposable?.dispose()
        self.pollDisposable = nil
        if let observer = self.observer {
            NotificationCenter.default.removeObserver(observer)
            self.observer = nil
        }
    }

    func reload() {
        let state = HarnessgramCockpitSync.shared.viewState
        // The full list; before it was ever saved, the widget snapshot's lines.
        self.decisions = state?.openDecisions ?? state?.snapshot?.decisions ?? []
        self.hasLogin = state?.hasLogin ?? false
        let open = Set(self.decisions.map { $0.id })
        self.rowStates = self.rowStates.filter { open.contains($0.key) }
    }

    func plan(for decision: HarnessgramCockpitSnapshot.Decision) -> HouseWaitingRowPlan {
        return self.actions.plan(for: decision)
    }

    /// Answers a plain yes/no row in place.
    func answer(_ decision: HarnessgramCockpitSnapshot.Decision, _ choice: HarnessgramCockpitLinks.Choice) {
        guard self.rowStates[decision.id] != .sending else {
            return
        }
        self.rowStates[decision.id] = .sending
        self.actions.answer(decision: decision, choice: choice, completion: { [weak self] outcome in
            guard let self else {
                return
            }
            switch outcome {
            case .sent, .gone:
                // The Cockpit store already dropped it and posted the change; the row leaves with the reload.
                self.rowStates[decision.id] = nil
                self.reload()
            case .notConfirmed:
                self.rowStates[decision.id] = nil
            case .unavailable:
                self.rowStates[decision.id] = .failed(HouseKnockStrings.t(.sendFailed))
            }
        })
    }

    /// A sensitive row: the app flow asks for Face ID before anything is sent.
    func approveWithFaceID(_ decision: HarnessgramCockpitSnapshot.Decision) {
        self.actions.openAppFlow(decision: decision, choice: nil)
    }

    func openRoom(_ decision: HarnessgramCockpitSnapshot.Decision) {
        self.actions.openRoom(topicURL: decision.topicURL)
    }

    func canOpenRoom(_ decision: HarnessgramCockpitSnapshot.Decision) -> Bool {
        return HarnessgramCockpitLinks.appURL(forTopicURL: decision.topicURL) != nil
    }
}
