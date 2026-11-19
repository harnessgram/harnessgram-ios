import Foundation
import Display
import SwiftSignalKit
import TelegramCore
import AccountContext
import AlertUI

/// Same local request queue as the channel/group allow list. Phase 1 only records the request.
public func harnessgramStickerApprovalAlert(context: AccountContext, pack: StickerPackReference?, present: @escaping (ViewController) -> Void) -> ViewController {
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    var actions = [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]
    if let id = HarnessgramPolicy.stickerPackRequestId(pack) {
        let title: String
        if case let .name(name)? = pack {
            title = "Sticker pack " + name
        } else {
            title = "Sticker pack " + id
        }
        actions.insert(TextAlertAction(type: .defaultAction, title: "Ask to approve", action: {
            let saved = HarnessgramPolicyStore.shared.requestApproval(accountPeerId: context.account.peerId, id: id, title: title)
            present(textAlertController(context: context, title: nil, text: saved ? "Request sent" : "Could not save request", actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]))
        }), at: 0)
    }
    return textAlertController(context: context, title: nil, text: HarnessgramPolicy.unapprovedStickerText, actions: actions)
}
