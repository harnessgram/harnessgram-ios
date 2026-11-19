import Foundation

/// What the native Cockpit screens show, read from the same `POST /api/state` answer as the widget snapshot. It lives
/// only in memory (HarnessgramCockpitSync keeps the latest one on the main queue and drops it on every account change);
/// it is never written to the shared files, which keep the widgets' small snapshot.
public struct HarnessgramCockpitScreen: Equatable, Sendable {
    /// How many agent sessions are in each state. A session counts once: one with an open decision in its topic counts
    /// as waiting, whatever the bridge says it is doing.
    public struct SessionCounts: Equatable, Sendable {
        public var working: Int
        public var waiting: Int
        public var idle: Int

        public init(working: Int, waiting: Int, idle: Int) {
            self.working = working
            self.waiting = waiting
            self.idle = idle
        }
    }

    /// One account's weekly quota, as the bridge last measured it.
    public struct Quota: Equatable, Sendable, Identifiable {
        public var account: String
        public var label: String
        /// Percent used this week (0 ... 999); nil when the bridge has no reading.
        public var weekly: Int?
        public var resetsAt: Date?
        /// Spare weekly resets the account holds; nil when unknown.
        public var banked: Int?

        public var id: String {
            return self.account
        }

        public init(account: String, label: String, weekly: Int?, resetsAt: Date?, banked: Int?) {
            self.account = account
            self.label = label
            self.weekly = weekly
            self.resetsAt = resetsAt
            self.banked = banked
        }
    }

    /// Where an answer or a message stands on its way into the agent's session (the bridge's delivery states).
    public enum DeliveryState: String, Equatable, Sendable {
        case delivered
        case inFlight = "in_flight"
        case queued
        case cancelled
        case unknown

        public init(bridgeValue: Any?) {
            self = (bridgeValue as? String).flatMap(DeliveryState.init(rawValue:)) ?? .unknown
        }
    }

    /// One delivery receipt (`deliveries[]`): a decision answer or a message on its way to a session.
    public struct Delivery: Equatable, Sendable {
        public var key: String
        /// The decision id for an answer.
        public var id: String
        public var state: DeliveryState
        /// The bridge could not wake the session yet and keeps trying.
        public var retrying: Bool

        public init(key: String, id: String, state: DeliveryState, retrying: Bool) {
            self.key = key
            self.id = id
            self.state = state
            self.retrying = retrying
        }
    }

    /// An open decision with everything the native screens need beyond the widget's fields.
    public struct Decision: Equatable, Identifiable, Sendable {
        public var base: HarnessgramCockpitSnapshot.Decision
        /// Older than the bridge's "old" age: still answerable, listed apart.
        public var isOld: Bool
        /// The asker marked it routine (`"sensitive": false`). A missing or malformed mark is never routine.
        public var routine: Bool
        /// A Claude Code permission request: its exact text. Answered only in the full Cockpit, which shows it whole.
        public var permissionRequest: String?
        /// A permission request that may only be declined.
        public var declineOnly: Bool
        /// Pictures, links, long context and the comment answer (rich decisions); `.none` from an older bridge.
        public var extras: HarnessgramDecisionExtras = .none
        /// The HTTPS origin that served this decision. Preview decisions have no origin.
        public let bridgeOrigin: URL?

        public var id: String {
            return self.base.id
        }

        /// Face ID before any answer: everything that is not explicitly routine.
        public var requiresOwnerCheck: Bool {
            return !self.routine || self.permissionRequest != nil
        }

        /// The native screen answers it itself: a plain yes/no question only. Permission requests and questions with
        /// their own options (or any kind other than a plain question) go to the full Cockpit, which shows every choice.
        public var answerableHere: Bool {
            guard self.permissionRequest == nil else {
                return false
            }
            if let options = self.base.options, !options.isEmpty {
                return false
            }
            if let kind = self.base.kind, !kind.isEmpty, kind != "yesno", kind != "decision" {
                return false
            }
            return true
        }

        public init(base: HarnessgramCockpitSnapshot.Decision, isOld: Bool, routine: Bool, permissionRequest: String?, declineOnly: Bool, extras: HarnessgramDecisionExtras = .none, bridgeOrigin: URL? = nil) {
            self.base = base
            self.isOld = isOld
            self.routine = routine
            self.permissionRequest = permissionRequest
            self.declineOnly = declineOnly
            self.extras = extras
            self.bridgeOrigin = bridgeOrigin
        }
    }

    public static let maxQuota = 12
    public static let maxDeliveries = 60

    public var now: Date
    public var sessions: SessionCounts
    /// The bridge's own count of what waits on the owner (decisions, reminders and requests); nil from an older bridge.
    public var waitingCount: Int?
    /// Fresh decisions first (newest first), then the old ones.
    public var decisions: [Decision]
    public var quota: [Quota]
    public var deliveries: [Delivery]
    public var radio: HarnessgramCockpitSnapshot.Radio?

    public init(now: Date, sessions: SessionCounts, waitingCount: Int?, decisions: [Decision], quota: [Quota], deliveries: [Delivery], radio: HarnessgramCockpitSnapshot.Radio?) {
        self.now = now
        self.sessions = sessions
        self.waitingCount = waitingCount
        self.decisions = decisions
        self.quota = quota
        self.deliveries = deliveries
        self.radio = radio
    }

    public var freshDecisions: [Decision] {
        return self.decisions.filter { !$0.isOld }
    }

    public var oldDecisions: [Decision] {
        return self.decisions.filter { $0.isOld }
    }

    public func decision(id: String) -> Decision? {
        return self.decisions.first(where: { $0.id == id })
    }

    /// The live state of one delivery (the key `/api/decide` returned).
    public func delivery(key: String) -> Delivery? {
        return self.deliveries.first(where: { $0.key == key })
    }

    /// The same screen without the given decisions (answered from this phone, before the bridge drops them).
    public func removingDecisions(_ ids: Set<String>) -> HarnessgramCockpitScreen {
        guard !ids.isEmpty else {
            return self
        }
        var copy = self
        copy.decisions = self.decisions.filter { !ids.contains($0.id) }
        return copy
    }
}

extension HarnessgramCockpitScreen {
    /// Reads the native screen from the panel's state answer. Anything malformed is dropped, never guessed.
    public static func parse(state: Data, radio: HarnessgramCockpitSnapshot.Radio?, now: Date, bridgeOrigin: URL? = nil) throws -> HarnessgramCockpitScreen {
        guard let root = (try? JSONSerialization.jsonObject(with: state)) as? [String: Any] else {
            throw HarnessgramCockpitParser.ParseError.notJSON
        }
        guard root["ok"] as? Bool == true else {
            throw HarnessgramCockpitParser.ParseError.notOK
        }
        // An id that appears more than once is ambiguous (which entry's text and Face ID mark belong to the answer?):
        // every entry with it is dropped here, never merged; the full Cockpit still shows it.
        var raw: [String: [String: Any]] = [:]
        var duplicated = Set<String>()
        for case let item as [String: Any] in (root["decisions"] as? [Any] ?? []) {
            guard let id = item["id"] as? String else {
                continue
            }
            if raw[id] != nil {
                duplicated.insert(id)
            } else {
                raw[id] = item
            }
        }
        let parsed = HarnessgramCockpitParser.parseDecisions(root, now: now, keepOld: true)
        var decisions: [Decision] = []
        for base in parsed {
            guard !duplicated.contains(base.id), let item = raw[base.id] else {
                continue
            }
            // The widgets cut the question to one line; this screen shows the whole question and detail, line breaks
            // kept, the Hebrew copy first.
            var base = base
            let fullTitle = full(item, "title_he") ?? full(item, "title")
            if let fullTitle {
                base.title = fullTitle
            }
            base.detail = full(item, "detail_he") ?? full(item, "detail") ?? base.detail
            let isOld = (item["stale"] as? String) == "old" || (item["old"] as? Bool) == true
            let request = item["request"] as? String
            decisions.append(Decision(
                base: base,
                isOld: isOld,
                routine: isJSONFalse(item["sensitive"]),
                permissionRequest: request.map { HarnessgramCockpitParser.cleanHebrew($0, limit: 4_000, multiline: true) },
                declineOnly: request != nil && (item["decline_only"] as? Bool ?? true),
                extras: HarnessgramDecisionExtras.parse(item),
                bridgeOrigin: bridgeOrigin
            ))
        }
        // Fresh ones first; the panel's newest-first order is kept inside each group.
        decisions = decisions.filter { !$0.isOld } + decisions.filter { $0.isOld }

        let topicsWithDecision = Set(decisions.map { $0.base.topicURL }.filter { !$0.isEmpty })
        var counts = SessionCounts(working: 0, waiting: 0, idle: 0)
        for case let item as [String: Any] in (root["sessions"] as? [Any] ?? []) {
            let state = item["state"] as? String ?? ""
            guard state == "working" || state == "idle" else {
                continue
            }
            let url = HarnessgramCockpitParser.clean(item["url"], limit: 200)
            if !url.isEmpty, topicsWithDecision.contains(url) {
                counts.waiting += 1
            } else if state == "working" {
                counts.working += 1
            } else {
                counts.idle += 1
            }
        }

        var quota: [Quota] = []
        for case let item as [String: Any] in (root["quota"] as? [Any] ?? []) {
            let account = HarnessgramCockpitParser.clean(item["account"], limit: 60)
            guard !account.isEmpty else {
                continue
            }
            let label = HarnessgramCockpitParser.clean(item["label"], limit: 60)
            let weekly = number(item["weekly"]).map { Int(min(max(0.0, $0), 999.0).rounded()) }
            let resets = HarnessgramCockpitParser.timeValue(item["weekly_resets"]).map { Date(timeIntervalSince1970: $0) }
            let banked = HarnessgramCockpitParser.pendingCount(item["banked"])
            quota.append(Quota(account: account, label: label.isEmpty ? account : label, weekly: weekly, resetsAt: resets, banked: banked))
            if quota.count == maxQuota {
                break
            }
        }

        var deliveries: [Delivery] = []
        for case let item as [String: Any] in (root["deliveries"] as? [Any] ?? []) {
            let key = HarnessgramCockpitParser.clean(item["key"], limit: 80)
            guard !key.isEmpty else {
                continue
            }
            deliveries.append(Delivery(key: key, id: HarnessgramCockpitParser.clean(item["id"], limit: 80), state: DeliveryState(bridgeValue: item["state"]), retrying: (item["retrying"] as? Bool) ?? false))
            if deliveries.count == maxDeliveries {
                break
            }
        }

        return HarnessgramCockpitScreen(
            now: HarnessgramCockpitParser.timeValue(root["now"]).map { Date(timeIntervalSince1970: $0) } ?? now,
            sessions: counts,
            waitingCount: HarnessgramCockpitParser.pendingCount(root["waiting_count"]),
            decisions: decisions,
            quota: quota,
            deliveries: deliveries,
            radio: radio
        )
    }

    static let fullTextLimit = 4_000

    /// A field's whole text with its paragraph breaks (controls and bidi overrides removed); nil when empty.
    static func full(_ item: [String: Any], _ key: String) -> String? {
        let text = HarnessgramCockpitParser.cleanHebrew(item[key], limit: fullTextLimit, multiline: true)
        return text.isEmpty ? nil : text
    }

    /// Exactly the JSON literal `false` (not 0, not "false", not missing).
    static func isJSONFalse(_ value: Any?) -> Bool {
        guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else {
            return false
        }
        return !number.boolValue
    }

    /// A finite JSON number, never a bool.
    private static func number(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite else {
            return nil
        }
        return number.doubleValue
    }
}

extension HarnessgramCockpitScreen {
    /// Simulator-only demo for the native Cockpit (HARNESSGRAM_DEMO_HOUSE=1): made-up lines, never real data. The same
    /// decisions as the House demo, with one old one, one routine one with a detail and a delivered answer receipt.
    public static func houseDemo(now: Date) -> HarnessgramCockpitScreen {
        let decisions = HarnessgramCockpitSnapshot.houseDemoOpenDecisions.enumerated().map { index, base -> Decision in
            var base = base
            base.askedAt = now.addingTimeInterval(-Double(120 + index * 900))
            if index == 0 {
                base.detail = "התיקון מחזיר את הכניסה עם קוד חד־פעמי.\nכל הבדיקות עברו, והשינוי מאחורי מתג."
            }
            return Decision(base: base, isOld: index == 6, routine: !base.sensitive, permissionRequest: nil, declineOnly: false)
        }
        return HarnessgramCockpitScreen(
            now: now,
            sessions: SessionCounts(working: 3, waiting: 2, idle: 4),
            waitingCount: decisions.count + 2,
            decisions: decisions.filter { !$0.isOld } + decisions.filter { $0.isOld },
            quota: [
                Quota(account: "main", label: "חשבון ראשי", weekly: 62, resetsAt: now.addingTimeInterval(2 * 86_400), banked: 1),
                Quota(account: "spare", label: "חשבון נוסף", weekly: 93, resetsAt: now.addingTimeInterval(5 * 3_600), banked: nil),
            ],
            deliveries: [Delivery(key: "demo-1", id: "0000000000000001", state: .delivered, retrying: false)],
            radio: HarnessgramCockpitSnapshot.Radio(enabled: true, on: true)
        )
    }
}
