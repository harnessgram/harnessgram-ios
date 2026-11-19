import Foundation

/// A system media command the radio can switch on or off (MPRemoteCommand in the app; a fake in tests).
public protocol HarnessgramRemoteCommandSwitch: AnyObject {
    var isEnabled: Bool { get set }
}

/// What Telegram's own player last set on each system media command (MediaManager reports every write here).
/// It is the authority the radio gives the commands back to: a command Telegram enabled stays enabled after the
/// radio stops, one it disabled stays disabled, whatever the radio found when it started.
public final class HarnessgramRemoteCommandAuthority {
    public static let shared = HarnessgramRemoteCommandAuthority()

    private let lock = NSLock()
    private var states: [ObjectIdentifier: Bool] = [:]

    public init() {
    }

    /// Telegram's player set `command.isEnabled = enabled` (call next to the write).
    public func telegramSet(_ command: AnyObject, enabled: Bool) {
        self.lock.lock()
        defer { self.lock.unlock() }
        self.states[ObjectIdentifier(command)] = enabled
    }

    /// Telegram's last write, or nil when its player never touched the command.
    public func telegramState(of command: AnyObject) -> Bool? {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.states[ObjectIdentifier(command)]
    }
}

/// The radio borrows the lock-screen / Control Center commands while it plays and gives them back after.
///
/// `take` records each command's state the first time the radio touches it and applies the radio's state.
/// `release` gives each command the state of the player that owns it now: Telegram's last write as the authority
/// reports it (so a write Telegram made while the radio played counts even when it wrote the same value the radio
/// had set); a command Telegram never touched returns to the state the radio found.
public final class HarnessgramCommandOwnership<Command: HarnessgramRemoteCommandSwitch> {
    private struct Entry {
        let command: Command
        let previous: Bool
    }

    private var entries: [Entry] = []
    private let authority: HarnessgramRemoteCommandAuthority

    public init(authority: HarnessgramRemoteCommandAuthority = .shared) {
        self.authority = authority
    }

    public var isOwning: Bool {
        return !self.entries.isEmpty
    }

    /// Switches `enabled` on and `disabled` off. Taking again keeps the first recorded states.
    public func take(enabled: [Command], disabled: [Command]) {
        for (commands, value) in [(enabled, true), (disabled, false)] {
            for command in commands {
                if !self.entries.contains(where: { $0.command === command }) {
                    self.entries.append(Entry(command: command, previous: command.isEnabled))
                }
                command.isEnabled = value
            }
        }
    }

    /// Gives every borrowed command back (see the type's comment).
    public func release() {
        for entry in self.entries {
            entry.command.isEnabled = self.authority.telegramState(of: entry.command) ?? entry.previous
        }
        self.entries = []
    }
}
