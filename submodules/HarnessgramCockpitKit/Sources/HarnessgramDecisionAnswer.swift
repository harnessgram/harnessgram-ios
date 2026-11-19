import Foundation

/// The native Cockpit's yes or no on one decision, through the bridge's own `POST /api/decide` with the signed Telegram
/// login, exactly as the Mini App sends it. The steps, in this order:
/// 1. refuse what this screen must not send (a permission request, a note that is too long);
/// 2. ask for Face ID when the decision is not explicitly routine; a cancel sends nothing;
/// 3. only then take the login, which must still be fresh enough to answer (`canAnswer`);
/// 4. send once and read the bridge's answer, with its delivery receipt.
/// Each dependency is passed in, so the flow is tested with a fake transport.
public enum HarnessgramDecisionAnswer {
    /// The bridge's note limit (decisions.NOTE_CHARS).
    public static let noteLimit = 300
    /// With rich decisions on, the bridge takes a longer note (NOTE_CHARS); a decision marked rich_decision says so.
    public static let richNoteLimit = 1_000

    public static func noteLimit(for decision: HarnessgramCockpitScreen.Decision) -> Int {
        return decision.extras.commentAllowed ? richNoteLimit : noteLimit
    }

    public enum Result: Equatable, Sendable {
        /// The bridge recorded the answer. `key` follows the delivery in the panel's `deliveries[]`.
        case sent(key: String?, delivery: HarnessgramCockpitScreen.DeliveryState)
        /// Someone answered it first, it was cancelled, or its session ended or asked again: nothing to do.
        /// `choice` is the earlier answer when the bridge says it.
        case alreadyClosed(choice: HarnessgramCockpitLinks.Choice?)
        /// Face ID was cancelled or failed: nothing was sent.
        case notConfirmed
        /// The app withdrew authorization before sending (switch, session, decision, or bridge changed).
        case cancelledLocally
        /// No login fresh enough to answer, or the bridge refused it.
        case loginExpired
        /// The bridge declined the answer because it was busy. Try again after `retryAfter` seconds when it said.
        case busy(retryAfter: TimeInterval?)
        /// This screen does not send it (a permission request, a "yes" to a decline-only request, a note over the limit).
        case notAllowed
        /// No answer, or one the app does not understand.
        case failed
    }

    /// `{"id", "choice", "note"?}`; nil for a malformed id or a note over the limit. An empty note is left out.
    public static func body(id: String, choice: HarnessgramCockpitLinks.Choice, note: String, limit: Int = noteLimit) -> Data? {
        guard HarnessgramCockpitLinks.isDecisionId(id) else {
            return nil
        }
        let note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard note.count <= limit else {
            return nil
        }
        var object: [String: Any] = ["id": id, "choice": choice.rawValue]
        if !note.isEmpty {
            object["note"] = note
        }
        return try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    /// The bridge's answer to `/api/decide` (docs/panel.md).
    public static func result(_ response: HarnessgramCockpitHTTPResponse) -> Result {
        let object = (try? JSONSerialization.jsonObject(with: response.body)) as? [String: Any]
        switch response.status {
        case 200:
            guard object?["ok"] as? Bool == true else {
                return .failed
            }
            let key = (object?["key"] as? String).flatMap { $0.isEmpty ? nil : String($0.prefix(80)) }
            return .sent(key: key, delivery: HarnessgramCockpitScreen.DeliveryState(bridgeValue: object?["delivery"]))
        case 401, 403:
            return .loginExpired
        case 404:
            return .alreadyClosed(choice: nil)
        case 409:
            if object?["error"] as? String == "queue full" {
                return .busy(retryAfter: response.retryAfter)
            }
            return .alreadyClosed(choice: (object?["choice"] as? String).flatMap(HarnessgramCockpitLinks.Choice.init(rawValue:)))
        case 429:
            return .busy(retryAfter: response.retryAfter)
        case 503:
            // A proxy or bridge failure can happen after the answer was recorded. Only a known explicit
            // rejection of this answer permits a retry.
            return object?["error"] as? String == "queue full" && object?["ok"] as? Bool != true
                ? .busy(retryAfter: response.retryAfter) : .failed
        default:
            return .failed
        }
    }

    /// Both stored and newly minted logins must come from the bridge that served this decision.
    public static func matchesBridge(_ login: HarnessgramCockpitCredential, for decision: HarnessgramCockpitScreen.Decision) -> Bool {
        return HarnessgramAnswerGuard.sameOrigin(shown: decision.bridgeOrigin, minted: login.originURL)
    }

    /// Whether this screen may send `choice` for `decision` with `note` (step 1).
    public static func mayAnswer(_ decision: HarnessgramCockpitScreen.Decision, choice: HarnessgramCockpitLinks.Choice, note: String) -> Bool {
        guard decision.answerableHere else {
            return false
        }
        if decision.declineOnly && choice == .yes {
            return false
        }
        return note.trimmingCharacters(in: .whitespacesAndNewlines).count <= noteLimit(for: decision)
    }

    /// Runs the whole answer. `confirm` shows Face ID with the given reason and says whether the owner passed;
    /// `credential` returns the login to answer with (called only after Face ID, so its freshness is checked then).
    @MainActor
    public static func run(
        decision: HarnessgramCockpitScreen.Decision,
        choice: HarnessgramCockpitLinks.Choice,
        note: String,
        reason: String,
        confirm: @Sendable (String) async -> Bool,
        credential: @MainActor () async -> HarnessgramCockpitCredential?,
        stillAllowed: @MainActor () -> Bool,
        willSend: @MainActor () -> Void = {},
        onLoginRejected: @MainActor (HarnessgramCockpitCredential) async -> Void = { _ in },
        transport: HarnessgramCockpitTransport,
        now: @Sendable () -> Date
    ) async -> Result {
        guard mayAnswer(decision, choice: choice, note: note), let body = body(id: decision.id, choice: choice, note: note, limit: noteLimit(for: decision)) else {
            return .notAllowed
        }
        if decision.requiresOwnerCheck {
            guard await confirm(reason) else {
                return .notConfirmed
            }
        }
        let candidate = await credential()
        guard stillAllowed() else {
            return .cancelledLocally
        }
        guard let login = candidate else {
            return .loginExpired
        }
        guard matchesBridge(login, for: decision) else {
            return .cancelledLocally
        }
        guard login.canAnswer(now: now()), let origin = login.originURL else {
            return .loginExpired
        }
        guard let request = HarnessgramCockpitClient.request(origin: origin, path: HarnessgramCockpitClient.decidePath, credential: login, body: body) else {
            return .loginExpired
        }
        do {
            guard let response = try await transport.perform(request, ifAllowed: {
                guard stillAllowed(), login.canAnswer(now: now()) else { return false }
                willSend()
                return true
            }) else {
                return .cancelledLocally
            }
            let outcome = result(response)
            if outcome == .loginExpired {
                await onLoginRejected(login)
            }
            return outcome
        } catch {
            return .failed
        }
    }
}
