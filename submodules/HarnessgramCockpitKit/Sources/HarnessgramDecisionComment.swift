import Foundation

/// The owner's own words on a decision without deciding (bridge rich decisions, docs/panel.md "A comment without
/// deciding"): `POST /api/decide {"id", "choice": "reply", "note"}`. It answers and approves nothing; the question
/// stays open and can still be answered yes or no. Only offered when the decision says `"rich_decision": true`.
public enum HarnessgramDecisionComment {
    /// The bridge's limit for a note with rich decisions on.
    public static let limit = 1_000

    public enum Result: Equatable, Sendable {
        /// The bridge took the comment (the session reads it as the owner's words, not an approval).
        case sent
        /// The decision closed or its session ended.
        case closed
        /// Refused: too many comments, a permission request, or comments are off on the bridge.
        case refused
        /// Face ID was cancelled or failed: nothing was sent.
        case notConfirmed
        /// No login fresh enough, the bridge refused it, or the account changed.
        case loginExpired
        /// The bridge is busy; try again later.
        case busy
        /// No answer, or one the app does not understand (it may have arrived).
        case failed
    }

    /// nil for a malformed id, an empty comment or one over the limit.
    public static func body(id: String, text: String) -> Data? {
        let note = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard HarnessgramCockpitLinks.isDecisionId(id), !note.isEmpty, note.count <= limit else {
            return nil
        }
        return try? JSONSerialization.data(withJSONObject: ["id": id, "choice": "reply", "note": note])
    }

    public static func result(_ response: HarnessgramCockpitHTTPResponse) -> Result {
        let object = (try? JSONSerialization.jsonObject(with: response.body)) as? [String: Any]
        switch response.status {
        case 200:
            return object?["ok"] as? Bool == true && object?["reply"] as? Bool == true ? .sent : .failed
        case 400:
            return .refused
        case 401, 403:
            return .loginExpired
        case 404, 409:
            return .closed
        case 429, 503:
            return .busy
        default:
            return .failed
        }
    }
}

extension HarnessgramCockpitClient {
    /// Sends one comment with a login that can answer; the caller has already asked for Face ID.
    public func comment(id: String, text: String, credential: HarnessgramCockpitCredential, now: Date) async -> HarnessgramDecisionComment.Result {
        guard credential.canAnswer(now: now), let origin = credential.originURL, let body = HarnessgramDecisionComment.body(id: id, text: text), let request = HarnessgramCockpitClient.request(origin: origin, path: HarnessgramCockpitClient.decidePath, credential: credential, body: body) else {
            return .loginExpired
        }
        guard let response = try? await self.transport.perform(request) else {
            return .failed
        }
        return HarnessgramDecisionComment.result(response)
    }
}
