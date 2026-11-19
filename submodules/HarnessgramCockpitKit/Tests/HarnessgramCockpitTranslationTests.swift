import XCTest
import HarnessgramCockpitKit

final class HarnessgramCockpitTranslationTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_763_200_000)

    private func state(_ fields: [String: Any]) throws -> Data {
        var root = fields
        root["ok"] = true
        return try JSONSerialization.data(withJSONObject: root)
    }

    private func snapshot(_ fields: [String: Any]) throws -> HarnessgramCockpitSnapshot {
        return try HarnessgramCockpitParser.snapshot(state: self.state(fields), radioPlayer: nil, now: self.now)
    }

    func testHebrewScalarsWinAndOriginalsRoundTrip() throws {
        let decision: [String: Any] = [
            "id": "00000000000000a1", "title": "Merge?", "title_he": "למזג?",
            "topic": "Example project", "topic_he": "פרויקט לדוגמה", "detail": "Review first", "detail_he": "לבדוק קודם",
            "yes": "Approve", "yes_he": "אישור", "no": "Decline", "no_he": "סירוב"
        ]
        let fields: [String: Any] = [
            "decisions": [decision],
            "sessions": [["id": "a", "state": "working", "name": "Builder", "name_he": "בנאי", "now": "Building", "now_he": "בונה"]],
            "cards": [["id": "p", "kind": "progress", "title": "Build", "title_he": "בנייה", "topic": "Bridge", "topic_he": "גשר", "steps": ["Code"], "steps_he": ["קוד"]]]
        ]
        let snapshot = try self.snapshot(fields)
        let item = try XCTUnwrap(snapshot.decisions.first)
        XCTAssertEqual(item.title, "למזג?")
        XCTAssertEqual(item.topic, "פרויקט לדוגמה")
        XCTAssertEqual(item.detail, "לבדוק קודם")
        XCTAssertEqual(item.yesLabel, "אישור")
        XCTAssertEqual(item.noLabel, "סירוב")
        XCTAssertEqual(item.originalTitle, "Merge?")
        XCTAssertEqual(item.originalTopic, "Example project")
        XCTAssertEqual(item.originalDetail, "Review first")
        XCTAssertEqual(item.originalYesLabel, "Approve")
        XCTAssertEqual(item.originalNoLabel, "Decline")
        XCTAssertTrue(item.sensitive, "a translation never changes the fail-closed sensitivity default")
        XCTAssertEqual(try HarnessgramCockpitParser.openDecisions(state: self.state(fields)), [item])
        XCTAssertEqual(snapshot.agents.first?.name, "בנאי")
        XCTAssertEqual(snapshot.agents.first?.step, "בונה")
        XCTAssertEqual(snapshot.agents.first?.originalName, "Builder")
        XCTAssertEqual(snapshot.agents.first?.originalStep, "Building")
        XCTAssertEqual(snapshot.progress.first?.title, "בנייה")
        XCTAssertEqual(snapshot.progress.first?.topic, "גשר")
        XCTAssertEqual(snapshot.progress.first?.originalTitle, "Build")
        XCTAssertEqual(snapshot.progress.first?.originalTopic, "Bridge")
        XCTAssertEqual(snapshot.progress.first?.originalSteps, ["Code"])
        XCTAssertEqual(try JSONDecoder().decode(HarnessgramCockpitSnapshot.self, from: JSONEncoder().encode(snapshot)), snapshot)
    }

    func testInvalidHebrewScalarsFallBackToSource() throws {
        let invalid: [Any?] = [nil, NSNull(), " \n\u{202E} ", 7, true, ["text"]]
        for value in invalid {
            var item: [String: Any] = ["id": "00000000000000a1", "title": " Source\n title ", "topic": "Room", "detail": "Details", "yes": "Yes", "no": "No"]
            for key in ["title", "topic", "detail", "yes", "no"] {
                item[key + "_he"] = value
            }
            let decision = try XCTUnwrap(self.snapshot(["decisions": [item]]).decisions.first)
            XCTAssertEqual(decision.title, "Source title")
            XCTAssertEqual(decision.topic, "Room")
            XCTAssertEqual(decision.detail, "Details")
            XCTAssertEqual(decision.yesLabel, "Yes")
            XCTAssertEqual(decision.noLabel, "No")
            XCTAssertEqual(decision.originalTitle, "Source title")

            var agent: [String: Any] = ["id": "a", "state": "working", "name": "Builder", "now": "Building"]
            agent["name_he"] = value
            agent["now_he"] = value
            var card: [String: Any] = ["id": "p", "kind": "progress", "title": "Build", "topic": "Bridge", "steps": ["Code"]]
            card["title_he"] = value
            card["topic_he"] = value
            card["steps_he"] = "not an array"
            let snapshot = try self.snapshot(["sessions": [agent], "cards": [card]])
            XCTAssertEqual(snapshot.agents.first?.name, "Builder")
            XCTAssertEqual(snapshot.agents.first?.step, "Building")
            XCTAssertEqual(snapshot.progress.first?.title, "Build")
            XCTAssertEqual(snapshot.progress.first?.topic, "Bridge")
            XCTAssertEqual(snapshot.progress.first?.steps, ["Code"])
        }
    }

    func testTranslatedListsKeepRawSourceIndicesAndCaps() throws {
        let source: [Any] = ["a", NSNull(), "b", " ", "c", "d"]
        let hebrew: [Any] = ["א", "ignored", NSNull(), "ignored", 7, "ד"]
        let snapshot = try self.snapshot([
            "decisions": [["id": "00000000000000a1", "title": "Choose", "options": source, "options_he": hebrew]],
            "cards": [["id": "p", "kind": "progress", "title": "Build", "steps": source, "steps_he": hebrew, "at": 2]]
        ])
        XCTAssertEqual(snapshot.decisions.first?.options, ["א", "b", "c", "ד"])
        XCTAssertEqual(snapshot.decisions.first?.originalOptions, ["a", "b", "c", "d"])
        XCTAssertEqual(snapshot.progress.first?.steps, ["א", "b", "c", "ד"])
        XCTAssertEqual(snapshot.progress.first?.originalSteps, ["a", "b", "c", "d"])
        XCTAssertEqual(snapshot.progress.first?.done, 2)

        let many = (0 ..< 16).map { "source\($0)" }
        let capped = try self.snapshot([
            "decisions": [["id": "00000000000000a1", "title": "Choose", "options": many, "options_he": ["א", " "]]],
            "cards": [["id": "p", "kind": "progress", "title": "Build", "steps": many, "steps_he": ["א", " "], "at": 99]]
        ])
        XCTAssertEqual(capped.decisions.first?.options, ["א"] + Array(many[1 ..< 8]))
        XCTAssertEqual(capped.decisions.first?.originalOptions, Array(many.prefix(8)))
        // All done (at past the end): the last 12 steps, every one done (the window ends at the current step).
        XCTAssertEqual(capped.progress.first?.steps, Array(many[4 ..< 16]))
        XCTAssertEqual(capped.progress.first?.originalSteps, Array(many[4 ..< 16]))
        XCTAssertEqual(capped.progress.first?.done, 12)

        // At the start: the first 12, the translation still on its own raw index.
        let first = try self.snapshot([
            "cards": [["id": "p", "kind": "progress", "title": "Build", "steps": many, "steps_he": ["א", " "], "at": 0]]
        ])
        XCTAssertEqual(first.progress.first?.steps, ["א"] + Array(many[1 ..< 12]))
        XCTAssertEqual(first.progress.first?.originalSteps, Array(many.prefix(12)))
        XCTAssertEqual(first.progress.first?.done, 0)
    }

    func testTranslationsPreserveValidationOrderAndDecisionCaps() throws {
        let decisions: [[String: Any]] = (1 ... 9).map { index in
            ["id": String(format: "%016x", index), "title": "Source", "title_he": "שאלה", "sensitive": false]
        }
        let data = try self.state(["decisions": decisions + [
            ["id": "000000000000000a", "title": " ", "title_he": "תרגום"],
            ["id": "invalid", "title": "Source", "title_he": "תרגום"],
            ["id": "000000000000000b", "title": "Source", "title_he": "תרגום", "stale": "ended"]
        ], "cards": [
            ["id": "p1", "kind": "progress", "title": "Source", "title_he": "א", "updated": 1],
            ["id": "p2", "kind": "progress", "title": "Source", "title_he": "ב", "updated": 2],
            ["id": "p3", "kind": "progress", "title": " ", "title_he": "ג"]
        ]])
        let open = try HarnessgramCockpitParser.openDecisions(state: data)
        let snapshot = try HarnessgramCockpitParser.snapshot(state: data, radioPlayer: nil, now: self.now)
        XCTAssertEqual(open.map(\.id), decisions.compactMap { $0["id"] as? String })
        XCTAssertTrue(open.allSatisfy { $0.title == "שאלה" && !$0.sensitive })
        XCTAssertEqual(snapshot.waitingCount, 9)
        XCTAssertEqual(snapshot.decisions, Array(open.prefix(HarnessgramCockpitSnapshot.maxDecisions)))
        XCTAssertEqual(snapshot.progress.map(\.id), ["p2", "p1"])
    }

    func testTranslatedTextIsSanitizedAndBounded() throws {
        let snapshot = try self.snapshot(["decisions": [[
            "id": "00000000000000a1", "title": String(repeating: "s", count: 2_000),
            "title_he": String(repeating: "א", count: 200), "topic_he": "  חדר\n\u{202E} חדש ",
            "detail_he": String(repeating: "ב", count: 1_600), "yes_he": String(repeating: "ג", count: 30),
            "options": ["Source"], "options_he": [String(repeating: "ד", count: 70)]
        ]]])
        let decision = try XCTUnwrap(snapshot.decisions.first)
        XCTAssertEqual(decision.title.count, 140)
        XCTAssertEqual(decision.originalTitle?.count, 1_600)
        XCTAssertEqual(decision.topic, "חדר חדש")
        XCTAssertEqual(decision.detail?.count, 1_500)
        XCTAssertEqual(decision.yesLabel.count, 24)
        XCTAssertEqual(decision.options?.first?.count, 60)
        XCTAssertEqual(decision.noLabel, HarnessgramWidgetStrings.decline)
    }

    func testHebrewFieldsPreserveBalancedIsolatesAndNewlines() throws {
        let hebrew = "א \u{2068}X\u{2069}\nEnglish\n\nב"
        let detail = hebrew + "\n" + String(repeating: "פ", count: 1_400)
        let snapshot = try self.snapshot([
            "decisions": [[
                "id": "00000000000000a1", "title": "Source", "title_he": hebrew,
                "topic": "Room", "topic_he": hebrew, "detail": "Detail", "detail_he": detail,
                "yes": "Yes", "yes_he": hebrew, "no": "No", "no_he": hebrew,
                "options": ["Choice"], "options_he": [hebrew]
            ]],
            "sessions": [["id": "a", "state": "working", "name": "Agent", "name_he": hebrew, "now": "Step", "now_he": hebrew]],
            "cards": [["id": "p", "kind": "progress", "title": "Task", "title_he": hebrew, "topic": "Room", "topic_he": hebrew, "steps": ["Step"], "steps_he": [hebrew]]]
        ])
        // Only the detail keeps line breaks; one-line fields join lines with a space and keep the isolates.
        let line = "א \u{2068}X\u{2069} English ב"
        let decision = try XCTUnwrap(snapshot.decisions.first)
        XCTAssertEqual(decision.title, line)
        XCTAssertEqual(decision.topic, line)
        XCTAssertEqual(decision.detail, detail)
        XCTAssertEqual(decision.yesLabel, line)
        XCTAssertEqual(decision.noLabel, line)
        XCTAssertEqual(decision.options, [line])
        XCTAssertEqual(snapshot.agents.first?.name, line)
        XCTAssertEqual(snapshot.agents.first?.step, line)
        XCTAssertEqual(snapshot.progress.first?.title, line)
        XCTAssertEqual(snapshot.progress.first?.topic, line)
        XCTAssertEqual(snapshot.progress.first?.steps, [line])
        XCTAssertEqual(try JSONDecoder().decode(HarnessgramCockpitSnapshot.self, from: JSONEncoder().encode(snapshot)), snapshot)
    }

    func testHebrewNewlineRunsAreLimitedToTwo() throws {
        let snapshot = try self.snapshot(["decisions": [[
            "id": "00000000000000a1", "title": "Source",
            "detail_he": " \nראשון\r\nEnglish\n \n\t\n\nאחרון\n "
        ]]])
        XCTAssertEqual(snapshot.decisions.first?.detail, "ראשון\nEnglish\n\nאחרון")
    }

    func testHebrewDropsUnbalancedIsolatesAndKeepsBalancedPairs() throws {
        let cases: [(String, String)] = [
            ("א \u{2068}X", "א X"),
            ("א X\u{2069}", "א X"),
            ("\u{2069}א \u{2068}X\u{2069} \u{2068}Y", "א \u{2068}X\u{2069} Y"),
            ("\u{2068}א \u{2068}X\u{2069}", "א \u{2068}X\u{2069}"),
            ("א \u{2068}X \u{2068}Y\u{2069}\u{2069}", "א \u{2068}X \u{2068}Y\u{2069}\u{2069}")
        ]
        for (input, expected) in cases {
            let snapshot = try self.snapshot(["decisions": [["id": "00000000000000a1", "title": "Source", "detail_he": input]]])
            XCTAssertEqual(snapshot.decisions.first?.detail, expected)
        }
    }

    func testHebrewTruncationDoesNotLeaveAnUnbalancedIsolate() throws {
        let prefix = String(repeating: "א", count: 1_490)
        let snapshot = try self.snapshot(["decisions": [[
            "id": "00000000000000a1", "title": "Source",
            "detail_he": prefix + "\u{2068}" + String(repeating: "X", count: 30) + "\u{2069}"
        ]]])
        let detail = try XCTUnwrap(snapshot.decisions.first?.detail)
        XCTAssertEqual(detail, prefix + String(repeating: "X", count: 8) + "…")
        XCTAssertLessThanOrEqual(detail.count, 1_500)
    }

    func testShortenedSourceDecisionDoesNotOfferOriginalText() throws {
        let source = String(repeating: "English ", count: 240)
        let snapshot = try self.snapshot(["decisions": [[
            "id": "00000000000000a1", "title": source, "topic": source,
            "detail": source, "yes": source, "no": source, "options": [source]
        ]]])
        let decision = try XCTUnwrap(snapshot.decisions.first)
        XCTAssertNotEqual(decision.title, decision.originalTitle)
        XCTAssertFalse(decision.hasOriginalText)
        var translated = decision
        translated.title = "כותרת בעברית"
        XCTAssertTrue(translated.hasOriginalText)
        translated = decision
        translated.options = ["אפשרות בעברית"]
        XCTAssertTrue(translated.hasOriginalText)
    }

    func testPendingTranslationCountIsOptionalAndRoundTrips() throws {
        XCTAssertNil(try self.snapshot([:]).pending)
        for count in [0, 1, 42] {
            let snapshot = try self.snapshot(["pending": count])
            XCTAssertEqual(snapshot.pending, count)
            XCTAssertEqual(try JSONDecoder().decode(HarnessgramCockpitSnapshot.self, from: JSONEncoder().encode(snapshot)).pending, count)
        }
        let invalid: [Any] = [NSNull(), true, false, -1, 1.5, "2", [2], 1e30]
        for value in invalid {
            XCTAssertNil(try self.snapshot(["pending": value]).pending)
        }
    }

    func testOldSnapshotsDecodeWithoutOriginalsOrPending() throws {
        let old = """
        {"updatedAt":0,"waitingCount":1,"decisions":[{"id":"00000000000000a1","title":"Source","topic":"Room","yesLabel":"Yes","noLabel":"No","topicURL":"","sensitive":true}],"runningAgents":1,"agents":[{"id":"a","name":"Builder","step":"Building","topicURL":""}],"progress":[{"id":"p","title":"Build","topic":"Room","steps":["Code"],"done":0,"topicURL":"","finished":false}]}
        """
        let snapshot = try JSONDecoder().decode(HarnessgramCockpitSnapshot.self, from: Data(old.utf8))
        XCTAssertNil(snapshot.pending)
        XCTAssertNil(snapshot.decisions.first?.detail)
        XCTAssertNil(snapshot.decisions.first?.originalTitle)
        XCTAssertNil(snapshot.decisions.first?.originalOptions)
        XCTAssertNil(snapshot.agents.first?.originalName)
        XCTAssertNil(snapshot.agents.first?.originalStep)
        XCTAssertNil(snapshot.progress.first?.originalTitle)
        XCTAssertNil(snapshot.progress.first?.originalSteps)
    }
}
