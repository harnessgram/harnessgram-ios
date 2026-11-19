import Foundation
import CoreGraphics

/// The quick-action ribbon above the composer in agent topics: four buttons that send the same short
/// texts the bridge already understands.
///
/// The bridge integration contract (docs/harnessgram-local-config.md) uses these exact
/// labels from its Hebrew reply keyboard:
/// - "▶️ המשך" (fixed_btn_continue) -> the continue word, delivered to the session as a keyboard tap;
/// - "📋 מצב" (fixed_btn_status) -> /status, answered in the topic;
/// - "⏹️ עצור" (fixed_btn_stop) -> Escape in the session's terminal (an immediate stop).
/// The bridge has no summary command, so Summary sends a short plain request that reaches the session
/// as an ordinary message.
public enum HarnessgramAgentRibbon {
    public enum Action: String, CaseIterable {
        case continueSession
        case status
        case summary
        case stop

        /// Right-to-left reading order: Continue at the right edge, Stop at the left.
        public static let ordered: [Action] = [.continueSession, .status, .summary, .stop]

        /// The exact text sent into the topic. Never shown to anyone but the bridge and the session.
        public var sentText: String {
            switch self {
            case .continueSession:
                return "\u{25B6}\u{FE0F} \u{05D4}\u{05DE}\u{05E9}\u{05DA}" // "▶️ המשך"
            case .status:
                return "\u{1F4CB} \u{05DE}\u{05E6}\u{05D1}" // "📋 מצב"
            case .summary:
                return "\u{1F4DD} \u{05E1}\u{05D9}\u{05DB}\u{05D5}\u{05DD}: \u{05DE}\u{05D4} \u{05E0}\u{05E2}\u{05E9}\u{05D4}, \u{05DE}\u{05D4} \u{05E0}\u{05E9}\u{05D0}\u{05E8} \u{05D5}\u{05DE}\u{05D4} \u{05DE}\u{05D7}\u{05DB}\u{05D4} \u{05DC}\u{05D9}?" // "📝 סיכום: מה נעשה, מה נשאר ומה מחכה לי?"
            case .stop:
                return "\u{23F9}\u{FE0F} \u{05E2}\u{05E6}\u{05D5}\u{05E8}" // "⏹️ עצור"
            }
        }

        public var icon: String {
            switch self {
            case .continueSession:
                return "\u{25B6}\u{FE0F}"
            case .status:
                return "\u{1F4CB}"
            case .summary:
                return "\u{1F4DD}"
            case .stop:
                return "\u{23F9}\u{FE0F}"
            }
        }

        public var title: String {
            switch self {
            case .continueSession:
                return HarnessgramAgentStrings.string(.ribbonContinue)
            case .status:
                return HarnessgramAgentStrings.string(.ribbonStatus)
            case .summary:
                return HarnessgramAgentStrings.string(.ribbonSummary)
            case .stop:
                return HarnessgramAgentStrings.string(.ribbonStop)
            }
        }

        /// What the button shows: its icon and word, like the bridge's own keyboard.
        public var label: String {
            return self.icon + " " + self.title
        }

        public var accessibilityLabel: String {
            switch self {
            case .continueSession:
                return HarnessgramAgentStrings.string(.ribbonContinueAccessibility)
            case .status:
                return HarnessgramAgentStrings.string(.ribbonStatusAccessibility)
            case .summary:
                return HarnessgramAgentStrings.string(.ribbonSummaryAccessibility)
            case .stop:
                return HarnessgramAgentStrings.string(.ribbonStopAccessibility)
            }
        }

        public var isDestructive: Bool {
            return self == .stop
        }

        /// Stop asks for a short confirmation before it sends (owner, 15.11: mistaken taps).
        public var needsConfirmation: Bool {
            return self == .stop
        }
    }

    /// The row's geometry, in points.
    public enum Layout {
        public static let rowHeight: CGFloat = 34.0
        /// Clear space between the row and the composer (input panels) under it.
        /// 16 points (build 12, was 8): the owner tapped the row by mistake while reaching for the field.
        public static let composerGap: CGFloat = 16.0
        /// What the chat keeps free above its input panels while the row shows. The history already keeps
        /// 11 points of its own there, so the newest message still clears the row by a few points.
        public static let reservedHeight: CGFloat = rowHeight + composerGap

        /// The row's top edge in a container whose bottom `panelsTopInset` points are the input panels.
        public static func rowOriginY(containerHeight: CGFloat, panelsTopInset: CGFloat) -> CGFloat {
            return max(0.0, containerHeight - panelsTopInset - composerGap - rowHeight)
        }
    }

    /// Telegram's General topic; it hosts no session, so no ribbon there.
    public static let generalThreadId: Int64 = 1

    /// What the chat screen knows when it decides whether to show the ribbon.
    public struct Context: Equatable {
        /// The chat's channel id, nil for anything but a channel.
        public var channelId: Int64?
        public var isForum: Bool
        /// The open topic, nil for the whole chat.
        public var threadId: Int64?
        public var composeTextIsEmpty: Bool
        public var isEditingMessage: Bool
        public var isRecordingMedia: Bool
        public var isSearching: Bool
        public var isSelectingMessages: Bool
        /// A special view of the chat (scheduled messages, pinned messages, ...).
        public var hasSubject: Bool
        /// Stickers, emoji or a bot keyboard occupy the input area.
        public var isInputPanelOccupied: Bool

        public init(channelId: Int64?, isForum: Bool, threadId: Int64?, composeTextIsEmpty: Bool, isEditingMessage: Bool, isRecordingMedia: Bool, isSearching: Bool, isSelectingMessages: Bool, hasSubject: Bool, isInputPanelOccupied: Bool) {
            self.channelId = channelId
            self.isForum = isForum
            self.threadId = threadId
            self.composeTextIsEmpty = composeTextIsEmpty
            self.isEditingMessage = isEditingMessage
            self.isRecordingMedia = isRecordingMedia
            self.isSearching = isSearching
            self.isSelectingMessages = isSelectingMessages
            self.hasSubject = hasSubject
            self.isInputPanelOccupied = isInputPanelOccupied
        }
    }

    /// Shown only in a session topic of an agent group, while the composer is empty and idle. Typing
    /// hides it (Telegram's own suggestions take the place), so it never covers what the owner writes.
    public static func isShown(_ context: Context, enabled: Bool, groups: HarnessgramAgentGroups) -> Bool {
        guard enabled, context.isForum, let channelId = context.channelId, groups.contains(channelId: channelId) else {
            return false
        }
        guard let threadId = context.threadId, threadId != HarnessgramAgentRibbon.generalThreadId else {
            return false
        }
        if !context.composeTextIsEmpty || context.isEditingMessage || context.isRecordingMedia || context.isSearching || context.isSelectingMessages || context.hasSubject || context.isInputPanelOccupied {
            return false
        }
        return true
    }
}
