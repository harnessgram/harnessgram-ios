import Foundation

/// What the widgets show: the owner's open decisions, the agents that are working, the radio and the
/// agents' progress cards, as the bridge's Cockpit last reported them. It holds no credential and no
/// session or chat id beyond the t.me topic links the Cockpit already shows.
public struct HarnessgramCockpitSnapshot: Codable, Equatable, Sendable {
    public struct Decision: Codable, Equatable, Identifiable, Sendable {
        public var id: String
        public var title: String
        public var topic: String
        public var yesLabel: String
        public var noLabel: String
        public var topicURL: String
        /// Sensitive decisions are answered only inside the app, after Face ID. The bridge does not mark
        /// decisions yet, so a decision without the mark is sensitive (fail closed).
        public var sensitive: Bool
        /// The Telegram channel id of the project group (the room) the decision came from, read from `topicURL`.
        public var roomChannelId: Int64?
        /// The kind of question the bridge asks ("yesno", "choice", ...). nil until the bridge sends it; the
        /// app then treats the decision as a yes/no question.
        public var kind: String?
        /// The answers of a choice question, in the bridge's order (nil for yes/no).
        public var options: [String]?
        public var detail: String?
        public var originalTitle: String?
        public var originalTopic: String?
        public var originalDetail: String?
        public var originalYesLabel: String?
        public var originalNoLabel: String?
        public var originalOptions: [String]?
        /// When the question was asked: the panel's "now" less the decision's "age". nil when the bridge sends no
        /// usable age (an older bridge, or a stored snapshot from before the field existed).
        public var askedAt: Date?

        public var hasOriginalText: Bool {
            return HarnessgramCockpitParser.hasTranslation(self.title, original: self.originalTitle, limit: 140)
                || HarnessgramCockpitParser.hasTranslation(self.topic, original: self.originalTopic, limit: 60)
                || HarnessgramCockpitParser.hasTranslation(self.detail, original: self.originalDetail, limit: 1_500)
                || HarnessgramCockpitParser.hasTranslation(self.yesLabel, original: self.originalYesLabel, limit: 24)
                || HarnessgramCockpitParser.hasTranslation(self.noLabel, original: self.originalNoLabel, limit: 24)
                || zip(self.options ?? [], self.originalOptions ?? []).contains { display, original in
                    HarnessgramCockpitParser.hasTranslation(display, original: original, limit: 60)
                }
        }

        public init(id: String, title: String, topic: String, yesLabel: String, noLabel: String, topicURL: String, sensitive: Bool, roomChannelId: Int64? = nil, kind: String? = nil, options: [String]? = nil, detail: String? = nil, originalTitle: String? = nil, originalTopic: String? = nil, originalDetail: String? = nil, originalYesLabel: String? = nil, originalNoLabel: String? = nil, originalOptions: [String]? = nil, askedAt: Date? = nil) {
            self.id = id
            self.title = title
            self.topic = topic
            self.yesLabel = yesLabel
            self.noLabel = noLabel
            self.topicURL = topicURL
            self.sensitive = sensitive
            self.roomChannelId = roomChannelId
            self.kind = kind
            self.options = options
            self.detail = detail
            self.originalTitle = originalTitle
            self.originalTopic = originalTopic
            self.originalDetail = originalDetail
            self.originalYesLabel = originalYesLabel
            self.originalNoLabel = originalNoLabel
            self.originalOptions = originalOptions
            self.askedAt = askedAt
        }
    }

    public struct Agent: Codable, Equatable, Identifiable, Sendable {
        public var id: String
        public var name: String
        /// The agent's current step ("" when the Cockpit has none).
        public var step: String
        public var topicURL: String
        public var roomChannelId: Int64?
        public var originalName: String?
        public var originalStep: String?

        public init(id: String, name: String, step: String, topicURL: String, roomChannelId: Int64? = nil, originalName: String? = nil, originalStep: String? = nil) {
            self.id = id
            self.name = name
            self.step = step
            self.topicURL = topicURL
            self.roomChannelId = roomChannelId
            self.originalName = originalName
            self.originalStep = originalStep
        }
    }

    public struct Progress: Codable, Equatable, Identifiable, Sendable {
        public var id: String
        public var title: String
        public var topic: String
        public var steps: [String]
        /// Steps done (0 ... steps.count).
        public var done: Int
        public var percent: Int?
        public var topicURL: String
        public var finished: Bool
        public var roomChannelId: Int64?
        /// When the card's plan last moved (steps, percent or title), in seconds since 1970: the bridge's "updated".
        /// Optional, so a snapshot stored before the field existed, or a bridge that does not send it, still decodes.
        public var updated: Double?
        /// The Cockpit marks the card stale (no sign of work for a while). Optional for the same reason; the parser
        /// already drops stale cards, so this only guards a card that reaches the Live Activity another way.
        public var stale: Bool?
        public var originalTitle: String?
        public var originalTopic: String?
        public var originalSteps: [String]?

        public init(id: String, title: String, topic: String, steps: [String], done: Int, percent: Int?, topicURL: String, finished: Bool, roomChannelId: Int64? = nil, updated: Double? = nil, stale: Bool? = nil, originalTitle: String? = nil, originalTopic: String? = nil, originalSteps: [String]? = nil) {
            self.id = id
            self.title = title
            self.topic = topic
            self.steps = steps
            self.done = done
            self.percent = percent
            self.topicURL = topicURL
            self.finished = finished
            self.roomChannelId = roomChannelId
            self.updated = updated
            self.stale = stale
            self.originalTitle = originalTitle
            self.originalTopic = originalTopic
            self.originalSteps = originalSteps
        }
    }

    public struct Radio: Codable, Equatable, Sendable {
        public var enabled: Bool
        public var on: Bool

        public init(enabled: Bool, on: Bool) {
            self.enabled = enabled
            self.on = on
        }
    }

    /// The bridge's owner-ledger summary for Today.
    public struct Today: Codable, Equatable, Sendable {
        public struct Waiting: Codable, Equatable, Sendable {
            public let title: String
            public let ageMinutes: Int
            public let url: URL

            public init(title: String, ageMinutes: Int, url: URL) {
                self.title = title
                self.ageMinutes = ageMinutes
                self.url = url
            }
        }

        public static let maxWaiting = 3
        public static let empty = Today(doneToday: 0, totalToday: 0, waiting: [])

        public let doneToday: Int
        public let totalToday: Int
        public let waiting: [Waiting]

        public init(doneToday: Int, totalToday: Int, waiting: [Waiting]) {
            self.totalToday = min(max(0, totalToday), 9_999)
            self.doneToday = min(max(0, doneToday), self.totalToday)
            self.waiting = waiting
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.init(
                doneToday: try container.decode(Int.self, forKey: .doneToday),
                totalToday: try container.decode(Int.self, forKey: .totalToday),
                waiting: try container.decode([Waiting].self, forKey: .waiting)
            )
        }
    }

    public static let maxDecisions = 5
    public static let maxAgents = 5
    public static let maxProgress = 3

    public var updatedAt: Date
    /// All fresh decisions, also those beyond `decisions`.
    public var waitingCount: Int
    /// Newest first, at most `maxDecisions`.
    public var decisions: [Decision]
    public var runningAgents: Int
    public var agents: [Agent]
    public var radio: Radio?
    /// Open progress cards, unfinished first and the most recently updated of those first.
    public var progress: [Progress]
    /// A short line for the owner after a widget answer could not be sent.
    public var notice: String?
    /// The bridge bot's Telegram user id, as the bridge's own authenticated panel reports it (getMe; "bot_id").
    /// The only source that pins the bridge (HarnessgramBridgeIdentity.observePanel).
    public var botId: Int64?
    /// Translations still in progress. nil when an older bridge does not report the count.
    public var pending: Int?
    /// The bridge panel's switches for new looks (nil: an older bridge, or a snapshot stored before the field
    /// existed). Every look is on unless its switch is explicitly false.
    public var appSwitches: AppSwitches?
    /// nil in snapshots saved before the Today widget was added.
    public var today: Today?

    /// Remote switches for new looks, set in the bridge panel ("appSwitches" in the panel's state). A key that is
    /// missing, or the whole object missing, means on, so a new look works before the bridge knows the key; only an
    /// explicit false brings back the old look exactly as it was. Bug fixes never get a switch.
    public struct AppSwitches: Codable, Equatable, Sendable {
        /// The Cockpit tab's two-pane tower on iPad, Split View and the unfolded phone.
        public var wideCockpit: Bool?
        /// The overflow summary Live Activity's rows (what waits, the hidden tasks), instead of "+N" with a radar.
        public var summaryRows: Bool?
        /// The Cockpit tab's phone tower (compact width): the dark control-tower page instead of the system list.
        public var towerPhone: Bool?

        public init(wideCockpit: Bool? = nil, summaryRows: Bool? = nil, towerPhone: Bool? = nil) {
            self.wideCockpit = wideCockpit
            self.summaryRows = summaryRows
            self.towerPhone = towerPhone
        }

        /// Tolerant: an object with booleans (JSON true/false, 0/1, or the strings true/false/on/off/1/0); anything
        /// else in a key counts as missing (on). Not an object: nil (every look on).
        public static func parse(_ value: Any?) -> AppSwitches? {
            guard let object = value as? [String: Any] else {
                return nil
            }
            return AppSwitches(wideCockpit: AppSwitches.flag(object["wideCockpit"] ?? object["wide_cockpit"]), summaryRows: AppSwitches.flag(object["summaryRows"] ?? object["summary_rows"]), towerPhone: AppSwitches.flag(object["towerPhone"] ?? object["tower_phone"]))
        }

        static func flag(_ value: Any?) -> Bool? {
            if let number = value as? NSNumber {
                // JSON true/false arrive as NSNumber too; any number other than 0 and 1 is not a switch value.
                if CFGetTypeID(number) == CFBooleanGetTypeID() {
                    return number.boolValue
                }
                switch number.intValue {
                case 0 where number.doubleValue == 0:
                    return false
                case 1 where number.doubleValue == 1:
                    return true
                default:
                    return nil
                }
            }
            if let text = value as? String {
                switch text.trimmingCharacters(in: .whitespaces).lowercased() {
                case "true", "on", "1", "yes":
                    return true
                case "false", "off", "0", "no":
                    return false
                default:
                    return nil
                }
            }
            if let flag = value as? Bool {
                return flag
            }
            return nil
        }
    }

    /// The two-pane Cockpit on wide screens (on unless the bridge switched it off).
    public static func wideCockpitOn(_ snapshot: HarnessgramCockpitSnapshot?) -> Bool {
        return snapshot?.appSwitches?.wideCockpit ?? true
    }

    /// The overflow summary's rows (on unless the bridge switched them off).
    public static func summaryRowsOn(_ snapshot: HarnessgramCockpitSnapshot?) -> Bool {
        return snapshot?.appSwitches?.summaryRows ?? true
    }

    /// The phone tower in the Cockpit tab on compact width (on unless the bridge switched it off).
    public static func towerPhoneOn(_ snapshot: HarnessgramCockpitSnapshot?) -> Bool {
        return snapshot?.appSwitches?.towerPhone ?? true
    }

    public init(updatedAt: Date, waitingCount: Int, decisions: [Decision], runningAgents: Int, agents: [Agent], radio: Radio?, progress: [Progress], notice: String? = nil, botId: Int64? = nil, pending: Int? = nil, appSwitches: AppSwitches? = nil, today: Today? = nil) {
        self.updatedAt = updatedAt
        self.waitingCount = waitingCount
        self.decisions = decisions
        self.runningAgents = runningAgents
        self.agents = agents
        self.radio = radio
        self.progress = progress
        self.notice = notice
        self.botId = botId
        self.pending = pending
        self.appSwitches = appSwitches
        self.today = today
    }

    /// The snapshot after the owner answered `id`: the line goes away at once, before the next refresh.
    public func removingDecision(_ id: String) -> HarnessgramCockpitSnapshot {
        var copy = self
        if copy.decisions.contains(where: { $0.id == id }) {
            copy.decisions.removeAll(where: { $0.id == id })
            copy.waitingCount = max(0, copy.waitingCount - 1)
        }
        copy.notice = nil
        return copy
    }

    public func withNotice(_ notice: String?) -> HarnessgramCockpitSnapshot {
        var copy = self
        copy.notice = notice
        return copy
    }

    /// Shown before the first refresh and in the widget gallery: made-up lines, never real data.
    public static let sample = HarnessgramCockpitSnapshot(
        updatedAt: Date(timeIntervalSince1970: 1_763_200_000),
        waitingCount: 3,
        decisions: [
            Decision(id: "0000000000000001", title: "למזג את תיקון ההתחברות?", topic: "פרויקט לדוגמה: מסך כניסה", yesLabel: "כן", noLabel: "לא", topicURL: "", sensitive: false, askedAt: Date(timeIntervalSince1970: 1_763_200_000 - 120)),
            Decision(id: "0000000000000002", title: "לשלוח את הסרטון לקבוצת ההורים?", topic: "תדריך בוקר", yesLabel: "כן", noLabel: "לא", topicURL: "", sensitive: true),
            Decision(id: "0000000000000003", title: "לבחור את עיצוב ב לדף הבית?", topic: "חנות לדוגמה: עיצוב", yesLabel: "כן", noLabel: "לא", topicURL: "", sensitive: false),
        ],
        runningAgents: 2,
        agents: [
            Agent(id: "a1", name: "הרנסגרם: וידג׳טים", step: "בונה את המסך", topicURL: ""),
            Agent(id: "a2", name: "פרויקט לדוגמה: בדיקות", step: "מריץ בדיקות", topicURL: ""),
        ],
        radio: Radio(enabled: true, on: true),
        progress: [
            Progress(id: "p1", title: "בניית גרסה 13", topic: "הרנסגרם", steps: ["קוד", "בדיקות", "בנייה", "העלאה"], done: 2, percent: 55, topicURL: "", finished: false),
        ]
    )

    /// Simulator-only demo for the House screens (HARNESSGRAM_DEMO_HOUSE=1): made-up lines in the channels of the
    /// project groups in approved.json, never real data. `houseDemoOpenDecisions` holds more lines than the widget
    /// snapshot keeps, as a real busy day does.
    public static let houseDemoOpenDecisions: [Decision] = {
        let rooms: [(channel: Int64, name: String)] = [(900000001, "גשר"), (900000002, "פרויקט לדוגמה"), (900000003, "תוכן לדוגמה"), (900000004, "חנות לדוגמה")]
        let titles = ["למזג את תיקון ההתחברות?", "לשלוח את הסרטון לקבוצת ההורים?", "לבחור את עיצוב ב לדף הבית?", "להעלות גרסה חדשה לבדיקה?", "לאשר את נוסח ההודעה?", "לפתוח בקשה חדשה?", "לעצור את הריצה הארוכה?"]
        return titles.enumerated().map { index, title in
            let room = rooms[index % rooms.count]
            return Decision(id: String(format: "%016x", index + 1), title: title, topic: room.name, yesLabel: "כן", noLabel: "לא", topicURL: "https://t.me/c/\(room.channel)/\(index + 2)", sensitive: index % 3 == 1, roomChannelId: room.channel, kind: index == 2 ? "choice" : nil, options: index == 2 ? ["א", "ב", "ג"] : nil)
        }
    }()

    public static let houseDemo = HarnessgramCockpitSnapshot(
        updatedAt: Date(),
        waitingCount: houseDemoOpenDecisions.count,
        decisions: Array(houseDemoOpenDecisions.prefix(maxDecisions)),
        runningAgents: 2,
        agents: [
            Agent(id: "a1", name: "פרויקט לדוגמה: בדיקות", step: "מריץ בדיקות", topicURL: "https://t.me/c/900000002/40", roomChannelId: 900000002),
            Agent(id: "a2", name: "תוכן לדוגמה: תוכן", step: "כותב סיכום", topicURL: "https://t.me/c/900000003/41", roomChannelId: 900000003),
        ],
        radio: Radio(enabled: true, on: false),
        // Several flights, so the wide Cockpit (the tower list and its desk) has a board to show; two share their
        // topic with an open decision (the first and the fourth), as a task that asks the owner something does.
        progress: [
            Progress(id: "p1", title: "בניית גרסה 16", topic: "גשר", steps: ["קוד", "בדיקות", "בנייה", "העלאה"], done: 2, percent: 55, topicURL: "https://t.me/c/900000001/42", finished: false, roomChannelId: 900000001, updated: Date().timeIntervalSince1970 - 360),
            Progress(id: "p2", title: "תיקון מסך ההתחברות", topic: "גשר", steps: ["סריקת קוד", "בדיקות", "סקירה", "מיזוג"], done: 3, percent: 76, topicURL: "https://t.me/c/900000001/2", finished: false, roomChannelId: 900000001, updated: Date().timeIntervalSince1970 - 120),
            Progress(id: "p3", title: "סרטון הסיכום השבועי", topic: "תוכן לדוגמה", steps: ["תסריט", "קריינות", "עריכה", "העלאה"], done: 1, percent: 38, topicURL: "https://t.me/c/900000003/41", finished: false, roomChannelId: 900000003, updated: Date().timeIntervalSince1970 - 900),
            Progress(id: "p4", title: "עמוד הבית החדש", topic: "חנות לדוגמה", steps: ["עיצוב", "קוד", "בדיקות"], done: 0, percent: 10, topicURL: "https://t.me/c/900000004/5", finished: false, roomChannelId: 900000004, updated: Date().timeIntervalSince1970 - 1_800),
            Progress(id: "p5", title: "סקירת אבטחה", topic: "פרויקט לדוגמה", steps: ["סריקה", "תיקונים", "בדיקה חוזרת"], done: 3, percent: 100, topicURL: "https://t.me/c/900000002/40", finished: true, roomChannelId: 900000002, updated: Date().timeIntervalSince1970 - 3_600),
        ]
    )
}
