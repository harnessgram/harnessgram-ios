import Foundation
import XCTest
import HarnessgramCockpitKit

final class HarnessgramCockpitTodayTests: XCTestCase {
    private func parse(_ json: String, bridgeOrigin: URL? = nil) throws -> HarnessgramCockpitSnapshot {
        return try HarnessgramCockpitParser.snapshot(state: Data(json.utf8), radioPlayer: nil, now: Date(timeIntervalSince1970: 0), bridgeOrigin: bridgeOrigin)
    }

    func testFullTodayCapsRowsAndTitleAndKeepsDeepLinks() throws {
        let title = String(repeating: "א", count: 65)
        let snapshot = try self.parse("""
        {"ok":true,"today":{"done_today":4,"total_today":7,"waiting":[
            {"title":"\(title)","age_minutes":12,"url":"https://t.me/example?startapp=r1"},
            {"title":"משימה שנייה","age_minutes":180,"url":"https://t.me/example?startapp=r2"},
            {"title":"משימה שלישית","age_minutes":1,"url":"https://t.me/example?startapp=r3"},
            {"title":"משימה רביעית","age_minutes":1,"url":"https://t.me/example?startapp=r4"}
        ]}}
        """)
        let today = try XCTUnwrap(snapshot.today)
        XCTAssertEqual(today.doneToday, 4)
        XCTAssertEqual(today.totalToday, 7)
        XCTAssertEqual(today.waiting.map(\.title), [String(repeating: "א", count: 59) + "…", "משימה שנייה", "משימה שלישית"])
        XCTAssertEqual(today.waiting.map(\.ageMinutes), [12, 180, 1])
        XCTAssertEqual(today.waiting.map { $0.url.absoluteString }, (1 ... 3).map { "https://t.me/example?startapp=r\($0)" })
        XCTAssertEqual(try JSONDecoder().decode(HarnessgramCockpitSnapshot.self, from: JSONEncoder().encode(snapshot)), snapshot)
    }

    func testMissingEmptyAndMalformedToday() throws {
        for json in [
            #"{"ok":true}"#,
            #"{"ok":true,"today":null}"#,
            #"{"ok":true,"today":[]}"#,
            #"{"ok":true,"today":{"done_today":0,"total_today":0,"waiting":[]}}"#,
            #"{"ok":true,"today":{"done_today":true,"total_today":"4","waiting":"none"}}"#,
            #"{"ok":true,"today":{"done_today":1.5,"total_today":false,"waiting":[9,{}]}}"#,
        ] {
            XCTAssertEqual(try self.parse(json).today, .empty)
        }
    }

    func testNegativeCountsClampAndInvalidRowsAreDiscarded() throws {
        let snapshot = try self.parse("""
        {"ok":true,"today":{"done_today":-4,"total_today":-7,"waiting":[
            {"title":"Insecure","age_minutes":12,"url":"http://t.me/example?startapp=r1"},
            {"title":"No host","age_minutes":12,"url":"https:/r1"},
            {"title":"Relative","age_minutes":12,"url":"/r1"},
            {"title":42,"age_minutes":12,"url":"https://t.me/example?startapp=r1"},
            {"title":"Boolean","age_minutes":true,"url":"https://t.me/example?startapp=r1"},
            {"title":"Fraction","age_minutes":1.5,"url":"https://t.me/example?startapp=r1"},
            {"title":"משימה תקינה","age_minutes":-5,"url":"https://t.me/example?startapp=r2"}
        ]}}
        """)
        let today = try XCTUnwrap(snapshot.today)
        XCTAssertEqual(today.doneToday, 0)
        XCTAssertEqual(today.totalToday, 0)
        XCTAssertEqual(today.waiting.map(\.title), ["משימה תקינה"])
        XCTAssertEqual(today.waiting.map(\.ageMinutes), [0])
    }

    func testAuthenticatedPanelSummaryAndWidgetKeyPrecedence() throws {
        let panel = try self.parse(#"{"ok":true,"ownerToday":{"done_today":2,"total_today":3,"waiting":[]}}"#)
        XCTAssertEqual(panel.today, .init(doneToday: 2, totalToday: 3, waiting: []))
        let widget = try self.parse(#"{"ok":true,"ownerToday":{"done_today":2,"total_today":3},"today":{"done_today":1,"total_today":4}}"#)
        XCTAssertEqual(widget.today, .init(doneToday: 1, totalToday: 4, waiting: []))
        let nullWidget = try self.parse(#"{"ok":true,"today":null,"ownerToday":{"done_today":2,"total_today":3}}"#)
        XCTAssertEqual(nullWidget.today, panel.today)
    }

    func testTodayCountsClampToFourDigitsAndDoneDoesNotExceedTotal() throws {
        let oversized = try XCTUnwrap(self.parse(#"{"ok":true,"today":{"done_today":50000,"total_today":20000}}"#).today)
        XCTAssertEqual(oversized.doneToday, 9_999)
        XCTAssertEqual(oversized.totalToday, 9_999)
        let inconsistent = try XCTUnwrap(self.parse(#"{"ok":true,"today":{"done_today":5,"total_today":3}}"#).today)
        XCTAssertEqual(inconsistent.doneToday, 3)
        XCTAssertEqual(inconsistent.totalToday, 3)

        let cached = Data(#"{"doneToday":50000,"totalToday":20000,"waiting":[]}"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(HarnessgramCockpitSnapshot.Today.self, from: cached), oversized)
    }

    func testTodayLinksRequireTelegramOrTheExactBridgeHost() throws {
        let bridge = try XCTUnwrap(URL(string: "https://bridge.private.example.test:8443"))
        let bridgeLink = "https://bridge.private.example.test/?startapp=r1"
        let telegramLink = "https://t.me/example?startapp=r2"
        for rejected in [
            "https://t.me@evil.com/",
            "https://another.private.example.test/",
            "https://bridge.private.example.test.evil.com/",
            "https://user:password@t.me/",
            "https://bridge.private.example.test:443/",
            "https://t.me:99999999999999999999999/",
        ] {
            XCTAssertNil(HarnessgramCockpitLinks.todayURL(rejected, bridgeOrigin: bridge), rejected)
        }

        let snapshot = try self.parse("""
        {"ok":true,"today":{"waiting":[
            {"title":"Wrong host","age_minutes":12,"url":"https://another.private.example.test/"},
            {"title":"Wrong authority","age_minutes":12,"url":"https://t.me@evil.com/"},
            {"title":"Bridge","age_minutes":12,"url":"\(bridgeLink)"},
            {"title":"Telegram","age_minutes":12,"url":"\(telegramLink)"}
        ]}}
        """, bridgeOrigin: bridge)
        XCTAssertEqual(snapshot.today?.waiting.map { $0.url.absoluteString }, [bridgeLink, telegramLink])
    }

    func testStoredSnapshotWithoutTodayStillDecodes() throws {
        let oldJSON = #"{"updatedAt":0,"waitingCount":0,"decisions":[],"runningAgents":0,"agents":[],"progress":[]}"#
        let snapshot = try JSONDecoder().decode(HarnessgramCockpitSnapshot.self, from: Data(oldJSON.utf8))
        XCTAssertNil(snapshot.today)
    }

    func testTodayFallbackLinkOpensTheCockpit() {
        XCTAssertEqual(HarnessgramCockpitLinks.parseWidgetLink(HarnessgramCockpitLinks.cockpitURL.absoluteString), .cockpit)
        XCTAssertNil(HarnessgramCockpitLinks.parseWidgetLink("harnessgram://widget/cockpit?extra=1"))
    }
}
