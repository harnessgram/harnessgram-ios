import Foundation

/// Simulator only, for screenshots of logged-in screens before a build goes to TestFlight: with
/// `HARNESSGRAM_TEST_LOGIN=99966XYYYY` (Telegram's test phone numbers; X is the test DC) the app, started with
/// `--harnessgram-test-dc`, runs Telegram's own login screens by itself on the test backend and types the code made of
/// the repeated digit. A device build compiles it out; no real account is ever used.
final class HarnessgramTestLogin {
    static let phone: String? = {
        #if targetEnvironment(simulator)
        guard let value = ProcessInfo.processInfo.environment["HARNESSGRAM_TEST_LOGIN"], value.count == 10, value.hasPrefix("99966"), value.allSatisfy({ $0.isASCII && $0.isNumber }) else {
            return nil
        }
        return value
        #else
        return nil
        #endif
    }()

    static var code: String? {
        guard let phone else {
            return nil
        }
        return String(repeating: phone[phone.index(phone.startIndex, offsetBy: 5)], count: 5)
    }

    /// Seconds before a step runs: HARNESSGRAM_TEST_LOGIN_DELAY (code step) or 2.5.
    static func delay(_ step: String) -> Double {
        if step.hasPrefix("code"), let value = ProcessInfo.processInfo.environment["HARNESSGRAM_TEST_LOGIN_DELAY"].flatMap(Double.init) {
            return value
        }
        return 2.5
    }

    private static let lock = NSLock()
    private static let steps = Steps()

    private final class Steps {
        var done = Set<String>()
    }

    /// Runs `action` once per screen instance (the flow can rebuild a screen), a moment after it appeared.
    static func once(_ step: String, _ screen: AnyObject?, _ action: @escaping () -> Void) {
        guard HarnessgramTestLogin.phone != nil else {
            return
        }
        lock.lock()
        let first = steps.done.insert(screen.map { step + ":\(ObjectIdentifier($0))" } ?? step).inserted
        lock.unlock()
        guard first else {
            return
        }
        NSLog("[HarnessgramTestLogin] \(step)")
        DispatchQueue.main.asyncAfter(deadline: .now() + HarnessgramTestLogin.delay(step), execute: {
            NSLog("[HarnessgramTestLogin] \(step) run")
            action()
        })
    }
}
