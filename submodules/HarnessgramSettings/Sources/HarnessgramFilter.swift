import Foundation
import CryptoKit
import Security

/// One rule of the Harnessgram content filter (HarnessgramPolicy). On (the default) is today's filter; off gives
/// Telegram's own behaviour for that one thing. Build 19: every addition on top of Telegram is visible and switchable.
/// Build 21: the owner can only turn rules on; a rule goes off only through a committee lock.
public enum HarnessgramFilterRule: String, CaseIterable, Sendable {
    /// Groups, channels and communities outside the approved list are hidden and cannot be joined.
    case approvedChats
    /// Private chats only with contacts; others wait in the request list.
    case contactsOnly
    /// Media follows each chat's level; chats that are not approved show photos only; rich messages stay hidden.
    case mediaFilter
    /// Media marked as a spoiler stays hidden at every chat media level.
    case mediaSpoilers
    /// Content marked sensitive stays hidden whatever Telegram's own setting says.
    case sensitiveContent
    /// Stickers and emoji only from approved packs.
    case stickerPacks
    /// Link previews only for approved sites.
    case linkPreviews
    /// Web links leave for Safari (no in-app browser, Instant View or embedded players; no unknown links).
    case linksOutside
    /// No global search, GIF search or online sticker search.
    case search
    /// No stories.
    case stories
    /// Sponsored messages keep their text only, without media.
    case adMedia
    /// Interactive widgets only from the bridge, in its own chats.
    case otherBotWidgets
}

/// Where a rule's value comes from: the owner's own switch, or a committee lock.
public enum HarnessgramFilterSource: Equatable, Sendable {
    case personal
    case locked
}

/// A committee's filter document. A newer `version` signed by the built-in committee key replaces the current one;
/// `locked == false` removes the lock (the switches become personal again).
public struct HarnessgramFilterLockDocument: Codable, Equatable, Sendable {
    public var version: Int64
    public var locked: Bool
    /// Rule raw value -> on. A rule the document leaves out stays on (the filter).
    public var rules: [String: Bool]

    public init(version: Int64, locked: Bool, rules: [String: Bool]) {
        self.version = version
        self.locked = locked
        self.rules = rules
    }

    public func isOn(_ rule: HarnessgramFilterRule) -> Bool {
        return self.rules[rule.rawValue] ?? true
    }
}

/// A document as the committee sends it: the exact signed bytes, the Ed25519 signature and the committee's public key.
public struct HarnessgramSignedFilterLock: Codable, Equatable, Sendable {
    public var payload: Data
    public var signature: Data
    public var publicKey: Data

    public init(payload: Data, signature: Data, publicKey: Data) {
        self.payload = payload
        self.signature = signature
        self.publicKey = publicKey
    }
}

/// Where the highest committee document version ever accepted on this device is kept (the rollback guard). The app
/// uses the Keychain (`HarnessgramFilterKeychainHighWater`); tests inject their own. Both calls throw when the store
/// cannot be read or written, and the filter then refuses the lock (fail closed).
public protocol HarnessgramFilterHighWaterStore: AnyObject {
    /// The highest accepted version, or nil when none was ever accepted.
    func readHighWater() throws -> Int64?
    func writeHighWater(_ version: Int64) throws
}

/// The high-water mark in the Keychain: the app's default keychain access group (the first group of its
/// keychain-access-groups entitlement, the base bundle id's), never synchronised to iCloud, readable after the first
/// unlock on this device only. Keychain items survive deleting and reinstalling the app and are not touched when the
/// app group's preferences are wiped or restored, so a reset or an older copy of the preferences cannot lower it.
/// A full device restore from a backup is outside what it covers.
public final class HarnessgramFilterKeychainHighWater: HarnessgramFilterHighWaterStore {
    public static let shared = HarnessgramFilterKeychainHighWater()

    public struct KeychainError: Error, Equatable {
        public var status: OSStatus
    }

    private let service: String
    private let account = "highWater"

    public init(service: String = "HarnessgramSettings.filterLock") {
        self.service = service
    }

    private var query: [String: Any] {
        return [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: self.service,
            kSecAttrAccount as String: self.account,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
        ]
    }

    public func readHighWater() throws -> Int64? {
        var query = self.query
        query[kSecReturnData as String] = kCFBooleanTrue
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess, let data = result as? Data, let text = String(data: data, encoding: .utf8), let version = Int64(text) else {
            throw KeychainError(status: status == errSecSuccess ? errSecDecode : status)
        }
        return version
    }

    public func writeHighWater(_ version: Int64) throws {
        let data = Data(String(version).utf8)
        let update: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        var status = SecItemUpdate(self.query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var add = self.query
            add.merge(update, uniquingKeysWith: { _, new in new })
            status = SecItemAdd(add as CFDictionary, nil)
        }
        guard status == errSecSuccess else {
            throw KeychainError(status: status)
        }
    }
}

/// The filter's switches. Interim "on only" mode (build 21, committee-approved): without a committee lock nobody can turn
/// a rule off, even with Face ID; turning rules on stays free, and a value stored as off by build 19 or 20 reads as on.
/// `allowsPersonalOff` (false by default, true only in tests) restores build 19's personal switches. A committee lock
/// (the data model and its verification are here; its flow comes from the bridge later) decides while it is in force and
/// makes every switch read-only until a newer document signed by the built-in committee key changes or removes it.
/// The lock is kept as the committee's signed envelope and verified against the committee key whenever its stored bytes
/// change (and once per instance): a stored value that does not verify, or the decoded-only document of builds 19 and
/// 20, is ignored and the filter is fully on. A version never goes back: see `applyLock`.
public final class HarnessgramFilterSettings {
    public static let shared = HarnessgramFilterSettings(defaults: HarnessgramSettings.appGroupDefaults())

    /// The filter committee's raw Ed25519 public key (32 bytes; public, not a secret). Only a document signed by this key
    /// is ever accepted: a document never brings its own trusted key, and nothing is pinned on first use.
    public static let builtInCommitteeKey: Data? = Data(base64Encoded: "mDPhgAqufSMB1BDhAUHN1Jwq97zGh6UQQRddmWWZAPw=")

    /// Posted on the main queue after any change.
    public static let didChangeNotification = Notification.Name("HarnessgramFilterSettingsDidChange")

    static let keyPrefix = "HarnessgramSettings.filter."
    /// The committee's signed envelope in force (HarnessgramSignedFilterLock, JSON), verified on read.
    static let signedLockKey = "HarnessgramSettings.filterLock.signed"
    /// Builds 19 and 20 kept only the decoded document here and trusted it on read. Never trusted; deleted on first read.
    static let lockKey = "HarnessgramSettings.filterLock.document"
    static let committeeKeyKey = "HarnessgramSettings.filterLock.committeeKey"

    public enum LockError: Error, Equatable {
        case badSignature
        case unreadable
        /// Signed by another key than the committee key.
        case otherCommittee
        /// No committee key is built in, so no lock is accepted.
        case noCommitteeKey
        /// Not newer than the document in force or than the highest version ever accepted on this device.
        case notNewer
        /// The rollback guard (the Keychain high-water mark) could not be read or written: refused, fail closed.
        case highWaterUnavailable
        /// Only the main app applies locks; an extension (share, widget, notifications) is refused.
        case notInApp
    }

    /// One lock for every instance in this process: several instances (the shared one, HarnessgramPolicyStore's) share
    /// the same storage, so the compare-and-write of `applyLock` must be atomic across all of them. It does not reach
    /// other processes; that is why only the main app may apply a lock (`notInApp`).
    private static let applyMutex = NSLock()

    private let defaults: UserDefaults
    private let committeeKey: Data?
    private let highWater: HarnessgramFilterHighWaterStore
    /// Guards the verified-read cache below.
    private let cacheLock = NSLock()
    private var legacyDropped = false
    /// The stored envelope bytes last verified and what they verified to (nil when they did not).
    private var verified: (bytes: Data, document: HarnessgramFilterLockDocument?)?

    /// Whether the owner may turn a rule off without a lock. False in the app (build 21: rules turn on only).
    public let allowsPersonalOff: Bool

    public init(defaults: UserDefaults, allowsPersonalOff: Bool = false, committeeKey: Data? = HarnessgramFilterSettings.builtInCommitteeKey, highWater: HarnessgramFilterHighWaterStore = HarnessgramFilterKeychainHighWater.shared) {
        self.defaults = defaults
        self.allowsPersonalOff = allowsPersonalOff
        self.committeeKey = committeeKey
        self.highWater = highWater
    }

    static func key(_ rule: HarnessgramFilterRule) -> String {
        return HarnessgramFilterSettings.keyPrefix + rule.rawValue
    }

    /// Whether a rule filters now: the lock's value while locked; otherwise always on unless personal off is allowed,
    /// then the owner's value (on when never set). A value an older build stored as off is ignored.
    public func isOn(_ rule: HarnessgramFilterRule) -> Bool {
        if let document = self.lockDocument, document.locked {
            return document.isOn(rule)
        }
        guard self.allowsPersonalOff else {
            return true
        }
        return (self.defaults.object(forKey: HarnessgramFilterSettings.key(rule)) as? Bool) ?? true
    }

    public func source(_ rule: HarnessgramFilterRule) -> HarnessgramFilterSource {
        if let document = self.lockDocument, document.locked {
            return .locked
        }
        return .personal
    }

    public var isLocked: Bool {
        return self.lockDocument?.locked == true
    }

    /// The owner's own switch. Refused (false) while a committee lock is in force, and refused for off (nothing is
    /// stored) unless `allowsPersonalOff`. Turning a rule on always works. With personal off allowed, the caller asks
    /// for Face ID before turning a rule off (HarnessgramFilterSwitch).
    @discardableResult
    public func setPersonal(_ rule: HarnessgramFilterRule, on: Bool) -> Bool {
        guard !self.isLocked else {
            return false
        }
        guard on || self.allowsPersonalOff else {
            return false
        }
        self.defaults.set(on, forKey: HarnessgramFilterSettings.key(rule))
        self.notify()
        return true
    }

    // MARK: Committee lock

    /// The document in force: the stored signed envelope, verified against the committee key (re-verified whenever the
    /// stored bytes change). nil, so the filter is fully on, when nothing is stored, no committee key is built in, or the
    /// stored value does not verify (edited, signed by another key, or the decoded-only document of builds 19 and 20).
    public var lockDocument: HarnessgramFilterLockDocument? {
        self.cacheLock.lock()
        defer { self.cacheLock.unlock() }
        if !self.legacyDropped {
            self.legacyDropped = true
            if self.defaults.object(forKey: HarnessgramFilterSettings.lockKey) != nil {
                self.defaults.removeObject(forKey: HarnessgramFilterSettings.lockKey)
            }
        }
        guard let committeeKey = self.committeeKey, let bytes = self.defaults.data(forKey: HarnessgramFilterSettings.signedLockKey) else {
            return nil
        }
        if let verified = self.verified, verified.bytes == bytes {
            return verified.document
        }
        var document: HarnessgramFilterLockDocument?
        if let signed = try? JSONDecoder().decode(HarnessgramSignedFilterLock.self, from: bytes), signed.publicKey == committeeKey {
            document = try? HarnessgramFilterSettings.verify(signed, committeeKey: committeeKey)
        }
        self.verified = (bytes, document)
        return document
    }

    /// A key that build 19 or 20 pinned with a first lock (raw Ed25519, 32 bytes). Kept for reading only: it never
    /// decides trust, and nothing writes it any more.
    public var pinnedCommitteeKey: Data? {
        return self.defaults.data(forKey: HarnessgramFilterSettings.committeeKeyKey)
    }

    /// Whether this process may apply a lock: the main app only, never an app extension.
    static var isMainApp: Bool {
        return Bundle.main.bundleURL.pathExtension != "appex"
    }

    /// Applies a signed committee document after checking it: this is the main app (otherwise `.notInApp`), a committee
    /// key is built in (otherwise `.noCommitteeKey`), the document names exactly that key (otherwise `.otherCommittee`),
    /// its Ed25519 signature over the exact `payload` bytes verifies against that same key (otherwise `.badSignature`),
    /// and its version is above both the verified document in force and the Keychain high-water mark of every version
    /// ever accepted here (otherwise `.notNewer`), so wiping or restoring the preferences cannot roll a lock back. The
    /// high-water mark is raised before the envelope is stored, also by an unlock document; when the Keychain cannot be
    /// read or written the lock is refused (`.highWaterUnavailable`) and nothing changes.
    public func applyLock(_ signed: HarnessgramSignedFilterLock) throws {
        guard HarnessgramFilterSettings.isMainApp else {
            throw LockError.notInApp
        }
        HarnessgramFilterSettings.applyMutex.lock()
        defer { HarnessgramFilterSettings.applyMutex.unlock() }
        guard let committeeKey = self.committeeKey else {
            throw LockError.noCommitteeKey
        }
        guard signed.publicKey == committeeKey else {
            throw LockError.otherCommittee
        }
        let document = try HarnessgramFilterSettings.verify(signed, committeeKey: committeeKey)
        let highWater: Int64?
        do {
            highWater = try self.highWater.readHighWater()
        } catch {
            throw LockError.highWaterUnavailable
        }
        if let floor = [self.lockDocument?.version, highWater].compactMap({ $0 }).max(), document.version <= floor {
            throw LockError.notNewer
        }
        guard let envelope = try? JSONEncoder().encode(signed) else {
            throw LockError.unreadable
        }
        do {
            try self.highWater.writeHighWater(document.version)
        } catch {
            throw LockError.highWaterUnavailable
        }
        self.defaults.set(envelope, forKey: HarnessgramFilterSettings.signedLockKey)
        self.notify()
    }

    /// The document if `signature` is a valid Ed25519 signature of the exact `payload` bytes by `committeeKey` (never
    /// by the key the document carries). The payload is decoded only after the signature verifies.
    static func verify(_ signed: HarnessgramSignedFilterLock, committeeKey: Data) throws -> HarnessgramFilterLockDocument {
        guard let key = try? Curve25519.Signing.PublicKey(rawRepresentation: committeeKey), key.isValidSignature(signed.signature, for: signed.payload) else {
            throw LockError.badSignature
        }
        guard let document = try? JSONDecoder().decode(HarnessgramFilterLockDocument.self, from: signed.payload) else {
            throw LockError.unreadable
        }
        return document
    }

    private func notify() {
        if Thread.isMainThread {
            NotificationCenter.default.post(name: HarnessgramFilterSettings.didChangeNotification, object: self)
        } else {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: HarnessgramFilterSettings.didChangeNotification, object: self)
            }
        }
    }
}
