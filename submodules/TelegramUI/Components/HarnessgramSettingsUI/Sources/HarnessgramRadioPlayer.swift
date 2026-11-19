import Foundation
import UIKit
import AVFoundation
import MediaPlayer
import Combine
import UserNotifications
import SwiftSignalKit
import TelegramAudio
import AccountContext
import HarnessgramSettings

/// The team radio: an AVPlayer on the bridge's HLS stream. It plays through Telegram's managed audio
/// session, keeps playing in the background, shows on the lock screen and in Control Center, and pauses
/// and resumes around voice notes and calls by HarnessgramRadioResumePolicy (always at the live edge).
public final class HarnessgramRadioPlayer: NSObject, ObservableObject, @unchecked Sendable {
    public static let shared = HarnessgramRadioPlayer()

    /// userInfo key of the "Resume the radio" notification; AppDelegate resumes on its tap.
    public static let resumeNotificationKey = "harnessgramRadioResume"

    public typealias State = HarnessgramRadioPlaybackState.State

    @Published public private(set) var state: State = .stopped {
        didSet { self.updateTitlePolling() }
    }
    @Published public private(set) var liveTitle: String?
    private let titleSession = URLSession(configuration: .ephemeral, delegate: HarnessgramRadioNoRedirect(), delegateQueue: nil)
    private var titleTimer: Foundation.Timer?
    private var titleTask: URLSessionDataTask?
    private var titleGeneration = 0
    private var settingsObserver: NSObjectProtocol?

    private var policy = HarnessgramRadioResumePolicy()
    private var playback = HarnessgramRadioPlaybackState()
    private var audioSessionRef: ManagedAudioSession?
    private var player: AVPlayer?
    private var playerGeneration = 0
    private var itemStatusObservation: NSKeyValueObservation?
    private var timeControlObservation: NSKeyValueObservation?
    private var audioSessionDisposable: Disposable?
    private var audioSessionToken = 0
    private var remoteTargets: [(MPRemoteCommand, Any)] = []
    /// The lock-screen / Control Center commands the radio borrows: play, pause and toggle on; skip, seek,
    /// next/previous and stop off (a live stream cannot honour them). Given back when the radio lets go, keeping
    /// any change Telegram's own player made meanwhile.
    private let commandOwnership = HarnessgramCommandOwnership<MPRemoteCommand>()
    /// Build 23: the owner's control tower at sunset (bundled); the drawn mark only if the image is missing.
    private lazy var artwork: MPMediaItemArtwork? = {
        let uiImage: UIImage
        if let bundled = UIImage(named: HarnessgramRadioArtwork.bundledImageName) {
            uiImage = bundled
        } else if let image = HarnessgramRadioArtwork.image(pixels: 600) {
            uiImage = UIImage(cgImage: image)
        } else {
            return nil
        }
        return MPMediaItemArtwork(boundsSize: uiImage.size, requestHandler: { _ in uiImage })
    }()
    private var retryTimer: Foundation.Timer?
    private var watchdogTimer: Foundation.Timer?
    private var failObserver: NSObjectProtocol?
    private var stallObserver: NSObjectProtocol?
    private var endObserver: NSObjectProtocol?
    private var interruptionObserver: NSObjectProtocol?

    private override init() {
        super.init()
        self.settingsObserver = NotificationCenter.default.addObserver(forName: HarnessgramSettings.didChangeNotification, object: nil, queue: .main, using: { [weak self] _ in
            self?.updateTitlePolling()
        })
        self.interruptionObserver = NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: AVAudioSession.sharedInstance(), queue: .main, using: { [weak self] notification in
            self?.systemInterruption(notification)
        })
    }

    private var now: Double {
        return ProcessInfo.processInfo.systemUptime
    }

    public var isActive: Bool {
        switch self.state {
        case .connecting, .playing:
            return true
        case .stopped, .paused, .failed:
            return false
        }
    }

    public func toggle(audioSession: ManagedAudioSession) {
        if self.isActive {
            self.pause()
        } else {
            self.play(audioSession: audioSession)
        }
    }

    /// Starts (or resumes) the stream from the saved listen link. Without a valid link nothing plays.
    public func play(audioSession: ManagedAudioSession) {
        assert(Thread.isMainThread)
        guard HarnessgramRadioLink.streamURL(fromListenLink: HarnessgramRadioLink.load()) != nil else {
            self.stop()
            return
        }
        self.pausePlayerOnly()
        self.playback.start()
        self.audioSessionRef = audioSession
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [HarnessgramRadioPlayer.resumeNotificationKey])
        self.perform(self.policy.userPlay())
    }

    public func pause() {
        assert(Thread.isMainThread)
        self.perform(self.policy.userPause())
        self.releaseAudioSession()
    }

    /// Stops and forgets the player, the lock-screen entry and the remote commands.
    public func stop() {
        assert(Thread.isMainThread)
        self.policy.stop()
        self.pausePlayerOnly()
        self.releaseAudioSession()
        self.player = nil
        self.itemStatusObservation = nil
        self.timeControlObservation = nil
        self.removeItemObservers()
        self.removeRemoteCommands()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        self.playback.stop()
        self.publishPlaybackState()
        self.liveTitle = nil
    }

    private func perform(_ action: HarnessgramRadioResumePolicy.Action) {
        switch action {
        case .none:
            break
        case .startAtLiveEdge:
            if let url = HarnessgramRadioLink.streamURL(fromListenLink: HarnessgramRadioLink.load()) {
                if self.playback.state == .paused {
                    self.playback.start()
                }
                self.playback.sessionActivated(at: self.now)
                self.publishPlaybackState()
                self.startPlayer(url: url)
            } else {
                self.stop()
            }
        case .pause:
            self.pausePlayerOnly()
        case .reactivateSession:
            if self.playback.state == .paused {
                self.playback.start()
            }
            self.publishPlaybackState()
            self.registerAudioSession()
        case .offerResume:
            self.pausePlayerOnly()
            self.releaseAudioSession()
            self.offerResume()
        }
    }

    /// One registration with Telegram's managed audio session. It is kept (not `once`) while another holder
    /// (a voice note, a call) has the session, so the manager makes it active again afterwards; the token
    /// ignores callbacks of an older registration. A .play registration waits behind an active .record
    /// holder, so manual play and interruption/notification resumes cannot take the camera's session.
    private func registerAudioSession() {
        guard let audioSession = self.audioSessionRef else {
            return
        }
        self.releaseAudioSession()
        self.audioSessionToken += 1
        let token = self.audioSessionToken
        self.audioSessionDisposable = audioSession.push(audioSessionType: .play(mixWithOthers: false), manualActivate: { [weak self] control in
            control.setupAndActivate { _ in
                // The manager swallows setActive errors. Check on its serial queue while this holder is
                // still active, never on the main queue where a camera recording could have taken over.
                let activated: Bool
                do {
                    try AVAudioSession.sharedInstance().setActive(true)
                    activated = true
                } catch {
                    activated = false
                }
                Queue.mainQueue().async {
                    guard let self, self.audioSessionToken == token else { return }
                    let action = self.policy.sessionActivated(at: self.now, isRecordingActive: self.audioSessionRef?.getIsRecordingActive() ?? false)
                    if !activated, action == .startAtLiveEdge {
                        if self.playback.state == .paused {
                            self.playback.start()
                        }
                        self.scheduleRetry(after: .audioSession)
                        return
                    }
                    if activated {
                        self.installRemoteCommands()
                    }
                    self.perform(action)
                }
            }
        }, deactivate: { [weak self] _ in
            return Signal { subscriber in
                Queue.mainQueue().async {
                    if let self, self.audioSessionToken == token {
                        self.perform(self.policy.sessionDeactivated(at: self.now))
                        // Whoever holds the session now (Telegram's player, a call) owns the lock-screen commands.
                        self.removeRemoteCommands()
                    }
                    subscriber.putCompletion()
                }
                return EmptyDisposable
            }
        })
    }

    private func releaseAudioSession() {
        self.audioSessionToken += 1
        self.audioSessionDisposable?.dispose()
        self.audioSessionDisposable = nil
    }

    private func systemInterruption(_ notification: Notification) {
        guard let info = notification.userInfo, let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt, let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }
        switch type {
        case .began:
            self.perform(self.policy.systemInterruptionBegan(at: self.now))
        case .ended:
            let options = (info[AVAudioSessionInterruptionOptionKey] as? UInt).map(AVAudioSession.InterruptionOptions.init(rawValue:)) ?? []
            self.perform(self.policy.systemInterruptionEnded(at: self.now, shouldResume: options.contains(.shouldResume)))
        @unknown default:
            break
        }
    }

    private func offerResume() {
        self.publishPlaybackState()
        // The lock screen and Control Center keep a play button; a notification offers the same tap.
        self.installRemoteCommands()
        let content = UNMutableNotificationContent()
        content.title = HarnessgramStrings.t(.radioStation)
        content.body = HarnessgramStrings.t(.radioResumeOffer)
        content.userInfo = [HarnessgramRadioPlayer.resumeNotificationKey: true]
        let request = UNNotificationRequest(identifier: HarnessgramRadioPlayer.resumeNotificationKey, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    private func pausePlayerOnly() {
        self.playerGeneration += 1
        self.retryTimer?.invalidate()
        self.retryTimer = nil
        self.watchdogTimer?.invalidate()
        self.watchdogTimer = nil
        self.itemStatusObservation = nil
        self.timeControlObservation = nil
        self.removeItemObservers()
        self.player?.pause()
        if self.playback.state != .stopped {
            self.playback.pause()
        }
        self.publishPlaybackState()
    }

    private func startPlayer(url: URL) {
        self.playerGeneration += 1
        self.itemStatusObservation = nil
        self.timeControlObservation = nil
        self.removeItemObservers()
        // A live stream always restarts at the live edge: a fresh item, never the paused buffer.
        let item = AVPlayerItem(url: url)
        item.preferredForwardBufferDuration = 8.0
        // A title the stream carries (timed ID3 / HLS metadata) names what the radio is on now; until then, and
        // when it carries none, the lock screen shows the station.
        self.liveTitle = nil
        let metadataOutput = AVPlayerItemMetadataOutput(identifiers: nil)
        metadataOutput.setDelegate(self, queue: .main)
        item.add(metadataOutput)
        let player = self.player ?? AVPlayer()
        player.automaticallyWaitsToMinimizeStalling = true
        player.replaceCurrentItem(with: item)
        self.player = player
        let token = self.audioSessionToken
        let generation = self.playerGeneration
        self.itemStatusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            DispatchQueue.main.async {
                guard let self, self.audioSessionToken == token, self.playerGeneration == generation, self.player?.currentItem === item else { return }
                if item.status == .failed {
                    self.scheduleRetry(after: .stream)
                }
            }
        }
        self.timeControlObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            DispatchQueue.main.async {
                guard let self, self.audioSessionToken == token, self.playerGeneration == generation, self.player === player, player.currentItem === item else {
                    return
                }
                guard item.status != .failed else {
                    self.scheduleRetry(after: .stream)
                    return
                }
                switch player.timeControlStatus {
                case .playing:
                    self.playback.observe(.playing, at: self.now)
                    // Telegram's media manager switches these off globally when its own player stops.
                    self.enableRemoteCommands()
                case .waitingToPlayAtSpecifiedRate:
                    self.playback.observe(.waiting, at: self.now)
                case .paused:
                    // A pause from outside our controls is also a real pause, never a reason to auto-play.
                    self.pause()
                @unknown default:
                    self.playback.observe(.waiting, at: self.now)
                }
                self.publishPlaybackState()
            }
        }
        self.failObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main, using: { [weak self] _ in
            guard let self, self.audioSessionToken == token, self.playerGeneration == generation, self.player?.currentItem === item else { return }
            self.scheduleRetry(after: .stream)
        })
        self.stallObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemPlaybackStalled, object: item, queue: .main, using: { [weak self] _ in
            guard let self, self.audioSessionToken == token, self.playerGeneration == generation, self.player?.currentItem === item else { return }
            self.playback.observe(.waiting, at: self.now)
            self.publishPlaybackState()
        })
        self.endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main, using: { [weak self] _ in
            guard let self, self.audioSessionToken == token, self.playerGeneration == generation, self.player?.currentItem === item else { return }
            self.scheduleRetry(after: .stream)
        })
        player.play()
        self.publishPlaybackState()
    }

    private func removeItemObservers() {
        if let failObserver = self.failObserver {
            NotificationCenter.default.removeObserver(failObserver)
            self.failObserver = nil
        }
        if let stallObserver = self.stallObserver {
            NotificationCenter.default.removeObserver(stallObserver)
            self.stallObserver = nil
        }
        if let endObserver = self.endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
    }

    /// Three reconnects (2, 4, 8 s). Brief bursts of audio do not replenish the retry budget.
    private func scheduleRetry(after failure: HarnessgramRadioPlaybackState.Failure) {
        guard self.retryTimer == nil, self.policy.phase == .playing || self.policy.phase == .starting else {
            return
        }
        let delay = self.playback.retry(after: failure, at: self.now)
        self.playerGeneration += 1
        self.watchdogTimer?.invalidate()
        self.watchdogTimer = nil
        self.itemStatusObservation = nil
        self.timeControlObservation = nil
        self.removeItemObservers()
        self.player?.pause()
        self.releaseAudioSession()
        self.publishPlaybackState()
        // Keep Retry available on the lock screen even when the first activation failed.
        self.installRemoteCommands()
        guard let delay else {
            _ = self.policy.userPause()
            return
        }
        self.retryTimer = Foundation.Timer.scheduledTimer(withTimeInterval: delay, repeats: false, block: { [weak self] timer in
            guard let self, self.retryTimer === timer else { return }
            self.retryTimer = nil
            guard self.playback.beginRetry() else { return }
            // Re-enter the same managed-session path as every manual/remote Play; recordings keep the hold.
            self.perform(self.policy.userPlay())
        })
    }

    private func publishPlaybackState() {
        self.state = self.playback.state
        self.updateNowPlaying()
        if let delay = self.playback.stallDelay(at: self.now) {
            guard self.watchdogTimer == nil else { return }
            let token = self.audioSessionToken
            self.watchdogTimer = Foundation.Timer.scheduledTimer(withTimeInterval: delay, repeats: false, block: { [weak self] timer in
                guard let self, self.audioSessionToken == token, self.watchdogTimer === timer else { return }
                self.watchdogTimer = nil
                if self.playback.isStalled(at: self.now) {
                    self.scheduleRetry(after: .stalled)
                }
            })
        } else {
            self.watchdogTimer?.invalidate()
            self.watchdogTimer = nil
        }
    }

    /// Poll only during playback and only for the House screen. The listen token stays in memory.
    private func updateTitlePolling() {
        guard self.state == .playing, HarnessgramSettings.shared.houseFeature(.radioScreen) else {
            self.titleTimer?.invalidate()
            self.titleTimer = nil
            self.titleTask?.cancel()
            self.titleTask = nil
            self.titleGeneration += 1
            return
        }
        guard self.titleTimer == nil else { return }
        self.fetchLiveTitle()
        self.titleTimer = Foundation.Timer.scheduledTimer(withTimeInterval: 20.0, repeats: true, block: { [weak self] _ in
            self?.fetchLiveTitle()
        })
    }

    private func fetchLiveTitle() {
        guard self.titleTask == nil, let stream = HarnessgramRadioLink.streamURL(fromListenLink: HarnessgramRadioLink.load()) else { return }
        let url = stream.deletingLastPathComponent().appendingPathComponent("now.json")
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15.0)
        request.httpMethod = "GET"
        let generation = self.titleGeneration
        self.titleTask = self.titleSession.dataTask(with: request, completionHandler: { [weak self] data, response, _ in
            Queue.mainQueue().async {
                guard let self, self.titleGeneration == generation else { return }
                self.titleTask = nil
                guard self.state == .playing, HarnessgramSettings.shared.houseFeature(.radioScreen),
                      let response = response as? HTTPURLResponse, response.statusCode == 200,
                      response.url == url, let data, data.count <= 16384,
                      let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                      let value = object["title"] as? String else { return }
                let title = value.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: .newlines).first ?? ""
                self.liveTitle = title.isEmpty ? nil : String(title.prefix(80))
                self.updateNowPlaying()
            }
        })
        self.titleTask?.resume()
    }

    private func updateNowPlaying() {
        guard self.state != .stopped else {
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: self.state == .playing ? (self.liveTitle ?? HarnessgramNowPlaying.Strings.title) : self.stateText,
            // The station's name as the artist and the album (build 23): the lock screen and the car show it.
            MPMediaItemPropertyArtist: HarnessgramNowPlaying.Strings.title,
            MPMediaItemPropertyAlbumTitle: HarnessgramNowPlaying.Strings.title,
            MPNowPlayingInfoPropertyIsLiveStream: true,
            MPNowPlayingInfoPropertyPlaybackRate: (self.state == .playing ? 1.0 : 0.0) as NSNumber
        ]
        if let artwork = self.artwork {
            info[MPMediaItemPropertyArtwork] = artwork
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func enableRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        let live: [MPRemoteCommand] = [center.skipForwardCommand, center.skipBackwardCommand, center.seekForwardCommand, center.seekBackwardCommand, center.changePlaybackPositionCommand, center.changePlaybackRateCommand, center.nextTrackCommand, center.previousTrackCommand, center.stopCommand]
        self.commandOwnership.take(enabled: self.remoteTargets.map { $0.0 }, disabled: live)
    }

    /// Remote commands may arrive off the main thread; the player is main-thread only.
    private static func onMain(_ body: @escaping () -> Void) -> MPRemoteCommandHandlerStatus {
        if Thread.isMainThread {
            body()
        } else {
            DispatchQueue.main.async(execute: body)
        }
        return .success
    }

    private func installRemoteCommands() {
        guard self.remoteTargets.isEmpty else {
            self.enableRemoteCommands()
            return
        }
        let center = MPRemoteCommandCenter.shared()
        let play = center.playCommand.addTarget { [weak self] _ in
            return HarnessgramRadioPlayer.onMain {
                guard let self, let audioSession = self.audioSessionRef else {
                    return
                }
                self.play(audioSession: audioSession)
            }
        }
        let pause = center.pauseCommand.addTarget { [weak self] _ in
            return HarnessgramRadioPlayer.onMain {
                self?.pause()
            }
        }
        let toggle = center.togglePlayPauseCommand.addTarget { [weak self] _ in
            return HarnessgramRadioPlayer.onMain {
                guard let self, let audioSession = self.audioSessionRef else {
                    return
                }
                self.toggle(audioSession: audioSession)
            }
        }
        self.remoteTargets = [(center.playCommand, play), (center.pauseCommand, pause), (center.togglePlayPauseCommand, toggle)]
        self.enableRemoteCommands()
    }

    private func removeRemoteCommands() {
        for (command, target) in self.remoteTargets {
            command.removeTarget(target)
        }
        self.remoteTargets = []
        self.commandOwnership.release()
    }
}

extension HarnessgramRadioPlayer: AVPlayerItemMetadataOutputPushDelegate {
    public func metadataOutput(_ output: AVPlayerItemMetadataOutput, didOutputTimedMetadataGroups groups: [AVTimedMetadataGroup], from track: AVPlayerItemTrack?) {
        guard !HarnessgramSettings.shared.houseFeature(.radioScreen), let title = HarnessgramRadioPlayer.streamTitle(groups.flatMap { $0.items }), title != self.liveTitle else {
            return
        }
        self.liveTitle = title
        self.updateNowPlaying()
    }

    /// The first title in the stream's metadata (ID3 TIT2, the common title or an ICY StreamTitle), trimmed
    /// to one short line.
    static func streamTitle(_ items: [AVMetadataItem]) -> String? {
        for item in items {
            let isTitle = item.commonKey == .commonKeyTitle || item.identifier == .id3MetadataTitleDescription || item.identifier == .icyMetadataStreamTitle
            guard isTitle, let value = item.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
                continue
            }
            let line = value.components(separatedBy: .newlines).first ?? value
            return String(line.prefix(80))
        }
        return nil
    }
}

extension MPRemoteCommand: @retroactive HarnessgramRemoteCommandSwitch {
}


/// A private listen URL must never be followed to a different server.
private final class HarnessgramRadioNoRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

extension HarnessgramRadioPlayer {
    /// Play or pause with the account's audio session (the Cockpit tab's radio row, build 23).
    public func toggle(context: AccountContext) {
        self.toggle(audioSession: context.sharedContext.mediaManager.audioSession)
    }

    /// A listen link is saved on this device (without one nothing can play).
    public var hasListenLink: Bool {
        return HarnessgramRadioLink.load() != nil
    }

    /// The state in plain Hebrew ("משדר", "מושהה", ...).
    public var stateText: String {
        if self.state == .failed {
            switch self.playback.failure {
            case .audioSession:
                return "לא ניתן להפעיל את השמע. אפשר לנסות שוב."
            case .stream, .stalled, .none:
                return "החיבור לשידורים נכשל. אפשר לנסות שוב."
            }
        }
        return harnessgramRadioStateText(self.state)
    }

    var buttonTitle: String {
        switch self.state {
        case .connecting:
            return "ביטול החיבור"
        case .playing:
            return HarnessgramStrings.t(.radioPause)
        case .failed:
            return "ניסיון נוסף"
        case .stopped, .paused:
            return HarnessgramStrings.t(.radioPlay)
        }
    }
}
