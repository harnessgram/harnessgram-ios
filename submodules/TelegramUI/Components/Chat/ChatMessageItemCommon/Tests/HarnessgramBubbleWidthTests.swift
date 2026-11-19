import XCTest
@testable import ChatMessageItemCommon

/// Harnessgram "Bubble width: wide": long agent replies wrap less.
final class HarnessgramBubbleWidthTests: XCTestCase {
    func testWideBubblesUseMoreOfTheScreen() {
        let fill = ChatMessageItemLayoutConstants.compact.bubble.maximumWidthFill
        // Phones (compact): normal keeps Telegram's 36 pt gap, wide a third of it.
        XCTAssertEqual(fill.widthFor(390.0, wide: false), 354.0)
        XCTAssertEqual(fill.widthFor(390.0, wide: true), 378.0)
        // Wide screens: 85% normally, 95% wide.
        XCTAssertEqual(fill.widthFor(1000.0, wide: false), 850.0)
        XCTAssertEqual(fill.widthFor(1000.0, wide: true), 950.0)
        let regular = ChatMessageItemLayoutConstants.regular.bubble.maximumWidthFill
        XCTAssertEqual(regular.widthFor(1000.0, wide: false), 650.0)
        XCTAssertEqual(regular.widthFor(1000.0, wide: true), 950.0)
    }

    /// Stickers, media and bubbleless columns call the plain `widthFor`: it never widens, whatever is set.
    func testPlainWidthIsTelegramsOwn() {
        for constants in [ChatMessageItemLayoutConstants.compact, ChatMessageItemLayoutConstants.regular] {
            let fill = constants.bubble.maximumWidthFill
            for width in [320.0, 390.0, 430.0, 768.0, 1000.0] as [CGFloat] {
                XCTAssertEqual(fill.widthFor(width), fill.widthFor(width, wide: false), "\(width)")
            }
        }
    }
}
