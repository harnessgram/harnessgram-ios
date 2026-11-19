import XCTest
@testable import HarnessgramCockpitKit

final class HarnessgramPairFailureTests: XCTestCase {
    /// Every step has its own text, and none of them is the old catch-all.
    func testEveryReasonHasItsOwnText() {
        let texts = HarnessgramPairFailure.allCases.map { $0.text }
        XCTAssertEqual(Set(texts).count, texts.count)
        for text in texts {
            XCTAssertFalse(text.isEmpty)
            XCTAssertNotEqual(text, HarnessgramWidgetStrings.pairBridgeUnavailable)
        }
    }

    func testThePanelStatusMapsToAReason() {
        XCTAssertNil(HarnessgramPairFailure.fromPanel(status: 200))
        XCTAssertEqual(HarnessgramPairFailure.fromPanel(status: nil), .panelUnreachable)
        XCTAssertEqual(HarnessgramPairFailure.fromPanel(status: 403), .panelRefused)
        XCTAssertEqual(HarnessgramPairFailure.fromPanel(status: 502), .panelUnreachable)
        XCTAssertEqual(HarnessgramPairFailure.fromPanel(status: 404), .panelBadAnswer)
    }
}
