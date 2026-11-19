import Foundation

/// Playback truth and bounded recovery, independent of AVFoundation and the audio-session resume policy.
public struct HarnessgramRadioPlaybackState {
    public enum State: Equatable {
        case stopped
        case connecting
        case playing
        case paused
        case failed
    }

    enum Status {
        case paused
        case waiting
        case playing
    }

    enum Failure: Equatable {
        case audioSession
        case stream
        case stalled
    }

    static let stallTimeout: Double = 15.0
    static let stablePlaybackDuration: Double = 30.0
    private(set) var state: State = .stopped
    private(set) var failure: Failure?
    private(set) var retryCount = 0
    private(set) var retryPending = false
    private var requested = false
    private var sessionActive = false
    private var waitingSince: Double?
    private var playingSince: Double?

    mutating func start() {
        self = HarnessgramRadioPlaybackState()
        self.requested = true
        self.state = .connecting
    }

    mutating func sessionActivated(at time: Double) {
        guard self.requested, !self.retryPending else { return }
        self.sessionActive = true
        self.waitingSince = time
    }

    mutating func observe(_ status: Status, at time: Double) {
        guard self.requested, self.sessionActive, !self.retryPending else { return }
        switch status {
        case .playing:
            if self.playingSince == nil { self.playingSince = time }
            self.waitingSince = nil
            self.failure = nil
            self.state = .playing
        case .waiting:
            self.resetRetriesIfStable(at: time)
            self.playingSince = nil
            if self.waitingSince == nil { self.waitingSince = time }
            self.state = .connecting
        case .paused:
            self.pause()
        }
    }

    func isStalled(at time: Double) -> Bool {
        return self.stallDelay(at: time) == 0.0
    }

    func stallDelay(at time: Double) -> Double? {
        guard self.requested, self.sessionActive, !self.retryPending, let since = self.waitingSince else { return nil }
        return max(0.0, Self.stallTimeout - (time - since))
    }

    /// Duplicate failures and late playback events cannot restart or postpone a pending recovery.
    mutating func retry(after failure: Failure, at time: Double) -> Double? {
        guard self.requested, !self.retryPending else { return nil }
        self.resetRetriesIfStable(at: time)
        self.failure = failure
        self.state = .failed
        self.sessionActive = false
        self.waitingSince = nil
        self.playingSince = nil
        guard self.retryCount < 3 else {
            self.requested = false
            return nil
        }
        let delay = pow(2.0, Double(self.retryCount + 1))
        self.retryCount += 1
        self.retryPending = true
        return delay
    }

    mutating func beginRetry() -> Bool {
        guard self.requested, self.retryPending else { return false }
        self.retryPending = false
        self.failure = nil
        self.state = .connecting
        return true
    }

    mutating func pause() {
        self.requested = false
        self.sessionActive = false
        self.retryPending = false
        self.waitingSince = nil
        self.playingSince = nil
        self.failure = nil
        self.state = .paused
    }

    mutating func stop() {
        self = HarnessgramRadioPlaybackState()
    }

    private mutating func resetRetriesIfStable(at time: Double) {
        if let since = self.playingSince, time - since >= Self.stablePlaybackDuration {
            self.retryCount = 0
        }
    }
}
