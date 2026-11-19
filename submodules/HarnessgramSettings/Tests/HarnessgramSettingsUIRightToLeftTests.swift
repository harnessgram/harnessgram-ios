import XCTest

/// Build 21 guard: Telegram's ItemListController follows the English app language, so a Harnessgram page built on it
/// is laid out left to right. Every page in HarnessgramSettingsUI is SwiftUI inside HarnessgramHostingScreen (forced
/// right to left) instead. This scans the module's sources.
final class HarnessgramSettingsUIRightToLeftTests: XCTestCase {
    /// The module's directory, found from this file's path, the working directory or the test bundle (under Bazel the
    /// bundle sits in the exec root, next to the `submodules` link).
    private func settingsUIDirectory() -> URL? {
        let relative = "TelegramUI/Components/HarnessgramSettingsUI/Sources"
        let starts = [
            URL(fileURLWithPath: #filePath).deletingLastPathComponent(),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
            Bundle(for: HarnessgramSettingsUIRightToLeftTests.self).bundleURL
        ]
        for start in starts {
            var directory = start.standardizedFileURL
            // At most 64 levels up: "/" has no parent (its own parent path would be "/..").
            for _ in 0 ..< 64 {
                for candidate in [directory.appendingPathComponent(relative), directory.appendingPathComponent("submodules/" + relative)] {
                    var isDirectory: ObjCBool = false
                    if FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory), isDirectory.boolValue {
                        return candidate
                    }
                }
                if directory.path == "/" {
                    break
                }
                directory = directory.deletingLastPathComponent().standardizedFileURL
            }
        }
        return nil
    }

    private func settingsUISources() throws -> [URL] {
        guard let directory = self.settingsUIDirectory(), let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else {
            XCTFail("HarnessgramSettingsUI sources not found (\(#filePath))")
            return []
        }
        let files = enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
        XCTAssertFalse(files.isEmpty, "no sources in \(directory.path)")
        return files
    }

    func testNoPageInHarnessgramSettingsUIUsesItemListController() throws {
        let files = try self.settingsUISources()
        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            XCTAssertFalse(source.contains("ItemListController"), "\(file.lastPathComponent) uses ItemListController (left to right); use HarnessgramHostingScreen")
        }
    }

    func testTheFilterAndAdditionsPagesAreHostedRightToLeft() throws {
        let files = try self.settingsUISources()
        for name in ["HarnessgramFilterScreen.swift", "HarnessgramAdditionsScreen.swift", "HarnessgramMediaLevelScreen.swift"] {
            guard let file = files.first(where: { $0.lastPathComponent == name }) else {
                XCTFail("\(name) is missing")
                continue
            }
            XCTAssertTrue(try String(contentsOf: file, encoding: .utf8).contains("HarnessgramHostingScreen("), name)
        }
        // The host itself stays forced right to left.
        if let host = files.first(where: { $0.lastPathComponent == "HarnessgramHostingScreen.swift" }) {
            let source = try String(contentsOf: host, encoding: .utf8)
            XCTAssertTrue(source.contains(".layoutDirection, .rightToLeft"))
            XCTAssertTrue(source.contains(".forceRightToLeft"))
        } else {
            XCTFail("HarnessgramHostingScreen.swift is missing")
        }
    }
}
