import Foundation
import CoreGraphics
import HarnessgramSettings
import HarnessgramCockpitKit

/// The native Cockpit tab (build 23): what it shows, built from the snapshot HarnessgramCockpitSync already fetches for
/// the widgets. Pure, so the screen and the tests read the same rules: decisions in the bridge's order (newest first),
/// task cards most recently updated first, the waiting count, and the not-paired and empty states.
public struct HarnessgramCockpitTabViewModel: Equatable, Sendable {
    public enum State: Equatable, Sendable {
        /// The widgets are not connected to the bridge: the tab offers the one-tap pairing. `paused` after a second
        /// account, a switch or a logout.
        case notPaired(paused: Bool)
        /// Connected, but the first read has not arrived yet.
        case loading
        /// Connected, and no snapshot came: the last read failed (its reason), or nothing arrived within
        /// `loadingTimeout` (nil). The tab says so and offers a retry instead of waiting forever.
        case unavailable(HarnessgramPairFailure?)
        /// Connected, and nothing waits and nothing flies.
        case empty
        case content
    }

    public struct Task: Equatable, Identifiable, Sendable {
        public var id: String
        public var title: String
        public var topic: String
        /// The step the card is on now ("" when the bridge sent no steps).
        public var step: String
        /// 0 ... 100.
        public var percent: Int
        public var finished: Bool
        public var topicURL: String
        public var updated: Double?
        public var originalTitle: String? = nil
        public var originalTopic: String? = nil
        public var originalStep: String? = nil
        /// Every step of the card's plan, in order, and how many are done (the wide layout's desk lists them all).
        public var steps: [String] = []
        public var done: Int = 0

        public var hasOriginalText: Bool {
            return HarnessgramCockpitParser.hasTranslation(self.title, original: self.originalTitle, limit: 140)
                || HarnessgramCockpitParser.hasTranslation(self.topic, original: self.originalTopic, limit: 60)
                || HarnessgramCockpitParser.hasTranslation(self.step, original: self.originalStep, limit: 100)
        }

        public var fraction: Double {
            return Double(self.percent) / 100.0
        }
    }

    public var state: State
    public var decisions: [HarnessgramCockpitSnapshot.Decision]
    public var tasks: [Task]
    /// Every open decision, also the ones the widget snapshot does not keep.
    public var waitingCount: Int
    public var updatedAt: Date?
    /// The tower's counts and radar blips (agents at work, decisions waiting); nil without a snapshot.
    public var tower: HarnessgramTowerSummary? = nil
    /// The agent sessions at work, as the bridge listed them (the wide layout's radar column).
    public var agents: [HarnessgramCockpitSnapshot.Agent] = []
    /// The bridge's "wideCockpit" switch (on unless the snapshot says false): the two-pane tower on wide screens.
    public var wideCockpit: Bool = true
    /// The bridge's "towerPhone" switch (on unless the snapshot says false): the phone tower on compact width. Without
    /// a snapshot (not paired, loading, no answer, a cold launch) the last value a snapshot carried
    /// (HarnessgramCockpitLookMemory), so the off switch also reaches those pages; on when none was ever seen.
    public var towerPhone: Bool = true

    /// How long the tab waits on view for the first snapshot before it says that nothing came.
    public static let loadingTimeout: TimeInterval = 15.0

    public static func make(snapshot: HarnessgramCockpitSnapshot?, openDecisions: [HarnessgramCockpitSnapshot.Decision]?, isPaired: Bool, isPaused: Bool) -> HarnessgramCockpitTabViewModel {
        return HarnessgramCockpitTabViewModel.make(snapshot: snapshot, openDecisions: openDecisions, isPaired: isPaired, isPaused: isPaused, failure: nil, loadingSince: nil, now: Date())
    }

    /// - Parameters:
    ///   - failure: why the last read failed; nil after a read stored a snapshot, or while a retry the owner asked for
    ///     runs.
    ///   - loadingSince: when the tab started waiting on view (it appeared, or the owner asked to retry); nil when it
    ///     is not on view.
    ///   - rememberedTowerPhone: the last "towerPhone" value a snapshot carried; used only without a snapshot.
    public static func make(snapshot: HarnessgramCockpitSnapshot?, openDecisions: [HarnessgramCockpitSnapshot.Decision]?, isPaired: Bool, isPaused: Bool, failure: HarnessgramPairFailure?, loadingSince: Date?, now: Date, rememberedTowerPhone: Bool? = nil) -> HarnessgramCockpitTabViewModel {
        guard isPaired else {
            var model = HarnessgramCockpitTabViewModel(state: .notPaired(paused: isPaused), decisions: [], tasks: [], waitingCount: 0, updatedAt: nil)
            model.towerPhone = rememberedTowerPhone ?? true
            return model
        }
        guard let snapshot else {
            let state = HarnessgramCockpitTabViewModel.waitingState(failure: failure, loadingSince: loadingSince, now: now)
            var model = HarnessgramCockpitTabViewModel(state: state, decisions: [], tasks: [], waitingCount: 0, updatedAt: nil)
            model.towerPhone = rememberedTowerPhone ?? true
            return model
        }
        let decisions = openDecisions ?? snapshot.decisions
        let tasks = HarnessgramCockpitTabViewModel.orderedTasks(snapshot.progress)
        let waiting = max(snapshot.waitingCount, decisions.count)
        let state: State = decisions.isEmpty && tasks.isEmpty ? .empty : .content
        return HarnessgramCockpitTabViewModel(state: state, decisions: decisions, tasks: tasks, waitingCount: waiting, updatedAt: snapshot.updatedAt, tower: HarnessgramCockpitDesk.tower(snapshot: snapshot, decisions: decisions, waiting: waiting), agents: snapshot.agents, wideCockpit: HarnessgramCockpitSnapshot.wideCockpitOn(snapshot), towerPhone: HarnessgramCockpitSnapshot.towerPhoneOn(snapshot))
    }

    /// Paired with no snapshot: the failed read's reason, else nothing within the time limit, otherwise still loading.
    static func waitingState(failure: HarnessgramPairFailure?, loadingSince: Date?, now: Date) -> State {
        if let failure {
            return .unavailable(failure)
        }
        if let loadingSince, now.timeIntervalSince(loadingSince) >= HarnessgramCockpitTabViewModel.loadingTimeout {
            return .unavailable(nil)
        }
        return .loading
    }

    /// When the tab should look again for the time limit (nil: no wait is running).
    public static func loadingDeadline(loadingSince: Date?) -> Date? {
        return loadingSince.map { $0.addingTimeInterval(HarnessgramCockpitTabViewModel.loadingTimeout) }
    }

    /// Newest updated first; a card without a time goes after the timed ones, in the bridge's order. Stale cards stay out.
    public static func orderedTasks(_ progress: [HarnessgramCockpitSnapshot.Progress]) -> [Task] {
        let indexed = progress.enumerated().filter { $0.element.stale != true }
        let sorted = indexed.sorted { a, b in
            switch (a.element.updated, b.element.updated) {
            case let (x?, y?) where x != y:
                return x > y
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                return a.offset < b.offset
            }
        }
        return sorted.map { HarnessgramCockpitTabViewModel.task($0.element) }
    }

    static func task(_ card: HarnessgramCockpitSnapshot.Progress) -> Task {
        let done = min(max(card.done, 0), card.steps.count)
        let step: String
        if card.steps.isEmpty {
            step = ""
        } else if done < card.steps.count {
            step = card.steps[done]
        } else {
            step = card.steps[card.steps.count - 1]
        }
        let percent: Int
        if card.finished {
            percent = 100
        } else if let value = card.percent {
            percent = min(max(value, 0), 100)
        } else if !card.steps.isEmpty {
            percent = done * 100 / card.steps.count
        } else {
            percent = 0
        }
        let originalSteps = card.originalSteps ?? card.steps
        let originalStep = originalSteps.isEmpty ? nil : originalSteps[min(done, originalSteps.count - 1)]
        return Task(id: card.id, title: card.title, topic: card.topic, step: step, percent: percent, finished: card.finished, topicURL: card.topicURL, updated: card.updated, originalTitle: card.originalTitle, originalTopic: card.originalTopic, originalStep: originalStep, steps: card.steps, done: done)
    }
}

/// Where the Cockpit tab sits in the root tab bar: right after Chats, only while its switch is on.
public enum HarnessgramCockpitTabPlacement {
    public static func isIncluded(settings: HarnessgramSettings = .shared) -> Bool {
        return settings.cockpitTab
    }

    /// `tabs` with `cockpit` inserted after the Chats tab (before the last tab when there is no Chats tab), or without
    /// it when the switch is off. A tab list that already holds the Cockpit keeps one copy.
    public static func arrange<T>(_ tabs: [T], cockpit: T, include: Bool, isChats: (T) -> Bool, isCockpit: (T) -> Bool) -> [T] {
        var result = tabs.filter { !isCockpit($0) }
        guard include else {
            return result
        }
        if let chats = result.firstIndex(where: isChats) {
            result.insert(cockpit, at: chats + 1)
        } else {
            result.insert(cockpit, at: max(0, result.count - 1))
        }
        return result
    }
}

/// The floating Cockpit button's place (build 23): it rests against the left or right edge, within the area that the
/// status bar, the tab bar and the keyboard leave free, and remembers its height as a fraction of that area.
public enum HarnessgramCockpitFloatingButtonLayout {
    public static let diameter: CGFloat = 52.0
    /// Space between the button and the screen edge or a bar.
    public static let margin: CGFloat = 16.0
    /// Where it sits before the owner moves it: the left edge (the far side of a right-to-left list), low on the screen.
    public static let defaultRightEdge = false
    public static let defaultY: Double = 0.85

    /// The free area for the button's centre.
    public static func centerArea(bounds: CGSize, top: CGFloat, bottom: CGFloat, left: CGFloat = 0.0, right: CGFloat = 0.0) -> CGRect {
        let half = HarnessgramCockpitFloatingButtonLayout.diameter / 2.0
        let m = HarnessgramCockpitFloatingButtonLayout.margin
        let minX = left + m + half
        let maxX = max(minX, bounds.width - right - m - half)
        let minY = top + m + half
        let maxY = max(minY, bounds.height - bottom - m - half)
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// Clamps a dragged centre into the area and snaps it to the nearer edge.
    public static func snapped(_ point: CGPoint, area: CGRect) -> CGPoint {
        let y = min(max(point.y, area.minY), area.maxY)
        let x = point.x < area.midX ? area.minX : area.maxX
        return CGPoint(x: x, y: y)
    }

    /// The centre for a stored place (edge and height fraction) in the current area.
    public static func center(rightEdge: Bool, y: Double, area: CGRect) -> CGPoint {
        let fraction = CGFloat(min(max(y.isFinite ? y : HarnessgramCockpitFloatingButtonLayout.defaultY, 0.0), 1.0))
        return CGPoint(x: rightEdge ? area.maxX : area.minX, y: area.minY + area.height * fraction)
    }

    /// The place to store for a snapped centre.
    public static func position(of center: CGPoint, area: CGRect) -> (rightEdge: Bool, y: Double) {
        let rightEdge = center.x >= area.midX
        let y = area.height > 0.0 ? Double((center.y - area.minY) / area.height) : HarnessgramCockpitFloatingButtonLayout.defaultY
        return (rightEdge, min(max(y, 0.0), 1.0))
    }
}

/// The last "towerPhone" switch a Cockpit snapshot carried, kept in the app group's defaults (the store the Cockpit
/// and its extensions share), so the pages without a snapshot and a cold launch draw the look the bridge chose.
public struct HarnessgramCockpitLookMemory: @unchecked Sendable {
    public static let towerPhoneKey = "Harnessgram.cockpit.towerPhone.v1"

    private let defaults: UserDefaults?

    public init(defaults: UserDefaults?) {
        self.defaults = defaults
    }

    /// `group.<base bundle id>` (an extension drops its own last bundle id component); standard defaults without it.
    public static func appGroupDefaults() -> UserDefaults {
        guard var id = Bundle.main.bundleIdentifier else {
            return .standard
        }
        if Bundle.main.bundleURL.pathExtension == "appex", let dot = id.range(of: ".", options: .backwards) {
            id = String(id[..<dot.lowerBound])
        }
        return UserDefaults(suiteName: "group." + id) ?? .standard
    }

    public static let shared = HarnessgramCockpitLookMemory(defaults: HarnessgramCockpitLookMemory.appGroupDefaults())

    public var towerPhone: Bool? {
        return self.defaults?.object(forKey: HarnessgramCockpitLookMemory.towerPhoneKey) as? Bool
    }

    /// Writes only a change.
    public func remember(towerPhone: Bool) {
        guard self.towerPhone != towerPhone else {
            return
        }
        self.defaults?.set(towerPhone, forKey: HarnessgramCockpitLookMemory.towerPhoneKey)
    }
}
