import Foundation
import LocalAuthentication

/// Asks the owner to confirm with Face ID (or the device passcode when Face ID fails) before a sensitive
/// button is pressed. Fails closed: no biometrics and no passcode, a cancel or an error all mean nothing
/// is sent.
///
/// A confirmed press is replayed through the normal button path once; `grant` and `consume` make that
/// replay pass the gate exactly one time, within a few seconds.
public final class HarnessgramOwnerConfirmation {
    public static let shared = HarnessgramOwnerConfirmation()

    /// How long a confirmed press stays valid for its one replay.
    public static let grantLifetime: TimeInterval = 10.0

    /// Asks the system for the owner (Face ID, then the passcode); `completion` gets true only on success.
    public typealias Authenticator = (_ reason: String, _ completion: @escaping (Bool) -> Void) -> Void

    /// Which check a confirmation asks for.
    public enum Policy: Sendable {
        /// Face ID, falling back to the device passcode (the bot buttons and the widgets' app flow).
        case ownerAuthentication
        /// Face ID only (no Touch ID), with no passcode fallback (the native Cockpit's answers).
        case biometrics
    }

    private let lock = NSLock()
    private var grants: [String: Date] = [:]
    /// Keys whose prompt is on screen: a second press of the same button waits for it instead of asking again.
    private var pending: Set<String> = []
    private let now: () -> Date
    private let authenticator: Authenticator
    private let biometricAuthenticator: Authenticator

    public init(now: @escaping () -> Date = Date.init, authenticator: Authenticator? = nil, biometricAuthenticator: Authenticator? = nil) {
        self.now = now
        self.authenticator = authenticator ?? HarnessgramOwnerConfirmation.deviceOwnerAuthentication
        self.biometricAuthenticator = biometricAuthenticator ?? HarnessgramOwnerConfirmation.deviceBiometricAuthentication
    }

    /// The one entry for a gated press. True when it may go ahead now (its single replay after a success);
    /// false when it waits for the owner: on success `proceed` runs once on the main queue, on a cancel or a
    /// failure nothing happens. Presses of the same key while its prompt is open are dropped.
    public func gate(key: String, reason: String, proceed: @escaping () -> Void) -> Bool {
        if self.consume(key) {
            return true
        }
        self.lock.lock()
        let isNew = self.pending.insert(key).inserted
        self.lock.unlock()
        guard isNew else {
            return false
        }
        self.confirm(reason: reason, completion: { [weak self] approved in
            guard let self else {
                return
            }
            self.lock.lock()
            self.pending.remove(key)
            self.lock.unlock()
            guard approved else {
                return
            }
            self.grant(key)
            proceed()
        })
        return false
    }

    /// An action with no replay path (a widget's request to its bot): `perform` runs once on the main queue after a
    /// successful owner check, `refuse` on a cancel or failure. While a prompt for `key` is open, another action with
    /// the same key is refused at once (no second prompt, nothing sent).
    public func confirmOnce(key: String, reason: String, perform: @escaping () -> Void, refuse: @escaping () -> Void) {
        self.lock.lock()
        let isNew = self.pending.insert(key).inserted
        self.lock.unlock()
        guard isNew else {
            refuse()
            return
        }
        self.confirm(reason: reason, completion: { [weak self] approved in
            if let self {
                self.lock.lock()
                self.pending.remove(key)
                self.lock.unlock()
            }
            if approved {
                perform()
            } else {
                refuse()
            }
        })
    }

    /// Whether a prompt for this key is on screen.
    public func isPending(_ key: String) -> Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.pending.contains(key)
    }

    /// One key per button press: the message and the button's callback data.
    public static func key(messageId: String, callbackData: Data) -> String {
        return messageId + "|" + callbackData.base64EncodedString()
    }

    public func grant(_ key: String) {
        self.lock.lock()
        defer { self.lock.unlock() }
        let now = self.now()
        self.grants = self.grants.filter { $0.value > now }
        self.grants[key] = now.addingTimeInterval(HarnessgramOwnerConfirmation.grantLifetime)
    }

    /// True once per grant, while it is fresh.
    public func consume(_ key: String) -> Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        guard let expiry = self.grants.removeValue(forKey: key) else {
            return false
        }
        return expiry > self.now()
    }

    /// `completion` runs on the main queue with true only after a successful owner authentication.
    public func confirm(reason: String, policy: Policy = .ownerAuthentication, completion: @escaping (Bool) -> Void) {
        let authenticator = policy == .biometrics ? self.biometricAuthenticator : self.authenticator
        authenticator(reason, { success in
            if Thread.isMainThread {
                completion(success)
            } else {
                DispatchQueue.main.async {
                    completion(success)
                }
            }
        })
    }

    /// The device's own owner check: Face ID, falling back to the passcode. No biometrics and no passcode, a
    /// cancel or an error all mean false.
    public static func deviceOwnerAuthentication(reason: String, completion: @escaping (Bool) -> Void) {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            DispatchQueue.main.async {
                completion(false)
            }
            return
        }
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason, reply: { success, _ in
            DispatchQueue.main.async {
                completion(success)
            }
        })
    }

    /// Face ID only: no Touch ID, no passcode fallback and no fallback button. No enrolled biometrics, a cancel or an
    /// error all mean false.
    public static func deviceBiometricAuthentication(reason: String, completion: @escaping (Bool) -> Void) {
        let context = LAContext()
        context.localizedFallbackTitle = ""
        var error: NSError?
        // Face ID only: a fingerprint (Touch ID) is not the owner's face check this path promises.
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error), HarnessgramOwnerConfirmation.isFaceID(context.biometryType) else {
            DispatchQueue.main.async {
                completion(false)
            }
            return
        }
        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason, reply: { success, _ in
            DispatchQueue.main.async {
                completion(success)
            }
        })
    }

    /// The biometrics policy accepts Face ID only (pure, unit tested).
    public static func isFaceID(_ type: LABiometryType) -> Bool {
        return type == .faceID
    }

    /// The system prompt's line: names the button when it has a readable title.
    public static func reason(buttonTitle: String?) -> String {
        let title = (buttonTitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty {
            return HarnessgramAgentStrings.string(.confirmSensitiveReason)
        }
        return HarnessgramAgentStrings.string(.confirmSensitiveReasonNamed, ["action": String(title.prefix(60))])
    }
}
