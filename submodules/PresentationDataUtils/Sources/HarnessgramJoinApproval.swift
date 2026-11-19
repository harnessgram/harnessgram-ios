import AccountContext
import AlertUI
import Display
import TelegramCore

private let waitingForCommitteeTitle = "ההצטרפות מחכה לאישור הוועדה"

/// Confirms a local queue entry (saved on this phone, passed to the committee later; never claims it was sent), or
/// reports a failure without claiming the request was saved.
public func harnessgramJoinApprovalAlert(context: AccountContext, requestRecorded: Bool, acknowledged: (() -> Void)? = nil) -> ViewController {
    return textAlertController(
        context: context,
        title: waitingForCommitteeTitle,
        text: requestRecorded ? "הבקשה נשמרה ותועבר לוועדה" : "לא הצלחנו לשמור את הבקשה",
        actions: [TextAlertAction(type: .defaultAction, title: "אישור", action: { acknowledged?() })],
        dismissOnOutsideTap: acknowledged == nil
    )
}

/// The restricted link preview lets the owner request approval without displaying the invite's media.
public func harnessgramJoinApprovalPrompt(context: AccountContext, requestId: String, name: String, present: @escaping (ViewController) -> Void) -> ViewController {
    return textAlertController(
        context: context,
        title: waitingForCommitteeTitle,
        text: "אפשר לשלוח בקשת אישור לוועדה.",
        actions: [
            TextAlertAction(type: .genericAction, title: "ביטול", action: {}),
            TextAlertAction(type: .defaultAction, title: "שליחת בקשה", action: {
                let recorded = HarnessgramPolicyStore.shared.requestJoinApproval(accountPeerId: context.account.peerId, id: requestId, name: name)
                present(harnessgramJoinApprovalAlert(context: context, requestRecorded: recorded))
            })
        ]
    )
}
