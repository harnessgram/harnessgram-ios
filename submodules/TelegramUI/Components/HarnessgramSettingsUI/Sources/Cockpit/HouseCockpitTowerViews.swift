import Foundation
import UIKit
import SwiftUI
import Display
import AccountContext
import HarnessgramCockpitKit
import HarnessgramHouseCore

// MARK: The tower list (the Cockpit tab's list column in the wide layout)

/// The Cockpit tab's list in the wide layout: the tower header, the decisions that belong to no task, the flight
/// strips (a tap puts the task on the desk beside the list), and the same radio, waiting list and full Cockpit rows as
/// the phone list. Every element of the phone list stays reachable here or on the desk.
struct HouseCockpitTowerListView: View {
    @ObservedObject var model: HouseCockpitTabModel
    @ObservedObject var radio: HarnessgramRadioPlayer
    /// false only for snapshot renders (ImageRenderer draws no scroll view content).
    var scrolls = true

    var body: some View {
        let tab = self.model.tab
        let unassigned = HarnessgramCockpitDesk.unassignedDecisions(tab.decisions, tasks: tab.tasks)
        let waitingByTask = HarnessgramCockpitDesk.waitingByTask(tasks: tab.tasks, decisions: tab.decisions)
        ZStack {
            HouseTowerBackground().ignoresSafeArea()
            HouseTowerScroll(scrolls: self.scrolls) {
                VStack(alignment: .leading, spacing: 12) {
                    self.header
                    // The flight board first (the tower's list); the decisions of no listed task right below it (the
                    // header already counts everything that waits, and each strip says what waits in its room).
                    self.sectionTitle(HouseCockpitStrings.header(HouseCockpitStrings.tasksHeader, count: tab.tasks.filter { !$0.finished }.count), systemImage: "list.bullet.rectangle")
                    if tab.tasks.isEmpty {
                        Text(HouseCockpitStrings.tasksEmpty)
                            .foregroundColor(HouseTowerPalette.secondaryText)
                            .houseTowerCard()
                    } else {
                        ForEach(tab.tasks) { task in
                            HouseCockpitFlightStrip(task: task, selected: task.id == self.model.selectedTaskId, waiting: waitingByTask[task.id] ?? 0, action: { self.model.select(task) })
                        }
                    }
                    if !unassigned.isEmpty {
                        self.sectionTitle(HouseCockpitStrings.header(HouseCockpitStrings.decisionsHeader, count: unassigned.count), systemImage: "checkmark.shield")
                        ForEach(unassigned) { decision in
                            HouseCockpitDecisionRow(model: self.model, decision: decision, iconColor: HouseTowerPalette.accent)
                                .houseTowerCard()
                        }
                    }
                    if !self.model.deskShowsRadio {
                        HouseCockpitTowerRadioCard(model: self.model, radio: self.radio)
                    }
                    HouseCockpitTowerWaitingRow(model: self.model)
                    HouseCockpitTowerFullCockpitButton(model: self.model)
                }
                .padding(16)
            }
            .modifier(HouseTowerRefreshable(model: self.model))
        }
        .modifier(HouseTowerArrowKeys(model: self.model))
        .tint(HouseTowerPalette.accent)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            HouseTowerBadge(size: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(HouseCockpitStrings.towerTitle)
                    .font(.title2.weight(.bold))
                    .foregroundColor(HouseTowerPalette.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(HouseCockpitStrings.towerLine(flying: self.model.tab.tasks.filter { !$0.finished }.count, waiting: self.model.tab.waitingCount))
                    .font(.subheadline)
                    .foregroundColor(HouseTowerPalette.secondaryText)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.bottom, 4)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private func sectionTitle(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.headline)
            .foregroundColor(HouseTowerPalette.primaryText)
            .padding(.top, 6)
            .accessibilityAddTraits(.isHeader)
    }
}

/// The waiting list's row as a glass card (the phone list's "מעגל ההמתנה" row): the count in an amber capsule.
struct HouseCockpitTowerWaitingRow: View {
    @ObservedObject var model: HouseCockpitTabModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button(action: { self.model.openWaitingList() }) {
            HStack(spacing: 12) {
                Image(systemName: "tray.full")
                    .foregroundColor(HouseTowerPalette.accent)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(HouseCockpitStrings.waitingRow)
                        .foregroundColor(HouseTowerPalette.primaryText)
                    Text(HouseCockpitStrings.waitingRowDetail)
                        .font(.footnote)
                        .foregroundColor(HouseTowerPalette.secondaryText)
                        .lineLimit(self.dynamicTypeSize.isAccessibilitySize ? nil : 2)
                }
                Spacer(minLength: 8)
                if self.model.tab.waitingCount > 0 {
                    Text("\(self.model.tab.waitingCount)")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundColor(HouseTowerPalette.background)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(HouseTowerPalette.horizonGlow))
                        .accessibilityLabel(Text(HouseCockpitStrings.waitingLabel(self.model.tab.waitingCount)))
                }
                Image(systemName: "chevron.forward")
                    .foregroundColor(HouseTowerPalette.secondaryText)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 44)
            .houseTowerCard()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .modifier(HouseTowerHover())
    }
}

/// "לקוקפיט המלא" in the house filled style, the plane taking off toward the reading direction.
struct HouseCockpitTowerFullCockpitButton: View {
    @ObservedObject var model: HouseCockpitTabModel

    var body: some View {
        Button(action: { self.model.openFullCockpit() }) {
            Label {
                Text(self.model.openingCockpit ? HouseCockpitStrings.fullCockpitOpening : HouseCockpitStrings.fullCockpit)
            } icon: {
                Image(systemName: "airplane.departure")
                    .flipsForRightToLeftLayoutDirection(true)
            }
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.harnessgramFilled(busy: self.model.openingCockpit))
        .disabled(self.model.openingCockpit)
        .padding(.top, 4)
    }
}

/// One flight strip: the plane, the task's name (two lines at most), its step and percent, the bar, and how many
/// decisions wait in its room. Selected: the mint glow.
struct HouseCockpitFlightStrip: View {
    let task: HarnessgramCockpitTabViewModel.Task
    let selected: Bool
    let waiting: Int
    let action: () -> Void

    var body: some View {
        Button(action: self.action) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Circle()
                            .fill(self.waiting > 0 ? HouseTowerPalette.horizonGlow : (self.task.finished ? HouseTowerPalette.approve : HouseTowerPalette.accent))
                            .frame(width: 9, height: 9)
                            .accessibilityHidden(true)
                        Text(self.task.title)
                            .font(.headline)
                            .foregroundColor(HouseTowerPalette.primaryText)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(HouseCockpitStrings.stripLine(position: HarnessgramCockpitDesk.stepPosition(self.task), percent: self.task.percent, finished: self.task.finished) + (self.task.topic.isEmpty ? "" : " · " + self.task.topic))
                        .font(.footnote)
                        .foregroundColor(HouseTowerPalette.secondaryText)
                        .lineLimit(1)
                    HouseTowerBar(fraction: self.task.fraction, finished: self.task.finished, height: 5)
                    if self.waiting > 0 {
                        Label(HouseCockpitStrings.deskWaiting(self.waiting), systemImage: "hand.raised.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(HouseTowerPalette.horizonGlow)
                    }
                }
                HouseTowerPlane(finished: self.task.finished)
                    .font(.title3)
            }
            .houseTowerCard(selected: self.selected, padding: 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .modifier(HouseTowerHover())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(self.selected ? [.isSelected, .isButton] : .isButton)
    }
}

/// The radio as a card (the phone list's radio row): play or pause, and the way to the radio screen.
struct HouseCockpitTowerRadioCard: View {
    @ObservedObject var model: HouseCockpitTabModel
    @ObservedObject var radio: HarnessgramRadioPlayer
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(spacing: 12) {
            Button(action: { self.model.toggleRadio() }) {
                Image(systemName: self.radio.state == .playing ? "pause.circle.fill" : (self.radio.state == .connecting ? "xmark.circle.fill" : "play.circle.fill"))
                    .font(.system(size: 36))
                    .foregroundColor(HouseTowerPalette.accent)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .modifier(HouseTowerHover())
            .accessibilityLabel(Text(self.radio.buttonTitle))
            Button(action: { self.model.openRadio() }) {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Label(HouseCockpitStrings.radioStation, systemImage: "dot.radiowaves.left.and.right")
                            .font(.headline)
                            .foregroundColor(HouseTowerPalette.primaryText)
                        Text(self.radio.hasListenLink ? (self.radio.state == .playing ? (self.radio.liveTitle ?? self.radio.stateText) : self.radio.stateText) : HouseCockpitStrings.radioNoLink)
                            .font(.footnote)
                            .foregroundColor(HouseTowerPalette.secondaryText)
                            .lineLimit(self.dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.forward")
                        .foregroundColor(HouseTowerPalette.secondaryText)
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .houseTowerCard()
    }
}

/// Pull to refresh on the tower list (a scroll view refreshes from iOS 16).
private struct HouseTowerRefreshable: ViewModifier {
    let model: HouseCockpitTabModel

    func body(content: Content) -> some View {
        if #available(iOS 16.0, *) {
            content.refreshable {
                await self.model.refreshAndWait()
            }
        } else {
            content
        }
    }
}

/// The pointer's highlight on iPad (trackpad or mouse).
struct HouseTowerHover: ViewModifier {
    func body(content: Content) -> some View {
        content.hoverEffect(.highlight)
    }
}

/// Up and down arrows on a hardware keyboard move the selection along the strips (iOS 17).
private struct HouseTowerArrowKeys: ViewModifier {
    let model: HouseCockpitTabModel

    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content
                .focusable()
                .focusEffectDisabled()
                .onKeyPress(.downArrow) {
                    self.model.moveSelection(by: 1)
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    self.model.moveSelection(by: -1)
                    return .handled
                }
        } else {
            content
        }
    }
}

// MARK: The desk (the detail column)

/// The selected task's desk: its state, name, every step, the altimeter, the bar, when it last moved, the way to its
/// room, its original text and the decisions waiting in its room (the same rows and answers as the phone list).
/// Beside it (wide enough) or below it: the radar with the agents at work, and the radio.
struct HouseCockpitDeskView: View {
    @ObservedObject var model: HouseCockpitTabModel
    @ObservedObject var radio: HarnessgramRadioPlayer

    var body: some View {
        GeometryReader { proxy in
            let columns = HarnessgramCockpitDesk.deskColumns(width: Double(proxy.size.width))
            ZStack {
                HouseTowerBackground().ignoresSafeArea()
                ScrollView {
                    Group {
                        if columns == 2 {
                            // Right to left: the radar column at the start edge (far from the list column), the task
                            // in the middle of the screen beside the list.
                            HStack(alignment: .top, spacing: 16) {
                                self.rail
                                    .frame(width: 280)
                                self.taskColumn
                                    .frame(maxWidth: .infinity)
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 16) {
                                self.taskColumn
                                self.rail
                            }
                        }
                    }
                    .padding(16)
                }
            }
        }
        .tint(HouseTowerPalette.accent)
        .onAppear {
            self.model.deskShowsRadio = true
        }
        .onDisappear {
            self.model.deskShowsRadio = false
        }
    }

    // MARK: The task

    @ViewBuilder
    private var taskColumn: some View {
        if let task = self.model.selectedTask {
            VStack(alignment: .leading, spacing: 16) {
                self.taskCard(task)
                let decisions = HarnessgramCockpitDesk.decisions(for: task, in: self.model.tab.decisions)
                if !decisions.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(HouseCockpitStrings.header(HouseCockpitStrings.deskTaskDecisions, count: decisions.count), systemImage: "hand.raised.fill")
                            .font(.headline)
                            .foregroundColor(HouseTowerPalette.horizonGlow)
                            .accessibilityAddTraits(.isHeader)
                        ForEach(decisions) { decision in
                            HouseCockpitDecisionRow(model: self.model, decision: decision, iconColor: HouseTowerPalette.accent)
                            if decision.id != decisions.last?.id {
                                Divider().overlay(HouseTowerPalette.track)
                            }
                        }
                    }
                    .houseTowerCard()
                }
            }
        } else {
            VStack(spacing: 12) {
                HouseTowerBadge(size: 56)
                Text(self.model.tab.tasks.isEmpty ? HouseCockpitStrings.tasksEmpty : HouseCockpitStrings.deskPickTask)
                    .font(.headline)
                    .foregroundColor(HouseTowerPalette.secondaryText)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .houseTowerCard()
        }
    }

    private func taskCard(_ task: HarnessgramCockpitTabViewModel.Task) -> some View {
        let headline = HarnessgramTaskHeadline.make(topic: task.topic, title: task.title)
        let position = HarnessgramCockpitDesk.stepPosition(task)
        return VStack(alignment: .leading, spacing: 16) {
            // The state badge.
            HStack(spacing: 8) {
                HouseTowerPlane(finished: task.finished)
                Text(task.finished ? HouseCockpitStrings.deskLanded : HouseCockpitStrings.deskActive)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(task.finished ? HouseTowerPalette.approve : HouseTowerPalette.accent)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(HouseTowerPalette.background.opacity(0.7)))
            .overlay(Capsule().stroke((task.finished ? HouseTowerPalette.approve : HouseTowerPalette.accent).opacity(0.7), lineWidth: 1))

            // The name: the topic on its own line when it cannot share the title's line (one direction per line).
            VStack(alignment: .leading, spacing: 4) {
                if let eyebrow = headline.eyebrow {
                    Text(eyebrow)
                        .font(.subheadline)
                        .foregroundColor(HouseTowerPalette.secondaryText)
                        .lineLimit(1)
                }
                Text(headline.line)
                    .font(.title2.weight(.bold))
                    .foregroundColor(HouseTowerPalette.primaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
            }

            // The plan beside the altimeter (the tape at the end edge, as on the lock screen card).
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    let rows = HarnessgramCockpitDesk.stepRows(task)
                    if !rows.isEmpty {
                        Text(HouseCockpitStrings.deskSteps)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(HouseTowerPalette.secondaryText)
                        ForEach(rows) { row in
                            HouseCockpitDeskStepRow(row: row)
                        }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(HouseCockpitStrings.deskProgress)
                                .foregroundColor(HouseTowerPalette.secondaryText)
                            Spacer()
                            Text("\(task.percent)%")
                                .font(.headline.monospacedDigit())
                                .foregroundColor(task.finished ? HouseTowerPalette.approve : HouseTowerPalette.accent)
                        }
                        HouseTowerBar(fraction: task.fraction, finished: task.finished, height: 10)
                    }
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(spacing: 6) {
                    Text(HouseCockpitStrings.deskAltitude)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(HouseTowerPalette.secondaryText)
                    HouseTowerAltimeterTape(fraction: task.fraction, finished: task.finished)
                        .frame(width: 92, height: 200)
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(HouseTowerPalette.background.opacity(0.6)))
            }

            // When it last moved, which step, which room.
            HStack(alignment: .top, spacing: 0) {
                if let position {
                    self.stat(HouseCockpitStrings.deskStepLabel, HouseCockpitStrings.deskStepOf(position.current, position.total), systemImage: "list.number")
                }
                if let updated = task.updated {
                    self.stat(HouseCockpitStrings.deskUpdatedLabel, HarnessgramWidgetStrings.askedAgo(Date().timeIntervalSince1970 - updated), systemImage: "clock")
                }
                if !task.topic.isEmpty {
                    self.stat(HouseCockpitStrings.deskRoomLabel, task.topic, systemImage: "bubble.left.and.bubble.right")
                }
            }
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(HouseTowerPalette.background.opacity(0.6)))

            Button(action: { self.model.openTask(task) }) {
                Label(HouseCockpitStrings.deskOpenRoom, systemImage: "bubble.left.and.text.bubble.right")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.harnessgramFilled)
            .disabled(!self.model.canOpenTask(task))

            if task.hasOriginalText {
                DisclosureGroup(HouseCockpitStrings.originalText) {
                    VStack(alignment: .leading, spacing: 4) {
                        if let value = task.originalTitle, value != task.title { Text(value) }
                        if let value = task.originalTopic, value != task.topic, !value.isEmpty { Text(value) }
                        if let value = task.originalStep, value != task.step, !value.isEmpty { Text(value) }
                    }
                    .font(.footnote)
                    .foregroundColor(HouseTowerPalette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .environment(\.layoutDirection, .leftToRight)
                }
                .font(.footnote)
            }
        }
        .houseTowerCard(padding: 16)
    }

    private func stat(_ title: String, _ value: String, systemImage: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: systemImage)
                .foregroundColor(HouseTowerPalette.accent)
                .accessibilityHidden(true)
            Text(title)
                .font(.caption)
                .foregroundColor(HouseTowerPalette.secondaryText)
                .lineLimit(1)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(HouseTowerPalette.primaryText)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.85)
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    // MARK: Radar and radio

    private var rail: some View {
        VStack(alignment: .leading, spacing: 16) {
            self.radarCard
            HouseCockpitTowerRadioCard(model: self.model, radio: self.radio)
        }
    }

    private var radarCard: some View {
        let tower = self.model.tab.tower
        let running = tower?.running ?? 0
        return VStack(alignment: .leading, spacing: 12) {
            Label(HouseCockpitStrings.deskAgents, systemImage: "scope")
                .font(.headline)
                .foregroundColor(HouseTowerPalette.primaryText)
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 4) {
                self.count(HouseCockpitStrings.deskRunning(running), color: HouseTowerPalette.accent)
                if self.model.tab.waitingCount > 0 {
                    self.count(HouseCockpitStrings.deskWaiting(self.model.tab.waitingCount), color: HouseTowerPalette.horizonGlow)
                }
            }
            HouseTowerRadar(summary: tower, sweep: HarnessgramTowerSummary.sweepBearing(at: Date()))
                .frame(height: 180)
                .frame(maxWidth: 220)
                .frame(maxWidth: .infinity)
            if self.model.tab.agents.isEmpty {
                Text(HouseCockpitStrings.deskNoAgents)
                    .font(.footnote)
                    .foregroundColor(HouseTowerPalette.secondaryText)
            } else {
                ForEach(self.model.tab.agents.prefix(6)) { agent in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        HouseTowerPlane(finished: false)
                            .font(.footnote)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(agent.name.isEmpty ? HouseCockpitStrings.deskUnnamedAgent : agent.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(HouseTowerPalette.primaryText)
                                .lineLimit(2)
                            if !agent.step.isEmpty {
                                Text(agent.step)
                                    .font(.footnote)
                                    .foregroundColor(HouseTowerPalette.secondaryText)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .houseTowerCard()
    }

    private func count(_ text: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 9, height: 9).accessibilityHidden(true)
            Text(text)
                .font(.subheadline)
                .foregroundColor(HouseTowerPalette.primaryText)
        }
    }
}

/// One step of the plan: a check when done, the glowing ring on the current one, a hollow ring ahead.
private struct HouseCockpitDeskStepRow: View {
    let row: HarnessgramCockpitDesk.StepRow

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                switch self.row.state {
                case .done:
                    Circle().fill(HouseTowerPalette.accent.opacity(0.9))
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundColor(HouseTowerPalette.background)
                case .current:
                    Circle().stroke(HouseTowerPalette.accent, lineWidth: 2)
                    Text("\(self.row.index + 1)")
                        .font(.system(size: 12, weight: .bold).monospacedDigit())
                        .foregroundColor(HouseTowerPalette.accent)
                case .ahead:
                    Circle().stroke(HouseTowerPalette.secondaryText.opacity(0.6), lineWidth: 1.2)
                    Text("\(self.row.index + 1)")
                        .font(.system(size: 12, weight: .medium).monospacedDigit())
                        .foregroundColor(HouseTowerPalette.secondaryText)
                }
            }
            .frame(width: 24, height: 24)
            .shadow(color: self.row.state == .current ? HouseTowerPalette.accent.opacity(0.6) : .clear, radius: 5)
            .accessibilityHidden(true)
            Text(self.row.title)
                .font(self.row.state == .current ? .body.weight(.semibold) : .body)
                .foregroundColor(self.row.state == .ahead ? HouseTowerPalette.secondaryText : HouseTowerPalette.primaryText)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(self.row.state == .current ? HouseTowerPalette.accent.opacity(0.12) : HouseTowerPalette.background.opacity(0.5)))
        .accessibilityElement(children: .combine)
    }
}

/// The desk screen for the detail column (a Harnessgram page like the tab itself).
func makeHouseCockpitDeskController(context: AccountContext, model: HouseCockpitTabModel) -> ViewController {
    let view = HouseCockpitDeskView(model: model, radio: .shared)
    let controller = HarnessgramHostingScreen(context: context, title: HouseCockpitStrings.deskTitle, content: view)
    // In compact navigation the covered tab may not receive a layout; the visible detail reports it too.
    controller.layoutUpdated = { [weak model] layout in
        model?.updateLayout(layout)
    }
    return controller
}
