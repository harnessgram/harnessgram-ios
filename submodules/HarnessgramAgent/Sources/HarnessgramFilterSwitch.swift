import Foundation
import HarnessgramSettings

/// A filter rule's switch in Settings > Harnessgram > "הסינון". Build 21 interim: rules turn on only; turning one off
/// is refused at once (`.committeeOnly`, no Face ID prompt) unless the filter allows personal off (tests). With personal
/// off allowed (build 19 behaviour): off only after Face ID or the passcode; never while a committee lock is in force.
public final class HarnessgramFilterSwitch {
    public enum Outcome: Equatable {
        case changed
        case unchanged
        /// Read-only: "נעול על ידי הוועדה".
        case locked
        /// Turning a rule off is possible only through the committee: refused without a Face ID prompt.
        case committeeOnly
        /// Face ID or the passcode was not confirmed: the rule stays on.
        case notConfirmed
    }

    private let filter: HarnessgramFilterSettings
    private let confirmation: HarnessgramOwnerConfirmation
    private var confirming: Set<HarnessgramFilterRule> = []

    public init(filter: HarnessgramFilterSettings = .shared, confirmation: HarnessgramOwnerConfirmation = .shared) {
        self.filter = filter
        self.confirmation = confirmation
    }

    /// Whether turning `rule` to `on` needs the owner first (only turning a rule off does).
    public static func needsOwner(from current: Bool, to on: Bool) -> Bool {
        return current && !on
    }

    public func set(_ rule: HarnessgramFilterRule, on: Bool, reason: String, completion: @escaping (Outcome) -> Void) {
        if self.filter.isLocked {
            completion(.locked)
            return
        }
        let current = self.filter.isOn(rule)
        guard current != on else {
            completion(.unchanged)
            return
        }
        if !on && !self.filter.allowsPersonalOff {
            completion(.committeeOnly)
            return
        }
        guard HarnessgramFilterSwitch.needsOwner(from: current, to: on) else {
            completion(self.filter.setPersonal(rule, on: on) ? .changed : .locked)
            return
        }
        guard self.confirming.insert(rule).inserted else {
            completion(.unchanged)
            return
        }
        self.confirmation.confirm(reason: reason, completion: { [weak self] confirmed in
            guard let self else {
                return
            }
            self.confirming.remove(rule)
            guard confirmed else {
                completion(.notConfirmed)
                return
            }
            // Checked again after Face ID: a lock that arrived meanwhile wins.
            completion(self.filter.setPersonal(rule, on: false) ? .changed : .locked)
        })
    }
}
