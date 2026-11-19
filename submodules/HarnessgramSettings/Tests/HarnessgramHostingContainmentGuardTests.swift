import XCTest

/// Build 23 guard (the Cockpit tab crashed on open): Telegram's tab bar loads a tab's display node before UIKit gives the
/// controller its view. A SwiftUI host added as a UIKit child inside `loadDisplayNode()` then sits under the tab bar
/// controller's view while its parent is the Harnessgram screen, and UIKit throws UIViewControllerHierarchyInconsistency
/// as it reaches the window. Every Harnessgram screen that hosts SwiftUI adds the child in `viewDidLoad()` instead.
final class HarnessgramHostingContainmentGuardTests: XCTestCase {
    private let screens = [
        ("TelegramUI/Components/HarnessgramSettingsUI/Sources", "HarnessgramHostingScreen.swift"),
        ("TelegramUI/Components/HarnessgramHouseUI/Sources", "HouseHostingController.swift"),
    ]

    private func body(of function: String, in text: String) -> String? {
        guard let start = text.range(of: function) else {
            return nil
        }
        var depth = 0
        var began = false
        var result = ""
        for character in text[start.upperBound...] {
            if character == "{" {
                depth += 1
                began = true
            } else if character == "}" {
                depth -= 1
            }
            if began {
                result.append(character)
                if depth == 0 {
                    return result
                }
            }
        }
        return nil
    }

    func testSwiftUIHostsBecomeChildrenOnlyInViewDidLoad() throws {
        var checked = 0
        for (folder, name) in self.screens {
            guard let file = HarnessgramSourceScan.swiftFiles(folder, anchor: HarnessgramHostingContainmentGuardTests.self).first(where: { $0.name == name }) else {
                continue
            }
            checked += 1
            let load = try XCTUnwrap(self.body(of: "func loadDisplayNode()", in: file.text), name)
            XCTAssertFalse(load.contains("addChild("), "\(name): loadDisplayNode adds a UIKit child")
            XCTAssertFalse(load.contains("didMove(toParent"), "\(name): loadDisplayNode finishes a UIKit containment")
            let didLoad = try XCTUnwrap(self.body(of: "func viewDidLoad()", in: file.text), "\(name) has no viewDidLoad")
            XCTAssertTrue(didLoad.contains("addChild(self.hostingController)"), name)
        }
        if checked == 0 {
            throw XCTSkip("the sources are not reachable from this test run")
        }
        XCTAssertEqual(checked, self.screens.count)
    }
}
