import Foundation
import Display
import AccountContext
import PresentationDataUtils
import TelegramPresentationData
import HarnessgramCockpitKit
import HarnessgramCockpitSync

/// Handles a home or lock-screen widget link for refreshing, opening the Cockpit, pairing or answering.
/// A decision is looked up again in the Cockpit with a
/// fresh login, so a closed or unknown decision is never answered and its sensitivity comes from the
/// Cockpit, not from the link. A plain decision with a chosen answer is sent at once; anything else asks
/// first, and a sensitive decision also needs Face ID (or the passcode). Returns false for other links.
func harnessgramOpenWidgetDeepLink(context: AccountContext, url: String) -> Bool {
    guard let link = HarnessgramCockpitLinks.parseWidgetLink(url) else {
        return false
    }
    let sync = HarnessgramCockpitSync.shared
    switch link {
    case .pair:
        // The unpaired widget's tap: connect the widgets to the bridge (Face ID), then say how it went.
        let present: (String) -> Void = { text in
            context.sharedContext.presentGlobalController(textAlertController(context: context, title: nil, text: text, actions: [TextAlertAction(type: .defaultAction, title: context.sharedContext.currentPresentationData.with { $0 }.strings.Common_OK, action: {})]), nil)
        }
        sync.pair(context: context, completion: { result in
            switch result {
            case .connected:
                present(HarnessgramWidgetStrings.pairConnected)
            case .needsOneAccount:
                present(HarnessgramWidgetStrings.pairNeedsOneAccount)
            case let .failed(reason):
                present(reason.text)
            case .notConfirmed:
                break
            }
        })
    case .open:
        sync.refresh(context: context, force: true)
    case .cockpit:
        harnessgramOpenCockpit(context: context)
    case let .decide(id, choice):
        let present: (String) -> Void = { text in
            context.sharedContext.presentGlobalController(textAlertController(context: context, title: nil, text: text, actions: [TextAlertAction(type: .defaultAction, title: context.sharedContext.currentPresentationData.with { $0 }.strings.Common_OK, action: {})]), nil)
        }
        sync.openDecision(context: context, id: id, completion: { decision, credential, session in
            guard let credential, let session else {
                present(HarnessgramWidgetStrings.cockpitUnavailable)
                return
            }
            guard let decision else {
                present(HarnessgramWidgetStrings.decisionGone)
                return
            }
            let send: (HarnessgramCockpitLinks.Choice) -> Void = { choice in
                sync.answer(decision: decision, choice: choice, credential: credential, session: session, completion: { result in
                    switch result {
                    case .sent:
                        present(HarnessgramWidgetStrings.answerSent)
                    case .gone:
                        present(HarnessgramWidgetStrings.decisionGone)
                    case .unavailable:
                        present(HarnessgramWidgetStrings.cockpitUnavailable)
                    case .notConfirmed:
                        break
                    }
                })
            }
            if let choice, !decision.sensitive {
                send(choice)
                return
            }
            var text = decision.title
            if !decision.topic.isEmpty {
                text += "\n" + decision.topic
            }
            let alert = textAlertController(
                context: context,
                title: HarnessgramWidgetStrings.confirmTitle,
                text: text,
                actions: [
                    TextAlertAction(type: .genericAction, title: HarnessgramWidgetStrings.cancel, action: {}),
                    TextAlertAction(type: .destructiveAction, title: decision.noLabel, action: {
                        send(.no)
                    }),
                    TextAlertAction(type: .defaultAction, title: decision.yesLabel, action: {
                        send(.yes)
                    }),
                ],
                actionLayout: .vertical
            )
            context.sharedContext.presentGlobalController(alert, nil)
        })
    }
    return true
}
