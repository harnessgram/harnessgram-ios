import XCTest
import HarnessgramCockpitKit

/// The overflow summary Live Activity lists what it stands for (owner report: "+3 and a radar tell me nothing"): rows
/// for the hidden tasks, what waits for the owner first, short one-line texts, at most three rows and "+K" beyond.
final class HarnessgramTaskSummaryRowTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_763_300_000)

    private func card(_ id: String, title: String? = nil, topic: String = "גשר", percent: Int? = 40, updated: Double, finished: Bool = false) -> HarnessgramCockpitSnapshot.Progress {
        return HarnessgramCockpitSnapshot.Progress(id: id, title: title ?? "משימה " + id, topic: topic, steps: ["קוד", "בדיקות"], done: 1, percent: percent, topicURL: "", finished: finished, updated: updated)
    }

    private func summary(_ plan: [HarnessgramTaskActivityPlan.Shown]) -> HarnessgramTaskState? {
        return plan.first(where: { $0.cardId == HarnessgramTaskActivityPlan.summaryCardId })?.state
    }

    func testTheRowsAreTheHiddenCardsMostRecentlyUpdatedFirst() {
        let t = self.now.timeIntervalSince1970
        let cards = [
            self.card("a", percent: 10, updated: t - 500),
            self.card("b", percent: 20, updated: t - 100),
            self.card("c", percent: nil, updated: t - 300),
            self.card("d", percent: 40, updated: t - 50),
            self.card("e", percent: 50, updated: t - 400),
        ]
        let plan = HarnessgramTaskActivityPlan.choose(cards, now: self.now)
        XCTAssertEqual(plan.map { $0.cardId }, ["d", "b", HarnessgramTaskActivityPlan.summaryCardId])
        guard let state = self.summary(plan) else {
            return XCTFail("no summary")
        }
        // The title and the count keep their old meaning.
        XCTAssertEqual(state.overflowCount, 3)
        XCTAssertEqual(state.title, "+3 משימות נוספות")
        let rows = HarnessgramTaskSummaryRow.decode(state)
        XCTAssertEqual(rows.map { $0.kind }, [.task, .task, .task])
        XCTAssertEqual(rows.map { $0.text }, ["גשר · משימה c", "גשר · משימה e", "גשר · משימה a"])
        // No percent when the card sends none.
        XCTAssertEqual(rows.map { $0.percent }, [nil, 50, 10])
        XCTAssertEqual(HarnessgramTaskSummaryRow.extraCount(state), 0)
    }

    func testWhatWaitsComesFirstAndTheBadgeCanSaySo() {
        let t = self.now.timeIntervalSince1970
        let cards = (0 ..< 6).map { self.card("c\($0)", updated: t - Double($0) * 60) }
        let waiting = HarnessgramTaskActivityPlan.Waiting(count: 2, firstTitle: "למזג את תיקון ההתחברות?", firstSensitive: true)
        guard let state = self.summary(HarnessgramTaskActivityPlan.choose(cards, waiting: waiting, now: self.now)) else {
            return XCTFail("no summary")
        }
        XCTAssertEqual(state.overflowCount, 4)
        let rows = HarnessgramTaskSummaryRow.decode(state)
        XCTAssertEqual(rows.count, HarnessgramTaskSummaryRow.maxRows)
        XCTAssertEqual(rows[0].kind, .waiting)
        XCTAssertEqual(rows[0].text, "2 החלטות מחכות לך · למזג את תיקון ההתחברות?")
        XCTAssertTrue(rows[0].sensitive)
        XCTAssertNil(rows[0].percent)
        XCTAssertEqual(rows.dropFirst().map { $0.text }, ["גשר · משימה c2", "גשר · משימה c3"])
        // Four hidden tasks, two listed: "+2".
        XCTAssertEqual(HarnessgramTaskSummaryRow.extraCount(state), 2)
        XCTAssertEqual(HarnessgramWidgetStrings.decisionsWaiting(1), "החלטה אחת מחכה לך")
    }

    func testTheWaitingInfoComesFromTheSnapshot() {
        XCTAssertNil(HarnessgramTaskActivityPlan.Waiting(snapshot: nil))
        let empty = HarnessgramCockpitSnapshot(updatedAt: self.now, waitingCount: 0, decisions: [], runningAgents: 0, agents: [], radio: nil, progress: [])
        XCTAssertNil(HarnessgramTaskActivityPlan.Waiting(snapshot: empty))
        let sample = HarnessgramTaskActivityPlan.Waiting(snapshot: .sample)
        XCTAssertEqual(sample?.count, 3)
        XCTAssertEqual(sample?.firstTitle, HarnessgramCockpitSnapshot.sample.decisions.first?.title)
        XCTAssertEqual(sample?.firstSensitive, false)
        // Nothing waits: no waiting row, tasks only.
        let t = self.now.timeIntervalSince1970
        let cards = (0 ..< 5).map { self.card("c\($0)", updated: t - Double($0) * 60) }
        let state = self.summary(HarnessgramTaskActivityPlan.choose(cards, waiting: HarnessgramTaskActivityPlan.Waiting(snapshot: empty), now: self.now))
        XCTAssertEqual(state.map { HarnessgramTaskSummaryRow.decode($0).map { $0.kind } }, [.task, .task, .task])
    }

    func testRowsStayShortOnOneLineAndKeepOneDirectionPerLine() {
        let long = String(repeating: "משימה ארוכה מאוד ", count: 6)
        let text = HarnessgramTaskSummaryRow.taskText(topic: "גשר", title: long)
        XCTAssertLessThanOrEqual(text.count, HarnessgramTaskSummaryRow.maxText)
        XCTAssertTrue(text.hasSuffix("…"))
        XCTAssertTrue(text.hasPrefix("גשר · "))
        // Line breaks never reach the lock screen.
        XCTAssertFalse(HarnessgramTaskSummaryRow.taskText(topic: "גשר", title: "שורה\nשנייה").contains("\n"))
        // A short English project name joins inside a bidi isolate; a long one leaves the row to the title.
        XCTAssertEqual(HarnessgramTaskSummaryRow.taskText(topic: "Wings", title: "בניית גרסה"), "\u{2068}Wings\u{2069} · בניית גרסה")
        XCTAssertEqual(HarnessgramTaskSummaryRow.taskText(topic: "Native lock screen widgets pack", title: "בניית גרסה"), "בניית גרסה")
        // No project: the title alone.
        XCTAssertEqual(HarnessgramTaskSummaryRow.taskText(topic: "", title: "בניית גרסה"), "בניית גרסה")
        // A long project is cut too.
        let longTopic = HarnessgramTaskSummaryRow.taskText(topic: String(repeating: "פרויקט ", count: 8), title: "בניית גרסה")
        XCTAssertLessThanOrEqual(longTopic.count, HarnessgramTaskSummaryRow.maxText)
        // A cut never leaves an isolate open.
        let isolated = HarnessgramTaskSummaryRow.truncated("\u{2068}Harnessgram widgets\u{2069} בנייה", 8)
        XCTAssertEqual(isolated.filter { $0 == "\u{2068}" }.count, isolated.filter { $0 == "\u{2069}" }.count)
        // The waiting row's title is cut as well.
        let rows = HarnessgramTaskSummaryRow.rows(hidden: [], waiting: HarnessgramTaskActivityPlan.Waiting(count: 1, firstTitle: long))
        XCTAssertEqual(rows.count, 1)
        XCTAssertTrue(rows[0].text.hasSuffix("…"))
        XCTAssertLessThanOrEqual(rows[0].text.count, HarnessgramTaskSummaryRow.maxText + 12)
    }

    func testAtMostThreeRowsAndTheContentStateStaysSmall() {
        let t = self.now.timeIntervalSince1970
        let cards = (0 ..< 12).map { self.card("c\($0)", title: String(repeating: "כותרת ארוכה ", count: 10), updated: t - Double($0) * 60) }
        let waiting = HarnessgramTaskActivityPlan.Waiting(count: 9, firstTitle: String(repeating: "שאלה ארוכה ", count: 20))
        guard let state = self.summary(HarnessgramTaskActivityPlan.choose(cards, waiting: waiting, now: self.now)) else {
            return XCTFail("no summary")
        }
        XCTAssertEqual(state.steps.count, HarnessgramTaskSummaryRow.maxRows)
        XCTAssertEqual(HarnessgramTaskSummaryRow.extraCount(state), 10 - 2)
        // ActivityKit allows 4 KB for the content state; the summary stays far below it.
        let data = try? JSONEncoder().encode(state)
        XCTAssertLessThan(data?.count ?? .max, 1_024)
    }

    func testRowsRoundTripAndOnlyTheSummaryHasThem() {
        let row = HarnessgramTaskSummaryRow(kind: .task, text: "גשר · בנייה", percent: 140)
        XCTAssertEqual(row.percent, 100)
        XCTAssertEqual(HarnessgramTaskSummaryRow(encoded: row.encoded), row)
        XCTAssertNil(HarnessgramTaskSummaryRow(encoded: "קוד"))
        // A task card's own steps are never read as rows.
        let task = HarnessgramTaskState(title: "בנייה", topic: "גשר", steps: [row.encoded], done: 0, percent: nil, finished: false)
        XCTAssertTrue(HarnessgramTaskSummaryRow.decode(task).isEmpty)
        XCTAssertEqual(HarnessgramTaskSummaryRow.extraCount(task), 0)
    }

    func testUnicodeSummaryFitsTheEncodedByteBudgetIncludingAttributes() throws {
        // Forty grapheme clusters, but over a kilobyte per row. Include JSON-escaped text and a single
        // unbounded combining cluster too: Character limits alone cannot bound any of these in bytes.
        for title in [String(repeating: "👨🏿‍👩🏾‍👧🏽‍👦🏼", count: 40), String(repeating: "\u{01}", count: 140), "a" + String(repeating: "\u{0301}", count: 4_000)] {
            let t = self.now.timeIntervalSince1970
            let cards = (0 ..< 5).map { self.card("c\($0)", title: title, topic: "", updated: t - Double($0)) }
            let state = try XCTUnwrap(self.summary(HarnessgramTaskActivityPlan.choose(cards, waiting: .init(count: 1, firstTitle: title), now: self.now)))
            let data = try JSONEncoder().encode(state)
            XCTAssertLessThanOrEqual(data.count, 3_072)
            let attributes = try JSONSerialization.data(withJSONObject: ["cardId": HarnessgramTaskActivityPlan.summaryCardId])
            XCTAssertLessThan(data.count + attributes.count, 4_096)
            XCTAssertEqual(HarnessgramTaskSummaryRow.decode(state).map { $0.kind }, [.waiting, .task, .task])
            XCTAssertEqual(try JSONDecoder().decode(HarnessgramTaskState.self, from: data), state)
        }
    }

    func testLocallyAnsweredDecisionUpdatesTheSummaryWithoutAnotherFetch() throws {
        let t = self.now.timeIntervalSince1970
        var snapshot = HarnessgramCockpitSnapshot.sample
        snapshot.progress = (0 ..< 5).map { self.card("c\($0)", updated: t - Double($0)) }
        snapshot.decisions = Array(snapshot.decisions.prefix(2))
        snapshot.waitingCount = snapshot.decisions.count
        let before = HarnessgramTaskActivityPlan.choose(snapshot.progress, waiting: .init(snapshot: snapshot), now: self.now)
        let first = try XCTUnwrap(snapshot.decisions.first)
        snapshot = snapshot.removingDecision(first.id)
        let after = HarnessgramTaskActivityPlan.choose(snapshot.progress, waiting: .init(snapshot: snapshot), now: self.now)
        let state = try XCTUnwrap(self.summary(after))
        XCTAssertEqual(HarnessgramTaskSummaryRow.decode(state).first?.text, HarnessgramTaskSummaryRow.rows(hidden: [], waiting: .init(snapshot: snapshot)).first?.text)
        XCTAssertFalse(HarnessgramTaskSummaryRow.decode(state).contains(where: { $0.text.contains(first.title) }))
        let pushes = HarnessgramTaskActivityPlan.pushes(after, lastShown: Dictionary(uniqueKeysWithValues: before.map { ($0.cardId, $0.state) }), lastTop: before.first?.cardId)
        XCTAssertTrue(pushes.contains(where: { $0.cardId == HarnessgramTaskActivityPlan.summaryCardId }))
        for decision in snapshot.decisions {
            snapshot = snapshot.removingDecision(decision.id)
        }
        let final = try XCTUnwrap(self.summary(HarnessgramTaskActivityPlan.choose(snapshot.progress, waiting: .init(snapshot: snapshot), now: self.now)))
        XCTAssertEqual(HarnessgramTaskSummaryRow.decode(final).map { $0.kind }, [.task, .task, .task])
    }

    func testAnOlderSummaryWithoutRowsStillDecodesAndCountsItsTasks() throws {
        let json = #"{"title":"+3 משימות נוספות","topic":"","steps":[],"done":0,"finished":false,"overflowCount":3}"#
        let state = try JSONDecoder().decode(HarnessgramTaskState.self, from: Data(json.utf8))
        XCTAssertEqual(state.overflowCount, 3)
        XCTAssertTrue(HarnessgramTaskSummaryRow.decode(state).isEmpty)
        XCTAssertEqual(HarnessgramTaskSummaryRow.extraCount(state), 3)
        // A new summary decodes back with its rows (the push contract keeps its fields).
        let t = self.now.timeIntervalSince1970
        let cards = (0 ..< 5).map { self.card("c\($0)", updated: t - Double($0) * 60) }
        let fresh = try XCTUnwrap(self.summary(HarnessgramTaskActivityPlan.choose(cards, now: self.now)))
        let decoded = try JSONDecoder().decode(HarnessgramTaskState.self, from: JSONEncoder().encode(fresh))
        XCTAssertEqual(decoded, fresh)
        XCTAssertEqual(HarnessgramTaskSummaryRow.decode(decoded).count, 3)
    }
}
