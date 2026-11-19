import Foundation

/// What the widgets and the lock screen know about the House: the rooms in short and the waiting count. Written by
/// the app, read by the widget extension (the app group), so it holds no credential, no chat id beyond the
/// channel id and only the room names the owner already sees.
public struct HouseRoomsSummary: Codable, Equatable, Sendable {
    public struct Room: Codable, Equatable, Sendable {
        public var channelId: Int64
        public var title: String
        public var state: HouseRoomState
        public var artKey: HouseRoomArtKey

        public init(channelId: Int64, title: String, state: HouseRoomState, artKey: HouseRoomArtKey) {
            self.channelId = channelId
            self.title = title
            self.state = state
            self.artKey = artKey
        }
    }

    /// At most this many rooms are kept (the largest widget shows six).
    public static let maxRooms = 6

    public var updatedAt: Date
    public var waitingCount: Int
    public var rooms: [Room]

    public init(updatedAt: Date, waitingCount: Int, rooms: [Room]) {
        self.updatedAt = updatedAt
        self.waitingCount = waitingCount
        self.rooms = rooms
    }

    public init(state: HouseHomeState, now: Date) {
        self.init(
            updatedAt: now,
            waitingCount: state.waitingCount,
            rooms: HouseRoomsResolver.sortedForHome(state.rooms).prefix(HouseRoomsSummary.maxRooms).map {
                Room(channelId: $0.channelId, title: $0.title, state: $0.state, artKey: $0.artKey)
            }
        )
    }

    public static let fileName = "house-rooms.json"

    public func encoded() -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(self)
    }

    /// nil for anything that is not a summary; an unknown room state in a newer file drops that file entirely.
    public static func decode(_ data: Data) -> HouseRoomsSummary? {
        guard data.count <= 200_000 else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(HouseRoomsSummary.self, from: data)
    }
}
