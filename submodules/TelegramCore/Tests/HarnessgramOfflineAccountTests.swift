import Foundation
import Postbox
import SwiftSignalKit
import TelegramCore
import XCTest

final class HarnessgramOfflineAccountTests: XCTestCase {
    func testOfflineAccountOpensSeededChatsWithoutNetworkConfiguration() throws {
        initializeAccountManagement()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            Postbox.sharedQueue.sync {}
            try? FileManager.default.removeItem(at: directory)
        }
        let wal = directory.appendingPathComponent("account/postbox/db/db_sqlite-wal")
        let opened = expectation(description: "offline account opened")
        let disposable = HarnessgramDemoSeed.openOfflineAccount(directory: directory).start(next: { chats in
            XCTAssertEqual(chats?.map(\.title), ["גשר", "פינת הקריאה", "גלריית הכיתה", "אתר החנות", "מסלול הלמידה", "תדריך הבוקר", "לוח המשימות", "רדיו הצוות"])
            XCTAssertTrue(chats?.allSatisfy { !$0.message.isEmpty } == true)
            XCTAssertFalse(FileManager.default.fileExists(atPath: wal.path), "The database must be closed before delivering the chats.")
            opened.fulfill()
        })
        defer { disposable.dispose() }
        wait(for: [opened], timeout: 10)
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("account/postbox/db").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("account/network-usage").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("accounts-metadata").path))
    }
}
