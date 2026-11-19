import Foundation
import SwiftSignalKit
import TelegramCore
import AccountContext
import UniversalMediaPlayer
import TelegramUIPreferences
import HarnessgramSettings

/// Harnessgram (build 18): the team radio in Telegram's own now-playing bar, behind the House "radioScreen" switch.
/// The radio is not one of Telegram's playlists, so the bar is given a stand-in item for it; its buttons go to the
/// radio through HarnessgramNowPlaying (MediaPlaybackHeaderPanelComponent).
public struct HarnessgramRadioPlaylistItemId: SharedMediaPlaylistItemId {
    public init() {
    }

    public func isEqual(to: SharedMediaPlaylistItemId) -> Bool {
        return to is HarnessgramRadioPlaylistItemId
    }
}

public struct HarnessgramRadioPlaylistId: SharedMediaPlaylistId {
    public init() {
    }

    public func isEqual(to: SharedMediaPlaylistId) -> Bool {
        return to is HarnessgramRadioPlaylistId
    }
}

public struct HarnessgramRadioPlaylistLocation: SharedMediaPlaylistLocation {
    public init() {
    }

    public func isEqual(to: SharedMediaPlaylistLocation) -> Bool {
        return to is HarnessgramRadioPlaylistLocation
    }
}

public struct HarnessgramRadioPlaylistItem: SharedMediaPlaylistItem {
    /// The live title, when the radio says what it is on (shown over the station name).
    public let liveTitle: String?

    public init(liveTitle: String? = nil) {
        self.liveTitle = liveTitle
    }

    public var stableId: AnyHashable {
        return AnyHashable(HarnessgramNowPlaying.radioItemKey)
    }

    public var id: SharedMediaPlaylistItemId {
        return HarnessgramRadioPlaylistItemId()
    }

    public var playbackData: SharedMediaPlaybackData? {
        return nil
    }

    public var displayData: SharedMediaPlaybackDisplayData? {
        let lines = HarnessgramNowPlaying.barLines(liveTitle: self.liveTitle)
        return .music(title: lines.title, performer: lines.subtitle, albumArt: nil, long: false, caption: nil)
    }
}

/// Whether the bar's item is the radio's stand-in.
public func harnessgramIsRadioItem(_ item: SharedMediaPlaylistItem?) -> Bool {
    return item?.stableId == AnyHashable(HarnessgramNowPlaying.radioItemKey)
}

/// The radio as the bar sees it: nil when the bar must not show it (switch off, radio stopped).
struct HarnessgramRadioBarState: Equatable {
    var isPlaying: Bool
    var liveTitle: String?
}

func harnessgramRadioBarState() -> Signal<HarnessgramRadioBarState?, NoError> {
    return Signal { subscriber in
        let current: () -> HarnessgramRadioBarState? = {
            guard HarnessgramSettings.shared.houseFeature(.radioScreen), let source = HarnessgramNowPlaying.source, source.isActive else {
                return nil
            }
            return HarnessgramRadioBarState(isPlaying: source.isPlaying, liveTitle: source.liveTitle)
        }
        subscriber.putNext(current())
        let center = NotificationCenter.default
        let observers = [HarnessgramNowPlaying.didChangeNotification, HarnessgramSettings.didChangeNotification].map { name in
            center.addObserver(forName: name, object: nil, queue: .main, using: { _ in
                subscriber.putNext(current())
            })
        }
        return ActionDisposable {
            for observer in observers {
                center.removeObserver(observer)
            }
        }
    }
    |> runOn(Queue.mainQueue())
    |> distinctUntilChanged
}

/// The playback status of the radio for the bar's play/pause icon (a live stream: no duration, no position).
public func harnessgramRadioStatus() -> Signal<MediaPlayerStatus, NoError> {
    return harnessgramRadioBarState()
    |> map { state -> Bool in
        return state?.isPlaying == true
    }
    |> distinctUntilChanged
    |> map { playing -> MediaPlayerStatus in
        return MediaPlayerStatus(generationTimestamp: 0.0, duration: 0.0, dimensions: CGSize(), timestamp: 0.0, baseRate: 1.0, seekId: 0, status: playing ? .playing : .paused, soundEnabled: true)
    }
}

/// Telegram's player state with the radio filled in when Telegram plays nothing (HarnessgramNowPlaying.showsRadio).
func harnessgramWithRadio(_ state: Signal<(Account, SharedMediaPlayerItemPlaybackStateOrLoading, MediaManagerPlayerType)?, NoError>, account: Account) -> Signal<(Account, SharedMediaPlayerItemPlaybackStateOrLoading, MediaManagerPlayerType)?, NoError> {
    return combineLatest(queue: Queue.mainQueue(), state, harnessgramRadioBarState())
    |> map { telegram, radio -> (Account, SharedMediaPlayerItemPlaybackStateOrLoading, MediaManagerPlayerType)? in
        guard HarnessgramNowPlaying.showsRadio(enabled: radio != nil, radioActive: radio != nil, telegramPlaying: telegram != nil) else {
            return telegram
        }
        let status = MediaPlayerStatus(generationTimestamp: 0.0, duration: 0.0, dimensions: CGSize(), timestamp: 0.0, baseRate: 1.0, seekId: 0, status: radio?.isPlaying == true ? .playing : .paused, soundEnabled: true)
        let playback = SharedMediaPlayerItemPlaybackState(playlistId: HarnessgramRadioPlaylistId(), playlistLocation: HarnessgramRadioPlaylistLocation(), item: HarnessgramRadioPlaylistItem(liveTitle: radio?.liveTitle), previousItem: nil, nextItem: nil, status: status, order: .regular, looping: .none, playerIndex: 0)
        return (account, .state(playback), .music)
    }
}
