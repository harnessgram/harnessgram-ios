import XCTest
@testable import HarnessgramSettings

final class HarnessgramWhatsNewTests: XCTestCase {
    func testEveryBuildHasOneToFiveLines() {
        for (build, lines) in HarnessgramWhatsNew.lines {
            XCTAssertTrue((1...5).contains(lines.count), build)
            XCTAssertNotNil(Int(build), build)
        }
    }

    func testShownOncePerBuild() {
        XCTAssertNotNil(HarnessgramWhatsNew.pending(build: "19", seen: nil))
        XCTAssertNotNil(HarnessgramWhatsNew.pending(build: "19", seen: "18"))
        XCTAssertNil(HarnessgramWhatsNew.pending(build: "19", seen: "19"))
        XCTAssertNil(HarnessgramWhatsNew.pending(build: "999", seen: nil))
        XCTAssertNil(HarnessgramWhatsNew.pending(build: nil, seen: nil))
    }

    func testTakePendingMarksTheBuildSeen() {
        let suite = "HarnessgramWhatsNewTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("18", forKey: HarnessgramWhatsNew.seenKey)
        XCTAssertNil(HarnessgramWhatsNew.pending(build: "19", seen: "19"))
        XCTAssertEqual(HarnessgramWhatsNew.pending(build: "19", seen: defaults.string(forKey: HarnessgramWhatsNew.seenKey))?.count, 4)
    }

    /// Build 22: the app font, the themes and the readable task cards (lock screen and CarPlay).
    func testBuild22SaysWhatChanged() {
        let lines = HarnessgramWhatsNew.lines["22"] ?? []
        XCTAssertTrue(lines.contains { $0.contains("גופן האפליקציה") })
        XCTAssertTrue(lines.contains { $0.contains("ערכת נושא") })
        XCTAssertTrue(lines.contains { $0.contains("כרטיסי המשימות") })
    }

    /// Build 23: the Cockpit tab, the radio's new name, one font, explained settings and readable themes.
    func testBuild23SaysWhatChanged() {
        let lines = HarnessgramWhatsNew.lines["23"] ?? []
        XCTAssertTrue(lines.contains { $0.contains("לשונית קוקפיט") })
        XCTAssertTrue(lines.contains { $0.contains("שידורי הקוקפיט") })
        XCTAssertTrue(lines.contains { $0.contains("גופן אחד") })
        XCTAssertEqual(HarnessgramWhatsNew.title, "עדכוני נתיב")
    }

    /// Build 34 (owner: "looks like a small update"): the visible changes, said on first launch.
    func testBuild34SaysWhatChanged() {
        let lines = HarnessgramWhatsNew.lines["34"] ?? []
        XCTAssertEqual(lines.count, 5)
        XCTAssertTrue(lines.contains { $0.contains("לשונית הקוקפיט") })
        XCTAssertTrue(lines.contains { $0.contains("תמונות וקישורים") && $0.contains("לא מאשרת") })
        XCTAssertTrue(lines.contains { $0.contains("Siri") })
        XCTAssertFalse(HarnessgramSettings.houseDefaultsOn.contains(.nativeDecisions), "answering stays off by default")
    }

    func testNoLineMixesHebrewWithALongEnglishRun() {
        for lines in HarnessgramWhatsNew.lines.values {
            for line in lines {
                // English stays inside a bidi isolate, at most one short name per line.
                let latin = line.unicodeScalars.filter { ("a"..."z").contains($0) || ("A"..."Z").contains($0) }.count
                if latin > 0 {
                    XCTAssertTrue(line.contains("\u{2068}") && line.contains("\u{2069}"), line)
                }
            }
        }
    }
}
