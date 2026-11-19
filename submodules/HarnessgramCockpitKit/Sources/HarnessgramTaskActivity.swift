import Foundation
#if canImport(ActivityKit)
import ActivityKit
#endif

/// One agent progress card as the Live Activity shows it (the Cockpit's progress card: steps, steps
/// done, percent). The same struct is the Live Activity's content state, so a push from the bridge later
/// only has to send these fields.
public struct HarnessgramTaskState: Codable, Hashable, Sendable {
    public var title: String
    public var topic: String
    public var steps: [String]
    public var done: Int
    public var percent: Int?
    public var finished: Bool
    public var overflowCount: Int?

    public init(title: String, topic: String, steps: [String], done: Int, percent: Int?, finished: Bool) {
        self.title = title
        self.topic = topic
        self.steps = steps
        self.done = min(max(0, done), steps.count)
        self.percent = percent.map { min(max(0, $0), 100) }
        self.finished = finished
        self.overflowCount = nil
    }

    private enum CodingKeys: String, CodingKey {
        case title, topic, steps, done, percent, finished, overflowCount
    }

    /// A state pushed by the bridge is clamped exactly like a local one, so a bad push can never index past the steps.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(title: try container.decode(String.self, forKey: .title), topic: try container.decode(String.self, forKey: .topic), steps: try container.decode([String].self, forKey: .steps), done: try container.decode(Int.self, forKey: .done), percent: try container.decodeIfPresent(Int.self, forKey: .percent), finished: try container.decode(Bool.self, forKey: .finished))
        self.overflowCount = try container.decodeIfPresent(Int.self, forKey: .overflowCount).map { max(0, $0) }
    }

    public init(progress: HarnessgramCockpitSnapshot.Progress) {
        self.init(title: progress.title, topic: progress.topic, steps: progress.steps, done: progress.done, percent: progress.percent, finished: progress.finished)
    }

    /// 0 ... 1: the card's percent when it has one, otherwise steps done over steps.
    public var fraction: Double {
        if self.finished {
            return 1.0
        }
        if let percent = self.percent {
            return Double(percent) / 100.0
        }
        guard !self.steps.isEmpty else {
            return 0.0
        }
        return Double(self.done) / Double(self.steps.count)
    }

    public var percentShown: Int {
        return Int((self.fraction * 100.0).rounded())
    }

    /// The step being worked on (nil when every step is done or there are none).
    public var currentStep: String? {
        guard !self.finished, self.done < self.steps.count else {
            return nil
        }
        return self.steps[self.done]
    }

    /// "שלב 3 מתוך 5" or "כל השלבים הושלמו"; "" for a card without steps.
    public var stepLine: String {
        if self.steps.isEmpty {
            return self.finished ? HarnessgramWidgetStrings.allStepsDone : ""
        }
        if self.currentStep == nil {
            return HarnessgramWidgetStrings.allStepsDone
        }
        return HarnessgramWidgetStrings.stepOf(self.done + 1, self.steps.count)
    }
}

#if canImport(ActivityKit)
@available(iOS 16.1, *)
public struct HarnessgramTaskActivityAttributes: ActivityAttributes {
    public typealias ContentState = HarnessgramTaskState

    /// The Cockpit card id: one Live Activity per card.
    public var cardId: String

    public init(cardId: String) {
        self.cardId = cardId
    }
}
#endif

/// Which progress cards have a Live Activity: up to `maxActivities` unfinished cards, the most recently updated
/// first, so the lock screen shows the tasks that are moving now, whichever project they belong to, with the newest
/// in front (and in the Dynamic Island). A card the Cockpit marks stale gets none. A card without an
/// update time (an older bridge) ranks after every card with one, the same rule as the parser's order, and ties
/// keep the snapshot's order. Every running activity whose card is not in the plan ends with its last state.
public enum HarnessgramTaskActivityPlan {
    public struct Shown: Equatable, Sendable {
        public var cardId: String
        public var state: HarnessgramTaskState

        public init(cardId: String, state: HarnessgramTaskState) {
            self.cardId = cardId
            self.state = state
        }
    }

    #if canImport(ActivityKit)
    /// Whether an activity in this state may be reused for its card: only an active or stale one. An ended or
    /// dismissed activity stays listed for a while, and matching it would update a card nobody sees.
    @available(iOS 16.2, *)
    public static func isLive(_ state: ActivityState) -> Bool {
        switch state {
        case .active, .stale:
            return true
        default:
            return false
        }
    }
    #endif

    /// At most this many task activities at once.
    public static let maxActivities = 3
    /// Longer than parser-accepted card ids, so it cannot collide with a real card.
    public static let summaryCardId = "harnessgram-task-activity-overflow-summary"

    /// What waits for the owner, for the overflow summary's first row: how many open decisions, and the newest one's
    /// short title (nothing else of it: the same rule as the lock screen widgets).
    public struct Waiting: Equatable, Sendable {
        public var count: Int
        public var firstTitle: String?
        public var firstSensitive: Bool

        public init(count: Int, firstTitle: String?, firstSensitive: Bool = false) {
            self.count = max(0, count)
            self.firstTitle = firstTitle
            self.firstSensitive = firstSensitive
        }

        /// From a Cockpit snapshot: every open decision it counts, and its newest line; nil when nothing waits.
        public init?(snapshot: HarnessgramCockpitSnapshot?) {
            guard let snapshot else {
                return nil
            }
            let count = max(0, snapshot.waitingCount, snapshot.decisions.count)
            guard count > 0 else {
                return nil
            }
            self.init(count: count, firstTitle: snapshot.decisions.first?.title, firstSensitive: snapshot.decisions.first?.sensitive ?? false)
        }
    }

    /// The cards to keep a Live Activity for, the most recently updated first; empty when none qualifies. The overflow
    /// summary (more cards than activities) lists the hidden cards it stands for, most recently updated first, and
    /// starts with what waits for the owner when `waiting` says something does (`HarnessgramTaskSummaryRow`).
    /// `summaryRows` false (the bridge's "summaryRows" switch) keeps the old summary exactly: no rows.
    public static func choose(_ progress: [HarnessgramCockpitSnapshot.Progress], waiting: Waiting? = nil, summaryRows: Bool = true, now: Date = Date()) -> [Shown] {
        let eligible = progress.enumerated().filter { _, card in
            return !card.finished && card.stale != true
        }
        let ordered = eligible.sorted { lhs, rhs in
            let left = lhs.element.updated ?? -Double.infinity
            let right = rhs.element.updated ?? -Double.infinity
            if left != right {
                return left > right
            }
            return lhs.offset < rhs.offset
        }
        let visibleCount = ordered.count > maxActivities ? maxActivities - 1 : maxActivities
        var shown = ordered.prefix(visibleCount).map {
            Shown(cardId: $0.element.id, state: HarnessgramTaskState(progress: $0.element))
        }
        if ordered.count > maxActivities {
            let count = ordered.count - visibleCount
            let hidden = ordered.dropFirst(visibleCount).map { $0.element }
            let rows = summaryRows ? HarnessgramTaskSummaryRow.rows(hidden: Array(hidden), waiting: waiting) : []
            // The rows ride in `steps` (the summary has no plan of its own), so the content state and the push
            // contract keep their fields; `overflowCount` marks the state as the summary.
            var state = HarnessgramTaskState(title: HarnessgramWidgetStrings.moreTasks(count), topic: "", steps: rows.map { $0.encoded }, done: 0, percent: nil, finished: false)
            state.overflowCount = count
            // ActivityKit's 4 KB limit includes attributes. Measure JSON bytes (a single Character can contain
            // arbitrarily many Unicode scalars), leaving 1 KB for attributes and envelope overhead.
            var boundedRows = rows
            while ((try? JSONEncoder().encode(state).count) ?? Int.max) > 3_072 {
                guard let index = boundedRows.indices.filter({ !boundedRows[$0].text.isEmpty }).max(by: {
                    boundedRows[$0].text.utf8.count < boundedRows[$1].text.utf8.count
                }) else {
                    break
                }
                let text = boundedRows[index].text
                boundedRows[index].text = text.count > 4 ? HarnessgramTaskSummaryRow.truncated(text, text.count - 2) : ""
                state.steps = boundedRows.map { $0.encoded }
            }
            shown.append(Shown(cardId: summaryCardId, state: state))
        }
        return shown
    }

    /// The updates to send for `plan`, in the order to send them. iOS decides the final order of activities on the
    /// lock screen; it puts the most recently updated one first, so the newest card (plan's first) must get the last
    /// update. Cards whose state did not change since `lastShown` are skipped (the throttle), except that the top card
    /// is pushed again, last, whenever another card was pushed before it or the top card changed (`lastTop`).
    /// Empty when nothing changed.
    public static func pushes(_ plan: [Shown], lastShown: [String: HarnessgramTaskState], lastTop: String?) -> [Shown] {
        guard let top = plan.first else {
            return []
        }
        var out = plan.dropFirst().reversed().filter { lastShown[$0.cardId] != $0.state }
        if !out.isEmpty || lastShown[top.cardId] != top.state || lastTop != top.cardId {
            out.append(top)
        }
        return out
    }
}

/// One line of the overflow summary Live Activity (owner report: "+3 and a radar tell me nothing"): a hidden task as
/// "<project> · <short title>" with its percent, or, first, what waits for the owner ("2 החלטות מחכות לך · <title>").
/// Encoded into the summary state's `steps` as plain strings, so an older summary (no rows) still decodes and shows
/// the plain card.
public struct HarnessgramTaskSummaryRow: Equatable, Sendable {
    public enum Kind: String, Sendable {
        case waiting = "w"
        case task = "t"
    }

    public var kind: Kind
    public var text: String
    /// 0 ... 100, nil when the card sends none (and for the waiting row).
    public var percent: Int?
    /// The waiting row's newest decision is a sensitive one (the card shows a lock beside it).
    public var sensitive: Bool

    public init(kind: Kind, text: String, percent: Int? = nil, sensitive: Bool = false) {
        self.kind = kind
        self.text = text
        self.percent = percent.map { min(max($0, 0), 100) }
        self.sensitive = sensitive
    }

    /// At most this many rows; tasks beyond them are counted ("+K").
    public static let maxRows = 3
    /// A row's text stays short (one line on the lock screen, and the content state stays far below ActivityKit's
    /// size limit).
    public static let maxText = 40
    /// The project's part of a task row.
    public static let maxTopic = 18
    /// The decision title's part of the waiting row.
    public static let maxDecisionTitle = 26

    private static let separator: Character = "\u{1F}"

    public var encoded: String {
        let fields = [self.kind.rawValue, self.percent.map { String($0) } ?? "", self.sensitive ? "1" : "0", self.text]
        return fields.joined(separator: String(HarnessgramTaskSummaryRow.separator))
    }

    public init?(encoded: String) {
        let fields = encoded.split(separator: HarnessgramTaskSummaryRow.separator, maxSplits: 3, omittingEmptySubsequences: false).map(String.init)
        guard fields.count == 4, let kind = Kind(rawValue: fields[0]) else {
            return nil
        }
        self.init(kind: kind, text: fields[3], percent: Int(fields[1]), sensitive: fields[2] == "1")
    }

    /// The rows a summary state carries (none for any other state, or an older summary).
    public static func decode(_ state: HarnessgramTaskState) -> [HarnessgramTaskSummaryRow] {
        guard state.overflowCount != nil else {
            return []
        }
        return Array(state.steps.compactMap { HarnessgramTaskSummaryRow(encoded: $0) }.prefix(HarnessgramTaskSummaryRow.maxRows))
    }

    /// The hidden tasks the rows do not list: the "+K" beside them (0: every hidden task has its row).
    public static func extraCount(_ state: HarnessgramTaskState) -> Int {
        guard let overflow = state.overflowCount else {
            return 0
        }
        let listed = HarnessgramTaskSummaryRow.decode(state).filter { $0.kind == .task }.count
        return max(0, overflow - listed)
    }

    /// The waiting row first (when something waits), then one row per hidden task in the order given, up to `maxRows`.
    public static func rows(hidden: [HarnessgramCockpitSnapshot.Progress], waiting: HarnessgramTaskActivityPlan.Waiting?) -> [HarnessgramTaskSummaryRow] {
        var rows: [HarnessgramTaskSummaryRow] = []
        if let waiting, waiting.count > 0 {
            var text = HarnessgramWidgetStrings.decisionsWaiting(waiting.count)
            if let title = waiting.firstTitle.map({ HarnessgramTaskSummaryRow.oneLine($0) }), !title.isEmpty {
                text += " · " + HarnessgramTaskSummaryRow.truncated(title, HarnessgramTaskSummaryRow.maxDecisionTitle)
            }
            rows.append(HarnessgramTaskSummaryRow(kind: .waiting, text: HarnessgramTaskSummaryRow.truncated(text, HarnessgramTaskSummaryRow.maxText + 12), sensitive: waiting.firstSensitive))
        }
        for card in hidden {
            guard rows.count < HarnessgramTaskSummaryRow.maxRows else {
                break
            }
            rows.append(HarnessgramTaskSummaryRow(kind: .task, text: HarnessgramTaskSummaryRow.taskText(topic: card.topic, title: card.title), percent: card.percent))
        }
        return rows
    }

    /// "<project> · <short title>", one direction per line: the project joins only when it shares the title's script
    /// (or is a short English name, inside a bidi isolate); otherwise the row is the title alone.
    public static func taskText(topic: String, title: String) -> String {
        let title = HarnessgramTaskSummaryRow.oneLine(title)
        let topic = HarnessgramTaskSummaryRow.oneLine(topic)
        let headline = HarnessgramTaskHeadline.make(topic: topic, title: title)
        guard !topic.isEmpty, headline.eyebrow == nil else {
            return HarnessgramTaskSummaryRow.truncated(title, HarnessgramTaskSummaryRow.maxText)
        }
        let topicPart: String
        if HarnessgramTaskHeadline.hasHebrew(title) && HarnessgramTaskHeadline.hasLatin(topic) && !HarnessgramTaskHeadline.hasHebrew(topic) {
            // A short English project name inside the Hebrew row: isolated, never cut.
            guard let name = HarnessgramTaskHeadline.isolatedShortName(topic), name.count <= HarnessgramTaskSummaryRow.maxTopic + 2 else {
                return HarnessgramTaskSummaryRow.truncated(title, HarnessgramTaskSummaryRow.maxText)
            }
            topicPart = name
        } else {
            topicPart = HarnessgramTaskSummaryRow.truncated(topic, HarnessgramTaskSummaryRow.maxTopic)
        }
        let room = max(14, HarnessgramTaskSummaryRow.maxText - topicPart.count - 3)
        return topicPart + " · " + HarnessgramTaskSummaryRow.truncated(title, room)
    }

    /// Line breaks and runs of spaces become one space.
    static func oneLine(_ text: String) -> String {
        return text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
    }

    /// At most `limit` characters, cut with "…" (never inside a bidi isolate).
    public static func truncated(_ text: String, _ limit: Int) -> String {
        guard text.count > limit, limit > 1 else {
            return text
        }
        var cut = String(text.prefix(limit - 1)).trimmingCharacters(in: .whitespaces)
        let opens = cut.filter { $0 == HarnessgramTaskHeadline.isolateStart }.count
        let closes = cut.filter { $0 == HarnessgramTaskHeadline.isolateEnd }.count
        if opens > closes {
            cut.append(HarnessgramTaskHeadline.isolateEnd)
        }
        return cut + "…"
    }
}
