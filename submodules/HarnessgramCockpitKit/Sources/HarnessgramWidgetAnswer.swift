import Foundation

/// The widget's Approve / Decline button (HarnessgramAnswerIntent) calls this. It answers only a
/// decision the widget showed, takes its sensitivity from the stored snapshot (never from the button),
/// and refuses anything sensitive: those are answered in the app after Face ID.
public enum HarnessgramWidgetAnswer {
    public enum Result: Equatable {
        /// Not a decision the widget showed, or not answerable on the widget: nothing was sent.
        case refused
        case answered(HarnessgramCockpitClient.AnswerOutcome)
    }

    public static func run(id: String, choice: String, store: HarnessgramCockpitStore, client: HarnessgramCockpitClient, now: Date) async -> Result {
        guard let choice = HarnessgramCockpitLinks.Choice(rawValue: choice), HarnessgramCockpitLinks.isDecisionId(id) else {
            return .refused
        }
        // One atomic read: the session, its snapshot and its login belong to the same account and epoch.
        // A busy store (the app holds the lock) is retried briefly; it never reads as "no such decision".
        guard case let .completed(context?) = await HarnessgramCockpitStore.retrying({ store.answerContextChecked() }), let decision = context.snapshot.decisions.first(where: { $0.id == id }) else {
            return .refused
        }
        let session = context.session
        // nil while the phone is locked: the login file has complete protection.
        guard HarnessgramDecisionGate.route(sensitive: decision.sensitive, credential: context.credential, now: now) == .answerOnWidget, let credential = context.credential else {
            store.updateSnapshot(forSession: session) { $0.withNotice(HarnessgramWidgetStrings.answerNotSent) }
            return .refused
        }
        // Checked again right before sending: a logout or a switch since the read sends nothing.
        guard case .completed(true) = await HarnessgramCockpitStore.retrying({ store.isCurrentChecked(session) }) else {
            return .refused
        }
        let outcome = await client.answer(id: id, choice: choice, credential: credential, now: now)
        // Every write afterwards is bound to the same session; a changed session drops it.
        switch outcome {
        case .sent, .closed:
            // The bridge took it: the answer must be remembered, or an older snapshot brings the decision back. Still
            // busy after the retries: the store keeps it pending and writes it with its next locked write.
            _ = await HarnessgramCockpitStore.retrying(attempts: 6, { store.markAnsweredChecked(id, forSession: session) })
        case .expired:
            store.forgetCredential(forSession: session)
            store.updateSnapshot(forSession: session) { $0.withNotice(HarnessgramWidgetStrings.answerNotSent) }
        case .failed:
            store.updateSnapshot(forSession: session) { $0.withNotice(HarnessgramWidgetStrings.answerNotSent) }
        }
        return .answered(outcome)
    }
}
