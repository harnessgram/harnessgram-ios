import XCTest
import HarnessgramSettings
import SwiftSignalKit
import TelegramApi
@testable import TelegramCore

final class HarnessgramAccountPrivacyBootstrapTests: XCTestCase {
    private let accountId = AccountRecordId(rawValue: 1)
    private let otherAccountId = AccountRecordId(rawValue: 2)

    private func withStore(_ run: (HarnessgramPolicyStore, UserDefaults) -> Void) {
        let suiteName = "HarnessgramAccountPrivacyBootstrapTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        // Match the app's main-thread consent mutations, even if the test was invoked elsewhere.
        Queue.mainQueue().sync {
            run(HarnessgramPolicyStore(defaults: defaults, approved: .init()), defaults)
        }
    }

    func testUnknownAndDeclinedDoNotStartBootstrap() {
        self.withStore { store, defaults in
            var starts = 0
            let apply: () -> Signal<Never, NoError> = {
                starts += 1
                return .complete()
            }
            XCTAssertEqual(store.accountPrivacyConsent(accountId: self.accountId), .unknown)
            let unknown = harnessgramAccountPrivacyBootstrap(store: store, accountId: self.accountId, apply: apply).start()
            store.setAccountPrivacyConsent(.declined, accountId: self.accountId)
            unknown.dispose()

            let reopened = HarnessgramPolicyStore(defaults: defaults, approved: .init())
            XCTAssertEqual(reopened.accountPrivacyConsent(accountId: self.accountId), .declined)
            let declined = harnessgramAccountPrivacyBootstrap(store: reopened, accountId: self.accountId, apply: apply).start()
            defer { declined.dispose() }
            XCTAssertEqual(starts, 0)
        }
    }

    func testGrantStartsBootstrapImmediatelyAndIsRemembered() {
        self.withStore { store, defaults in
            var starts = 0
            let apply: () -> Signal<Never, NoError> = {
                starts += 1
                return .complete()
            }
            let active = harnessgramAccountPrivacyBootstrap(store: store, accountId: self.accountId, apply: apply).start()
            defer { active.dispose() }

            store.setAccountPrivacyConsent(.granted, accountId: self.accountId)
            XCTAssertEqual(starts, 1)
            store.setAccountPrivacyConsent(.granted, accountId: self.accountId)
            XCTAssertEqual(starts, 1)

            let reopened = HarnessgramPolicyStore(defaults: defaults, approved: .init())
            XCTAssertEqual(reopened.accountPrivacyConsent(accountId: self.accountId), .granted)
            let nextLaunch = harnessgramAccountPrivacyBootstrap(store: reopened, accountId: self.accountId, apply: apply).start()
            defer { nextLaunch.dispose() }
            XCTAssertEqual(starts, 2)
        }
    }

    func testWithdrawalCancelsPendingPassAndPreventsLaterLaunches() {
        self.withStore { store, defaults in
            let readFinished = ValuePipe<Void>()
            var starts = 0
            var writes = 0
            var cancellations = 0
            let apply: () -> Signal<Never, NoError> = {
                starts += 1
                return readFinished.signal()
                |> take(1)
                |> mapToSignal { _ -> Signal<Never, NoError> in
                    writes += 1
                    return .complete()
                }
                |> afterDisposed {
                    cancellations += 1
                }
            }
            let active = harnessgramAccountPrivacyBootstrap(store: store, accountId: self.accountId, apply: apply).start()
            defer { active.dispose() }

            store.setAccountPrivacyConsent(.granted, accountId: self.accountId)
            XCTAssertEqual(starts, 1)
            store.setAccountPrivacyConsent(.declined, accountId: self.accountId)
            XCTAssertEqual(cancellations, 1)
            readFinished.putNext(())
            XCTAssertEqual(writes, 0)

            let reopened = HarnessgramPolicyStore(defaults: defaults, approved: .init())
            let nextLaunch = harnessgramAccountPrivacyBootstrap(store: reopened, accountId: self.accountId, apply: apply).start()
            defer { nextLaunch.dispose() }
            XCTAssertEqual(reopened.accountPrivacyConsent(accountId: self.accountId), .declined)
            XCTAssertEqual(starts, 1)
        }
    }

    func testContactsOnlyRuleGatesAndCancelsBootstrapWithConsentGranted() {
        self.withStore { _, defaults in
            let filter = HarnessgramFilterSettings(defaults: defaults, allowsPersonalOff: true)
            let store = HarnessgramPolicyStore(defaults: defaults, approved: .init(), filter: filter)
            // Filter settings can be changed by another instance sharing these defaults.
            let settings = HarnessgramFilterSettings(defaults: defaults, allowsPersonalOff: true)
            XCTAssertTrue(settings.setPersonal(.contactsOnly, on: false))
            store.setAccountPrivacyConsent(.granted, accountId: self.accountId)

            let readFinished = ValuePipe<Void>()
            var starts = 0
            var writes = 0
            let active = harnessgramAccountPrivacyBootstrap(store: store, accountId: self.accountId, apply: {
                starts += 1
                return readFinished.signal()
                |> take(1)
                |> mapToSignal { _ -> Signal<Never, NoError> in
                    writes += 1
                    return .complete()
                }
            }).start()
            defer { active.dispose() }

            XCTAssertEqual(starts, 0)
            XCTAssertTrue(settings.setPersonal(.contactsOnly, on: true))
            XCTAssertEqual(starts, 1)
            XCTAssertTrue(settings.setPersonal(.stories, on: false))
            XCTAssertEqual(starts, 1)

            XCTAssertTrue(settings.setPersonal(.contactsOnly, on: false))
            readFinished.putNext(())
            XCTAssertEqual(writes, 0)
            XCTAssertEqual(store.accountPrivacyConsent(accountId: self.accountId), .granted)

            XCTAssertTrue(settings.setPersonal(.contactsOnly, on: true))
            XCTAssertEqual(starts, 2)
            readFinished.putNext(())
            XCTAssertEqual(writes, 1)
        }
    }

    func testConsentIsIsolatedBetweenSignedInAccounts() {
        self.withStore { store, defaults in
            var firstStarts = 0
            var otherStarts = 0
            let first = harnessgramAccountPrivacyBootstrap(store: store, accountId: self.accountId, apply: {
                firstStarts += 1
                return .complete()
            }).start()
            defer { first.dispose() }
            let other = harnessgramAccountPrivacyBootstrap(store: store, accountId: self.otherAccountId, apply: {
                otherStarts += 1
                return .complete()
            }).start()
            defer { other.dispose() }

            store.setAccountPrivacyConsent(.granted, accountId: self.accountId)
            XCTAssertEqual(firstStarts, 1)
            XCTAssertEqual(otherStarts, 0)
            XCTAssertEqual(store.accountPrivacyConsent(accountId: self.otherAccountId), .unknown)

            store.setAccountPrivacyConsent(.granted, accountId: self.otherAccountId)
            store.setAccountPrivacyConsent(.declined, accountId: self.accountId)
            let reopened = HarnessgramPolicyStore(defaults: defaults, approved: .init())
            XCTAssertEqual(reopened.accountPrivacyConsent(accountId: self.accountId), .declined)
            XCTAssertEqual(reopened.accountPrivacyConsent(accountId: self.otherAccountId), .granted)
            XCTAssertEqual(firstStarts, 1)
            XCTAssertEqual(otherStarts, 1)
        }
    }

    func testRestrictedPrivacyLeavesNobodyAndContactsOnlyIntact() {
        XCTAssertNil(harnessgramRestrictedPrivacyRule([]))
        XCTAssertNil(harnessgramRestrictedPrivacyRule([.disallowAll]))
        XCTAssertNil(harnessgramRestrictedPrivacyRule([.disallowSome, .allowContacts]))

        guard case .inputPrivacyValueDisallowAll? = harnessgramRestrictedPrivacyRule([.allowSome]),
              case .inputPrivacyValueDisallowAll? = harnessgramRestrictedPrivacyRule([.allowSome, .disallowAll]),
              case .inputPrivacyValueAllowContacts? = harnessgramRestrictedPrivacyRule([.allowAll]),
              case .inputPrivacyValueAllowContacts? = harnessgramRestrictedPrivacyRule([.allowSome, .allowContacts]) else {
            return XCTFail("Replacing broad permissions must respect the existing privacy baseline")
        }
    }
}
