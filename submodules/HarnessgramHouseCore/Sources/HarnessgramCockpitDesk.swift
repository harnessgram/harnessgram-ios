import Foundation
import CoreGraphics
import HarnessgramCockpitKit

/// The Cockpit tab on wide screens, "מגדל פיקוח" (control tower): iPad in any orientation, Split View and Stage Manager
/// windows, and the unfolded iPhone Duo. Telegram's root navigation splits into a list column and a detail column
/// whenever its layout has the regular width class; the Cockpit tab then draws its list as flight strips (the tower
/// list) and the detail column shows the selected task's desk. The phone (compact width) keeps its list as it was.
/// Pure rules only, so the screens and the tests read the same decisions.
public enum HarnessgramCockpitDesk {
    /// How the Cockpit tab's list draws.
    public enum ListStyle: Equatable, Sendable {
        /// The phone list (compact width, and every state without content on any width).
        case phone
        /// Flight strips beside the selected task's desk (regular width with content).
        case tower
        /// The phone tower (compact width, every state): the dark control-tower page with the instruments, what waits
        /// for the owner first, the lead flight and the flight strips, the agents, the radio and the full Cockpit.
        case towerPhone
    }

    /// The tower list only in the regular width class (the app is split into list and detail columns), only with
    /// content (pairing, loading, the error and the empty state keep the phone list's own pages), and only while the
    /// bridge's "wideCockpit" switch is on (false: the phone list everywhere, as before). The compact width shows the
    /// phone tower while the bridge's "towerPhone" switch is on, in every state (false: today's phone list exactly).
    /// The regular width never shows the phone tower: its rule above stays as it was.
    public static func listStyle(isRegularWidth: Bool, state: HarnessgramCockpitTabViewModel.State, wideCockpit: Bool = true, towerPhone: Bool = false) -> ListStyle {
        if !isRegularWidth {
            return towerPhone ? .towerPhone : .phone
        }
        guard wideCockpit, case .content = state else {
            return .phone
        }
        return .tower
    }

    /// Telegram's width class for a window size (Display's layoutMetricsForWindowSize): regular above 690 x 650
    /// points. Seeds the tab before its first layout, so an iPad never draws one frame of the phone tower.
    public static func isRegularWidth(windowSize: CGSize) -> Bool {
        return windowSize.width > 690.0 && windowSize.height > 650.0
    }

    /// The parts of the Cockpit tab's phone pages, in order. Both phone looks read this one list, so the phone tower
    /// keeps every section of the phone list (it adds its instruments and the agents).
    public enum PageSection: String, CaseIterable, Sendable {
        case pairing
        case loading
        case unavailable
        case empty
        case instruments
        case decisions
        case tasks
        case agents
        case radio
        case waitingList
        case fullCockpit
    }

    public static func pageSections(state: HarnessgramCockpitTabViewModel.State, tower: Bool) -> [PageSection] {
        var sections: [PageSection]
        var isPaired = true
        switch state {
        case .notPaired:
            sections = [.pairing]
            isPaired = false
        case .loading:
            sections = [.loading]
        case .unavailable:
            sections = [.unavailable]
        case .empty:
            sections = [.empty]
        case .content:
            sections = tower ? [.instruments, .decisions, .tasks, .agents] : [.decisions, .tasks]
        }
        sections.append(.radio)
        if isPaired {
            sections.append(.waitingList)
        }
        sections.append(.fullCockpit)
        return sections
    }

    // MARK: The phone tower

    /// The phone tower's lead flight (the big card under the header): the first task still in the air, in the tab's
    /// order (the most recently updated first); nil when every task landed or there is none.
    public static func leadTask(_ tasks: [HarnessgramCockpitTabViewModel.Task]) -> HarnessgramCockpitTabViewModel.Task? {
        return tasks.first(where: { !$0.finished })
    }

    /// The flight strips below the lead flight: every other task, in the same order, so each task shows once.
    public static func stripTasks(_ tasks: [HarnessgramCockpitTabViewModel.Task]) -> [HarnessgramCockpitTabViewModel.Task] {
        guard let lead = HarnessgramCockpitDesk.leadTask(tasks) else {
            return tasks
        }
        return tasks.filter { $0.id != lead.id }
    }

    /// The desk's narrowest width that also fits the radar and radio column beside the task (iPad landscape; the
    /// portrait iPad, Split View and the unfolded phone get one column with that part below the task).
    public static let railMinWidth: Double = 720.0

    /// 2 (task and the radar/radio column) or 1 (one column) for the desk's width.
    public static func deskColumns(width: Double) -> Int {
        return width.isFinite && width >= HarnessgramCockpitDesk.railMinWidth ? 2 : 1
    }

    // MARK: Selection

    /// The selected task after the list changed: the same task while it is still listed, otherwise the first one
    /// (nil without tasks). Rotation and size changes never touch it.
    public static func resolvedSelection(_ current: String?, tasks: [HarnessgramCockpitTabViewModel.Task]) -> String? {
        if let current, tasks.contains(where: { $0.id == current }) {
            return current
        }
        return tasks.first?.id
    }

    /// The arrow keys: the next (`delta` 1) or previous (-1) task, clamped at both ends.
    public static func movedSelection(_ current: String?, by delta: Int, tasks: [HarnessgramCockpitTabViewModel.Task]) -> String? {
        guard !tasks.isEmpty else {
            return nil
        }
        guard let current, let index = tasks.firstIndex(where: { $0.id == current }) else {
            return tasks.first?.id
        }
        let next = min(max(index + delta, 0), tasks.count - 1)
        return tasks[next].id
    }

    // MARK: Decisions beside their task

    /// A topic link compared without case, surrounding spaces or a trailing slash; nil when there is none.
    public static func topicKey(_ url: String) -> String? {
        var value = url.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        while value.hasSuffix("/") {
            value.removeLast()
        }
        return value.isEmpty ? nil : value
    }

    /// The open decisions asked in the task's own topic (same topic link), in the bridge's order.
    public static func decisions(for task: HarnessgramCockpitTabViewModel.Task, in decisions: [HarnessgramCockpitSnapshot.Decision]) -> [HarnessgramCockpitSnapshot.Decision] {
        guard let key = HarnessgramCockpitDesk.topicKey(task.topicURL) else {
            return []
        }
        return decisions.filter { HarnessgramCockpitDesk.topicKey($0.topicURL) == key }
    }

    /// The decisions that belong to no listed task: the tower list shows them above the strips, so every decision is
    /// on screen exactly once (the others sit on their task's desk, and their strip says that something waits).
    public static func unassignedDecisions(_ decisions: [HarnessgramCockpitSnapshot.Decision], tasks: [HarnessgramCockpitTabViewModel.Task]) -> [HarnessgramCockpitSnapshot.Decision] {
        let keys = Set(tasks.compactMap { HarnessgramCockpitDesk.topicKey($0.topicURL) })
        return decisions.filter { decision in
            guard let key = HarnessgramCockpitDesk.topicKey(decision.topicURL) else {
                return true
            }
            return !keys.contains(key)
        }
    }

    // MARK: The task's plan

    public enum StepState: Equatable, Sendable {
        case done
        case current
        case ahead
    }

    public struct StepRow: Equatable, Identifiable, Sendable {
        public let index: Int
        public let title: String
        public let state: StepState

        public var id: Int {
            return self.index
        }

        public init(index: Int, title: String, state: StepState) {
            self.index = index
            self.title = title
            self.state = state
        }
    }

    /// Every step with its state: done before `done`, the one at `done` is current, the rest ahead; all done once
    /// the task landed.
    public static func stepRows(_ task: HarnessgramCockpitTabViewModel.Task) -> [StepRow] {
        let done = min(max(task.done, 0), task.steps.count)
        return task.steps.enumerated().map { index, title in
            let state: StepState
            if task.finished || index < done {
                state = .done
            } else if index == done {
                state = .current
            } else {
                state = .ahead
            }
            return StepRow(index: index, title: title, state: state)
        }
    }

    /// (step number, of) for "שלב 3 מתוך 5": the current step, the last one once all are done; nil without steps.
    public static func stepPosition(_ task: HarnessgramCockpitTabViewModel.Task) -> (current: Int, total: Int)? {
        guard !task.steps.isEmpty else {
            return nil
        }
        let done = min(max(task.done, 0), task.steps.count)
        let current = task.finished ? task.steps.count : min(done + 1, task.steps.count)
        return (current, task.steps.count)
    }

    /// How many open decisions wait in each task's topic, by task id (tasks without any are left out).
    public static func waitingByTask(tasks: [HarnessgramCockpitTabViewModel.Task], decisions: [HarnessgramCockpitSnapshot.Decision]) -> [String: Int] {
        var out: [String: Int] = [:]
        for task in tasks {
            let count = HarnessgramCockpitDesk.decisions(for: task, in: decisions).count
            if count > 0 {
                out[task.id] = count
            }
        }
        return out
    }

    // MARK: Radar

    /// The tower's counts for the radar: agents at work from the snapshot, and the tab's own waiting count (every open
    /// decision, also those the widget snapshot does not keep).
    public static func tower(snapshot: HarnessgramCockpitSnapshot, decisions: [HarnessgramCockpitSnapshot.Decision], waiting: Int) -> HarnessgramTowerSummary {
        let next = decisions.first
        let count = max(0, waiting)
        return HarnessgramTowerSummary(running: max(0, snapshot.runningAgents), waiting: count, nextTitle: next?.title, nextSensitive: next?.sensitive ?? false, nextAskedAt: next?.askedAt, moreWaiting: next == nil ? 0 : max(0, count - 1))
    }
}
