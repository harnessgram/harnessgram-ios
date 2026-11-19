import Foundation
import HarnessgramAgent
import HarnessgramCockpitKit

/// A project group as the app knows it from Telegram: the group's channel id, its title and the state icons
/// of its session topics (read with `HarnessgramTopicStatus.from(title:)`).
public struct HouseRoomSource: Equatable, Sendable {
    public var channelId: Int64
    public var title: String
    public var topicStatuses: [HarnessgramTopicStatus]

    public init(channelId: Int64, title: String, topicStatuses: [HarnessgramTopicStatus]) {
        self.channelId = channelId
        self.title = title
        self.topicStatuses = topicStatuses
    }
}

/// Agent groups + peer titles + topic statuses + the Cockpit gives the rooms.
public enum HouseRoomsResolver {
    /// One room per source, in the sources' order (the caller sorts them: the Home screen shows rooms that wait
    /// first, via `sortedForHome`).
    ///
    /// - A room waits when an open decision belongs to it (the Cockpit's `roomChannelId`) or one of its topics shows
    ///   the "waiting for you" icon.
    /// - It is lit when an agent works in it (the Cockpit) or a topic shows the "working" icon.
    /// - Otherwise it is dim.
    /// The Cockpit's numbers win over the icons when both exist, so a room never counts one question twice.
    public static func resolve(sources: [HouseRoomSource], openDecisions: [HarnessgramCockpitSnapshot.Decision], agents: [HarnessgramCockpitSnapshot.Agent]) -> [HouseRoom] {
        return sources.map { source in
            let decisions = openDecisions.filter { $0.roomChannelId == source.channelId }.count
            let topicWaiting = source.topicStatuses.filter { $0 == .waitingForYou }.count
            let waiting = max(decisions, topicWaiting)
            let cockpitWorking = agents.filter { $0.roomChannelId == source.channelId }.count
            let topicWorking = source.topicStatuses.filter { $0 == .working }.count
            let working = max(cockpitWorking, topicWorking)
            let state: HouseRoomState
            if waiting > 0 {
                state = .waiting
            } else if working > 0 {
                state = .lit
            } else {
                state = .dim
            }
            let title = source.title.trimmingCharacters(in: .whitespacesAndNewlines)
            return HouseRoom(
                channelId: source.channelId,
                title: title.isEmpty ? HouseHomeStrings.string(.unnamedRoom) : title,
                state: state,
                waitingCount: waiting,
                workingAgents: working,
                artKey: HouseRoomArtKey.key(forTitle: title)
            )
        }
    }

    /// Rooms that wait first, then lit ones, then quiet ones; rooms of the same kind keep their order.
    public static func sortedForHome(_ rooms: [HouseRoom]) -> [HouseRoom] {
        func rank(_ state: HouseRoomState) -> Int {
            switch state {
            case .waiting:
                return 0
            case .lit:
                return 1
            case .dim:
                return 2
            }
        }
        return rooms.enumerated().sorted { lhs, rhs in
            let l = rank(lhs.element.state)
            let r = rank(rhs.element.state)
            return l != r ? l < r : lhs.offset < rhs.offset
        }.map { $0.element }
    }
}
