import Foundation
import HarnessgramCockpitKit

/// What the native Cockpit's home shows, from the sync's state (pure, so tests and previews build it directly).
enum NativeCockpitHome: Equatable {
    struct QuotaRow: Equatable, Identifiable {
        let id: String
        let label: String
        let used: String
        let detail: String
        /// 0 ... 1 for the bar; nil without a reading.
        let fraction: Double?
    }

    enum Radio: Equatable {
        case on
        case off
        case notSetUp
        case unknown
    }

    struct Content: Equatable {
        let working: Int
        let waitingSessions: Int
        let idle: Int
        let decisions: Int
        let waitingTotal: Int?
        let quota: [QuotaRow]
        let radio: Radio
        let updated: Date
    }

    /// No session, or paused after an account change: the connect button.
    case disconnected(paused: Bool)
    case loading
    /// Connected, but the last read failed: why, and when the next try goes when the bridge asked to wait.
    case unavailable(reason: String, retryIn: TimeInterval?)
    case content(Content)

    static func make(screen: HarnessgramCockpitScreen?, isConnected: Bool, isPaused: Bool, failure: HarnessgramPairFailure?, retryIn: TimeInterval?, now: Date) -> NativeCockpitHome {
        if isPaused {
            return .disconnected(paused: true)
        }
        guard isConnected else {
            return .disconnected(paused: false)
        }
        guard let screen else {
            if let failure {
                return .unavailable(reason: failure.text, retryIn: failure == .panelBusy ? retryIn : nil)
            }
            return .loading
        }
        let quota = screen.quota.map { item -> QuotaRow in
            var parts: [String] = []
            if let resets = item.resetsAt {
                parts.append(NativeCockpitStrings.t(.quotaResets) + " " + NativeCockpitFormat.relative(resets, now: now))
            }
            if let banked = item.banked, banked > 0 {
                parts.append(NativeCockpitStrings.t(.quotaBanked) + ": " + NativeCockpitFormat.count(banked))
            }
            return QuotaRow(
                id: item.account,
                label: item.label,
                used: item.weekly.map { NativeCockpitFormat.percent($0) } ?? "—",
                detail: parts.joined(separator: " · "),
                fraction: item.weekly.map { min(1.0, max(0.0, Double($0) / 100.0)) }
            )
        }
        let radio: Radio
        if let value = screen.radio {
            radio = !value.enabled ? .notSetUp : (value.on ? .on : .off)
        } else {
            radio = .unknown
        }
        return .content(Content(
            working: screen.sessions.working,
            waitingSessions: screen.sessions.waiting,
            idle: screen.sessions.idle,
            decisions: screen.decisions.count,
            waitingTotal: screen.waitingCount,
            quota: quota,
            radio: radio,
            updated: screen.now
        ))
    }
}

/// Where one answer stands on the decision screen.
enum NativeDecisionAnswerState: Equatable {
    case idle
    case sending(HarnessgramCockpitLinks.Choice)
    case finished(HarnessgramDecisionAnswer.Result, choice: HarnessgramCockpitLinks.Choice)

    /// The result's lines: the headline and, for a delivery, its live state from the panel's receipts.
    static func lines(result: HarnessgramDecisionAnswer.Result, choice: HarnessgramCockpitLinks.Choice, live: HarnessgramCockpitScreen.Delivery?) -> [String] {
        switch result {
        case let .sent(_, delivery):
            let state = live?.state ?? delivery
            var lines = [NativeCockpitStrings.t(.resultSent) + " (" + answer(choice) + ")", deliveryText(state)]
            if live?.retrying == true {
                lines.append(NativeCockpitStrings.t(.resultRetrying))
            }
            return lines
        case let .alreadyClosed(earlier):
            if let earlier {
                return [NativeCockpitStrings.t(.resultClosedChoice) + " " + answer(earlier)]
            }
            return [NativeCockpitStrings.t(.resultClosed)]
        case .notConfirmed:
            return [NativeCockpitStrings.t(.resultNotConfirmed)]
        case .cancelledLocally:
            return [NativeCockpitStrings.t(.resultCancelledLocally)]
        case .loginExpired:
            return [NativeCockpitStrings.t(.resultLoginExpired)]
        case .busy:
            return [NativeCockpitStrings.t(.resultBusy)]
        case .notAllowed:
            return [NativeCockpitStrings.t(.resultNotAllowed)]
        case .failed:
            return [NativeCockpitStrings.t(.resultFailed)]
        }
    }

    /// Whether the owner may try again after this result (the decision is still open on the bridge).
    static func mayRetry(_ result: HarnessgramDecisionAnswer.Result) -> Bool {
        switch result {
        case .notConfirmed, .cancelledLocally, .loginExpired, .busy, .failed:
            return true
        case .sent, .alreadyClosed, .notAllowed:
            return false
        }
    }

    static func answer(_ choice: HarnessgramCockpitLinks.Choice) -> String {
        return NativeCockpitStrings.t(choice == .yes ? .answeredYes : .answeredNo)
    }

    static func deliveryText(_ state: HarnessgramCockpitScreen.DeliveryState) -> String {
        switch state {
        case .delivered: return NativeCockpitStrings.t(.resultDelivered)
        case .inFlight: return NativeCockpitStrings.t(.resultInFlight)
        case .queued: return NativeCockpitStrings.t(.resultQueued)
        case .cancelled: return NativeCockpitStrings.t(.resultCancelled)
        case .unknown: return NativeCockpitStrings.t(.resultUnknown)
        }
    }
}
