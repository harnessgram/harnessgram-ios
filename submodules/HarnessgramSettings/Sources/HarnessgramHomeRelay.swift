import Foundation

/// Non-secret build inputs merged into approved.json. See docs/harnessgram-local-config.md.
/// Public builds contain no bridge, relay, bot or project identity.
public struct HarnessgramLocalConfig: Decodable {
    public var bridgeOrigin: String?
    public var bridgeHostSuffixes: [String]?
    public var bridgeBotUsername: String?
    public var relayHost: String?
    public var relayPort: Int32?
    public var roomArtStorageKeys: [String: String]?
    public var roomArtAliases: [String: [String]]?

    public init(bridgeOrigin: String? = nil, bridgeHostSuffixes: [String]? = nil, bridgeBotUsername: String? = nil, relayHost: String? = nil, relayPort: Int32? = nil, roomArtAliases: [String: [String]]? = nil, roomArtStorageKeys: [String: String]? = nil) {
        self.bridgeOrigin = bridgeOrigin
        self.bridgeHostSuffixes = bridgeHostSuffixes
        self.bridgeBotUsername = bridgeBotUsername
        self.relayHost = relayHost
        self.relayPort = relayPort
        self.roomArtAliases = roomArtAliases
        self.roomArtStorageKeys = roomArtStorageKeys
    }

    public static func decode(_ data: Data) -> HarnessgramLocalConfig {
        return (try? JSONDecoder().decode(HarnessgramLocalConfig.self, from: data)) ?? HarnessgramLocalConfig()
    }

    public static let bundled: HarnessgramLocalConfig = {
        var bundles = [Bundle.main]
        if Bundle.main.bundleURL.pathExtension == "appex", let app = Bundle(url: Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent()) {
            bundles.append(app)
        }
        for bundle in bundles {
            if let url = bundle.url(forResource: "approved", withExtension: "json", subdirectory: "Harnessgram") ?? bundle.url(forResource: "approved", withExtension: "json"), let data = try? Data(contentsOf: url) {
                return HarnessgramLocalConfig.decode(data)
            }
        }
        return HarnessgramLocalConfig()
    }()

    /// Canonical HTTPS origin, never userinfo, a path, a query or a fragment.
    public static func originURL(_ value: String?) -> URL? {
        guard let value, let c = URLComponents(string: value), c.scheme?.lowercased() == "https", let host = c.host, !host.isEmpty, c.user == nil, c.password == nil, c.path.isEmpty || c.path == "/", c.query == nil, c.fragment == nil, c.port.map({ (1 ... 65535).contains($0) }) ?? true else {
            return nil
        }
        var origin = URLComponents()
        origin.scheme = "https"
        origin.host = host.lowercased()
        origin.port = c.port
        return origin.url
    }

    /// Initial pairing must match a configured origin or a specifically configured private network.
    /// A bare public suffix is never a safe private network boundary.
    public func allowsBridgeOrigin(_ origin: URL) -> Bool {
        guard let canonical = HarnessgramLocalConfig.originURL(origin.absoluteString), let host = canonical.host else { return false }
        if let configured = HarnessgramLocalConfig.originURL(self.bridgeOrigin), canonical == configured { return true }
        return (self.bridgeHostSuffixes ?? []).contains { suffix in
            let suffix = suffix.lowercased()
            return suffix.hasPrefix(".") && suffix.split(separator: ".").count >= 3 && host.hasSuffix(suffix) && host.count > suffix.count
        }
    }
}

/// A user-supplied SOCKS5 relay on their computer. No endpoint means no probe and no proxy installation.
public enum HarnessgramHomeRelay {
    public static let missingConfigurationMessage = "לא הוגדרה כתובת לממסר במחשב שלך. יש להגדיר כתובת לפני החיבור."

    public static func configuredHost(_ config: HarnessgramLocalConfig = .bundled) -> String? {
        guard let host = config.relayHost?.trimmingCharacters(in: .whitespacesAndNewlines), !host.isEmpty, !host.contains(where: { $0.isWhitespace }), let url = URL(string: "https://\(host)"), url.host?.lowercased() == host.lowercased(), url.user == nil, url.password == nil, url.port == nil, url.path.isEmpty, url.query == nil, url.fragment == nil else { return nil }
        return host
    }

    public static var host: String? { return self.configuredHost() }
    public static var port: Int32 {
        guard let port = HarnessgramLocalConfig.bundled.relayPort, (1 ... 65535).contains(port) else { return 1080 }
        return port
    }
}
