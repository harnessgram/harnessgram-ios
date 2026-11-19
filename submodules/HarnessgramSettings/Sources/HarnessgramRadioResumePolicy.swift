import Foundation

/// When the team radio pauses and resumes around voice notes and calls. Pure, so it is unit tested;
/// HarnessgramRadioPlayer feeds it the audio-session events and carries out its actions.
///
/// - Another holder of Telegram's managed audio session (a voice note, a Telegram voice or video call)
///   pauses the radio; when that holder is gone the session comes back and the radio resumes.
/// - A system interruption (a phone call) pauses it; it resumes when the interruption ends with
///   `.shouldResume`. Without `.shouldResume`, or after a pause longer than `autoResumeLimit`, the radio
///   waits for a tap (lock screen, Control Center, the notification or the radio screen).
/// - Every resume starts at the live edge of the stream; old audio is never replayed.
public struct HarnessgramRadioResumePolicy: Equatable {
    public enum Phase: Equatable {
        case off
        case starting
        case playing
        case interrupted(since: Double, system: Bool)
        case paused
        case waitingForTap
    }

    public enum Action: Equatable {
        case none
        /// Start a fresh player item at the live edge (the session is active).
        case startAtLiveEdge
        /// Stop the player now; the session is someone else's.
        case pause
        /// Register with the audio session again; an active recording keeps the registration waiting.
        case reactivateSession
        /// Show "Resume the radio" (notification, lock screen) and wait for a tap.
        case offerResume
    }

    public static let autoResumeLimit: Double = 10.0 * 60.0

    public private(set) var phase: Phase = .off

    public init() {
    }

    /// The owner pressed play (radio screen, lock screen, the resume notification).
    public mutating func userPlay() -> Action {
        self.phase = .starting
        return .reactivateSession
    }

    public mutating func userPause() -> Action {
        if self.phase == .off {
            return .none
        }
        self.phase = .paused
        return .pause
    }

    public mutating func stop() {
        self.phase = .off
    }

    /// The managed audio session made the radio's holder active (first start, or after another holder).
    public mutating func sessionActivated(at time: Double, isRecordingActive: Bool = false) -> Action {
        // A resume (including a manual play) must wait for the recording's hold to end.
        guard !isRecordingActive else {
            return .none
        }
        switch self.phase {
        case .starting:
            self.phase = .playing
            return .startAtLiveEdge
        case let .interrupted(since, system):
            if system {
                // Telegram's session manager reactivates right after a phone call starts; wait for its end.
                return .none
            }
            return self.resume(at: time, since: since, shouldResume: true)
        case .off, .playing, .paused, .waitingForTap:
            return .none
        }
    }

    /// Another holder (a voice note, a Telegram call) took the managed audio session.
    public mutating func sessionDeactivated(at time: Double) -> Action {
        switch self.phase {
        case .playing, .starting:
            self.phase = .interrupted(since: time, system: false)
            return .pause
        case .off, .interrupted, .paused, .waitingForTap:
            return .none
        }
    }

    /// AVAudioSession interruption began (a phone call, an alarm).
    public mutating func systemInterruptionBegan(at time: Double) -> Action {
        switch self.phase {
        case .playing, .starting:
            self.phase = .interrupted(since: time, system: true)
            return .pause
        case let .interrupted(since, _):
            self.phase = .interrupted(since: since, system: true)
            return .none
        case .off, .paused, .waitingForTap:
            return .none
        }
    }

    /// AVAudioSession interruption ended; `shouldResume` is the system's `.shouldResume` option.
    public mutating func systemInterruptionEnded(at time: Double, shouldResume: Bool) -> Action {
        guard case let .interrupted(since, true) = self.phase else {
            return .none
        }
        let action = self.resume(at: time, since: since, shouldResume: shouldResume)
        if action == .startAtLiveEdge {
            // The session must be activated again after a system interruption.
            self.phase = .starting
            return .reactivateSession
        }
        return action
    }

    private mutating func resume(at time: Double, since: Double, shouldResume: Bool) -> Action {
        if !shouldResume || time - since > HarnessgramRadioResumePolicy.autoResumeLimit {
            self.phase = .waitingForTap
            return .offerResume
        }
        self.phase = .playing
        return .startAtLiveEdge
    }
}
