import Foundation
import Combine
import Display
import AccountContext
import HarnessgramSettings
import HarnessgramSettingsUI

/// Harnessgram (build 18): hands the team radio to Telegram's now-playing bar through HarnessgramNowPlaying, so the bar
/// modules never depend on HarnessgramSettingsUI. It only reads and drives HarnessgramRadioPlayer.shared.
final class HarnessgramRadioNowPlayingSource: HarnessgramNowPlayingSource {
    static let shared = HarnessgramRadioNowPlayingSource()

    private var stateObservation: AnyCancellable?
    private var titleObservation: AnyCancellable?
    private weak var context: AccountContext?
    private weak var navigationController: NavigationController?

    private init() {
        // @Published sends before the value changes: read it on the next main-queue turn.
        self.stateObservation = HarnessgramRadioPlayer.shared.$state
        .receive(on: DispatchQueue.main)
        .sink(receiveValue: { _ in
            HarnessgramNowPlaying.notifyChanged()
        })
        // The live title (now.json or the stream's own) shows in the bar too.
        self.titleObservation = HarnessgramRadioPlayer.shared.$liveTitle
        .receive(on: DispatchQueue.main)
        .sink(receiveValue: { _ in
            HarnessgramNowPlaying.notifyChanged()
        })
    }

    var liveTitle: String? {
        let radio = HarnessgramRadioPlayer.shared
        return radio.state == .playing ? radio.liveTitle : radio.stateText
    }

    /// The logged-in context and the root navigation the Radio screen opens in (nil when logged out).
    func attach(context: AccountContext?, navigationController: NavigationController?) {
        self.context = context
        self.navigationController = navigationController
        HarnessgramNowPlaying.register(context == nil ? nil : self)
    }

    var isActive: Bool {
        return HarnessgramRadioPlayer.shared.state != .stopped
    }

    var isPlaying: Bool {
        return HarnessgramRadioPlayer.shared.state == .playing
    }

    func togglePlayPause() {
        guard let context = self.context else {
            return
        }
        HarnessgramRadioPlayer.shared.toggle(audioSession: context.sharedContext.mediaManager.audioSession)
    }

    func close() {
        HarnessgramRadioPlayer.shared.stop()
    }

    func open() {
        guard let context = self.context, let navigationController = self.navigationController else {
            return
        }
        navigationController.pushViewController(harnessgramRadioController(context: context))
    }
}
