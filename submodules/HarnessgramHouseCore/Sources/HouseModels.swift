import Foundation
import HarnessgramCockpitKit
import HarnessgramSettings

/// A room is lit while an agent works in it, dim when nothing happens and amber when something waits for the
/// owner (brand kit: window states).
public enum HouseRoomState: String, Codable, Equatable, Sendable {
    case lit
    case dim
    case waiting
}

/// Names the room's picture in the asset catalog (`room-gesher`, `life-yoman`, ...). The art itself ships as
/// default and the owner can replace it; the key is only a name.
public struct HouseRoomArtKey: RawRepresentable, Hashable, Codable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(from decoder: Decoder) throws {
        self.rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(self.rawValue)
    }

    public static let gesher = HouseRoomArtKey(rawValue: "room-gesher")
    public static let projectA = HouseRoomArtKey(rawValue: "room-project-a")
    public static let projectB = HouseRoomArtKey(rawValue: "room-project-b")
    public static let projectC = HouseRoomArtKey(rawValue: "room-project-c")
    public static let newRoom = HouseRoomArtKey(rawValue: "room-new")

    /// The art for a project by its name (Hebrew or Latin, any case); unknown names get the empty new room.
    public static func key(forTitle title: String, aliases: [String: [String]] = HarnessgramLocalConfig.bundled.roomArtAliases ?? [:]) -> HouseRoomArtKey {
        let folded = title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).lowercased()
        let defaults: [(HouseRoomArtKey, [String])] = [
            (.gesher, ["גשר", "gesher", "harnessgram", "הרנסגרם"]),
            (.projectA, ["פרויקט לדוגמה", "example project"]),
            (.projectB, ["תוכן לדוגמה", "example content"]),
            (.projectC, ["חנות לדוגמה", "example shop"]),
        ]
        let matches = defaults.map { (key, names) in (key, aliases[key.rawValue] ?? names) }
        for (key, needles) in matches where needles.contains(where: { folded.contains($0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).lowercased()) }) {
            return key
        }
        return .newRoom
    }
}

/// One room card: a project group (the bridge's forum group) with its state.
public struct HouseRoom: Equatable, Identifiable, Codable, Sendable {
    /// The Telegram channel id of the project group.
    public var channelId: Int64
    public var title: String
    public var state: HouseRoomState
    /// Open decisions that belong to the room.
    public var waitingCount: Int
    public var workingAgents: Int
    public var artKey: HouseRoomArtKey

    public var id: Int64 {
        return self.channelId
    }

    public init(channelId: Int64, title: String, state: HouseRoomState, waitingCount: Int, workingAgents: Int, artKey: HouseRoomArtKey) {
        self.channelId = channelId
        self.title = title
        self.state = state
        self.waitingCount = waitingCount
        self.workingAgents = workingAgents
        self.artKey = artKey
    }

    /// The one status line under the room's name.
    public var statusLine: String {
        switch self.state {
        case .waiting:
            return HouseHomeStrings.string(self.waitingCount > 1 ? .roomWaitingMany : .roomWaitingOne)
        case .lit:
            return HouseHomeStrings.string(.roomWorking)
        case .dim:
            return HouseHomeStrings.string(.roomQuiet)
        }
    }
}

/// How the bridge asks: yes/no (the default until the bridge sends a kind) or a choice of options.
public enum HouseWaitingKind: Equatable, Sendable {
    case yesNo
    case choice(options: [String])
}

/// One thing that waits for the owner: a line in the doorway and in the waiting list.
public struct HouseWaitingItem: Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    /// The project the question came from, as the Cockpit names it.
    public var roomTitle: String
    public var roomChannelId: Int64?
    public var kind: HouseWaitingKind
    public var sensitive: Bool
    public var topicURL: String

    public init(id: String, title: String, roomTitle: String, roomChannelId: Int64?, kind: HouseWaitingKind, sensitive: Bool, topicURL: String) {
        self.id = id
        self.title = title
        self.roomTitle = roomTitle
        self.roomChannelId = roomChannelId
        self.kind = kind
        self.sensitive = sensitive
        self.topicURL = topicURL
    }

    /// A Cockpit decision as a waiting item. Anything but a "choice" with at least two options is a yes/no question;
    /// the decision's own `sensitive` mark is kept as is (fail closed stays with the Cockpit parser).
    public init(decision: HarnessgramCockpitSnapshot.Decision) {
        let kind: HouseWaitingKind
        if decision.kind == "choice", let options = decision.options, options.count >= 2 {
            kind = .choice(options: options)
        } else {
            kind = .yesNo
        }
        self.init(id: decision.id, title: decision.title, roomTitle: decision.topic, roomChannelId: decision.roomChannelId, kind: kind, sensitive: decision.sensitive, topicURL: decision.topicURL)
    }
}

/// Everything the Home screen shows.
public struct HouseHomeState: Equatable, Sendable {
    public var greeting: HouseGreeting
    /// Open items, the first is previewed in the doorway.
    public var waiting: [HouseWaitingItem]
    public var rooms: [HouseRoom]

    public init(greeting: HouseGreeting, waiting: [HouseWaitingItem], rooms: [HouseRoom]) {
        self.greeting = greeting
        self.waiting = waiting
        self.rooms = rooms
    }

    public var waitingCount: Int {
        return self.waiting.count
    }

    /// The doorway stays when nothing waits (must-keep 1): it then shows the "all done" state.
    public var doorwayIsEmpty: Bool {
        return self.waiting.isEmpty
    }

    public var doorwayPreview: HouseWaitingItem? {
        return self.waiting.first
    }

    public static func make(now: Date, calendar: Calendar = .current, openDecisions: [HarnessgramCockpitSnapshot.Decision], rooms: [HouseRoom]) -> HouseHomeState {
        return HouseHomeState(greeting: HouseGreeting(date: now, calendar: calendar), waiting: openDecisions.map(HouseWaitingItem.init(decision:)), rooms: rooms)
    }
}
