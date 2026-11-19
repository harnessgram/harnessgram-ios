import XCTest
import CryptoKit
@testable import HarnessgramSettings

/// The Keychain high-water mark's stand-in: in memory, thread safe, and able to fail like a locked Keychain.
final class MemoryHighWater: HarnessgramFilterHighWaterStore {
    struct Unavailable: Error {}

    private let lock = NSLock()
    private var value: Int64?
    var failReads = false
    var failWrites = false

    var current: Int64? {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.value
    }

    func readHighWater() throws -> Int64? {
        self.lock.lock()
        defer { self.lock.unlock() }
        if self.failReads {
            throw Unavailable()
        }
        return self.value
    }

    func writeHighWater(_ version: Int64) throws {
        self.lock.lock()
        defer { self.lock.unlock() }
        if self.failWrites {
            throw Unavailable()
        }
        self.value = version
    }
}

final class HarnessgramFilterTests: XCTestCase {
    /// The test committee: locks in these tests are signed with this key, passed to the filter as its committee key.
    private let committee = Curve25519.Signing.PrivateKey()

    private func withFilter(allowsPersonalOff: Bool = true, committeeKey: Data?? = nil, highWater: MemoryHighWater = MemoryHighWater(), _ body: (HarnessgramFilterSettings, UserDefaults) throws -> Void) rethrows {
        let suite = "HarnessgramFilterTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let key: Data? = committeeKey ?? self.committee.publicKey.rawRepresentation
        try body(HarnessgramFilterSettings(defaults: defaults, allowsPersonalOff: allowsPersonalOff, committeeKey: key, highWater: highWater), defaults)
    }

    private func filter(_ defaults: UserDefaults, _ highWater: MemoryHighWater) -> HarnessgramFilterSettings {
        return HarnessgramFilterSettings(defaults: defaults, allowsPersonalOff: false, committeeKey: self.committee.publicKey.rawRepresentation, highWater: highWater)
    }

    private func freshDefaults() -> (UserDefaults, String) {
        let suite = "HarnessgramFilterTests." + UUID().uuidString
        return (UserDefaults(suiteName: suite)!, suite)
    }

    private func signed(_ document: HarnessgramFilterLockDocument, key: Curve25519.Signing.PrivateKey) throws -> HarnessgramSignedFilterLock {
        let payload = try JSONEncoder().encode(document)
        return HarnessgramSignedFilterLock(payload: payload, signature: try key.signature(for: payload), publicKey: key.publicKey.rawRepresentation)
    }

    /// Every rule defaults to today's filter.
    func testEveryRuleIsOnByDefaultAndPersonal() {
        for allowsPersonalOff in [false, true] {
            self.withFilter(allowsPersonalOff: allowsPersonalOff) { filter, _ in
                for rule in HarnessgramFilterRule.allCases {
                    XCTAssertTrue(filter.isOn(rule), rule.rawValue)
                    XCTAssertEqual(filter.source(rule), .personal)
                }
                XCTAssertFalse(filter.isLocked)
            }
        }
    }

    /// Build 21: the app's filter refuses off and stores nothing; turning a rule on still works.
    func testTheDefaultFilterRefusesOff() {
        let suite = "HarnessgramFilterTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let filter = HarnessgramFilterSettings(defaults: defaults)
        XCTAssertFalse(filter.allowsPersonalOff)
        for rule in HarnessgramFilterRule.allCases {
            XCTAssertFalse(filter.setPersonal(rule, on: false), rule.rawValue)
            XCTAssertNil(defaults.object(forKey: HarnessgramFilterSettings.key(rule)), rule.rawValue)
            XCTAssertTrue(filter.isOn(rule), rule.rawValue)
            XCTAssertTrue(filter.setPersonal(rule, on: true), rule.rawValue)
            XCTAssertTrue(filter.isOn(rule), rule.rawValue)
        }
        XCTAssertFalse(HarnessgramFilterSettings.shared.allowsPersonalOff)
    }

    /// A rule that build 19 or 20 stored as off reads as on again.
    func testAValueStoredAsOffReadsAsOn() {
        self.withFilter(allowsPersonalOff: false) { filter, defaults in
            for rule in HarnessgramFilterRule.allCases {
                defaults.set(false, forKey: HarnessgramFilterSettings.key(rule))
            }
            for rule in HarnessgramFilterRule.allCases {
                XCTAssertTrue(filter.isOn(rule), rule.rawValue)
            }
            // The same stored values with personal off allowed: the older behaviour.
            XCTAssertFalse(HarnessgramFilterSettings(defaults: defaults, allowsPersonalOff: true).isOn(.stories))
        }
    }

    func testPersonalSwitchesTouchOnlyTheirRule() {
        self.withFilter { filter, defaults in
            XCTAssertTrue(filter.setPersonal(.stories, on: false))
            XCTAssertFalse(filter.isOn(.stories))
            XCTAssertTrue(filter.isOn(.search))
            XCTAssertFalse(HarnessgramFilterSettings(defaults: defaults, allowsPersonalOff: true).isOn(.stories))
            XCTAssertTrue(filter.setPersonal(.stories, on: true))
            XCTAssertTrue(filter.isOn(.stories))
        }
    }

    func testASignedLockMakesTheSwitchesReadOnlyAndPinsNothing() throws {
        try self.withFilter { filter, _ in
            filter.setPersonal(.search, on: false)
            try filter.applyLock(self.signed(HarnessgramFilterLockDocument(version: 1, locked: true, rules: ["stories": false]), key: self.committee))
            XCTAssertTrue(filter.isLocked)
            XCTAssertNil(filter.pinnedCommitteeKey)
            // The lock's values win; a rule it leaves out stays on, whatever the personal switch said.
            XCTAssertFalse(filter.isOn(.stories))
            XCTAssertTrue(filter.isOn(.search))
            XCTAssertEqual(filter.source(.search), .locked)
            // Read-only, even for the owner.
            XCTAssertFalse(filter.setPersonal(.search, on: false))
            XCTAssertFalse(filter.setPersonal(.stories, on: true))
            XCTAssertTrue(filter.isOn(.search))
        }
    }

    /// A committee lock decides even when personal off is not allowed (it may turn a rule off).
    func testALockDecidesInTheOnOnlyMode() throws {
        try self.withFilter(allowsPersonalOff: false) { filter, _ in
            try filter.applyLock(self.signed(HarnessgramFilterLockDocument(version: 1, locked: true, rules: ["stories": false]), key: self.committee))
            XCTAssertFalse(filter.isOn(.stories))
            XCTAssertTrue(filter.isOn(.search))
            try filter.applyLock(self.signed(HarnessgramFilterLockDocument(version: 2, locked: false, rules: ["stories": false]), key: self.committee))
            XCTAssertFalse(filter.isLocked)
            XCTAssertTrue(filter.isOn(.stories))
        }
    }

    func testOnlyANewerDocumentFromTheCommitteeKeyChangesOrRemovesTheLock() throws {
        let stranger = Curve25519.Signing.PrivateKey()
        try self.withFilter { filter, _ in
            try filter.applyLock(self.signed(HarnessgramFilterLockDocument(version: 5, locked: true, rules: [:]), key: self.committee))
            XCTAssertThrowsError(try filter.applyLock(self.signed(HarnessgramFilterLockDocument(version: 6, locked: false, rules: [:]), key: stranger))) { error in
                XCTAssertEqual(error as? HarnessgramFilterSettings.LockError, .otherCommittee)
            }
            XCTAssertThrowsError(try filter.applyLock(self.signed(HarnessgramFilterLockDocument(version: 5, locked: false, rules: [:]), key: self.committee))) { error in
                XCTAssertEqual(error as? HarnessgramFilterSettings.LockError, .notNewer)
            }
            XCTAssertTrue(filter.isLocked)
            try filter.applyLock(self.signed(HarnessgramFilterLockDocument(version: 6, locked: false, rules: [:]), key: self.committee))
            XCTAssertFalse(filter.isLocked)
            XCTAssertEqual(filter.source(.stories), .personal)
            XCTAssertTrue(filter.setPersonal(.stories, on: false))
        }
    }

    /// No trust on first use: a first document signed by another key is refused, even though it carries its own
    /// public key, and a key that build 19 or 20 pinned changes nothing.
    func testADocumentSignedByAnotherKeyIsRefusedEvenWithItsOwnPublicKey() throws {
        let stranger = Curve25519.Signing.PrivateKey()
        try self.withFilter { filter, defaults in
            let lock = try self.signed(HarnessgramFilterLockDocument(version: 1, locked: true, rules: ["stories": false]), key: stranger)
            XCTAssertEqual(lock.publicKey, stranger.publicKey.rawRepresentation)
            XCTAssertThrowsError(try filter.applyLock(lock)) { error in
                XCTAssertEqual(error as? HarnessgramFilterSettings.LockError, .otherCommittee)
            }
            // An older build pinned the stranger's key: still refused.
            defaults.set(stranger.publicKey.rawRepresentation, forKey: HarnessgramFilterSettings.committeeKeyKey)
            XCTAssertThrowsError(try filter.applyLock(lock)) { error in
                XCTAssertEqual(error as? HarnessgramFilterSettings.LockError, .otherCommittee)
            }
            // A stranger's signature presented under the committee's public key fails verification.
            var forged = lock
            forged.publicKey = self.committee.publicKey.rawRepresentation
            XCTAssertThrowsError(try filter.applyLock(forged)) { error in
                XCTAssertEqual(error as? HarnessgramFilterSettings.LockError, .badSignature)
            }
            XCTAssertFalse(filter.isLocked)
            XCTAssertTrue(filter.isOn(.stories))
            // The committee's own document is accepted whatever was pinned.
            try filter.applyLock(self.signed(HarnessgramFilterLockDocument(version: 1, locked: true, rules: [:]), key: self.committee))
            XCTAssertTrue(filter.isLocked)
        }
    }

    func testANilCommitteeKeyRefusesEveryLock() throws {
        try self.withFilter(committeeKey: .some(nil)) { filter, _ in
            XCTAssertThrowsError(try filter.applyLock(self.signed(HarnessgramFilterLockDocument(version: 1, locked: true, rules: [:]), key: self.committee))) { error in
                XCTAssertEqual(error as? HarnessgramFilterSettings.LockError, .noCommitteeKey)
            }
            XCTAssertFalse(filter.isLocked)
            XCTAssertNil(filter.pinnedCommitteeKey)
        }
    }

    func testABadSignatureOrATamperedPayloadIsRefused() throws {
        try self.withFilter { filter, _ in
            var lock = try self.signed(HarnessgramFilterLockDocument(version: 1, locked: true, rules: [:]), key: self.committee)
            lock.payload = try JSONEncoder().encode(HarnessgramFilterLockDocument(version: 1, locked: true, rules: ["search": false]))
            XCTAssertThrowsError(try filter.applyLock(lock)) { error in
                XCTAssertEqual(error as? HarnessgramFilterSettings.LockError, .badSignature)
            }
            lock = HarnessgramSignedFilterLock(payload: Data("not json".utf8), signature: try self.committee.signature(for: Data("not json".utf8)), publicKey: self.committee.publicKey.rawRepresentation)
            XCTAssertThrowsError(try filter.applyLock(lock)) { error in
                XCTAssertEqual(error as? HarnessgramFilterSettings.LockError, .unreadable)
            }
            XCTAssertFalse(filter.isLocked)
            XCTAssertNil(filter.pinnedCommitteeKey)
        }
    }

    /// The signature covers the exact compact payload bytes the committee sent.
    func testTheCompactCommitteePayloadIsReadAfterVerifying() throws {
        try self.withFilter(allowsPersonalOff: false) { filter, _ in
            let payload = Data(#"{"version":3,"locked":true,"rules":{"search":false}}"#.utf8)
            let lock = HarnessgramSignedFilterLock(payload: payload, signature: try self.committee.signature(for: payload), publicKey: self.committee.publicKey.rawRepresentation)
            try filter.applyLock(lock)
            XCTAssertEqual(filter.lockDocument, HarnessgramFilterLockDocument(version: 3, locked: true, rules: ["search": false]))
            XCTAssertFalse(filter.isOn(.search))
        }
    }

    /// Builds 19 and 20 stored only the decoded document and trusted it. That value is ignored (the filter is fully on)
    /// and deleted on the first read; an envelope without a valid committee signature is ignored too.
    func testAnUnsignedOrLegacyStoredDocumentIsIgnored() throws {
        let stranger = Curve25519.Signing.PrivateKey()
        try self.withFilter(allowsPersonalOff: false) { filter, defaults in
            let permissive = HarnessgramFilterLockDocument(version: 99, locked: true, rules: Dictionary(uniqueKeysWithValues: HarnessgramFilterRule.allCases.map { ($0.rawValue, false) }))
            defaults.set(try JSONEncoder().encode(permissive), forKey: HarnessgramFilterSettings.lockKey)
            XCTAssertFalse(filter.isLocked)
            XCTAssertNil(filter.lockDocument)
            XCTAssertNil(defaults.object(forKey: HarnessgramFilterSettings.lockKey))
            for rule in HarnessgramFilterRule.allCases {
                XCTAssertTrue(filter.isOn(rule), rule.rawValue)
            }
            // An envelope with no signature, and one signed by another key (even naming the committee key).
            let payload = try JSONEncoder().encode(permissive)
            let unsigned = HarnessgramSignedFilterLock(payload: payload, signature: Data(), publicKey: self.committee.publicKey.rawRepresentation)
            defaults.set(try JSONEncoder().encode(unsigned), forKey: HarnessgramFilterSettings.signedLockKey)
            XCTAssertNil(filter.lockDocument)
            XCTAssertTrue(filter.isOn(.stories))
            let foreign = HarnessgramSignedFilterLock(payload: payload, signature: try stranger.signature(for: payload), publicKey: self.committee.publicKey.rawRepresentation)
            defaults.set(try JSONEncoder().encode(foreign), forKey: HarnessgramFilterSettings.signedLockKey)
            XCTAssertNil(filter.lockDocument)
            let ownKey = HarnessgramSignedFilterLock(payload: payload, signature: try stranger.signature(for: payload), publicKey: stranger.publicKey.rawRepresentation)
            defaults.set(try JSONEncoder().encode(ownKey), forKey: HarnessgramFilterSettings.signedLockKey)
            XCTAssertNil(filter.lockDocument)
            defaults.set(Data("garbage".utf8), forKey: HarnessgramFilterSettings.signedLockKey)
            XCTAssertNil(filter.lockDocument)
            XCTAssertTrue(filter.isOn(.search))
        }
    }

    /// A stored envelope edited after it was applied (another payload, or another signature) no longer counts, also on
    /// an instance that verified the original bytes before.
    func testATamperedStoredEnvelopeIsIgnored() throws {
        try self.withFilter(allowsPersonalOff: false) { filter, defaults in
            try filter.applyLock(self.signed(HarnessgramFilterLockDocument(version: 4, locked: true, rules: ["stories": true]), key: self.committee))
            XCTAssertTrue(filter.isLocked)
            let stored = try XCTUnwrap(defaults.data(forKey: HarnessgramFilterSettings.signedLockKey))
            var envelope = try JSONDecoder().decode(HarnessgramSignedFilterLock.self, from: stored)
            envelope.payload = try JSONEncoder().encode(HarnessgramFilterLockDocument(version: 4, locked: true, rules: ["stories": false, "search": false]))
            defaults.set(try JSONEncoder().encode(envelope), forKey: HarnessgramFilterSettings.signedLockKey)
            XCTAssertNil(filter.lockDocument)
            XCTAssertTrue(filter.isOn(.stories))
            XCTAssertTrue(filter.isOn(.search))
            // The original bytes verify again.
            defaults.set(stored, forKey: HarnessgramFilterSettings.signedLockKey)
            XCTAssertEqual(filter.lockDocument?.version, 4)
            var flipped = Array(envelope.signature)
            flipped[0] ^= 0x01
            envelope = try JSONDecoder().decode(HarnessgramSignedFilterLock.self, from: stored)
            envelope.signature = Data(flipped)
            defaults.set(try JSONEncoder().encode(envelope), forKey: HarnessgramFilterSettings.signedLockKey)
            XCTAssertFalse(filter.isLocked)
        }
    }

    /// The Keychain high-water mark survives a wiped or restored preferences file: v10 cannot come back after v11.
    func testTheHighWaterBlocksAnOlderVersionEvenAfterThePreferencesAreReset() throws {
        let highWater = MemoryHighWater()
        let (first, firstSuite) = self.freshDefaults()
        defer { first.removePersistentDomain(forName: firstSuite) }
        let v10 = try self.signed(HarnessgramFilterLockDocument(version: 10, locked: true, rules: ["stories": false]), key: self.committee)
        try self.filter(first, highWater).applyLock(v10)
        try self.filter(first, highWater).applyLock(self.signed(HarnessgramFilterLockDocument(version: 11, locked: false, rules: [:]), key: self.committee))
        XCTAssertEqual(highWater.current, 11)
        // The preferences are wiped (or an older copy restored): nothing of the lock is stored any more.
        let (reset, resetSuite) = self.freshDefaults()
        defer { reset.removePersistentDomain(forName: resetSuite) }
        let filter = self.filter(reset, highWater)
        for version: Int64 in [10, 11] {
            XCTAssertThrowsError(try filter.applyLock(self.signed(HarnessgramFilterLockDocument(version: version, locked: true, rules: ["stories": false]), key: self.committee))) { error in
                XCTAssertEqual(error as? HarnessgramFilterSettings.LockError, .notNewer)
            }
        }
        XCTAssertThrowsError(try filter.applyLock(v10))
        XCTAssertFalse(filter.isLocked)
        XCTAssertTrue(filter.isOn(.stories))
        try filter.applyLock(self.signed(HarnessgramFilterLockDocument(version: 12, locked: true, rules: [:]), key: self.committee))
        XCTAssertEqual(highWater.current, 12)
    }

    /// Fail closed: a Keychain that cannot be read or written refuses the lock and changes nothing.
    func testAnUnavailableHighWaterRefusesTheLock() throws {
        for failReads in [true, false] {
            let highWater = MemoryHighWater()
            highWater.failReads = failReads
            highWater.failWrites = !failReads
            try self.withFilter(allowsPersonalOff: false, highWater: highWater) { filter, defaults in
                XCTAssertThrowsError(try filter.applyLock(self.signed(HarnessgramFilterLockDocument(version: 1, locked: true, rules: ["stories": false]), key: self.committee))) { error in
                    XCTAssertEqual(error as? HarnessgramFilterSettings.LockError, .highWaterUnavailable)
                }
                XCTAssertNil(defaults.object(forKey: HarnessgramFilterSettings.signedLockKey))
                XCTAssertFalse(filter.isLocked)
                XCTAssertTrue(filter.isOn(.stories))
            }
        }
    }

    /// Two instances on the same storage apply versions at once: the version in force and the high-water mark end at
    /// the highest one, never lower.
    func testConcurrentLocksFromTwoInstancesNeverRegress() throws {
        let highWater = MemoryHighWater()
        let (defaults, suite) = self.freshDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let instances = [self.filter(defaults, highWater), self.filter(defaults, highWater)]
        let documents = try (1...60).map { try self.signed(HarnessgramFilterLockDocument(version: Int64($0), locked: true, rules: [:]), key: self.committee) }.shuffled()
        let seen = NSLock()
        var applied: [Int64] = []
        DispatchQueue.concurrentPerform(iterations: documents.count) { index in
            if (try? instances[index % 2].applyLock(documents[index])) != nil {
                let version = (try? JSONDecoder().decode(HarnessgramFilterLockDocument.self, from: documents[index].payload))?.version ?? 0
                seen.lock()
                applied.append(version)
                seen.unlock()
            }
        }
        XCTAssertEqual(instances[0].lockDocument?.version, 60)
        XCTAssertEqual(instances[1].lockDocument?.version, 60)
        XCTAssertEqual(highWater.current, 60)
        // No version was accepted twice.
        XCTAssertEqual(Set(applied).count, applied.count)
        XCTAssertTrue(applied.contains(60))
    }

    func testTheBuiltInCommitteeKeyIsAnEd25519PublicKey() throws {
        let key = try XCTUnwrap(HarnessgramFilterSettings.builtInCommitteeKey)
        XCTAssertEqual(key.count, 32)
        XCTAssertNoThrow(try Curve25519.Signing.PublicKey(rawRepresentation: key))
    }
}
