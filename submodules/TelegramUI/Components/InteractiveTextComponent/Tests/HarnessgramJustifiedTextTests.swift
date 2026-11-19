import XCTest
import UIKit
import Display
import InteractiveTextComponent
import TextFormat

/// Harnessgram "Justified text": messages of 4 or more lines are justified, each paragraph's last line
/// keeps its natural alignment, Hebrew stays right to left, and short messages are untouched.
final class HarnessgramJustifiedTextTests: XCTestCase {
    private let font = UIFont.systemFont(ofSize: 17.0)
    private let width: CGFloat = 240.0

    private func layout(_ text: String, justify: Bool, lineSpacing: CGFloat = 0.12) -> InteractiveTextNodeLayout {
        return InteractiveTextNode.asyncLayout(nil)(InteractiveTextNodeLayoutArguments(
            attributedString: NSAttributedString(string: text, attributes: [.font: self.font]),
            maximumNumberOfLines: 0,
            truncationType: .end,
            constrainedSize: CGSize(width: self.width, height: 10000.0),
            lineSpacing: lineSpacing,
            justifyLongText: justify
        )).0
    }

    private let hebrew = "זהו משפט ארוך בעברית שנועד לבדוק יישור לשני הצדדים בהודעות ארוכות, כך שכל שורה מלאה תתפרס על כל רוחב הבועה והשורה האחרונה תישאר במקומה הטבעי בלי רווחים גדולים בין המילים."
    private let english = "This is a long English sentence that checks justified text in long messages, so that every full line spans the whole bubble width while the last line keeps its natural alignment."

    func testLongMessagesAreJustifiedExceptTheLastLine() {
        for text in [self.hebrew, self.english] {
            let plain = self.layout(text, justify: false).linesRects()
            let justified = self.layout(text, justify: true).linesRects()
            XCTAssertGreaterThanOrEqual(justified.count, 4, text)
            XCTAssertEqual(plain.count, justified.count)
            for rect in justified.dropLast() {
                XCTAssertEqual(rect.width, self.width, accuracy: 1.0, text)
            }
            XCTAssertLessThan(justified.last!.width, self.width - 10.0)
            XCTAssertEqual(justified.last!.width, plain.last!.width, accuracy: 0.5)
            XCTAssertTrue(plain.dropLast().contains(where: { $0.width < self.width - 1.0 }), "the plain layout is ragged")
        }
    }

    func testHebrewStaysRightToLeft() {
        // Justification keeps each line's direction: the Hebrew layout is still right to left and the
        // English one is not.
        XCTAssertTrue(self.layout(self.hebrew, justify: true).segments.contains(where: { $0.hasRTL }))
        XCTAssertEqual(self.layout(self.hebrew, justify: true).segments.map(\.hasRTL), self.layout(self.hebrew, justify: false).segments.map(\.hasRTL))
        XCTAssertFalse(self.layout(self.english, justify: true).segments.contains(where: { $0.hasRTL }))
    }

    func testShortMessagesAndParagraphEndsAreLeftAsTheyAre() {
        let short = "שורה ראשונה ארוכה מספיק כדי לגלוש לשורה נוספת אחת בלבד."
        XCTAssertEqual(self.layout(short, justify: true).linesRects().map(\.width), self.layout(short, justify: false).linesRects().map(\.width))
        let list = "אחד\nשניים\nשלושה\nארבעה\nחמישה"
        XCTAssertEqual(self.layout(list, justify: true).linesRects().map(\.width), self.layout(list, justify: false).linesRects().map(\.width))
    }

    func testComfortableLineSpacingAddsHeight() {
        XCTAssertGreaterThan(self.layout(self.english, justify: false, lineSpacing: 0.3).size.height, self.layout(self.english, justify: false).size.height)
    }

    func testJustifiedRangeDropsTrailingSpacesAndSkipsParagraphEnds() {
        let string = "abc def \nxyz" as NSString
        XCTAssertEqual(interactiveTextJustifiedLineRange(string: string, line: NSRange(location: 0, length: 4), isLastLineOfSegment: false), NSRange(location: 0, length: 3))
        XCTAssertNil(interactiveTextJustifiedLineRange(string: string, line: NSRange(location: 4, length: 5), isLastLineOfSegment: false))
        XCTAssertNil(interactiveTextJustifiedLineRange(string: string, line: NSRange(location: 9, length: 3), isLastLineOfSegment: true))
        XCTAssertNil(interactiveTextJustifiedLineRange(string: string, line: nil, isLastLineOfSegment: false))
    }

    // MARK: Build 14: prose only (owner screenshot 15.11 21:17, a long Bash command spread letter by letter)

    private func layout(_ string: NSAttributedString, justify: Bool) -> InteractiveTextNodeLayout {
        return InteractiveTextNode.asyncLayout(nil)(InteractiveTextNodeLayoutArguments(
            attributedString: string,
            maximumNumberOfLines: 0,
            truncationType: .end,
            constrainedSize: CGSize(width: self.width, height: 10000.0),
            lineSpacing: 0.12,
            justifyLongText: justify
        )).0
    }

    func testALongCommandOrPathIsNeverSpreadOut() {
        let command = "Bash: Retry /Users/example/Projects/app/submodules/TelegramUI/Components/InteractiveTextComponent/Sources/InteractiveTextComponent.swift --flag=value --another-flag=/private/tmp/some/very/long/path/name.log"
        let plain = self.layout(command, justify: false).linesRects().map(\.width)
        let justified = self.layout(command, justify: true).linesRects().map(\.width)
        XCTAssertGreaterThanOrEqual(justified.count, 4)
        XCTAssertEqual(justified, plain, "a path or command keeps its natural alignment")
    }

    func testCodeAndMonospacedTextIsNeverJustified() {
        let monospace = UIFont.monospacedSystemFont(ofSize: 17.0, weight: .regular)
        let code = NSMutableAttributedString(string: self.english, attributes: [.font: monospace])
        XCTAssertEqual(self.layout(code, justify: true).linesRects().map(\.width), self.layout(code, justify: false).linesRects().map(\.width), "monospaced")
        let entity = NSMutableAttributedString(string: self.english, attributes: [.font: self.font])
        entity.addAttribute(NSAttributedString.Key(rawValue: TelegramTextAttributes.Code), value: self.english, range: NSRange(location: 0, length: (self.english as NSString).length))
        XCTAssertEqual(self.layout(entity, justify: true).linesRects().map(\.width), self.layout(entity, justify: false).linesRects().map(\.width), "a code entity")
    }

    func testProseIsStillJustifiedAndTheRuleIsPerLine() {
        let prose = NSAttributedString(string: self.english, attributes: [.font: self.font])
        XCTAssertTrue(interactiveTextLineIsProse(prose, range: NSRange(location: 0, length: 40)))
        XCTAssertFalse(interactiveTextLineIsProse(NSAttributedString(string: "one two", attributes: [.font: self.font]), range: NSRange(location: 0, length: 7)), "too few word gaps")
        let path = "see /Volumes/Data/Projects/a/b/c/d/e/f now"
        XCTAssertFalse(interactiveTextLineIsProse(NSAttributedString(string: path, attributes: [.font: self.font]), range: NSRange(location: 0, length: (path as NSString).length)), "one token takes most of the line")
        let justified = self.layout(prose, justify: true).linesRects()
        for rect in justified.dropLast() {
            XCTAssertEqual(rect.width, self.width, accuracy: 1.0)
        }
    }
}

