import Foundation

/// Something playing outside Telegram's own media player that Telegram's now-playing bar can show: the team radio
/// ("שידורי הקוקפיט" since build 23).
/// HarnessgramRadioPlayer lives above Telegram's bar modules, so it reaches them through this registry instead of a
/// module dependency (build 18).
public protocol HarnessgramNowPlayingSource: AnyObject {
    /// Started and not stopped (connecting, playing, paused, or reconnecting after a failure).
    var isActive: Bool { get }
    var isPlaying: Bool { get }
    /// What the radio is on now (the bridge's now.json or the stream's own title), when known.
    var liveTitle: String? { get }
    func togglePlayPause()
    /// Stops it and takes the bar away.
    func close()
    /// Opens its own screen (the Radio screen).
    func open()
}

public enum HarnessgramNowPlaying {
    /// The bar item's stable id: Telegram's bar code recognises the radio by it.
    public static let radioItemKey = "harnessgram.radio"

    /// Posted on the main queue when the source's state changes or a source is registered.
    public static let didChangeNotification = Notification.Name("HarnessgramNowPlayingDidChange")

    private static weak var registered: HarnessgramNowPlayingSource?

    public static var source: HarnessgramNowPlayingSource? {
        return HarnessgramNowPlaying.registered
    }

    public static func register(_ source: HarnessgramNowPlayingSource?) {
        HarnessgramNowPlaying.registered = source
        HarnessgramNowPlaying.notifyChanged()
    }

    public static func notifyChanged() {
        if Thread.isMainThread {
            NotificationCenter.default.post(name: HarnessgramNowPlaying.didChangeNotification, object: nil)
        } else {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: HarnessgramNowPlaying.didChangeNotification, object: nil)
            }
        }
    }

    /// Whether Telegram's bar shows the radio: the House radio switch is on, the radio is active, and Telegram's own
    /// player is not playing anything (its voice notes and music keep the bar first).
    public static func showsRadio(enabled: Bool, radioActive: Bool, telegramPlaying: Bool) -> Bool {
        return enabled && radioActive && !telegramPlaying
    }

    /// The bar's two lines: the live title over the station name when the radio says what it is on, otherwise the
    /// station name over "live".
    public static func barLines(liveTitle: String?) -> (title: String, subtitle: String) {
        let trimmed = liveTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            return (HarnessgramNowPlaying.Strings.title, HarnessgramNowPlaying.Strings.subtitle)
        }
        return (String(trimmed.prefix(80)), HarnessgramNowPlaying.Strings.title)
    }

    /// The bar's Hebrew copy and VoiceOver labels.
    public enum Strings {
        /// The station's name everywhere in the app and in the system's Now Playing (build 23, the owner's choice).
        public static let title = "שידורי הקוקפיט"
        public static let subtitle = "שידור חי"
        public static let play = "הפעלת השידורים"
        public static let pause = "השהיית השידורים"
        public static let close = "סגירת השידורים"
        /// The bar itself: what it is and what a tap does.
        public static let bar = "שידורי הקוקפיט, שידור חי. הקשה פותחת את מסך השידורים"
        public static let openHint = "הקשה פותחת את מסך השידורים"

        /// The bar's VoiceOver line for its two shown lines.
        public static func barLabel(title: String, subtitle: String) -> String {
            return title + ", " + subtitle + ". " + HarnessgramNowPlaying.Strings.openHint
        }
    }
}
