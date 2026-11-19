import Foundation
import XCTest
@testable import HarnessgramWatchLink

final class HarnessgramWatchLinkTests: XCTestCase {
    func testTDLibChatIds() {
        XCTAssertEqual(HarnessgramWatchChatId.tdlib(kind: .user, id: 777), 777)
        XCTAssertEqual(HarnessgramWatchChatId.tdlib(kind: .basicGroup, id: 4321), -4321)
        XCTAssertEqual(HarnessgramWatchChatId.tdlib(kind: .channel, id: 1_234_567_890), -1_001_234_567_890)
        XCTAssertNil(HarnessgramWatchChatId.tdlib(kind: .secretChat, id: 5))
        XCTAssertNil(HarnessgramWatchChatId.tdlib(kind: .user, id: 0))
        XCTAssertNil(HarnessgramWatchChatId.tdlib(kind: .user, id: -3))
    }

    /// The watch decodes exactly these keys (HarnessgramWatchAllowlist in Telegram/WatchApp/Packages/HarnessgramWatchPolicy).
    func testWireFormatMatchesTheWatch() throws {
        let issued = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let payload = HarnessgramWatchAllowlistPayload(accountUserId: 42, allowedChatIds: [1, -2, -1_000_000_000_003], textOnlyChatIds: [-2, 99], issuedAt: issued)
        XCTAssertEqual(payload.textOnlyChatIds, [-2], "a text-only entry never adds a chat")
        let context = try payload.applicationContext()
        let data = try XCTUnwrap(context["harnessgram.allowlist.v1"] as? Data)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["version", "accountUserId", "allowedChatIds", "textOnlyChatIds", "issuedAt"])
        XCTAssertEqual(object["version"] as? Int, 1)
        XCTAssertEqual(object["issuedAt"] as? Double, 800_000_000, "JSONEncoder's default date encoding (reference date seconds)")
        XCTAssertEqual(try JSONDecoder().decode(HarnessgramWatchAllowlistPayload.self, from: data), payload)
    }

    func testDenyAllAndCaps() {
        let now = Date()
        let deny = HarnessgramWatchAllowlistPayload.denyAll(issuedAt: now)
        XCTAssertEqual(deny.accountUserId, 0)
        XCTAssertTrue(deny.allowedChatIds.isEmpty)
        let many = HarnessgramWatchAllowlistPayload(accountUserId: 1, allowedChatIds: Array(1 ... 500), textOnlyChatIds: [], issuedAt: now)
        XCTAssertEqual(many.allowedChatIds.count, HarnessgramWatchAllowlistPayload.maxChats)
        let later = HarnessgramWatchAllowlistPayload(accountUserId: 1, allowedChatIds: Array(1 ... 500), textOnlyChatIds: [], issuedAt: now.addingTimeInterval(60))
        XCTAssertTrue(many.sameChats(as: later))
        XCTAssertFalse(many.sameChats(as: deny))
    }
}
