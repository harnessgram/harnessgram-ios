import Foundation
import HarnessgramSettings

/// Which chats count as agent chats, and the decisions that depend on it. Pure, so they are unit tested
/// without Telegram's UI modules. Nothing here approves a chat: visibility stays with approved.json and
/// the request flow (HarnessgramPolicyStore).
public enum HarnessgramAgentChat {
    /// A chat as the message list sees it.
    public struct Kind: Equatable {
        /// A one-to-one chat with a bot.
        public var isBotPrivateChat: Bool
        /// The chat's channel id when it is a channel or supergroup.
        public var channelId: Int64?
        public var isForum: Bool

        public init(isBotPrivateChat: Bool, channelId: Int64?, isForum: Bool) {
            self.isBotPrivateChat = isBotPrivateChat
            self.channelId = channelId
            self.isForum = isForum
        }
    }

    /// The Harnessgram bridge bot's username (lower-cased, no "@"), used ONLY to resolve its user id once
    /// (HarnessgramBridgeIdentity). Every privilege checks the pinned id (`isBridgeBot(userId:)`), never a username,
    /// because a username can be handed to another bot.
    public static var bridgeBotUsernames: Set<String> {
        let name = self.bridgeBotResolveName.lowercased()
        return name.isEmpty ? [] : [name]
    }
    /// The username the app resolves to pin the bridge (as Telegram spells it).
    public static var bridgeBotResolveName: String {
        return HarnessgramLocalConfig.bundled.bridgeBotUsername?.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "@")) ?? ""
    }

    /// The pinned bridge bot (and nothing while a change of bot waits for the owner).
    public static func isBridgeBot(userId: Int64?, identity: HarnessgramBridgeIdentity = .shared) -> Bool {
        return identity.isBridge(userId: userId)
    }

    /// Whether a resolved username is the bridge's (for pinning only).
    public static func isBridgeBot(username: String?, configuredUsername: String = HarnessgramAgentChat.bridgeBotResolveName) -> Bool {
        guard let username else {
            return false
        }
        var name = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if name.hasPrefix("@") {
            name.removeFirst()
        }
        return !configuredUsername.isEmpty && name == configuredUsername.lowercased()
    }

    /// A bot chat, or any topic of a forum group the bridge runs agent sessions in.
    public static func isAgentChat(_ kind: Kind, groups: HarnessgramAgentGroups) -> Bool {
        if kind.isBotPrivateChat {
            return true
        }
        guard kind.isForum, let channelId = kind.channelId else {
            return false
        }
        return groups.contains(channelId: channelId)
    }

    /// "Bubble width: wide" widens only text bubbles (all of a message's parts are text) in agent chats.
    /// Stickers, media, bubbleless layouts and ordinary personal or group chats keep Telegram's width.
    public static func usesWideBubble(setting: HarnessgramSettings.BubbleWidth, kind: Kind, groups: HarnessgramAgentGroups, isTextOnly: Bool, isBubbleless: Bool) -> Bool {
        guard setting == .wide, isTextOnly, !isBubbleless else {
            return false
        }
        return self.isAgentChat(kind, groups: groups)
    }
}

/// The agent switches in Settings > Harnessgram.
public enum HarnessgramAgentSwitches {
    /// Turning the Face ID gate for sensitive buttons off needs the owner (Face ID or passcode) first, so
    /// someone holding an unlocked phone cannot switch the protection off. Turning it on never asks.
    public static func turningGateNeedsOwner(from current: Bool, to newValue: Bool) -> Bool {
        return current && !newValue
    }
}

/// The "Face ID for sensitive buttons" switch: on at once, off only after the owner confirms. One prompt at a
/// time: taps while it is open are ignored. A cancel or a failure leaves the gate on.
public final class HarnessgramGateSwitch {
    private let settings: HarnessgramSettings
    private let confirmation: HarnessgramOwnerConfirmation
    private let reason: String
    public private(set) var isConfirming = false
    /// Called on the main queue whenever the value or `isConfirming` changes (the screen redraws).
    public var onChange: (() -> Void)?

    public init(settings: HarnessgramSettings, confirmation: HarnessgramOwnerConfirmation = .shared, reason: String) {
        self.settings = settings
        self.confirmation = confirmation
        self.reason = reason
    }

    public var isOn: Bool {
        return self.settings.confirmSensitiveButtons
    }

    public func set(_ value: Bool) {
        guard value != self.isOn, !self.isConfirming else {
            return
        }
        guard HarnessgramAgentSwitches.turningGateNeedsOwner(from: self.isOn, to: value) else {
            self.settings.confirmSensitiveButtons = value
            self.onChange?()
            return
        }
        self.isConfirming = true
        self.onChange?()
        self.confirmation.confirm(reason: self.reason, completion: { [weak self] confirmed in
            guard let self else {
                return
            }
            self.isConfirming = false
            if confirmed {
                self.settings.confirmSensitiveButtons = false
            }
            self.onChange?()
        })
    }
}

/// The bridge's decision widgets (shown in agent chats since build 13) can ask the bot to act. Build 14 review P1:
/// such a request passes the same owner check as a marked button before anything is sent.
public enum HarnessgramWidgetActions {
    /// A widget request is sensitive unless the bridge explicitly says it is not. The bridge sends no flag yet, so
    /// every request asks for Face ID or the passcode.
    public static func isSensitive(bridgeFlag: Bool?) -> Bool {
        return bridgeFlag ?? true
    }

    /// What a card request was about when the owner was asked: the account and the message (build 15, review P2).
    public struct Target: Equatable {
        public let accountId: Int64
        public let messageKey: String

        public init(accountId: Int64, messageKey: String) {
            self.accountId = accountId
            self.messageKey = messageKey
        }
    }

    /// After Face ID: the request goes out only if the card on screen is still the same message of the same account,
    /// that message still exists, and its widget is still alive. Anything else sends nothing.
    public static func mayStillSend(captured: Target, current: Target?, messageExists: Bool, widgetAlive: Bool) -> Bool {
        return widgetAlive && messageExists && current == captured
    }
}

