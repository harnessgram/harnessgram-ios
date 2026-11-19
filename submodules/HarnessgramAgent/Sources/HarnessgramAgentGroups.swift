import Foundation
import HarnessgramSettings

/// The forum groups where the Telegram bridge runs agent sessions (one topic per session): the home
/// group and the project groups. Only these get the agent shortcuts (quick-action ribbon, topic status
/// dots). Membership here approves nothing: which chats are visible stays with approved.json and the
/// request flow (HarnessgramPolicyStore).
///
/// Ids are Bot API chat ids, as the bridge's own settings name them: a supergroup is "-100" followed by
/// its channel id. A plain positive channel id is accepted too. Anything else is ignored.
public struct HarnessgramAgentGroups: Equatable {
    public let channelIds: Set<Int64>

    public init(channelIds: Set<Int64>) {
        self.channelIds = channelIds
    }

    public init(ids: [String]) {
        self.channelIds = Set(ids.compactMap(HarnessgramAgentGroups.channelId(fromChatId:)))
    }

    public func contains(channelId: Int64) -> Bool {
        return self.channelIds.contains(channelId)
    }

    public func union(_ other: HarnessgramAgentGroups) -> HarnessgramAgentGroups {
        return HarnessgramAgentGroups(channelIds: self.channelIds.union(other.channelIds))
    }

    /// "-100900000002" -> 900000002; "900000002" -> 900000002; anything else -> nil.
    public static func channelId(fromChatId value: String) -> Int64? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits: Substring
        if trimmed.hasPrefix("-100") {
            digits = trimmed.dropFirst(4)
        } else {
            digits = Substring(trimmed)
        }
        guard !digits.isEmpty, digits.allSatisfy({ $0.isASCII && $0.isNumber }), let id = Int64(digits), id > 0 else {
            return nil
        }
        return id
    }

    private struct Bundled: Decodable {
        var agentProjectGroups: [String]?
    }

    /// approved.json "agentProjectGroups"; a missing key or malformed file marks no group.
    public static func decodeBundled(_ data: Data) -> HarnessgramAgentGroups {
        let bundled = try? JSONDecoder().decode(Bundled.self, from: data)
        return HarnessgramAgentGroups(ids: bundled?.agentProjectGroups ?? [])
    }

    /// The groups shipped in the app's approved.json (read once).
    public static let bundled: HarnessgramAgentGroups = {
        return HarnessgramAgentGroups.bundledApprovedData().map(HarnessgramAgentGroups.decodeBundled) ?? HarnessgramAgentGroups(channelIds: [])
    }()

    /// The shipped groups plus the ones added in the Harnessgram settings.
    public static func current(settings: HarnessgramSettings = .shared) -> HarnessgramAgentGroups {
        let extra = settings.agentProjectGroups
        if extra.isEmpty {
            return HarnessgramAgentGroups.bundled
        }
        return HarnessgramAgentGroups.bundled.union(HarnessgramAgentGroups(ids: extra))
    }

    /// approved.json ships in the app bundle; an extension finds it two levels up (App.app/PlugIns/X.appex).
    private static func bundledApprovedData() -> Data? {
        var bundles = [Bundle.main]
        if Bundle.main.bundleURL.pathExtension == "appex", let app = Bundle(url: Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent()) {
            bundles.append(app)
        }
        for bundle in bundles {
            if let url = bundle.url(forResource: "approved", withExtension: "json", subdirectory: "Harnessgram") ?? bundle.url(forResource: "approved", withExtension: "json"), let data = try? Data(contentsOf: url) {
                return data
            }
        }
        return nil
    }
}
