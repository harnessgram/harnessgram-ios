import Foundation
import HarnessgramSettings

/// The Cockpit's own login: the signed Mini App `initData` Telegram issues to this app when it opens the
/// Cockpit bot's web app, plus the Cockpit origin. The bridge accepts it for reading for an hour and for
/// answering for 15 minutes after Telegram signed it (see docs/harnessgram-local-config.md), so it
/// is short-lived by design. It is kept only in the app group's protected file (unreadable while the
/// phone is locked) and is never logged.
public struct HarnessgramCockpitCredential: Codable, Equatable, Sendable {
    /// Reads stop a little before the bridge's hour, answers a little before its 15 minutes, so a
    /// request never arrives just after the bridge stopped taking the login.
    public static let readWindow: TimeInterval = 3300
    public static let answerWindow: TimeInterval = 780
    /// A login the bridge would call "from the future".
    static let futureSlack: TimeInterval = 30

    public var initData: String
    /// `https://host[:port]`, authorized during pairing and kept in protected storage.
    public var origin: String
    public var authDate: Date
    /// Pairing authorization, stored with the credential under complete file protection.
    private var pairedOrigin: String?

    public init(initData: String, origin: String, authDate: Date, configuration: HarnessgramLocalConfig = .bundled) {
        self.initData = initData
        self.origin = origin
        self.authDate = authDate
        if let url = HarnessgramLocalConfig.originURL(origin), configuration.allowsBridgeOrigin(url) {
            self.pairedOrigin = url.absoluteString
        } else {
            self.pairedOrigin = nil
        }
    }

    public var originURL: URL? {
        guard let origin = HarnessgramLocalConfig.originURL(self.origin) else { return nil }
        // Legacy credentials have no pairing marker: authorize them against the local build input.
        guard self.pairedOrigin == origin.absoluteString || HarnessgramLocalConfig.bundled.allowsBridgeOrigin(origin) else { return nil }
        return origin
    }

    public func canRead(now: Date) -> Bool {
        return self.age(now: now).map { $0 < HarnessgramCockpitCredential.readWindow } ?? false
    }

    public func canAnswer(now: Date) -> Bool {
        return self.age(now: now).map { $0 < HarnessgramCockpitCredential.answerWindow } ?? false
    }

    func age(now: Date) -> TimeInterval? {
        let age = now.timeIntervalSince(self.authDate)
        guard age > -HarnessgramCockpitCredential.futureSlack, self.originURL != nil else {
            return nil
        }
        return max(0, age)
    }

    /// The bot menu origin, accepted only against the local pairing configuration.
    /// Missing configuration fails closed before any login is sent.
    public static func origin(ofMenuURL value: String, configuration: HarnessgramLocalConfig = .bundled) -> URL? {
        guard let components = URLComponents(string: value), components.scheme?.lowercased() == "https", let host = components.host?.lowercased(), !host.isEmpty, components.user == nil, components.password == nil else {
            return nil
        }
        var origin = URLComponents()
        origin.scheme = "https"
        origin.host = host
        origin.port = components.port
        guard let url = origin.url, configuration.allowsBridgeOrigin(url) else {
            return nil
        }
        return url
    }

    static func isAllowedOrigin(_ url: URL) -> Bool {
        return HarnessgramLocalConfig.originURL(url.absoluteString) != nil
    }

    /// The login from the URL Telegram returns for the Cockpit web app: its fragment carries
    /// `tgWebAppData=<initData>`. nil unless the login has a signature, a user and a sane auth date.
    public static func from(webAppURL: String, menuURL: String, configuration: HarnessgramLocalConfig = .bundled) -> HarnessgramCockpitCredential? {
        guard let origin = origin(ofMenuURL: menuURL, configuration: configuration), let signed = URLComponents(string: webAppURL), signed.scheme?.lowercased() == origin.scheme, signed.host?.lowercased() == origin.host, signed.port == origin.port, signed.user == nil, signed.password == nil, let hash = webAppURL.firstIndex(of: "#") else {
            return nil
        }
        let fragment = String(webAppURL[webAppURL.index(after: hash)...])
        guard !fragment.isEmpty else {
            return nil
        }
        // Parsed by hand: URLComponents traps on a badly percent-encoded query set from outside.
        guard let initData = queryPairs(fragment).first(where: { $0.0 == "tgWebAppData" })?.1, !initData.isEmpty, initData.utf8.count <= 4096 else {
            return nil
        }
        let items = queryPairs(initData)
        guard Set(items.map { $0.0 }).count == items.count, items.contains(where: { $0.0 == "hash" && !$0.1.isEmpty }), items.contains(where: { $0.0 == "user" }), let authText = items.first(where: { $0.0 == "auth_date" })?.1, let auth = TimeInterval(authText), auth > 0 else {
            return nil
        }
        return HarnessgramCockpitCredential(initData: initData, origin: origin.absoluteString, authDate: Date(timeIntervalSince1970: auth), configuration: configuration)
    }

    /// `a=1&b=%20` -> [("a", "1"), ("b", " ")]; a pair that does not decode is dropped.
    static func queryPairs(_ query: String) -> [(String, String)] {
        return query.split(separator: "&", omittingEmptySubsequences: true).compactMap { pair in
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard let name = String(parts[0]).removingPercentEncoding, let value = String(parts.count > 1 ? parts[1] : "").removingPercentEncoding else {
                return nil
            }
            return (name, value)
        }
    }
}

/// Where an answer to one decision may happen.
public enum HarnessgramDecisionGate {
    public enum Route: Equatable {
        /// Approve and decline buttons on the widget itself (iOS asks to unlock the phone first).
        case answerOnWidget
        /// The buttons open the app, which answers with a fresh login.
        case answerInApp
        /// Only inside the app, after Face ID or the passcode.
        case answerInAppWithFaceID
    }

    /// A sensitive decision never gets an in-place button, whatever the login. A plain one gets it only
    /// while the login can still answer.
    public static func route(sensitive: Bool, credential: HarnessgramCockpitCredential?, now: Date) -> Route {
        if sensitive {
            return .answerInAppWithFaceID
        }
        guard let credential, credential.canAnswer(now: now) else {
            return .answerInApp
        }
        return .answerOnWidget
    }
}
