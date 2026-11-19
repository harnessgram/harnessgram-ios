import Foundation
import Display
import AccountContext
import TelegramPresentationData
import HarnessgramCockpitKit
import HarnessgramCockpitSync
import HarnessgramHouseCore

/// What the knock sheet and the waiting list do with a decision. Both go through here, so the Face ID rule lives in
/// one place: a sensitive decision is never answered in place; it opens the app flow (the same one the widgets use),
/// which looks the decision up again in the Cockpit and asks for Face ID (or the passcode) before anything is sent.
public final class HouseDecisionActions: @unchecked Sendable {
    public enum Outcome: Equatable, Sendable {
        case sent
        case gone
        case notConfirmed
        case unavailable
    }

    private let context: AccountContext

    public init(context: AccountContext) {
        self.context = context
    }

    /// What the owner may do with this decision right now (`HouseWaitingRowPlan`, which follows the widget's rule).
    public func plan(for decision: HarnessgramCockpitSnapshot.Decision) -> HouseWaitingRowPlan {
        let fallback = HouseWaitingRowPlan.make(decision: decision, credential: nil, now: Date())
        guard !decision.sensitive, HarnessgramCockpitSync.shared.viewState?.credentialCanAnswer == true, fallback.style == .answerViaApp else {
            return fallback
        }
        return HouseWaitingRowPlan(style: .answerInPlace, yesLabel: fallback.yesLabel, noLabel: fallback.noLabel)
    }

    /// Answers a plain yes/no decision from the row or the sheet, with a fresh login when the stored one is too old.
    /// Never used for a sensitive decision: it refuses before anything is sent.
    public func answer(decision: HarnessgramCockpitSnapshot.Decision, choice: HarnessgramCockpitLinks.Choice, completion: @escaping (Outcome) -> Void) {
        assert(Thread.isMainThread)
        guard !decision.sensitive else {
            completion(.unavailable)
            return
        }
        let sync = HarnessgramCockpitSync.shared
        sync.answerUsingStoredCredential(context: self.context, decision: decision, choice: choice, completion: { result in
            switch result {
            case .sent: completion(.sent)
            case .gone: completion(.gone)
            case .notConfirmed: completion(.notConfirmed)
            case .unavailable: completion(.unavailable)
            }
        })
    }

    /// The app flow for a decision: the same screen the widgets open. A sensitive decision asks for Face ID there.
    public func openAppFlow(decision: HarnessgramCockpitSnapshot.Decision, choice: HarnessgramCockpitLinks.Choice?) {
        guard let url = HarnessgramCockpitLinks.decideURL(id: decision.id, choice: choice) else {
            return
        }
        self.open(url: url.absoluteString)
    }

    /// Opens the room's topic from a Cockpit topic link (`https://t.me/c/<channel>/<thread>`); false for any other link.
    @discardableResult
    public func openRoom(topicURL: String) -> Bool {
        guard let url = HarnessgramCockpitLinks.appURL(forTopicURL: topicURL) else {
            return false
        }
        self.open(url: url.absoluteString)
        return true
    }

    /// Opens a Telegram link (a topic, a bot chat) or an app link through Telegram's own URL handling.
    public func open(url: String) {
        let presentationData = self.context.sharedContext.currentPresentationData.with { $0 }
        let navigationController = self.context.sharedContext.mainWindow?.viewController as? NavigationController
        self.context.sharedContext.openExternalUrl(context: self.context, urlContext: .generic, url: url, forceExternal: false, presentationData: presentationData, navigationController: navigationController, dismissInput: {})
    }
}
