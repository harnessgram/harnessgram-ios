import Foundation
import HarnessgramSettings

/// The links a widget opens, including the bridge's Today deep links.
public enum HarnessgramCockpitLinks {
    /// What a `harnessgram://widget/...` link asks for.
    public enum WidgetLink: Equatable {
        /// Open the app and refresh the widgets.
        case open
        /// Open the Cockpit screen.
        case cockpit
        /// Answer one decision inside the app. `choice` nil: the app asks which answer.
        case decide(id: String, choice: Choice?)
        /// Connect the widgets to the bridge (build 18): the unpaired widget's tap.
        case pair
    }

    public enum Choice: String, CaseIterable, Sendable {
        case yes
        case no
    }

    /// The bridge's decision ids: 16 lower-case hex characters (see docs/harnessgram-local-config.md).
    public static func isDecisionId(_ value: String) -> Bool {
        return value.utf8.count == 16 && value.utf8.allSatisfy { (0x30 ... 0x39).contains($0) || (0x61 ... 0x66).contains($0) }
    }

    /// `https://t.me/c/<channel>/<thread>` (the Cockpit's topic link) becomes
    /// `tg://privatepost?channel=<channel>&thread=<thread>`, which the app resolves to that topic.
    /// Anything else gives nil and the widget opens the app without a topic.
    public static func appURL(forTopicURL value: String) -> URL? {
        guard let components = URLComponents(string: value), components.scheme?.lowercased() == "https", components.host?.lowercased() == "t.me", components.user == nil, components.password == nil, components.port == nil else {
            return nil
        }
        let parts = components.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard parts.count == 3, parts[0] == "c", let channel = Int64(parts[1]), channel > 0, let thread = Int64(parts[2]), thread > 0 else {
            return nil
        }
        return URL(string: "tg://privatepost?channel=\(channel)&thread=\(thread)")
    }

    /// The channel id inside `https://t.me/c/<channel>/<thread>` (the room an item belongs to), or nil for any other
    /// link. The same strict check as `appURL(forTopicURL:)`.
    public static func channelId(fromTopicURL value: String) -> Int64? {
        guard let components = URLComponents(string: value), components.scheme?.lowercased() == "https", components.host?.lowercased() == "t.me", components.user == nil, components.password == nil, components.port == nil else {
            return nil
        }
        let parts = components.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard parts.count == 3, parts[0] == "c", let channel = Int64(parts[1]), channel > 0, let thread = Int64(parts[2]), thread > 0 else {
            return nil
        }
        return channel
    }

    /// A Today destination on Telegram or on the exact paired or configured Mini App host.
    public static func todayURL(_ value: String, bridgeOrigin: URL? = nil) -> URL? {
        guard let components = URLComponents(string: value), components.scheme?.lowercased() == "https",
              let host = components.host?.lowercased(), components.user == nil, components.password == nil,
              components.rangeOfPort == nil, let url = components.url else {
            return nil
        }
        if host == "t.me" {
            return url
        }
        let origin = bridgeOrigin ?? HarnessgramLocalConfig.originURL(HarnessgramLocalConfig.bundled.bridgeOrigin)
        return host == origin?.host?.lowercased() ? url : nil
    }

    public static let openURL = URL(string: "harnessgram://widget/open")!
    public static let cockpitURL = URL(string: "harnessgram://widget/cockpit")!
    /// The unpaired widget opens this: the app connects the widgets to the bridge.
    public static let pairURL = URL(string: "harnessgram://widget/pair")!

    public static func decideURL(id: String, choice: Choice?) -> URL? {
        guard isDecisionId(id) else {
            return nil
        }
        var components = URLComponents()
        components.scheme = "harnessgram"
        components.host = "widget"
        components.path = "/decide"
        var items = [URLQueryItem(name: "id", value: id)]
        if let choice {
            items.append(URLQueryItem(name: "choice", value: choice.rawValue))
        }
        components.queryItems = items
        return components.url
    }

    /// Parses widget navigation, pairing and decision links.
    /// nil for any other link, and for a decide link with a bad id, an unknown choice or extra fields.
    public static func parseWidgetLink(_ value: String) -> WidgetLink? {
        guard let components = URLComponents(string: value.trimmingCharacters(in: .whitespacesAndNewlines)), components.scheme?.lowercased() == "harnessgram", components.host?.lowercased() == "widget" else {
            return nil
        }
        let path = components.path.lowercased()
        let items = components.queryItems ?? []
        if path == "/open" || path == "/open/" {
            return items.isEmpty ? .open : nil
        }
        if path == "/cockpit" || path == "/cockpit/" {
            return items.isEmpty ? .cockpit : nil
        }
        if path == "/pair" || path == "/pair/" {
            return items.isEmpty ? .pair : nil
        }
        guard path == "/decide" || path == "/decide/" else {
            return nil
        }
        var id: String?
        var choice: Choice?
        var seen = Set<String>()
        for item in items {
            guard seen.insert(item.name).inserted else {
                return nil
            }
            switch item.name {
            case "id":
                id = item.value
            case "choice":
                guard let value = item.value, let parsed = Choice(rawValue: value) else {
                    return nil
                }
                choice = parsed
            default:
                return nil
            }
        }
        guard let id, isDecisionId(id) else {
            return nil
        }
        return .decide(id: id, choice: choice)
    }
}
