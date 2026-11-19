import Foundation
import Security

/// The private listen link for the team radio (the bridge's listen_link feature). It is a secret:
/// it lives only in this device's Keychain, never in defaults, files or logs, and is never built in.
public enum HarnessgramRadioLink {
    private static let service = "Harnessgram.radio"
    private static let account = "listenLink"
    private static let trustedHostAccount = "trustedHost"

    public static let missingHostMessage = "לא הוגדרה כתובת לגשר במחשב שלך. יש לחבר את הגשר או להגדיר כתובת לפני שמירת קישור האזנה."

    /// What a radio deep link leads to.
    public enum DeepLinkDecision: Equatable {
        /// Not a radio deep link: other handlers take it.
        case notRadioLink
        /// No screen can be shown: nothing is saved, nothing opens.
        case drop
        /// The link fails the rules or points at a host that is not allowed: nothing is saved; the
        /// Radio screen opens to show the current state.
        case refuse
        /// The same stream is already saved: the Radio screen opens.
        case unchanged
        /// No link saved yet: save it, then open the Radio screen.
        case save(link: String)
        /// Another link is saved: ask "Replace the radio link?" naming `host`, save only on Replace.
        case confirmReplace(link: String, host: String)
    }

    /// The HLS playlist for a listen link: `https://host/listen/<token>` (the page the Cockpit opens)
    /// becomes `https://host/listen/<token>/live.m3u8`; a playlist link is used as is. Anything else,
    /// including plain http, is refused.
    public static func streamURL(fromListenLink link: String?) -> URL? {
        guard let link = link?.trimmingCharacters(in: .whitespacesAndNewlines), !link.isEmpty, var components = URLComponents(string: link), components.scheme?.lowercased() == "https", let host = components.host, !host.isEmpty, components.user == nil, components.password == nil else {
            return nil
        }
        components.fragment = nil
        components.query = nil
        var parts = components.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard let listenIndex = parts.firstIndex(of: "listen"), listenIndex + 1 < parts.count else {
            return nil
        }
        let token = parts[listenIndex + 1]
        guard token.count >= 16, token.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }), token.allSatisfy({ $0.isASCII }) else {
            return nil
        }
        let rest = Array(parts[(listenIndex + 2)...])
        if rest.isEmpty {
            parts.append("live.m3u8")
        } else if rest != ["live.m3u8"] {
            return nil
        }
        components.path = "/" + parts.joined(separator: "/")
        return components.url
    }

    /// The bridge hands the listen link over as a deep link, so the owner never copies it by hand:
    /// `harnessgram://radio?link=<listen link>` or, for Telegram buttons (which only take http and tg
    /// links), `tg://harnessgram/radio?link=<listen link>`.
    public static func isRadioDeepLink(_ value: String) -> Bool {
        guard let components = URLComponents(string: value.trimmingCharacters(in: .whitespacesAndNewlines)), let scheme = components.scheme?.lowercased() else {
            return false
        }
        let host = components.host?.lowercased() ?? ""
        let path = components.path.lowercased()
        if scheme == "harnessgram" {
            return host == "radio" && (path.isEmpty || path == "/")
        }
        if scheme == "tg" {
            return host == "harnessgram" && (path == "/radio" || path == "/radio/")
        }
        return false
    }

    /// The lower-cased host of a listen link that passes the link rules.
    public static func host(ofListenLink link: String) -> String? {
        return HarnessgramRadioLink.streamURL(fromListenLink: link)?.host?.lowercased()
    }

    /// Exact paired/saved host, or an explicitly configured origin/private network. No public fallback.
    public static func isAllowedHost(_ host: String, trustedHost: String?, pairedOrigin: String? = nil, configuration: HarnessgramLocalConfig = .bundled) -> Bool {
        let host = host.lowercased()
        if let pairedHost = HarnessgramLocalConfig.originURL(pairedOrigin)?.host, host == pairedHost { return true }
        if let trustedHost, !trustedHost.isEmpty, host == trustedHost.lowercased() { return true }
        var origin = URLComponents()
        origin.scheme = "https"
        origin.host = host
        guard let url = origin.url else { return false }
        if let configuredHost = HarnessgramLocalConfig.originURL(configuration.bridgeOrigin)?.host, host == configuredHost { return true }
        return configuration.allowsBridgeOrigin(url)
    }

    /// The decision for a radio deep link, from the saved link, the trusted host and whether a screen
    /// can be shown. Pure: the caller does the saving, asking and opening.
    public static func deepLinkDecision(_ url: String, currentLink: String?, trustedHost: String?, canPresent: Bool, pairedOrigin: String? = nil, configuration: HarnessgramLocalConfig = .bundled) -> DeepLinkDecision {
        guard HarnessgramRadioLink.isRadioDeepLink(url) else {
            return .notRadioLink
        }
        guard canPresent else {
            return .drop
        }
        guard let link = HarnessgramRadioLink.listenLink(fromDeepLink: url), let host = HarnessgramRadioLink.host(ofListenLink: link), HarnessgramRadioLink.isAllowedHost(host, trustedHost: trustedHost, pairedOrigin: pairedOrigin, configuration: configuration) else {
            return .refuse
        }
        if let currentLink, let currentStream = HarnessgramRadioLink.streamURL(fromListenLink: currentLink) {
            if currentStream == HarnessgramRadioLink.streamURL(fromListenLink: link) {
                return .unchanged
            }
            return .confirmReplace(link: link, host: host)
        }
        return .save(link: link)
    }

    /// The host of the first link the owner saved, kept in the Keychain next to the link.
    public static func trustedHost() -> String? {
        return HarnessgramRadioLink.loadItem(account: HarnessgramRadioLink.trustedHostAccount)
    }

    /// The listen link a radio deep link carries, only when it passes the same rules as a pasted one.
    public static func listenLink(fromDeepLink value: String) -> String? {
        guard HarnessgramRadioLink.isRadioDeepLink(value), let components = URLComponents(string: value.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return nil
        }
        let links = (components.queryItems ?? []).filter { $0.name == "link" }
        guard links.count == 1, let link = links[0].value?.trimmingCharacters(in: .whitespacesAndNewlines), HarnessgramRadioLink.streamURL(fromListenLink: link) != nil else {
            return nil
        }
        return link
    }

    public static func load() -> String? {
        return HarnessgramRadioLink.loadItem(account: HarnessgramRadioLink.account)
    }

    private static func loadItem(account: String) -> String? {
        var query = self.baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult public static func save(_ link: String, pairedOrigin: String? = nil) -> Bool {
        guard let host = self.host(ofListenLink: link), self.isAllowedHost(host, trustedHost: self.trustedHost(), pairedOrigin: pairedOrigin), let data = link.data(using: .utf8) else {
            return false
        }
        guard HarnessgramRadioLink.saveItem(data, account: HarnessgramRadioLink.account) else {
            return false
        }
        // Trust on first use: the first saved link's host is remembered and never replaced by later links.
        if HarnessgramRadioLink.trustedHost() == nil, let host = HarnessgramRadioLink.host(ofListenLink: link), let hostData = host.data(using: .utf8) {
            HarnessgramRadioLink.saveItem(hostData, account: HarnessgramRadioLink.trustedHostAccount)
        }
        return true
    }

    @discardableResult private static func saveItem(_ data: Data, account: String) -> Bool {
        SecItemDelete(self.baseQuery(account: account) as CFDictionary)
        var query = self.baseQuery(account: account)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    /// Removes the link only; the trusted host stays.
    public static func clear() {
        SecItemDelete(self.baseQuery(account: HarnessgramRadioLink.account) as CFDictionary)
    }

    private static func baseQuery(account: String) -> [String: Any] {
        return [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: self.service,
            kSecAttrAccount as String: account
        ]
    }
}
