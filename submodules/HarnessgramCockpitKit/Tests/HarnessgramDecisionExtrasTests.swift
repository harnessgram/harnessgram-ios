import Foundation
import XCTest
@testable import HarnessgramCockpitKit
import HarnessgramSettings

/// Rich decisions: every field optional and tolerant until the bridge's final schema lands.
final class HarnessgramDecisionExtrasTests: XCTestCase {
    private let image1 = String(repeating: "a", count: 32)
    private let image2 = String(repeating: "0", count: 31) + "f"

    func testAnOlderBridgeGivesNoExtras() {
        let extras = HarnessgramDecisionExtras.parse(["id": "x", "title": "Ship?"])
        XCTAssertEqual(extras, .none)
        XCTAssertTrue(extras.isEmpty)
        XCTAssertFalse(extras.commentAllowed)
    }

    func testImagesAreValidatedDeduplicatedAndCapped() {
        let many = (0 ..< 10).map { String(format: "%032x", $0) }
        let extras = HarnessgramDecisionExtras.parse(["images": [self.image1, "not-an-id", self.image1, 42, self.image2.uppercased()] + many])
        XCTAssertEqual(extras.imageIds.first, self.image1)
        XCTAssertFalse(extras.imageIds.contains("not-an-id"))
        XCTAssertFalse(extras.imageIds.contains(self.image2.uppercased()), "ids are lowercase hex only")
        XCTAssertEqual(extras.imageIds.count, HarnessgramDecisionExtras.maxImages)
        XCTAssertEqual(Set(extras.imageIds).count, extras.imageIds.count)
        XCTAssertEqual(HarnessgramDecisionExtras.parse(["media": [self.image2]]).imageIds, [self.image2])
    }

    func testOnlyHTTPSLinksWithTitles() {
        let extras = HarnessgramDecisionExtras.parse([
            "link": "https://example.test/a",
            "links": [
                ["title": "Design", "url": "https://example.test/design"],
                ["label": "Plan", "href": "https://example.test/plan"],
                "http://example.test/insecure",
                "javascript:alert(1)",
                "https://user:pass@example.test/secret",
                ["title": "No url"],
                "https://example.test/a",
            ],
        ])
        XCTAssertEqual(extras.links.map(\.url.absoluteString), ["https://example.test/a", "https://example.test/design", "https://example.test/plan"])
        XCTAssertEqual(extras.links.map(\.title), ["example.test", "Design", "Plan"])
    }

    func testLongContextPrefersHebrewAndKeepsParagraphs() {
        let extras = HarnessgramDecisionExtras.parse(["context": "English body", "context_he": "שורה ראשונה\n\nשורה שנייה"])
        XCTAssertEqual(extras.context, "שורה ראשונה\n\nשורה שנייה")
        XCTAssertEqual(HarnessgramDecisionExtras.parse(["body": "Plain body"]).context, "Plain body")
        let long = String(repeating: "א", count: 9_000)
        XCTAssertLessThanOrEqual(HarnessgramDecisionExtras.parse(["context": long]).context?.count ?? 0, HarnessgramDecisionExtras.contextLimit + 1)
        XCTAssertNil(HarnessgramDecisionExtras.parse(["context": "   "]).context)
    }

    func testCommentNeedsAnExplicitTrue() {
        XCTAssertTrue(HarnessgramDecisionExtras.parse(["comment": true]).commentAllowed)
        XCTAssertTrue(HarnessgramDecisionExtras.parse(["allow_comment": true]).commentAllowed)
        XCTAssertTrue(HarnessgramDecisionExtras.parse(["answers": ["yes", "no", "comment"]]).commentAllowed)
        XCTAssertFalse(HarnessgramDecisionExtras.parse(["comment": 1]).commentAllowed)
        XCTAssertFalse(HarnessgramDecisionExtras.parse(["comment": "true"]).commentAllowed)
        XCTAssertFalse(HarnessgramDecisionExtras.parse(["comment": false]).commentAllowed)
    }

    func testTheScreenCarriesTheExtras() throws {
        let state: [String: Any] = ["ok": true, "now": 1_763_200_000, "decisions": [[
            "id": "eeeeeeeeeeeeeee1", "title": "Pick a design", "yes": "Ship", "no": "Hold", "age": 60, "url": "",
            "images": [self.image1], "links": [["title": "Mock", "url": "https://example.test/mock"]], "context": "Why it matters", "comment": true,
        ]], "sessions": [], "cards": []]
        let screen = try HarnessgramCockpitScreen.parse(state: try JSONSerialization.data(withJSONObject: state), radio: nil, now: Date(timeIntervalSince1970: 1_763_200_000))
        let extras = try XCTUnwrap(screen.decision(id: "eeeeeeeeeeeeeee1")).extras
        XCTAssertEqual(extras.imageIds, [self.image1])
        XCTAssertEqual(extras.links.first?.title, "Mock")
        XCTAssertEqual(extras.context, "Why it matters")
        XCTAssertTrue(extras.commentAllowed)
    }

    /// The bridge's final shape (feat/rich-decisions): "rich_decision": true, links with "label", "replies".
    func testTheBridgeRichDecisionShape() {
        let extras = HarnessgramDecisionExtras.parse([
            "rich_decision": true,
            "links": [["label": "PR", "url": "https://github.com/example/repo/pull/1"]],
            "replies": [["at": 1, "text": "First thought"], ["at": 2, "text": "  "], ["text": "Second"]],
        ])
        XCTAssertTrue(extras.commentAllowed)
        XCTAssertEqual(extras.links.first?.title, "PR")
        XCTAssertEqual(extras.replies, ["First thought", "Second"])
    }

    func testCommentBodyAndResults() throws {
        let id = "ffffffffffffff01"
        let body = try XCTUnwrap(HarnessgramDecisionComment.body(id: id, text: "  please wait for the design  "))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: String])
        XCTAssertEqual(object, ["id": id, "choice": "reply", "note": "please wait for the design"])
        XCTAssertNil(HarnessgramDecisionComment.body(id: id, text: "   "), "a comment needs words")
        XCTAssertNil(HarnessgramDecisionComment.body(id: id, text: String(repeating: "א", count: 1_001)))
        XCTAssertNil(HarnessgramDecisionComment.body(id: "../x", text: "hi"))
        let ok = HarnessgramCockpitHTTPResponse(status: 200, body: Data(#"{"ok":true,"reply":true,"key":"k","delivery":"queued"}"#.utf8))
        XCTAssertEqual(HarnessgramDecisionComment.result(ok), .sent)
        XCTAssertEqual(HarnessgramDecisionComment.result(HarnessgramCockpitHTTPResponse(status: 200, body: Data(#"{"ok":true}"#.utf8))), .failed, "a yes/no answer is never read as a comment")
        XCTAssertEqual(HarnessgramDecisionComment.result(HarnessgramCockpitHTTPResponse(status: 409, body: Data())), .closed)
        XCTAssertEqual(HarnessgramDecisionComment.result(HarnessgramCockpitHTTPResponse(status: 400, body: Data())), .refused)
        XCTAssertEqual(HarnessgramDecisionComment.result(HarnessgramCockpitHTTPResponse(status: 403, body: Data())), .loginExpired)
        XCTAssertEqual(HarnessgramDecisionComment.result(HarnessgramCockpitHTTPResponse(status: 429, body: Data())), .busy)
        XCTAssertEqual(HarnessgramDecisionComment.result(HarnessgramCockpitHTTPResponse(status: 500, body: Data())), .failed)
    }

    /// A rich decision takes the bridge's longer note; an older one keeps 300.
    func testRichDecisionsTakeTheLongerNote() throws {
        let long = String(repeating: "א", count: 800)
        XCTAssertNil(HarnessgramDecisionAnswer.body(id: "ffffffffffffff02", choice: .yes, note: long))
        XCTAssertNotNil(HarnessgramDecisionAnswer.body(id: "ffffffffffffff02", choice: .yes, note: long, limit: HarnessgramDecisionAnswer.richNoteLimit))
        XCTAssertEqual(HarnessgramDecisionAnswer.richNoteLimit, HarnessgramDecisionComment.limit)
    }

    // MARK: Card media

    private let origin = "https://mac.private.example.test:10000"

    private func credential() -> HarnessgramCockpitCredential {
        return HarnessgramCockpitCredential(initData: "query_id=1&user=%7B%7D&auth_date=1&hash=abc", origin: self.origin, authDate: Date().addingTimeInterval(-10), configuration: HarnessgramLocalConfig(bridgeHostSuffixes: [".private.example.test"]))
    }

    private let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 13, 1, 2, 3])

    func testCardImageAsksForATokenThenGetsTheImageOnTheSameOrigin() async throws {
        let transport = ScriptedTransport(responses: [
            HarnessgramCockpitHTTPResponse(status: 200, body: Data(#"{"token":"abc.def","expires":1}"#.utf8)),
            HarnessgramCockpitHTTPResponse(status: 200, body: self.png),
        ])
        let data = await HarnessgramCockpitClient(transport: transport).cardImage(id: self.image1, credential: self.credential(), now: Date())
        XCTAssertEqual(data, self.png)
        let requests = transport.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[0].httpMethod, "POST")
        XCTAssertEqual(requests[0].url?.path, "/api/card-media-token")
        XCTAssertNotNil(requests[0].value(forHTTPHeaderField: HarnessgramCockpitClient.initHeader))
        XCTAssertEqual(requests[1].httpMethod, "GET")
        XCTAssertEqual(requests[1].url?.host, "mac.private.example.test")
        XCTAssertEqual(requests[1].url?.path, "/card-media/" + self.image1)
        XCTAssertEqual(requests[1].url?.query, "auth=abc.def")
        XCTAssertNil(requests[1].value(forHTTPHeaderField: HarnessgramCockpitClient.initHeader), "the login is never sent with the image")
    }

    func testCardImageFailsClosed() async {
        let client = { (responses: [HarnessgramCockpitHTTPResponse]) in HarnessgramCockpitClient(transport: ScriptedTransport(responses: responses)) }
        let refused = await client([HarnessgramCockpitHTTPResponse(status: 403, body: Data())]).cardImage(id: self.image1, credential: self.credential(), now: Date())
        XCTAssertNil(refused)
        let notImage = await client([
            HarnessgramCockpitHTTPResponse(status: 200, body: Data(#"{"token":"t"}"#.utf8)),
            HarnessgramCockpitHTTPResponse(status: 200, body: Data("<html>not an image</html>".utf8)),
        ]).cardImage(id: self.image1, credential: self.credential(), now: Date())
        XCTAssertNil(notImage)
        let badId = await client([]).cardImage(id: "../state", credential: self.credential(), now: Date())
        XCTAssertNil(badId)
        XCTAssertNil(HarnessgramCardMedia.imageRequest(origin: URL(string: "http://mac.private.example.test")!, id: self.image1, token: "t"))
        XCTAssertNil(HarnessgramCardMedia.imageRequest(origin: URL(string: self.origin)!, id: self.image1, token: "a b"))
    }
}

private final class ScriptedTransport: HarnessgramCockpitTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var responses: [HarnessgramCockpitHTTPResponse]
    private var recorded: [URLRequest] = []

    init(responses: [HarnessgramCockpitHTTPResponse]) {
        self.responses = responses
    }

    var requests: [URLRequest] {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.recorded
    }

    func perform(_ request: URLRequest) async throws -> HarnessgramCockpitHTTPResponse {
        self.lock.lock()
        defer { self.lock.unlock() }
        self.recorded.append(request)
        guard !self.responses.isEmpty else {
            throw URLError(.notConnectedToInternet)
        }
        return self.responses.removeFirst()
    }
}
