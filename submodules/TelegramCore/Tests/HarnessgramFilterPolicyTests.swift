import XCTest
import Postbox
import HarnessgramSettings
@testable import TelegramCore

/// Build 20: each filter rule switched off gives Telegram's own behaviour for that one thing; on (the default) is
/// exactly today's filter. Build 21: only a filter that allows personal off (tests) can switch a rule off.
final class HarnessgramFilterPolicyTests: XCTestCase {
    private func withStore(_ body: (HarnessgramPolicyStore, HarnessgramFilterSettings) -> Void) {
        let suite = "HarnessgramFilterPolicyTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let filter = HarnessgramFilterSettings(defaults: defaults, allowsPersonalOff: true)
        let store = HarnessgramPolicyStore(defaults: defaults, approved: .init(), stickerPacks: .init(), linkPreviewDomains: [], mediaLevels: [:], filter: filter)
        body(store, filter)
    }

    private let account = EnginePeer.Id(namespace: Namespaces.Peer.CloudUser, id: EnginePeer.Id.Id._internalFromInt64Value(1))
    private let channel = EnginePeer.Id(namespace: Namespaces.Peer.CloudChannel, id: EnginePeer.Id.Id._internalFromInt64Value(777))

    func testDefaultsKeepTodaysFilter() {
        self.withStore { store, _ in
            XCTAssertFalse(store.isApprovedChatId(self.channel, accountPeerId: self.account))
            XCTAssertFalse(store.isApprovedStickerPack(.name("anypack")))
            XCTAssertFalse(store.isApprovedLinkPreviewUrl("https://example.com/page"))
            XCTAssertNotEqual(store.mediaLevel(forChatId: self.channel, accountPeerId: self.account), .all)
        }
    }

    func testApprovedChatsOffShowsEveryGroupAndChannel() {
        self.withStore { store, filter in
            filter.setPersonal(.approvedChats, on: false)
            XCTAssertTrue(store.isApprovedChatId(self.channel, accountPeerId: self.account))
        }
    }

    func testStickerPacksOffShowsEveryPack() {
        self.withStore { store, filter in
            filter.setPersonal(.stickerPacks, on: false)
            XCTAssertTrue(store.isApprovedStickerPack(.name("anypack")))
            XCTAssertTrue(store.isApprovedStickerPack(nil))
        }
    }

    func testLinkPreviewsOffPreviewsEverySite() {
        self.withStore { store, filter in
            filter.setPersonal(.linkPreviews, on: false)
            XCTAssertTrue(store.isApprovedLinkPreviewUrl("https://example.com/page"))
        }
    }

    func testMediaFilterOffShowsEverything() {
        self.withStore { store, filter in
            filter.setPersonal(.mediaFilter, on: false)
            XCTAssertEqual(store.mediaLevel(forChatId: self.channel, accountPeerId: self.account), .all)
        }
    }

    /// The app's filter (personal off not allowed) keeps today's filter even when build 19 or 20 stored a rule as off.
    func testAnOffValueFromAnOlderBuildStillFilters() {
        let suite = "HarnessgramFilterPolicyTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        // What build 19 or 20 left behind: rules switched off by the owner.
        let olderBuild = HarnessgramFilterSettings(defaults: defaults, allowsPersonalOff: true)
        XCTAssertTrue(olderBuild.setPersonal(.approvedChats, on: false))
        XCTAssertTrue(olderBuild.setPersonal(.stickerPacks, on: false))
        let store = HarnessgramPolicyStore(defaults: defaults, approved: .init(), stickerPacks: .init(), linkPreviewDomains: [], mediaLevels: [:])
        XCTAssertFalse(store.isApprovedChatId(self.channel, accountPeerId: self.account))
        XCTAssertFalse(store.isApprovedStickerPack(.name("anypack")))
        XCTAssertFalse(store.filter.setPersonal(.linkPreviews, on: false))
        XCTAssertFalse(store.isApprovedLinkPreviewUrl("https://example.com/page"))
    }

    func testRulesAreIndependent() {
        self.withStore { store, filter in
            filter.setPersonal(.stickerPacks, on: false)
            XCTAssertFalse(store.isApprovedChatId(self.channel, accountPeerId: self.account))
            XCTAssertFalse(store.isApprovedLinkPreviewUrl("https://example.com/page"))
        }
    }
}
