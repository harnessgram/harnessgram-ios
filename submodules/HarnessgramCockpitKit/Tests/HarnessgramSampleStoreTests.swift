import Foundation
import HarnessgramCockpitKit
import XCTest

final class HarnessgramSampleStoreTests: XCTestCase {
    func testSampleStorageIsASiblingOfRealAccountsAndCockpit() throws {
        let container = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: container) }
        let realAccount = container.appendingPathComponent("telegram-data", isDirectory: true)
        let realCockpit = container.appendingPathComponent("harnessgram-cockpit", isDirectory: true)
        let bytes = Data([4, 2])
        for directory in [realAccount, realCockpit] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
            try bytes.write(to: directory.appendingPathComponent("sentinel"))
        }

        let store = HarnessgramSampleStore(container: container)
        let cockpit = HarnessgramCockpitStore(directory: realCockpit)
        try store.prepare()
        try store.write(HarnessgramSampleStore.initialState())
        XCTAssertEqual(store.directory.deletingLastPathComponent().standardizedFileURL.path, container.standardizedFileURL.path)
        XCTAssertNotEqual(store.directory, realAccount)
        XCTAssertNotEqual(store.directory, realCockpit)
        XCTAssertNotNil(store.read(cockpitStore: cockpit))

        let postbox = store.directory.appendingPathComponent("account/postbox/db", isDirectory: true)
        try FileManager.default.createDirectory(at: postbox, withIntermediateDirectories: true)
        try bytes.write(to: postbox.appendingPathComponent("sqlite"))
        try store.erase()
        try store.erase()
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.directory.path))
        XCTAssertNil(store.read(cockpitStore: cockpit))
        for directory in [realAccount, realCockpit] {
            XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("sentinel")), bytes)
        }
    }

    func testExistingSampleIsHiddenByRealAccountEvenWhenCockpitIsPaused() throws {
        let container = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: container) }
        let store = HarnessgramSampleStore(container: container)
        let cockpit = HarnessgramCockpitStore(directory: container.appendingPathComponent("harnessgram-cockpit"))

        try store.prepare()
        try store.write(HarnessgramSampleStore.initialState())
        XCTAssertNotNil(store.read(cockpitStore: cockpit))

        XCTAssertNotNil(cockpit.setActiveAccount(42))
        XCTAssertNil(store.read(cockpitStore: cockpit))

        try store.markRealAccountActive()
        cockpit.pause()
        XCTAssertNil(cockpit.activeAccount)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.directory.path))
        XCTAssertNil(store.read(cockpitStore: cockpit))

        // After sign-out, a new explicit sample can be shown even though Cockpit is still paused.
        try store.prepare()
        try store.write(HarnessgramSampleStore.initialState())
        XCTAssertNotNil(store.read(cockpitStore: cockpit))
    }

    func testSampleAnswerUpdatesBothWidgetViewsAndNeverResolvesSensitiveDecision() throws {
        var state = HarnessgramSampleStore.initialState()
        let plain = try XCTUnwrap(state.snapshot.decisions.first(where: { !$0.sensitive }))
        let sensitive = try XCTUnwrap(state.snapshot.decisions.first(where: \.sensitive))
        let initial = state.snapshot

        XCTAssertEqual(state.answer(sensitive.id, choice: .yes), .refused)
        XCTAssertEqual(state.snapshot, initial)
        XCTAssertTrue(state.answers.isEmpty)
        XCTAssertEqual(state.answer(plain.id, choice: .no), .applied)
        XCTAssertEqual(state.answer(plain.id, choice: .yes), .closed)
        XCTAssertEqual(state.answers, [plain.id: "no"])
        XCTAssertEqual(state.snapshot.decisions.map(\.id), [sensitive.id])
        XCTAssertEqual(state.snapshot.waitingCount, 1)
        XCTAssertEqual(state.snapshot.today?.doneToday, 5)
        XCTAssertEqual(state.snapshot.today?.waiting.map(\.url), [HarnessgramSampleStore.openURL])
        XCTAssertNotEqual(state.snapshot.today?.waiting.first?.title, sensitive.title)
        XCTAssertFalse(HarnessgramCockpitLinks.isDecisionId(plain.id))
        XCTAssertFalse(HarnessgramCockpitLinks.isDecisionId(sensitive.id))
        XCTAssertTrue(state.snapshot.decisions.allSatisfy { $0.topicURL.isEmpty })
        XCTAssertTrue(state.snapshot.agents.allSatisfy { $0.topicURL.isEmpty })
        XCTAssertTrue(state.snapshot.progress.allSatisfy { $0.topicURL.isEmpty })
    }
}
