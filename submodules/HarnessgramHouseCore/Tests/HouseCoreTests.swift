import XCTest
import HarnessgramAgent
import HarnessgramCockpitKit
import HarnessgramHouseCore

final class HouseCoreTests: XCTestCase {
    private func decision(_ id: String, channel: Int64?, kind: String? = nil, options: [String]? = nil) -> HarnessgramCockpitSnapshot.Decision {
        return HarnessgramCockpitSnapshot.Decision(id: id, title: "למזג?", topic: "פרויקט לדוגמה", yesLabel: "כן", noLabel: "לא", topicURL: "", sensitive: false, roomChannelId: channel, kind: kind, options: options)
    }

    private func agent(_ id: String, channel: Int64?) -> HarnessgramCockpitSnapshot.Agent {
        return HarnessgramCockpitSnapshot.Agent(id: id, name: "n", step: "", topicURL: "", roomChannelId: channel)
    }

    // MARK: greeting

    func testGreetingByHour() {
        XCTAssertEqual(HouseGreeting(hour: 4), .evening)
        XCTAssertEqual(HouseGreeting(hour: 5), .morning)
        XCTAssertEqual(HouseGreeting(hour: 11), .morning)
        XCTAssertEqual(HouseGreeting(hour: 12), .noon)
        XCTAssertEqual(HouseGreeting(hour: 16), .noon)
        XCTAssertEqual(HouseGreeting(hour: 17), .evening)
        XCTAssertEqual(HouseGreeting(hour: 23), .evening)
        XCTAssertEqual(HouseGreeting(hour: 0), .evening)
        XCTAssertEqual(HouseGreeting.morning.text, "בוקר טוב")
        XCTAssertEqual(HouseGreeting.noon.text, "צהריים טובים")
        XCTAssertEqual(HouseGreeting.evening.text, "ערב טוב")
    }

    func testLocalRoomAliasesKeepTheSelectedArt() {
        XCTAssertEqual(HouseRoomArtKey.key(forTitle: "Example workspace: task", aliases: ["room-project-a": ["example workspace"]]), .projectA)
        XCTAssertEqual(HouseRoomArtKey.key(forTitle: "Another workspace", aliases: [:]), .newRoom)
    }

    func testGreetingUsesTheCalendarsTimeZone() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 2 * 3600)!
        // 06:00 UTC is 08:00 there.
        let date = Date(timeIntervalSince1970: 1_763_272_800)
        XCTAssertEqual(HouseGreeting(date: date, calendar: calendar), .morning)
    }

    // MARK: art keys

    func testRoomArtFollowsTheProjectName() {
        XCTAssertEqual(HouseRoomArtKey.key(forTitle: "פרויקט לדוגמה: מסך כניסה"), .projectA)
        XCTAssertEqual(HouseRoomArtKey.key(forTitle: "Example project"), .projectA)
        XCTAssertEqual(HouseRoomArtKey.key(forTitle: "תוכן לדוגמה"), .projectB)
        XCTAssertEqual(HouseRoomArtKey.key(forTitle: "Example shop"), .projectC)
        XCTAssertEqual(HouseRoomArtKey.key(forTitle: "גשר"), .gesher)
        XCTAssertEqual(HouseRoomArtKey.key(forTitle: "משהו אחר"), .newRoom)
        XCTAssertEqual(HouseRoomArtKey.key(forTitle: ""), .newRoom)
    }

    // MARK: resolver

    func testRoomStates() {
        let sources = [
            HouseRoomSource(channelId: 1, title: "פרויקט לדוגמה", topicStatuses: [.done]),
            HouseRoomSource(channelId: 2, title: "תוכן לדוגמה", topicStatuses: [.working, .done]),
            HouseRoomSource(channelId: 3, title: "חנות לדוגמה", topicStatuses: [.working, .waitingForYou]),
            HouseRoomSource(channelId: 4, title: "גשר", topicStatuses: []),
        ]
        let rooms = HouseRoomsResolver.resolve(sources: sources, openDecisions: [self.decision("00000000000000a1", channel: 4)], agents: [])
        XCTAssertEqual(rooms.map(\.state), [.dim, .lit, .waiting, .waiting])
        XCTAssertEqual(rooms.map(\.waitingCount), [0, 0, 1, 1])
        XCTAssertEqual(rooms[1].workingAgents, 1)
    }

    func testTheCockpitAndTheTopicIconsDoNotCountOneQuestionTwice() {
        let sources = [HouseRoomSource(channelId: 7, title: "פרויקט לדוגמה", topicStatuses: [.waitingForYou])]
        let rooms = HouseRoomsResolver.resolve(sources: sources, openDecisions: [self.decision("00000000000000a1", channel: 7)], agents: [self.agent("a", channel: 7)])
        XCTAssertEqual(rooms[0].waitingCount, 1)
        XCTAssertEqual(rooms[0].workingAgents, 1)
        XCTAssertEqual(rooms[0].state, .waiting)
    }

    func testItemsOfOtherRoomsAndWithoutARoomAreNotCounted() {
        let sources = [HouseRoomSource(channelId: 7, title: "פרויקט לדוגמה", topicStatuses: [])]
        let rooms = HouseRoomsResolver.resolve(sources: sources, openDecisions: [self.decision("00000000000000a1", channel: 8), self.decision("00000000000000a2", channel: nil)], agents: [self.agent("a", channel: nil)])
        XCTAssertEqual(rooms[0].state, .dim)
        XCTAssertEqual(rooms[0].waitingCount, 0)
    }

    func testStatusLines() {
        let waitingOne = HouseRoom(channelId: 1, title: "א", state: .waiting, waitingCount: 1, workingAgents: 0, artKey: .newRoom)
        let waitingMany = HouseRoom(channelId: 1, title: "א", state: .waiting, waitingCount: 3, workingAgents: 0, artKey: .newRoom)
        XCTAssertEqual(waitingOne.statusLine, "מחכה לך")
        XCTAssertEqual(waitingMany.statusLine, "מחכים לך")
        XCTAssertEqual(HouseRoom(channelId: 1, title: "א", state: .lit, waitingCount: 0, workingAgents: 1, artKey: .newRoom).statusLine, "בעבודה")
        XCTAssertEqual(HouseRoom(channelId: 1, title: "א", state: .dim, waitingCount: 0, workingAgents: 0, artKey: .newRoom).statusLine, "שקט")
    }

    func testAnUnnamedRoomGetsAPlainName() {
        let rooms = HouseRoomsResolver.resolve(sources: [HouseRoomSource(channelId: 1, title: "  ", topicStatuses: [])], openDecisions: [], agents: [])
        XCTAssertEqual(rooms[0].title, "חדר")
        XCTAssertEqual(rooms[0].artKey, .newRoom)
    }

    func testHomeOrderPutsWaitingFirstThenLitAndKeepsTheRest() {
        func room(_ id: Int64, _ state: HouseRoomState) -> HouseRoom {
            return HouseRoom(channelId: id, title: "ח\(id)", state: state, waitingCount: state == .waiting ? 1 : 0, workingAgents: 0, artKey: .newRoom)
        }
        let sorted = HouseRoomsResolver.sortedForHome([room(1, .dim), room(2, .lit), room(3, .waiting), room(4, .dim), room(5, .waiting)])
        XCTAssertEqual(sorted.map(\.channelId), [3, 5, 2, 1, 4])
    }

    // MARK: waiting items and the home state

    func testDecisionsBecomeYesNoOrChoiceItems() {
        XCTAssertEqual(HouseWaitingItem(decision: self.decision("00000000000000a1", channel: 1)).kind, .yesNo)
        XCTAssertEqual(HouseWaitingItem(decision: self.decision("00000000000000a2", channel: 1, kind: "choice", options: ["א", "ב"])).kind, .choice(options: ["א", "ב"]))
        // A choice with fewer than two options is only a yes/no question.
        XCTAssertEqual(HouseWaitingItem(decision: self.decision("00000000000000a3", channel: 1, kind: "choice", options: ["א"])).kind, .yesNo)
        XCTAssertEqual(HouseWaitingItem(decision: self.decision("00000000000000a4", channel: 1, kind: "future-kind")).kind, .yesNo)
    }

    func testTheDoorwayStaysWhenNothingWaits() {
        let empty = HouseHomeState.make(now: Date(timeIntervalSince1970: 1_763_200_000), openDecisions: [], rooms: [])
        XCTAssertTrue(empty.doorwayIsEmpty)
        XCTAssertNil(empty.doorwayPreview)
        XCTAssertEqual(empty.waitingCount, 0)
        let state = HouseHomeState.make(now: Date(timeIntervalSince1970: 1_763_200_000), openDecisions: (1 ... 7).map { self.decision(String(format: "%016x", $0), channel: 1) }, rooms: [])
        XCTAssertEqual(state.waitingCount, 7)
        XCTAssertEqual(state.doorwayPreview?.id, "0000000000000001")
    }

    // MARK: summary for widgets

    func testSummaryRoundTripsAndKeepsTheBusiestRooms() throws {
        let rooms = (1 ... 9).map { HouseRoom(channelId: Int64($0), title: "ח\($0)", state: $0 == 9 ? .waiting : .dim, waitingCount: $0 == 9 ? 2 : 0, workingAgents: 0, artKey: .newRoom) }
        let state = HouseHomeState(greeting: .morning, waiting: [], rooms: rooms)
        let summary = HouseRoomsSummary(state: state, now: Date(timeIntervalSince1970: 1_763_200_000))
        XCTAssertEqual(summary.rooms.count, HouseRoomsSummary.maxRooms)
        XCTAssertEqual(summary.rooms.first?.channelId, 9)
        let data = try XCTUnwrap(summary.encoded())
        XCTAssertEqual(HouseRoomsSummary.decode(data), summary)
        XCTAssertNil(HouseRoomsSummary.decode(Data("nope".utf8)))
        XCTAssertNil(HouseRoomsSummary.decode(Data("{\"updatedAt\":1,\"waitingCount\":0,\"rooms\":[{\"channelId\":1,\"title\":\"x\",\"state\":\"burning\",\"artKey\":\"room-new\"}]}".utf8)))
    }

    func testStringsAreHebrewAndEveryKeyHasText() {
        for key in HouseHomeStrings.Key.allCases {
            XCTAssertFalse(HouseHomeStrings.string(key).isEmpty, key.rawValue)
        }
        XCTAssertTrue(HouseHomeStrings.isRightToLeft)
    }

    // MARK: palette

    /// HarnessgramAgent cannot see the palette (it sits below this module), so it carries its three dot colours itself:
    /// they must stay the palette's working, waiting and olive.
    func testTopicStatusDotsFollowThePalette() {
        for dark in [false, true] {
            let palette = HouseColors.palette(darkAppearance: dark)
            XCTAssertEqual(HarnessgramTopicStatus.working.rgb(house: true, darkAppearance: dark), palette.statusWorking.rgb)
            XCTAssertEqual(HarnessgramTopicStatus.waitingForYou.rgb(house: true, darkAppearance: dark), palette.statusWaiting.rgb)
            XCTAssertEqual(HarnessgramTopicStatus.done.rgb(house: true, darkAppearance: dark), palette.olive.rgb)
        }
        // Without the House theme the dots keep Telegram's colours.
        for status in HarnessgramTopicStatus.allCases {
            XCTAssertEqual(status.rgb(house: false, darkAppearance: true), status.rgb)
        }
    }

    func testLiveSurfacesStayDarkGlassWhateverTheTheme() {
        XCTAssertEqual(HouseColors.LiveSurfaces.progress, HouseColors.dark.amber)
        XCTAssertEqual(HouseColors.LiveSurfaces.done, HouseColors.dark.olive)
        XCTAssertEqual(HouseColors.LiveSurfaces.text, HouseColors.dark.ink)
    }
}
