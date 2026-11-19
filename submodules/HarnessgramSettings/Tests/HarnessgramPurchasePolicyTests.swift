import HarnessgramSettings
import XCTest

final class HarnessgramPurchasePolicyTests: XCTestCase {
    func testPurchasesStayHiddenEvenWhenTheServerEnablesThem() {
        XCTAssertFalse(HarnessgramSettings.allowsTelegramPurchases())
        XCTAssertFalse(HarnessgramSettings.allowsTelegramPurchases(serverAllowsPurchases: true))
        XCTAssertFalse(HarnessgramSettings.allowsTelegramPurchases(serverAllowsPurchases: false))
    }
}
