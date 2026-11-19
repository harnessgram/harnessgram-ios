import XCTest

/// Build 23 guard (owner: "it is unclear what each thing does", "illustrate everything"): on the Settings > Harnessgram
/// screen and the "מה Harnessgram מוסיף" page every row is drawn through the row components in HarnessgramSettingsRows,
/// which require an icon, a title and an explanation; no bare Toggle, Picker or Stepper; no empty explanation or icon;
/// every segmented control sits under its own labelled header. Scans HarnessgramSettingsUI's sources.
final class HarnessgramSettingsRowsGuardTests: XCTestCase {
    private let folder = "TelegramUI/Components/HarnessgramSettingsUI/Sources"
    private let pages = ["HarnessgramSettingsScreen.swift", "HarnessgramAdditionsScreen.swift"]
    private let rowCall = try! NSRegularExpression(pattern: "Harnessgram(Toggle|Link|Segmented|Menu|Stepper|Custom)Row\\(")

    private func sources() throws -> [String: String] {
        let files = HarnessgramSourceScan.swiftFiles(self.folder, anchor: HarnessgramSettingsRowsGuardTests.self)
        if files.isEmpty {
            throw XCTSkip("the sources are not reachable from this test run")
        }
        var result: [String: String] = [:]
        for file in files {
            result[file.name] = file.text
        }
        return result
    }

    /// Code lines only (comments dropped).
    private func codeLines(_ text: String) -> [String] {
        return text.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
    }

    func testThePagesDrawNoBareControls() throws {
        let sources = try self.sources()
        for page in self.pages {
            let text = try XCTUnwrap(sources[page], page)
            for (index, line) in self.codeLines(text).enumerated() {
                for bare in ["Toggle(", "Picker(", "Stepper(", "HarnessgramSettingsRowLabel(", "SegmentedPickerStyle", ".pickerStyle("] {
                    XCTAssertFalse(line.contains(bare), "\(page):\(index + 1) draws \(bare) outside the row components: \(line)")
                }
            }
        }
    }

    func testEveryRowHasAnIconAndAnExplanation() throws {
        let sources = try self.sources()
        var rows = 0
        for page in self.pages {
            let text = try XCTUnwrap(sources[page], page)
            for (index, line) in self.codeLines(text).enumerated() {
                let range = NSRange(line.startIndex..., in: line)
                guard self.rowCall.firstMatch(in: line, range: range) != nil else {
                    continue
                }
                rows += 1
                XCTAssertTrue(line.contains("icon: "), "\(page):\(index + 1) a row without an icon: \(line)")
                XCTAssertTrue(line.contains("detail: "), "\(page):\(index + 1) a row without an explanation: \(line)")
                XCTAssertFalse(line.contains("detail: \"\""), "\(page):\(index + 1) an empty explanation")
                XCTAssertFalse(line.contains("icon: \"\""), "\(page):\(index + 1) an empty icon")
            }
        }
        XCTAssertGreaterThanOrEqual(rows, 18, "the settings screen and the additions page draw their rows through the components")
    }

    func testEverySegmentedControlSitsUnderItsLabel() throws {
        let sources = try self.sources()
        let rows = try XCTUnwrap(sources["HarnessgramSettingsRows.swift"])
        let segmented = try XCTUnwrap(rows.components(separatedBy: "struct HarnessgramSegmentedRow").dropFirst().first)
        let body = try XCTUnwrap(segmented.components(separatedBy: "var body: some View {").dropFirst().first)
        let header = try XCTUnwrap(body.range(of: "HarnessgramRowHeader("), "the segmented row draws its label")
        let picker = try XCTUnwrap(body.range(of: "Picker("))
        XCTAssertLessThan(header.lowerBound, picker.lowerBound, "the label comes before the control")
        XCTAssertTrue(body.contains(".accessibilityLabel(Text(self.title))"), "VoiceOver reads the control's label")
        // The components require an icon and an explanation: no optional or defaulted ones.
        XCTAssertFalse(rows.contains("let icon: String?"))
        XCTAssertFalse(rows.contains("detail: String = \"\""))
    }

    func testEveryAdditionHasAnIconAndAnExplanation() throws {
        let sources = try self.sources()
        let additions = try XCTUnwrap(sources["HarnessgramAdditionsScreen.swift"])
        XCTAssertTrue(additions.contains("var icon: String {"))
        XCTAssertTrue(additions.contains("var explanation: String {"))
        XCTAssertFalse(additions.contains("return \"\"\n"), "no addition returns an empty title, explanation or icon")
        let strings = try XCTUnwrap(sources["HarnessgramSettingsStrings.swift"])
        XCTAssertFalse(strings.contains("Detail: \"\""))
        XCTAssertFalse(strings.contains("Footer: \"\""))
    }

    func testTheDuplicatedHousePreviewSectionIsGone() throws {
        let sources = try self.sources()
        XCTAssertNil(sources["HarnessgramHousePreviewSection.swift"])
        for (name, text) in sources {
            XCTAssertFalse(text.contains("תצוגה מקדימה: הבית"), name)
        }
    }
}
