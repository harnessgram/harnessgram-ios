import XCTest
@testable import HarnessgramCockpitKit

final class HarnessgramCarSummaryTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_763_200_000)
    private let unpairedText = "צריך לפתוח את האפליקציה כדי לחבר את הגשר."

    private func makeDecision(
        id: String,
        title: String,
        sensitive: Bool = false,
        askedAt: Date? = nil
    ) -> HarnessgramCockpitSnapshot.Decision {
        return HarnessgramCockpitSnapshot.Decision(
            id: id,
            title: title,
            topic: "פרויקט",
            yesLabel: "כן",
            noLabel: "לא",
            topicURL: "https://t.me/c/900000001/10",
            sensitive: sensitive,
            askedAt: askedAt
        )
    }

    private func makeSnapshot(
        waitingCount: Int,
        decisions: [HarnessgramCockpitSnapshot.Decision],
        updatedAt: Date? = nil
    ) -> HarnessgramCockpitSnapshot {
        return HarnessgramCockpitSnapshot(
            updatedAt: updatedAt ?? self.now,
            waitingCount: waitingCount,
            decisions: decisions,
            runningAgents: 0,
            agents: [],
            radio: nil,
            progress: []
        )
    }

    func testUnpairedAndNilSnapshot() {
        let snapshot = self.makeSnapshot(
            waitingCount: 1,
            decisions: [self.makeDecision(id: "d1", title: "לאשר פריסה")]
        )
        XCTAssertEqual(HarnessgramCarSummary.spokenSummary(snapshot: nil, paired: false, now: self.now), self.unpairedText)
        XCTAssertEqual(HarnessgramCarSummary.spokenSummary(snapshot: snapshot, paired: false, now: self.now), self.unpairedText)
        XCTAssertEqual(HarnessgramCarSummary.spokenSummary(snapshot: nil, paired: true, now: self.now), self.unpairedText)
    }

    func testCountsZeroOneTwoFiveEleven() {
        let zero = self.makeSnapshot(waitingCount: 0, decisions: [])
        XCTAssertEqual(HarnessgramCarSummary.spokenSummary(snapshot: zero, paired: true, now: self.now), "אין משהו שמחכה לך.")

        let one = self.makeSnapshot(waitingCount: 1, decisions: [self.makeDecision(id: "d1", title: "לאשר גרסה")])
        XCTAssertEqual(HarnessgramCarSummary.spokenSummary(snapshot: one, paired: true, now: self.now), "דבר אחד מחכה לך. לאשר גרסה.")

        let two = self.makeSnapshot(
            waitingCount: 2,
            decisions: [
                self.makeDecision(id: "d1", title: "משימה א"),
                self.makeDecision(id: "d2", title: "משימה ב"),
            ]
        )
        XCTAssertEqual(HarnessgramCarSummary.spokenSummary(snapshot: two, paired: true, now: self.now), "שני דברים מחכים לך. משימה א. משימה ב.")

        let expectedWords: [(Int, String)] = [
            (3, "שלושה"),
            (4, "ארבעה"),
            (5, "חמישה"),
            (6, "שישה"),
            (7, "שבעה"),
            (8, "שמונה"),
            (9, "תשעה"),
            (10, "עשרה"),
        ]
        for (count, word) in expectedWords {
            let snapshot = self.makeSnapshot(waitingCount: count, decisions: [])
            XCTAssertEqual(HarnessgramCarSummary.spokenSummary(snapshot: snapshot, paired: true, now: self.now), "\(word) דברים מחכים לך.")
        }

        let eleven = self.makeSnapshot(waitingCount: 11, decisions: [])
        XCTAssertEqual(HarnessgramCarSummary.spokenSummary(snapshot: eleven, paired: true, now: self.now), "11 דברים מחכים לך.")
    }

    func testSensitiveDecisionRedactsTitle() {
        let secretTitle = "להעביר מפתח סודי לשרת חיצוני"
        let snapshot = self.makeSnapshot(
            waitingCount: 2,
            decisions: [
                self.makeDecision(id: "d1", title: secretTitle, sensitive: true),
                self.makeDecision(id: "d2", title: "לעדכן צבע כפתור?", sensitive: false),
            ]
        )
        let summary = HarnessgramCarSummary.spokenSummary(snapshot: snapshot, paired: true, now: self.now)
        XCTAssertFalse(summary.contains(secretTitle))
        XCTAssertFalse(summary.contains("סודי"))
        XCTAssertEqual(summary, "שני דברים מחכים לך. החלטה רגישה שמחכה לאישור בטלפון. לעדכן צבע כפתור?")
    }

    func testNewestFirstOrderAndMaxThree() {
        let snapshot = self.makeSnapshot(
            waitingCount: 5,
            decisions: [
                self.makeDecision(id: "d1", title: "ישנה מאוד", askedAt: self.now.addingTimeInterval(-500)),
                self.makeDecision(id: "d2", title: "ראשונה", askedAt: self.now.addingTimeInterval(-10)),
                self.makeDecision(id: "d3", title: "שלישית", askedAt: self.now.addingTimeInterval(-120)),
                self.makeDecision(id: "d4", title: "ללא זמן", askedAt: nil),
                self.makeDecision(id: "d5", title: "שנייה", askedAt: self.now.addingTimeInterval(-40)),
            ]
        )
        let summary = HarnessgramCarSummary.spokenSummary(snapshot: snapshot, paired: true, now: self.now)
        XCTAssertEqual(summary, "חמישה דברים מחכים לך. ראשונה. שנייה. שלישית.")
        XCTAssertFalse(summary.contains("ישנה מאוד"))
        XCTAssertFalse(summary.contains("ללא זמן"))
    }

    func testStrippingEmojiURLsBackticksBidiMarksAndEmptyTitles() {
        let dirty = "\u{2068}🚀 עדכון\u{200F} גרסה 16 `git push --force` ב https://example.com/a?b=1 ⚠️ 1️⃣  \t\n חדש\u{2069}"
        let emptyAfterStrip = "🔥 `npm test` https://t.me/c/1/2 \u{200E}\u{2066}\u{2067}\u{2069}"
        let snapshot = self.makeSnapshot(
            waitingCount: 2,
            decisions: [
                self.makeDecision(id: "d1", title: emptyAfterStrip, askedAt: self.now.addingTimeInterval(-10)),
                self.makeDecision(id: "d2", title: dirty, askedAt: self.now.addingTimeInterval(-20)),
            ]
        )
        let summary = HarnessgramCarSummary.spokenSummary(snapshot: snapshot, paired: true, now: self.now)
        XCTAssertEqual(summary, "שני דברים מחכים לך. עדכון גרסה 16 ב חדש.")
    }

    func testStaleMinutesAndHours() {
        let fresh = self.makeSnapshot(waitingCount: 0, decisions: [], updatedAt: self.now.addingTimeInterval(-30 * 60))
        XCTAssertEqual(HarnessgramCarSummary.spokenSummary(snapshot: fresh, paired: true, now: self.now), "אין משהו שמחכה לך.")

        let staleMinutes = self.makeSnapshot(waitingCount: 0, decisions: [], updatedAt: self.now.addingTimeInterval(-45 * 60))
        XCTAssertEqual(HarnessgramCarSummary.spokenSummary(snapshot: staleMinutes, paired: true, now: self.now), "אין משהו שמחכה לך. המידע מלפני 45 דקות.")

        let staleOneHour = self.makeSnapshot(waitingCount: 0, decisions: [], updatedAt: self.now.addingTimeInterval(-60 * 60))
        XCTAssertEqual(HarnessgramCarSummary.spokenSummary(snapshot: staleOneHour, paired: true, now: self.now), "אין משהו שמחכה לך. המידע מלפני שעה.")

        let staleThreeHours = self.makeSnapshot(waitingCount: 0, decisions: [], updatedAt: self.now.addingTimeInterval(-185 * 60))
        XCTAssertEqual(HarnessgramCarSummary.spokenSummary(snapshot: staleThreeHours, paired: true, now: self.now), "אין משהו שמחכה לך. המידע מלפני 3 שעות.")
    }

    func testCappedAt300CharactersAtSentenceEnd() {
        let longTitle1 = String(repeating: "א", count: 120)
        let longTitle2 = String(repeating: "ב", count: 120)
        let longTitle3 = String(repeating: "ג", count: 120)
        let snapshot = self.makeSnapshot(
            waitingCount: 3,
            decisions: [
                self.makeDecision(id: "d1", title: longTitle1, askedAt: self.now.addingTimeInterval(-10)),
                self.makeDecision(id: "d2", title: longTitle2, askedAt: self.now.addingTimeInterval(-20)),
                self.makeDecision(id: "d3", title: longTitle3, askedAt: self.now.addingTimeInterval(-30)),
            ]
        )
        let summary = HarnessgramCarSummary.spokenSummary(snapshot: snapshot, paired: true, now: self.now)
        XCTAssertLessThanOrEqual(summary.count, 300)
        XCTAssertTrue(summary.hasSuffix("."))
        XCTAssertTrue(summary.contains(longTitle1))
        XCTAssertTrue(summary.contains(longTitle2))
        XCTAssertFalse(summary.contains(longTitle3))

        let staleSnapshot = self.makeSnapshot(
            waitingCount: 3,
            decisions: snapshot.decisions,
            updatedAt: self.now.addingTimeInterval(-40 * 60)
        )
        let staleSummary = HarnessgramCarSummary.spokenSummary(snapshot: staleSnapshot, paired: true, now: self.now)
        XCTAssertLessThanOrEqual(staleSummary.count, 300)
        XCTAssertTrue(staleSummary.hasSuffix("המידע מלפני 40 דקות."))
    }
}
