import Foundation
import HarnessgramCockpitKit

// The pure rules behind the knock (House step 3): which new messages may knock, which decisions are new, how many
// sheets one poke may show, what a waiting-list row can do, and the Hebrew counts. Foundation only, so every rule is
// unit tested without Telegram. The screens live in HarnessgramHouseUI (Knock, Waiting).

/// Which new messages may knock instead of Telegram's banner.
public enum HouseKnockRule {
    /// What the hook reads from a new message.
    public struct MessageFacts: Equatable, Sendable {
        /// The author is the pinned bridge bot (its user id, never its username: HarnessgramBridgeIdentity).
        public var authorIsPinnedBridgeBot: Bool
        /// A forwarded message is never a knock, whoever sent the original.
        public var isForward: Bool
        /// Sent through an inline bot ("via @bot"): never the bridge's own message.
        public var isViaBot: Bool
        /// The bot's private chat with the owner, or a topic of an agent group.
        public var isInAgentChat: Bool
        /// The message asks a question: it carries inline buttons or a bridge widget.
        public var asksQuestion: Bool

        public init(authorIsPinnedBridgeBot: Bool, isForward: Bool, isViaBot: Bool, isInAgentChat: Bool, asksQuestion: Bool) {
            self.authorIsPinnedBridgeBot = authorIsPinnedBridgeBot
            self.isForward = isForward
            self.isViaBot = isViaBot
            self.isInAgentChat = isInAgentChat
            self.asksQuestion = asksQuestion
        }
    }

    /// The bridge bot itself, in its own agent chats, asking a question; never a forward, never through another bot.
    /// Everything else keeps Telegram's banner.
    public static func mayKnock(_ facts: MessageFacts) -> Bool {
        return facts.authorIsPinnedBridgeBot && !facts.isForward && !facts.isViaBot && facts.isInAgentChat && facts.asksQuestion
    }
}

/// The ids already knocked for one account, kept between launches.
public struct HouseKnockRecord: Codable, Equatable, Sendable {
    /// False until the first comparison: the decisions that were already open then are not knocked (see `HouseKnockLedger`).
    public var initialized: Bool
    /// Decision id -> when it knocked.
    public var knocked: [String: Date]

    public init(initialized: Bool = false, knocked: [String: Date] = [:]) {
        self.initialized = initialized
        self.knocked = knocked
    }
}

public protocol HouseKnockStorage: AnyObject {
    func load() -> HouseKnockRecord?
    func save(_ record: HouseKnockRecord)
}

/// Stores the record in UserDefaults, one key per account (the ids are the bridge's random hex ids: no secret).
public final class HouseKnockUserDefaultsStorage: HouseKnockStorage, @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String

    public init(accountId: Int64, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.key = "HarnessgramHouse.knocked." + String(accountId)
    }

    public func load() -> HouseKnockRecord? {
        guard let data = self.defaults.data(forKey: self.key) else {
            return nil
        }
        return try? JSONDecoder().decode(HouseKnockRecord.self, from: data)
    }

    public func save(_ record: HouseKnockRecord) {
        if let data = try? JSONEncoder().encode(record) {
            self.defaults.set(data, forKey: self.key)
        }
    }
}

/// Remembers which decisions already knocked, so the same one never knocks twice (also after a relaunch), and "later"
/// (`אחר כך`) is the same thing: a decision that knocked once stays in the list and the doorway, and does not knock
/// again.
public final class HouseKnockLedger: @unchecked Sendable {
    /// An id is forgotten after this long (the bridge closes decisions well within it).
    public static let memory: TimeInterval = 14 * 24 * 3600
    public static let maxEntries = 400

    private let storage: HouseKnockStorage
    private let now: () -> Date
    private let lock = NSLock()

    public init(storage: HouseKnockStorage, now: @escaping () -> Date = Date.init) {
        self.storage = storage
        self.now = now
    }

    /// The decisions in `open` that have not knocked yet, in the order given (the bridge lists the newest first).
    ///
    /// The very first comparison on a phone has no history, and every decision that is already open would knock at
    /// once. Only the first of them (the newest; a poke means something just arrived) is kept as new, and the others
    /// are recorded as seen without a sheet: they are in the list.
    public func newDecisions(open: [HarnessgramCockpitSnapshot.Decision]) -> [HarnessgramCockpitSnapshot.Decision] {
        self.lock.lock()
        defer { self.lock.unlock() }
        var record = self.storage.load() ?? HouseKnockRecord()
        let moment = self.now()
        if !record.initialized {
            record.initialized = true
            for decision in open.dropFirst() {
                record.knocked[decision.id] = moment
            }
            self.storage.save(self.pruned(record, now: moment))
            return Array(open.prefix(1))
        }
        return open.filter { record.knocked[$0.id] == nil }
    }

    /// The decision knocked (or was left for later).
    public func markKnocked(_ id: String) {
        self.lock.lock()
        defer { self.lock.unlock() }
        var record = self.storage.load() ?? HouseKnockRecord()
        record.initialized = true
        record.knocked[id] = self.now()
        self.storage.save(self.pruned(record, now: self.now()))
    }

    public func hasKnocked(_ id: String) -> Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.storage.load()?.knocked[id] != nil
    }

    private func pruned(_ record: HouseKnockRecord, now: Date) -> HouseKnockRecord {
        var result = record
        result.knocked = result.knocked.filter { now.timeIntervalSince($0.value) < HouseKnockLedger.memory }
        if result.knocked.count > HouseKnockLedger.maxEntries {
            let kept = result.knocked.sorted(by: { $0.value > $1.value }).prefix(HouseKnockLedger.maxEntries)
            result.knocked = Dictionary(uniqueKeysWithValues: kept.map { ($0.key, $0.value) })
        }
        return result
    }
}

/// One poke can show a few sheets one after another, never a pile: the rest wait in the list and the doorway.
public enum HouseKnockQueue {
    public static let maxSheetsPerPoke = 3

    public struct Batch: Equatable, Sendable {
        /// Shown one after another, newest first.
        public var show: [HarnessgramCockpitSnapshot.Decision]
        /// New decisions beyond the cap: recorded as seen, they stay in the list.
        public var skipped: [HarnessgramCockpitSnapshot.Decision]
    }

    public static func batch(from new: [HarnessgramCockpitSnapshot.Decision]) -> Batch {
        return Batch(show: Array(new.prefix(HouseKnockQueue.maxSheetsPerPoke)), skipped: Array(new.dropFirst(HouseKnockQueue.maxSheetsPerPoke)))
    }
}

/// What one waiting-list row (or the knock sheet) lets the owner do with a decision.
///
/// The widget's rule decides, never the screen: a sensitive decision is never answered in place, and a plain one only
/// while the login can still answer (`HarnessgramDecisionGate`). Everything else opens the app flow, which looks the
/// decision up again and asks for Face ID where it is sensitive.
public struct HouseWaitingRowPlan: Equatable, Sendable {
    public enum Style: Equatable, Sendable {
        /// Yes and no buttons answered right in the row.
        case answerInPlace
        /// Yes and no buttons that open the app flow, which sends the chosen answer after a fresh lookup.
        case answerViaApp
        /// One approve button (with the Face ID glyph) that opens the app flow: its alert and Face ID come first.
        case approveWithFaceID
        /// A question with more than two answers: "לבחור" opens the room's topic.
        case chooseInRoom
    }

    public var style: Style
    public var yesLabel: String
    public var noLabel: String

    public init(style: Style, yesLabel: String, noLabel: String) {
        self.style = style
        self.yesLabel = yesLabel
        self.noLabel = noLabel
    }

    public static func make(decision: HarnessgramCockpitSnapshot.Decision, credential: HarnessgramCockpitCredential?, now: Date) -> HouseWaitingRowPlan {
        let item = HouseWaitingItem(decision: decision)
        let yes = decision.yesLabel.isEmpty ? HouseKnockText.yesFallback : decision.yesLabel
        let no = decision.noLabel.isEmpty ? HouseKnockText.noFallback : decision.noLabel
        if case .choice = item.kind {
            return HouseWaitingRowPlan(style: .chooseInRoom, yesLabel: yes, noLabel: no)
        }
        switch HarnessgramDecisionGate.route(sensitive: decision.sensitive, credential: credential, now: now) {
        case .answerOnWidget:
            return HouseWaitingRowPlan(style: .answerInPlace, yesLabel: yes, noLabel: no)
        case .answerInApp:
            return HouseWaitingRowPlan(style: .answerViaApp, yesLabel: yes, noLabel: no)
        case .answerInAppWithFaceID:
            return HouseWaitingRowPlan(style: .approveWithFaceID, yesLabel: yes, noLabel: no)
        }
    }
}

/// Words and counts the logic speaks (Hebrew, right to left).
public enum HouseKnockText {
    public static let yesFallback = "כן"
    public static let noFallback = "לא"

    /// "N things" for the waiting list header: one is "דבר אחד", two "שני דברים", then "N דברים".
    public static func thingsCount(_ count: Int) -> String {
        switch count {
        case 1:
            return "דבר אחד"
        case 2:
            return "שני דברים"
        default:
            return HouseKnockText.number(count) + " דברים"
        }
    }

    /// The line under a sheet that was not the only new question: "עוד אחד מחכה לך", "עוד 2 מחכים לך".
    public static func moreWaiting(_ count: Int) -> String? {
        guard count > 0 else {
            return nil
        }
        if count == 1 {
            return "עוד אחד מחכה לך"
        }
        return "עוד " + HouseKnockText.number(count) + " מחכים לך"
    }

    /// The room's name from the Cockpit's topic line ("פרויקט לדוגמה: מסך כניסה" is the room "פרויקט לדוגמה"); "חדר" when it is empty.
    public static func roomName(fromTopic topic: String) -> String {
        let first = topic.split(whereSeparator: { $0 == ":" || $0 == "\u{5C3}" }).first.map(String.init) ?? topic
        let trimmed = first.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? HouseKnockText.roomFallback : trimmed
    }

    /// The part of the topic line after the room's name ("מסך כניסה"), or nil.
    public static func topicDetail(fromTopic topic: String) -> String? {
        guard let separator = topic.firstIndex(where: { $0 == ":" || $0 == "\u{5C3}" }) else {
            return nil
        }
        let rest = topic[topic.index(after: separator)...].trimmingCharacters(in: .whitespacesAndNewlines)
        return rest.isEmpty ? nil : rest
    }

    /// The question a plain bridge message asks, for a knock that has no Cockpit decision behind it: the message's first
    /// line, at most `limit` characters (cut at a word, with an ellipsis), or nil when the message has no text.
    public static func questionLine(fromMessageText text: String, limit: Int = 140) -> String? {
        let firstLine = text.split(whereSeparator: { $0.isNewline }).map { $0.trimmingCharacters(in: .whitespaces) }.first(where: { !$0.isEmpty })
        guard let firstLine else {
            return nil
        }
        if firstLine.count <= limit {
            return firstLine
        }
        let cut = String(firstLine.prefix(limit))
        if let space = cut.lastIndex(of: " "), cut.distance(from: cut.startIndex, to: space) > limit / 2 {
            return String(cut[..<space]) + "\u{2026}"
        }
        return cut + "\u{2026}"
    }

    public static let roomFallback = "חדר"

    static func number(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "he_IL")
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }
}
