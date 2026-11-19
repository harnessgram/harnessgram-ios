import Foundation
import CoreGraphics

/// The owner's Harnessgram preferences: comfort switches only. Nothing here can approve a chat, a
/// domain, a sticker pack or a bot, and nothing here can widen the media filter; approvals stay in
/// approved.json and the request flow (HarnessgramPolicyStore in TelegramCore).
///
/// Values live in the app group's defaults so the app and its extensions read one state. Defaults
/// are in code; a missing value always means the default.
public final class HarnessgramSettings {
    public static let shared: HarnessgramSettings = {
        let settings = HarnessgramSettings(defaults: HarnessgramSettings.appGroupDefaults())
        // Build 23: one font for the app and the messages; earlier choices carry over once, before anything reads them.
        settings.migrateToOneFontIfNeeded()
        // What the restart banner compares against (HarnessgramSettingApply).
        settings.rememberLaunchValues()
        return settings
    }()

    /// Posted on the main queue after any value changes.
    public static let didChangeNotification = Notification.Name("HarnessgramSettingsDidChange")

    public enum Key: String, CaseIterable {
        case recordWithBuiltInMic = "HarnessgramSettings.recordWithBuiltInMic"
        case autoDownloadInApprovedChats = "HarnessgramSettings.autoDownloadInApprovedChats"
        case connectThroughHomeRelay = "HarnessgramSettings.connectThroughHomeRelay"
        case justifiedText = "HarnessgramSettings.justifiedText"
        case lineSpacing = "HarnessgramSettings.lineSpacing"
        case messageFont = "HarnessgramSettings.messageFont"
        case fontWeight = "HarnessgramSettings.fontWeight"
        case textSizeSteps = "HarnessgramSettings.textSizeSteps"
        case bubbleWidth = "HarnessgramSettings.bubbleWidth"
        case agentQuickActions = "HarnessgramSettings.agentQuickActions"
        /// Set when the owner chooses the quick-action switch himself (Settings, build 12 on). Without it any
        /// stored value is the old build 11 default and is ignored.
        case agentQuickActionsChosen = "HarnessgramSettings.agentQuickActionsChosen"
        case agentProjectGroups = "HarnessgramSettings.agentProjectGroups"
        case topicStatusDots = "HarnessgramSettings.topicStatusDots"
        case confirmSensitiveButtons = "HarnessgramSettings.confirmSensitiveButtons"
        /// The bridge bot's Telegram user id, pinned the first time its username resolved (HarnessgramBridgeIdentity).
        case bridgeBotId = "HarnessgramSettings.bridgeBotId"
        /// A different user id the bridge username resolved to later; the bridge has no privileges until the owner
        /// confirms it.
        case bridgeBotPendingId = "HarnessgramSettings.bridgeBotPendingId"
        /// Where the pinned bridge id came from. Only "panel" is trusted (build 16); a pin without it (builds 13-14,
        /// taken from the username) is discarded.
        case bridgeBotIdSource = "HarnessgramSettings.bridgeBotIdSource"
        /// The House (Harnessgram "The House" redesign): one switch per screen, plus the mark that the owner chose it himself.
        /// Frozen in step 0 so later steps never edit this enum (see HarnessgramHouseFeatures.swift).
        case houseTheme = "HarnessgramSettings.house.theme"
        case houseThemeChosen = "HarnessgramSettings.house.theme.chosen"
        case houseHomeTab = "HarnessgramSettings.house.homeTab"
        case houseHomeTabChosen = "HarnessgramSettings.house.homeTab.chosen"
        case houseRadioTab = "HarnessgramSettings.house.radioTab"
        case houseRadioTabChosen = "HarnessgramSettings.house.radioTab.chosen"
        case houseKnock = "HarnessgramSettings.house.knock"
        case houseKnockChosen = "HarnessgramSettings.house.knock.chosen"
        case houseWaitingList = "HarnessgramSettings.house.waitingList"
        case houseWaitingListChosen = "HarnessgramSettings.house.waitingList.chosen"
        case houseRoom = "HarnessgramSettings.house.room"
        case houseRoomChosen = "HarnessgramSettings.house.room.chosen"
        case houseReadingView = "HarnessgramSettings.house.readingView"
        case houseReadingViewChosen = "HarnessgramSettings.house.readingView.chosen"
        case houseLiveSurfaces = "HarnessgramSettings.house.liveSurfaces"
        case houseLiveSurfacesChosen = "HarnessgramSettings.house.liveSurfaces.chosen"
        case houseRadioScreen = "HarnessgramSettings.house.radioScreen"
        case houseRadioScreenChosen = "HarnessgramSettings.house.radioScreen.chosen"
        case houseCarPlay = "HarnessgramSettings.house.carPlay"
        case houseCarPlayChosen = "HarnessgramSettings.house.carPlay.chosen"
        case houseConnect = "HarnessgramSettings.house.connect"
        case houseConnectChosen = "HarnessgramSettings.house.connect.chosen"
        case houseLifeRooms = "HarnessgramSettings.house.lifeRooms"
        case houseLifeRoomsChosen = "HarnessgramSettings.house.lifeRooms.chosen"
        case houseOnboarding = "HarnessgramSettings.house.onboarding"
        case houseOnboardingChosen = "HarnessgramSettings.house.onboarding.chosen"
        case houseSettingsRestyle = "HarnessgramSettings.house.settingsRestyle"
        case houseSettingsRestyleChosen = "HarnessgramSettings.house.settingsRestyle.chosen"
        case houseNativeCockpit = "HarnessgramSettings.house.nativeCockpit"
        case houseNativeCockpitChosen = "HarnessgramSettings.house.nativeCockpit.chosen"
        case houseNativeDecisions = "HarnessgramSettings.house.nativeDecisions"
        case houseNativeDecisionsChosen = "HarnessgramSettings.house.nativeDecisions.chosen"
        /// The whole app's font family (build 22); read once at launch.
        case appFont = "HarnessgramSettings.appFont"
        /// A built-in Harnessgram theme over Telegram's own (build 22).
        case theme = "HarnessgramSettings.theme"
        /// The Cockpit tab in the root tab bar (build 23), on by default.
        case cockpitTab = "HarnessgramSettings.cockpitTab"
        /// The floating Cockpit button on the chat list (build 23), off by default.
        case cockpitFloatingButton = "HarnessgramSettings.cockpitFloatingButton"
        /// Where the owner left the floating button: the screen edge ("left" or "right") and the height (0 top ... 1 bottom).
        case cockpitFloatingButtonSide = "HarnessgramSettings.cockpitFloatingButton.side"
        case cockpitFloatingButtonY = "HarnessgramSettings.cockpitFloatingButton.y"
        /// The app icon's number also counts what waits in the Cockpit (build 23), on by default.
        case cockpitAppBadge = "HarnessgramSettings.cockpitAppBadge"
        /// Messages use their own font instead of the app font (build 23), off by default.
        case separateMessageFont = "HarnessgramSettings.separateMessageFont"
        /// Set once the build 22 fonts (app and message) were folded into one choice.
        case oneFontMigrated = "HarnessgramSettings.oneFontMigrated"
    }

    /// Message text font (bubbles and the input field). Build 23: the same six as the app font, Secular One included.
    public enum MessageFont: String, CaseIterable {
        case system
        case assistant
        case heebo
        case rubik
        /// Serif, for Torah texts.
        case frankRuhlLibre
        /// A bold display face with one weight.
        case secularOne

        /// The same family as an app font.
        public init(_ appFont: AppFont) {
            self = MessageFont(rawValue: appFont.rawValue) ?? .system
        }
    }

    /// The whole app's font family (build 22): the chat list, settings, chats and navigation. It replaces the family
    /// behind Display's `Font` helpers at launch, so a change shows on the next launch. The message font, when the
    /// owner chose one, still wins inside the bubbles and the input field.
    public enum AppFont: String, CaseIterable {
        case system
        case heebo
        case assistant
        case rubik
        /// Serif.
        case frankRuhlLibre
        /// A bold display face with one weight (400): bold requests draw at that weight.
        case secularOne
    }

    /// Built-in Harnessgram themes (build 22), in the cockpit spirit. `none` is the owner's own Telegram theme. A theme
    /// applies at once (the presentation data is rebuilt) and wins over the House colours while it is chosen.
    public enum Theme: String, CaseIterable, Sendable {
        case none
        /// "לילה בקוקפיט": dark navy, amber accents.
        case cockpitNight
        /// "שחר על המסלול": warm light, sunrise orange accents.
        case runwayDawn
        /// "שמיים פתוחים": light, sky blue accents.
        case openSky
        /// "מכשירים": dark, green instrument accents.
        case instruments
    }

    public enum FontWeight: String, CaseIterable {
        case light
        case regular
        case medium
        case semibold

        /// CSS-style weight (100–900).
        public var value: CGFloat {
            switch self {
            case .light:
                return 300.0
            case .regular:
                return 400.0
            case .medium:
                return 500.0
            case .semibold:
                return 600.0
            }
        }
    }

    public enum BubbleWidth: String, CaseIterable {
        case normal
        /// Less wrapping on long agent replies.
        case wide
    }

    public static let textSizeStepRange: ClosedRange<Int> = -2 ... 4
    /// Points per Text size step, on top of Telegram's own Text Size.
    public static let textSizeStepPoints: CGFloat = 1.0

    public enum LineSpacing: String, CaseIterable {
        case normal
        case comfortable

        /// The text layout's line spacing factor (Telegram's default is 0.12).
        public var factor: CGFloat {
            switch self {
            case .normal:
                return 0.12
            case .comfortable:
                return 0.3
            }
        }
    }

    public static let defaultRecordWithBuiltInMic = true
    public static let defaultAutoDownloadInApprovedChats = true
    public static let defaultJustifiedText = false
    public static let defaultLineSpacing: LineSpacing = .normal
    public static let defaultMessageFont: MessageFont = .system
    public static let defaultFontWeight: FontWeight = .regular
    public static let defaultAppFont: AppFont = .system
    public static let defaultTheme: Theme = .none
    public static let defaultTextSizeSteps = 0
    public static let defaultBubbleWidth: BubbleWidth = .normal
    public static let defaultConnectThroughHomeRelay = true
    /// Off (owner, 15.11: the row was tapped by mistake); the owner turns it on in Settings > Harnessgram.
    public static let defaultAgentQuickActions = false
    public static let defaultTopicStatusDots = true
    public static let defaultConfirmSensitiveButtons = true
    /// On: whoever has Harnessgram gets a native Cockpit next to the chats (owner, build 23).
    public static let defaultCockpitTab = true
    /// Off: a floating button covers chat content and is not Telegram's own look, so it stays opt-in (build 23).
    public static let defaultCockpitFloatingButton = false
    /// On: Telegram already puts its unread count on the icon; the Cockpit's waiting items join it.
    public static let defaultCockpitAppBadge = true

    let defaults: UserDefaults
    /// The restart-needing values at launch (HarnessgramSettingApply), taken on first use.
    var restartLaunchValues: [Key: String]?
    let restartLaunchLock = NSLock()

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// Voice notes record through the iPhone microphone even when a car or headset is connected over
    /// Bluetooth (playback still goes to the car speakers). Calls are not affected.
    public var recordWithBuiltInMic: Bool {
        get { return self.bool(.recordWithBuiltInMic, default: HarnessgramSettings.defaultRecordWithBuiltInMic) }
        set { self.set(newValue, for: .recordWithBuiltInMic) }
    }

    /// Approved chats download media automatically at their own media level (still within Telegram's
    /// own auto-download sizes). Off, or for any chat that is not approved, the photos-only fallback holds.
    public var autoDownloadInApprovedChats: Bool {
        get { return self.bool(.autoDownloadInApprovedChats, default: HarnessgramSettings.defaultAutoDownloadInApprovedChats) }
        set { self.set(newValue, for: .autoDownloadInApprovedChats) }
    }

    /// Telegram connects through the configured computer relay (HarnessgramHomeRelay) while it answers, and
    /// directly otherwise. Calls never go through it.
    public var connectThroughHomeRelay: Bool {
        get { return self.bool(.connectThroughHomeRelay, default: HarnessgramSettings.defaultConnectThroughHomeRelay) }
        set { self.set(newValue, for: .connectThroughHomeRelay) }
    }

    /// Messages of 4 or more lines are justified; each paragraph's last line keeps its natural alignment.
    public var justifiedText: Bool {
        get { return self.bool(.justifiedText, default: HarnessgramSettings.defaultJustifiedText) }
        set { self.set(newValue, for: .justifiedText) }
    }

    public var lineSpacing: LineSpacing {
        get { return self.string(.lineSpacing).flatMap(LineSpacing.init(rawValue:)) ?? HarnessgramSettings.defaultLineSpacing }
        set { self.set(newValue.rawValue, for: .lineSpacing) }
    }

    /// What messages and the input field draw in (build 23): the app font, unless "גופן שונה להודעות" is on, then the
    /// owner's message font. Setting it is choosing a message font of its own, so the separate switch turns on.
    public var messageFont: MessageFont {
        get {
            guard self.separateMessageFont else {
                return MessageFont(self.appFont)
            }
            return self.messageFontChoice
        }
        set {
            self.defaults.set(true, forKey: Key.separateMessageFont.rawValue)
            self.set(newValue.rawValue, for: .messageFont)
        }
    }

    /// The font picked for messages alone (used only while `separateMessageFont` is on).
    public var messageFontChoice: MessageFont {
        get { return self.string(.messageFont).flatMap(MessageFont.init(rawValue:)) ?? HarnessgramSettings.defaultMessageFont }
        set { self.set(newValue.rawValue, for: .messageFont) }
    }

    /// "גופן שונה להודעות" (build 23): off, the messages follow the app font.
    public var separateMessageFont: Bool {
        get { return self.bool(.separateMessageFont, default: false) }
        set {
            if newValue && self.string(.messageFont) == nil {
                // Turned on for the first time: start from the font the messages draw in now.
                self.defaults.set(MessageFont(self.appFont).rawValue, forKey: Key.messageFont.rawValue)
            }
            self.set(newValue, for: .separateMessageFont)
        }
    }

    /// Build 22 had two separate choices; build 23 has one font with an optional message font. Runs once:
    /// - a message font and no app font: the message font becomes the app font (the switch stays off);
    /// - both, and they differ: both are kept and the switch turns on;
    /// - both the same, or no message font: nothing to carry over.
    public func migrateToOneFontIfNeeded() {
        guard !self.bool(.oneFontMigrated, default: false) else {
            return
        }
        self.defaults.set(true, forKey: Key.oneFontMigrated.rawValue)
        guard let storedMessage = self.string(.messageFont).flatMap(MessageFont.init(rawValue:)), storedMessage != .system else {
            return
        }
        let storedApp = self.string(.appFont).flatMap(AppFont.init(rawValue:))
        if storedApp == nil || storedApp == .system {
            if let font = AppFont(rawValue: storedMessage.rawValue) {
                self.defaults.set(font.rawValue, forKey: Key.appFont.rawValue)
            }
            self.defaults.set(false, forKey: Key.separateMessageFont.rawValue)
        } else if let storedApp, MessageFont(storedApp) != storedMessage {
            self.defaults.set(true, forKey: Key.separateMessageFont.rawValue)
        }
    }

    public var appFont: AppFont {
        get { return self.string(.appFont).flatMap(AppFont.init(rawValue:)) ?? HarnessgramSettings.defaultAppFont }
        set { self.set(newValue == HarnessgramSettings.defaultAppFont ? nil : newValue.rawValue, for: .appFont) }
    }

    public var theme: Theme {
        get { return self.string(.theme).flatMap(Theme.init(rawValue:)) ?? HarnessgramSettings.defaultTheme }
        set { self.set(newValue == HarnessgramSettings.defaultTheme ? nil : newValue.rawValue, for: .theme) }
    }

    public var fontWeight: FontWeight {
        get { return self.string(.fontWeight).flatMap(FontWeight.init(rawValue:)) ?? HarnessgramSettings.defaultFontWeight }
        set { self.set(newValue.rawValue, for: .fontWeight) }
    }

    /// -2 ... +4 steps on top of Telegram's Text Size; out-of-range stored values are clamped.
    public var textSizeSteps: Int {
        get {
            guard let stored = self.defaults.object(forKey: Key.textSizeSteps.rawValue) as? Int else {
                return HarnessgramSettings.defaultTextSizeSteps
            }
            return min(max(stored, HarnessgramSettings.textSizeStepRange.lowerBound), HarnessgramSettings.textSizeStepRange.upperBound)
        }
        set {
            self.set(min(max(newValue, HarnessgramSettings.textSizeStepRange.lowerBound), HarnessgramSettings.textSizeStepRange.upperBound), for: .textSizeSteps)
        }
    }

    /// Message text size for a base size from Telegram's Text Size.
    public func messageFontSize(base: CGFloat) -> CGFloat {
        return max(10.0, base + CGFloat(self.textSizeSteps) * HarnessgramSettings.textSizeStepPoints)
    }

    public var bubbleWidth: BubbleWidth {
        get { return self.string(.bubbleWidth).flatMap(BubbleWidth.init(rawValue:)) ?? HarnessgramSettings.defaultBubbleWidth }
        set { self.set(newValue.rawValue, for: .bubbleWidth) }
    }

    /// Agent topics (topics of the bridge's project groups) show a slim row above the composer with
    /// Continue, Status, Summary and Stop. Each sends the same short text as the bridge's own keyboard.
    /// Off by default. Only a choice the owner made himself counts: build 11 had no switch, so a value stored
    /// without the `agentQuickActionsChosen` mark is the old default (on) and reads as the new default (off).
    ///
    /// Why an unmarked stored `true` is dropped on purpose (build 12 review, P2): no build before 12 offered a
    /// switch or any other path that writes this key from the owner's hand (Settings had no row; the bridge and
    /// deep links never write it), so an unmarked value can only be a default or a test write. The old format
    /// cannot tell those apart from a choice, and the owner asked (15.11) for the row to be off for everyone who
    /// has not chosen it. Every write from build 12 on sets the mark, so later choices are always kept.
    /// Guarded by HarnessgramSettingsTests.testAnUnmarkedStoredTrueIsTheOldDefaultAndReadsAsOff.
    public var agentQuickActions: Bool {
        get {
            guard self.bool(.agentQuickActionsChosen, default: false) else {
                return HarnessgramSettings.defaultAgentQuickActions
            }
            return self.bool(.agentQuickActions, default: HarnessgramSettings.defaultAgentQuickActions)
        }
        set {
            self.defaults.set(true, forKey: Key.agentQuickActionsChosen.rawValue)
            self.set(newValue, for: .agentQuickActions)
        }
    }

    /// Extra agent project groups, as Bot API chat ids ("-100..."), on top of the ones shipped in
    /// approved.json "agentProjectGroups". Only marks where the agent shortcuts appear: it approves nothing.
    public var agentProjectGroups: [String] {
        get { return (self.defaults.array(forKey: Key.agentProjectGroups.rawValue) as? [String]) ?? [] }
        set { self.set(newValue.isEmpty ? nil : newValue, for: .agentProjectGroups) }
    }

    /// The topic list of an agent group shows a coloured dot before each session topic: blue working,
    /// orange waiting for you, green done (read from the state icon the bridge puts in the topic name).
    public var topicStatusDots: Bool {
        get { return self.bool(.topicStatusDots, default: HarnessgramSettings.defaultTopicStatusDots) }
        set { self.set(newValue, for: .topicStatusDots) }
    }

    /// A bot button that names a sensitive action (money, deletion, publication, store, production,
    /// accounts) asks for Face ID or the passcode before it is pressed; without it nothing is sent.
    public var confirmSensitiveButtons: Bool {
        get { return self.bool(.confirmSensitiveButtons, default: HarnessgramSettings.defaultConfirmSensitiveButtons) }
        set { self.set(newValue, for: .confirmSensitiveButtons) }
    }

    /// The Cockpit tab next to Chats (build 23): open decisions, task cards, the radio and a way into the full Cockpit.
    public var cockpitTab: Bool {
        get { return self.bool(.cockpitTab, default: HarnessgramSettings.defaultCockpitTab) }
        set { self.set(newValue, for: .cockpitTab) }
    }

    /// A small round Cockpit button over the chat list (build 23). Off by default.
    public var cockpitFloatingButton: Bool {
        get { return self.bool(.cockpitFloatingButton, default: HarnessgramSettings.defaultCockpitFloatingButton) }
        set { self.set(newValue, for: .cockpitFloatingButton) }
    }

    /// The app icon's number counts the Cockpit's waiting items too (Telegram's unread count stays in it either way).
    public var cockpitAppBadge: Bool {
        get { return self.bool(.cockpitAppBadge, default: HarnessgramSettings.defaultCockpitAppBadge) }
        set { self.set(newValue, for: .cockpitAppBadge) }
    }

    /// The floating button's resting place: the edge it snapped to and its height as a fraction of the free area.
    /// nil until the owner moved it (it then sits at its default place).
    public var cockpitFloatingButtonPosition: (rightEdge: Bool, y: Double)? {
        get {
            guard let side = self.string(.cockpitFloatingButtonSide), side == "left" || side == "right", let y = self.defaults.object(forKey: Key.cockpitFloatingButtonY.rawValue) as? Double, y.isFinite else {
                return nil
            }
            return (side == "right", min(max(y, 0.0), 1.0))
        }
        set {
            // One write for both values: the side is stored without a notification, the height with one.
            if let newValue {
                self.defaults.set(newValue.rightEdge ? "right" : "left", forKey: Key.cockpitFloatingButtonSide.rawValue)
                self.set(min(max(newValue.y, 0.0), 1.0), for: .cockpitFloatingButtonY)
            } else {
                self.defaults.removeObject(forKey: Key.cockpitFloatingButtonSide.rawValue)
                self.set(nil, for: .cockpitFloatingButtonY)
            }
        }
    }

    /// Stored bot user ids (positive 64-bit integers); anything else reads as none.
    public var bridgeBotId: Int64? {
        get { return self.int64(.bridgeBotId) }
        set { self.set(newValue.map { NSNumber(value: $0) }, for: .bridgeBotId) }
    }

    public var bridgeBotPendingId: Int64? {
        get { return self.int64(.bridgeBotPendingId) }
        set { self.set(newValue.map { NSNumber(value: $0) }, for: .bridgeBotPendingId) }
    }

    public var bridgeBotIdSource: String? {
        get { return self.string(.bridgeBotIdSource) }
        set { self.set(newValue, for: .bridgeBotIdSource) }
    }

    func int64(_ key: Key) -> Int64? {
        guard let number = self.defaults.object(forKey: key.rawValue) as? NSNumber, !CFNumberIsFloatType(number as CFNumber), number.int64Value > 0 else {
            return nil
        }
        return number.int64Value
    }

    func bool(_ key: Key, default value: Bool) -> Bool {
        guard let stored = self.defaults.object(forKey: key.rawValue) as? Bool else {
            return value
        }
        return stored
    }

    func string(_ key: Key) -> String? {
        return self.defaults.string(forKey: key.rawValue)
    }

    func set(_ value: Any?, for key: Key) {
        if let value {
            self.defaults.set(value, forKey: key.rawValue)
        } else {
            self.defaults.removeObject(forKey: key.rawValue)
        }
        if Thread.isMainThread {
            NotificationCenter.default.post(name: HarnessgramSettings.didChangeNotification, object: self)
        } else {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: HarnessgramSettings.didChangeNotification, object: self)
            }
        }
    }

    /// The app group `group.<base bundle id>`; an extension drops its own last bundle id component.
    public static func appGroupDefaults() -> UserDefaults {
        guard var id = Bundle.main.bundleIdentifier else {
            return .standard
        }
        if Bundle.main.bundleURL.pathExtension == "appex", let dot = id.range(of: ".", options: .backwards) {
            id = String(id[..<dot.lowerBound])
        }
        return UserDefaults(suiteName: "group." + id) ?? .standard
    }
}
