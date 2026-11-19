import Foundation

/// The lock screen pack's view models ("flight deck"): the task card's headline, its altimeter, and the tower summary
/// the lock screen accessory widgets show. Plain values from the Cockpit snapshot and the task state only; nothing
/// here is made up. Foundation only, so every rule is unit tested without SwiftUI.

// MARK: Headline

/// The task card's title line, "<topic>: <title>", kept to one direction per line: English and Hebrew share a line
/// only when the English part is a short name (up to three words) wrapped in a bidi isolate (U+2068 ... U+2069).
/// Otherwise the topic moves to a small line of its own above the title (the eyebrow).
public struct HarnessgramTaskHeadline: Equatable, Sendable {
    /// The topic on its own line, or nil when it is part of `line` (or empty).
    public let eyebrow: String?
    public let line: String

    public init(eyebrow: String?, line: String) {
        self.eyebrow = eyebrow
        self.line = line
    }

    public static let isolateStart: Character = "\u{2068}"
    public static let isolateEnd: Character = "\u{2069}"
    /// The longest English name that may sit inside a Hebrew line.
    public static let shortNameWords = 3

    public static func hasHebrew(_ text: String) -> Bool {
        return text.unicodeScalars.contains { (0x0590 ... 0x05FF).contains($0.value) || (0xFB1D ... 0xFB4F).contains($0.value) }
    }

    public static func hasLatin(_ text: String) -> Bool {
        return text.unicodeScalars.contains { ("a" ... "z").contains($0) || ("A" ... "Z").contains($0) }
    }

    /// A Latin-only text of at most three words, wrapped in an isolate (once); nil when it is longer.
    public static func isolatedShortName(_ text: String) -> String? {
        let bare = text.filter { $0 != isolateStart && $0 != isolateEnd }
        let words = bare.split(whereSeparator: { $0.isWhitespace })
        guard !words.isEmpty, words.count <= shortNameWords else {
            return nil
        }
        return String(isolateStart) + bare + String(isolateEnd)
    }

    public static func make(topic: String, title: String) -> HarnessgramTaskHeadline {
        let topic = topic.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !topic.isEmpty else {
            return HarnessgramTaskHeadline(eyebrow: nil, line: title)
        }
        let topicHebrew = hasHebrew(topic)
        let titleHebrew = hasHebrew(title)
        let topicLatin = hasLatin(topic)
        let titleLatin = hasLatin(title)
        let oneLine = HarnessgramTaskHeadline(eyebrow: nil, line: "\(topic): \(title)")
        // No Hebrew at all (an untranslated card), or Hebrew on both sides (the bridge already isolates names
        // inside its Hebrew text): one line.
        if (!topicHebrew && !titleHebrew) || (topicHebrew && titleHebrew) {
            return oneLine
        }
        if titleHebrew {
            // A topic without letters (a number) joins as is; a short English name joins inside an isolate.
            if !topicLatin {
                return oneLine
            }
            if let name = isolatedShortName(topic) {
                return HarnessgramTaskHeadline(eyebrow: nil, line: "\(name): \(title)")
            }
        } else if !titleLatin {
            return oneLine
        }
        // Anything else would mix scripts on one line: the topic gets its own line.
        return HarnessgramTaskHeadline(eyebrow: topic, line: title)
    }
}

extension HarnessgramTaskState {
    public var headline: HarnessgramTaskHeadline {
        return HarnessgramTaskHeadline.make(topic: self.topic, title: self.title)
    }

    /// "שלב 2/5" for the watch-size card; "נחת בשלום" when every step is done; nil for a card without steps.
    public var stepShort: String? {
        if self.steps.isEmpty {
            return self.finished ? HarnessgramWidgetStrings.allStepsDone : nil
        }
        if self.currentStep == nil {
            return HarnessgramWidgetStrings.allStepsDone
        }
        return HarnessgramWidgetStrings.stepShort(self.done + 1, self.steps.count)
    }

    /// The badge on the card: "משימה פעילה", "הושלמה", or "אין עדכון" when iOS marks the activity stale.
    public func badge(isStale: Bool) -> String {
        if self.finished {
            return HarnessgramWidgetStrings.taskLanded
        }
        return isStale ? HarnessgramWidgetStrings.taskNoSignal : HarnessgramWidgetStrings.activeTask
    }
}

// MARK: Altimeter

/// The card's altimeter: the task's progress drawn as a climb to cruise altitude. Purely a picture of the percent
/// already on the card (0 % is the runway, 100 % is cruise), never a separate measurement.
public enum HarnessgramAltimeter {
    /// Cruise: where 100 % sits on the tape.
    public static let cruise = 17_000
    /// The tape shows this much above and below the current value.
    public static let halfSpan = 1_600
    /// A minor tick every 250 ft, a labelled one every 1,000 ft.
    public static let minorStep = 250
    public static let majorStep = 1_000

    /// The altitude for a progress fraction, to the nearest 10 ft, clamped to 0 ... cruise.
    public static func altitude(fraction: Double) -> Int {
        let clamped = fraction.isFinite ? min(1.0, max(0.0, fraction)) : 0.0
        return Int((clamped * Double(cruise) / 10.0).rounded()) * 10
    }

    public struct Tick: Equatable, Sendable {
        public let value: Int
        public let major: Bool
        /// -1 (bottom of the tape) ... 1 (top); 0 is the readout.
        public let offset: Double

        public init(value: Int, major: Bool, offset: Double) {
            self.value = value
            self.major = major
            self.offset = offset
        }
    }

    /// The ticks visible around `altitude`, lowest first; never below the ground (0).
    public static func ticks(around altitude: Int) -> [Tick] {
        let low = max(0, altitude - halfSpan)
        let high = altitude + halfSpan
        var value = (low + minorStep - 1) / minorStep * minorStep
        var out: [Tick] = []
        while value <= high {
            out.append(Tick(value: value, major: value % majorStep == 0, offset: Double(value - altitude) / Double(halfSpan)))
            value += minorStep
        }
        return out
    }

    /// "12,240": grouped digits in a fixed locale, so the tape reads the same on every phone.
    public static func label(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.groupingSeparator = ","
        formatter.groupingSize = 3
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    /// The compact dial's needle: -135° at 0 % to +135° at 100 % (0° points straight up).
    public static func needleDegrees(fraction: Double) -> Double {
        let clamped = fraction.isFinite ? min(1.0, max(0.0, fraction)) : 0.0
        return -135.0 + 270.0 * clamped
    }
}

// MARK: Tower summary (lock screen accessory widgets)

/// What the lock screen accessories show, from the widget's Cockpit snapshot: agents at work, what waits for the
/// owner, and the next decision with its age. nil snapshot (never synced, not paired, store busy) gives nil.
public struct HarnessgramTowerSummary: Equatable, Sendable {
    /// Working agent sessions ("in the air").
    public let running: Int
    /// Open decisions waiting for the owner (all of them, also beyond the snapshot's lines).
    public let waiting: Int
    /// The newest open decision's title, if any.
    public let nextTitle: String?
    /// The next decision is answered only in the app, after Face ID.
    public let nextSensitive: Bool
    /// When the next decision was asked (nil when the bridge sent no age).
    public let nextAskedAt: Date?
    /// Decisions after the next one.
    public let moreWaiting: Int

    public init(running: Int, waiting: Int, nextTitle: String?, nextSensitive: Bool, nextAskedAt: Date?, moreWaiting: Int) {
        self.running = running
        self.waiting = waiting
        self.nextTitle = nextTitle
        self.nextSensitive = nextSensitive
        self.nextAskedAt = nextAskedAt
        self.moreWaiting = moreWaiting
    }

    public init?(snapshot: HarnessgramCockpitSnapshot?) {
        guard let snapshot else {
            return nil
        }
        let next = snapshot.decisions.first
        let waiting = max(0, snapshot.waitingCount, snapshot.decisions.count)
        self.init(
            running: max(0, snapshot.runningAgents),
            waiting: waiting,
            nextTitle: next?.title,
            nextSensitive: next?.sensitive ?? false,
            nextAskedAt: next?.askedAt,
            moreWaiting: next == nil ? 0 : max(0, waiting - 1)
        )
    }

    /// "לפני 4 דק׳" for the next decision at `now`; nil without an age.
    public func nextAge(now: Date) -> String? {
        guard let asked = self.nextAskedAt else {
            return nil
        }
        return HarnessgramWidgetStrings.askedAgo(now.timeIntervalSince(asked))
    }

    /// "3 משימות באוויר · 1 מחכה לך".
    public var inlineLine: String {
        return HarnessgramWidgetStrings.tasksInAir(self.running) + " · " + HarnessgramWidgetStrings.waitingForYou(self.waiting)
    }

    /// The radar's spoken summary.
    public var radarAccessibility: String {
        return HarnessgramWidgetStrings.tasksInAir(self.running) + ", " + HarnessgramWidgetStrings.waitingForYou(self.waiting)
    }

    /// The radar's blips: at most `maxBlips` of each kind, each at a fixed bearing (degrees, 0 = up, clockwise) and
    /// distance (0 ... 1), so the picture is the same for the same counts.
    public static let maxBlips = 4

    public struct Blip: Equatable, Sendable {
        public let bearing: Double
        public let distance: Double
        public let waiting: Bool

        public init(bearing: Double, distance: Double, waiting: Bool) {
            self.bearing = bearing
            self.distance = distance
            self.waiting = waiting
        }
    }

    public var blips: [Blip] {
        let runningBearings: [Double] = [52, 128, 205, 300]
        let runningDistances: [Double] = [0.62, 0.42, 0.7, 0.5]
        let waitingBearings: [Double] = [338, 248, 92, 170]
        let waitingDistances: [Double] = [0.55, 0.66, 0.3, 0.6]
        var out: [Blip] = []
        for index in 0 ..< min(self.running, Self.maxBlips) {
            out.append(Blip(bearing: runningBearings[index], distance: runningDistances[index], waiting: false))
        }
        for index in 0 ..< min(self.waiting, Self.maxBlips) {
            out.append(Blip(bearing: waitingBearings[index], distance: waitingDistances[index], waiting: true))
        }
        return out
    }

    /// The sweep's bearing for a timeline entry: it moves on with every refresh (a quarter turn per 15 minutes),
    /// so the radar looks alive without animation.
    public static func sweepBearing(at date: Date) -> Double {
        let minutes = date.timeIntervalSince1970 / 60.0
        let degrees = (minutes * 6.0).truncatingRemainder(dividingBy: 360.0)
        return degrees < 0 ? degrees + 360.0 : degrees
    }
}
