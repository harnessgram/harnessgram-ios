import Foundation
import HarnessgramSettings

/// Requests to the bridge's Cockpit, with the login in the `X-Telegram-Init-Data` header exactly as the
/// Cockpit page sends it. Only the read routes, `/api/decide` and `/api/live-activity-token` are used; nothing else is
/// ever called.
public struct HarnessgramCockpitClient {
    public static let initHeader = "X-Telegram-Init-Data"
    public static let statePath = "/api/state"
    public static let radioPath = "/api/radio-player"
    public static let decidePath = "/api/decide"
    /// Registers (or forgets) the push token of one task Live Activity, so the bridge can update it while the app is closed.
    public static let liveActivityTokenPath = "/api/live-activity-token"
    public static let cardMediaTokenPath = "/api/card-media-token"
    static let timeout: TimeInterval = 25

    public enum FetchError: Error, Equatable {
        case noCredential
        /// The bridge refused the login (too old or not the owner's): mint a new one in the app.
        case expired
        /// The bridge answered with another status than 200 or 403.
        case unavailable
        /// No answer at all (network, Tailscale or the panel down).
        case unreachable
        /// A 200 the parser could not read.
        case badAnswer
        /// The bridge asked the app to wait (429 or 503), for this many seconds when it said.
        case rateLimited(TimeInterval?)
    }

    public enum AnswerOutcome: Equatable {
        case sent
        /// Answered before, closed or no longer waiting: nothing more to do.
        case closed
        case expired
        case failed
    }

    public let transport: HarnessgramCockpitTransport

    public init(session: URLSession = HarnessgramCockpitClient.makeSession()) {
        self.transport = HarnessgramCockpitURLSessionTransport(session: session)
    }

    public init(transport: HarnessgramCockpitTransport) {
        self.transport = transport
    }

    /// No cookies, no cache, no redirects: a redirect would carry the login header to another host.
    public static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout + 5
        return URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
    }

    final class NoRedirects: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }

    public static func request(origin: URL, path: String, credential: HarnessgramCockpitCredential, body: Data) -> URLRequest? {
        guard HarnessgramCockpitCredential.isAllowedOrigin(origin), HarnessgramLocalConfig.originURL(origin.absoluteString) == credential.originURL, [statePath, radioPath, decidePath, liveActivityTokenPath, cardMediaTokenPath].contains(path), var components = URLComponents(url: origin, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.path = path
        guard let url = components.url else {
            return nil
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.httpShouldHandleCookies = false
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(credential.initData, forHTTPHeaderField: initHeader)
        request.httpBody = body
        return request
    }

    /// `{"id", "choice"}` with no note: the bridge's decide body.
    public static func decideBody(id: String, choice: HarnessgramCockpitLinks.Choice) -> Data? {
        guard HarnessgramCockpitLinks.isDecisionId(id) else {
            return nil
        }
        return try? JSONSerialization.data(withJSONObject: ["id": id, "choice": choice.rawValue], options: [.sortedKeys])
    }

    public static let maxLiveActivityTokenBytes = 256

    /// The Live Activity token body: `{"card_id", "token" (hex), "env"}`, or `{"card_id", "ended": true}` when the
    /// activity ended. `sandbox` is true for development-signed builds.
    public static func liveActivityTokenBody(cardId: String, token: Data?, sandbox: Bool) -> Data? {
        guard (1 ... 128).contains(cardId.utf8.count), cardId.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._:-").contains($0) }) else {
            return nil
        }
        guard let token else {
            return try? JSONSerialization.data(withJSONObject: ["card_id": cardId, "ended": true], options: [.sortedKeys])
        }
        // APNs device and Live Activity tokens are 32 bytes today; Apple allows them to grow (up to 100 bytes and
        // more), so up to 256 are sent.
        guard (1 ... HarnessgramCockpitClient.maxLiveActivityTokenBytes).contains(token.count) else {
            return nil
        }
        let hex = token.map { String(format: "%02x", $0) }.joined()
        return try? JSONSerialization.data(withJSONObject: ["card_id": cardId, "token": hex, "env": sandbox ? "sandbox" : "production"], options: [.sortedKeys])
    }

    /// The diagnosis body: `{"card_id", "problem"}`, where `problem` is one of the bridge's allow-listed codes
    /// (HarnessgramLiveActivityTokenRule). The bridge only logs the code; it stores nothing.
    public static func liveActivityProblemBody(cardId: String, problem: String) -> Data? {
        guard HarnessgramLiveActivityTokenRule.isProblemCode(problem), liveActivityTokenBody(cardId: cardId, token: nil, sandbox: false) != nil else {
            return nil
        }
        return try? JSONSerialization.data(withJSONObject: ["card_id": cardId, "problem": problem], options: [.sortedKeys])
    }

    /// How the bridge answered `/api/decide` (see docs/harnessgram-local-config.md).
    public static func answerOutcome(status: Int, body: Data) -> AnswerOutcome {
        switch status {
        case 200:
            let ok = ((try? JSONSerialization.jsonObject(with: body)) as? [String: Any])?["ok"] as? Bool
            return ok == true ? .sent : .failed
        case 403:
            return .expired
        case 404, 409:
            // 409 "queue full" is the only conflict that is not final.
            let error = ((try? JSONSerialization.jsonObject(with: body)) as? [String: Any])?["error"] as? String
            return error == "queue full" ? .failed : .closed
        default:
            return .failed
        }
    }

    /// The widget snapshot and, for the app, every open decision (uncapped) and the native Cockpit's screen model from
    /// the same answer. `screen` is nil only when its own fields could not be read; the snapshot still counts.
    public struct Fetched: Sendable {
        public let snapshot: HarnessgramCockpitSnapshot
        public let openDecisions: [HarnessgramCockpitSnapshot.Decision]
        public let screen: HarnessgramCockpitScreen?
    }

    public func fetchSnapshot(credential: HarnessgramCockpitCredential, now: Date) async throws -> HarnessgramCockpitSnapshot {
        return try await self.fetch(credential: credential, now: now).snapshot
    }

    public func fetch(credential: HarnessgramCockpitCredential, now: Date) async throws -> Fetched {
        guard credential.canRead(now: now), let origin = credential.originURL, let stateRequest = HarnessgramCockpitClient.request(origin: origin, path: HarnessgramCockpitClient.statePath, credential: credential, body: Data("{}".utf8)), let radioRequest = HarnessgramCockpitClient.request(origin: origin, path: HarnessgramCockpitClient.radioPath, credential: credential, body: Data("{}".utf8)) else {
            throw FetchError.noCredential
        }
        let state: HarnessgramCockpitHTTPResponse
        do {
            state = try await self.load(stateRequest)
        } catch {
            throw FetchError.unreachable
        }
        guard state.status != 403 else {
            throw FetchError.expired
        }
        if state.status == 429 || state.status == 503 {
            throw FetchError.rateLimited(state.retryAfter)
        }
        guard state.status == 200 else {
            throw FetchError.unavailable
        }
        // The radio line is a bonus: the widget still shows the decisions when its read fails.
        let radio = try? await self.load(radioRequest)
        do {
            let snapshot = try HarnessgramCockpitParser.snapshot(state: state.body, radioPlayer: radio?.status == 200 ? radio?.body : nil, now: now, bridgeOrigin: origin)
            let screen = try? HarnessgramCockpitScreen.parse(state: state.body, radio: snapshot.radio, now: now, bridgeOrigin: origin)
            return Fetched(snapshot: snapshot, openDecisions: try HarnessgramCockpitParser.openDecisions(state: state.body), screen: screen)
        } catch {
            throw FetchError.badAnswer
        }
    }

    public func answer(id: String, choice: HarnessgramCockpitLinks.Choice, credential: HarnessgramCockpitCredential, now: Date) async -> AnswerOutcome {
        guard credential.canAnswer(now: now) else {
            return .expired
        }
        guard let origin = credential.originURL, let body = HarnessgramCockpitClient.decideBody(id: id, choice: choice), let request = HarnessgramCockpitClient.request(origin: origin, path: HarnessgramCockpitClient.decidePath, credential: credential, body: body) else {
            return .failed
        }
        guard let response = try? await self.load(request) else {
            return .failed
        }
        return HarnessgramCockpitClient.answerOutcome(status: response.status, body: response.body)
    }

    /// What became of one Live Activity token change.
    public enum TokenOutcome: Equatable {
        case stored
        /// Offline, login too old, rate limited or a server error: send it again later.
        case retry
        /// The bridge (or the app) refused the request itself: sending it again cannot help.
        case drop
    }

    /// Sends one Live Activity token change. A login of read age is enough: the token only lets this phone receive
    /// the progress cards the same login can already read.
    public func registerLiveActivityToken(cardId: String, token: Data?, sandbox: Bool, credential: HarnessgramCockpitCredential, now: Date) async -> TokenOutcome {
        guard let body = HarnessgramCockpitClient.liveActivityTokenBody(cardId: cardId, token: token, sandbox: sandbox) else {
            return .drop
        }
        return await self.postLiveActivityToken(body: body, credential: credential, now: now)
    }

    /// Tells the bridge why a task Live Activity has no push token (one allow-listed code), with the same login rules.
    public func reportLiveActivityProblem(cardId: String, problem: String, credential: HarnessgramCockpitCredential, now: Date) async -> TokenOutcome {
        guard let body = HarnessgramCockpitClient.liveActivityProblemBody(cardId: cardId, problem: problem) else {
            return .drop
        }
        return await self.postLiveActivityToken(body: body, credential: credential, now: now)
    }

    private func postLiveActivityToken(body: Data, credential: HarnessgramCockpitCredential, now: Date) async -> TokenOutcome {
        guard credential.canRead(now: now), let origin = credential.originURL, let request = HarnessgramCockpitClient.request(origin: origin, path: HarnessgramCockpitClient.liveActivityTokenPath, credential: credential, body: body) else {
            return .retry
        }
        guard let response = try? await self.load(request) else {
            return .retry
        }
        switch response.status {
        case 200:
            return .stored
        case 400, 404, 413:
            return .drop
        default:
            return .retry
        }
    }

    private func load(_ request: URLRequest) async throws -> HarnessgramCockpitHTTPResponse {
        return try await self.transport.perform(request)
    }
}
