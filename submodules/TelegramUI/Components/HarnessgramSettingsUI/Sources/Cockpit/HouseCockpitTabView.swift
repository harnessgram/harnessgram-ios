import Foundation
import UIKit
import SwiftUI
import Display
import AccountContext
import HarnessgramSettings
import HarnessgramCockpitKit
import HarnessgramHouseCore

/// The Cockpit tab (build 23): a native list in the Harnessgram settings style (SwiftUI in HarnessgramHostingScreen,
/// right to left). Open decisions with their answers, the task cards, the radio, the waiting list and the way into the
/// full Cockpit; pull to refresh, and the not-paired and empty states.
struct HouseCockpitTabView: View {
    @ObservedObject var model: HouseCockpitTabModel
    @ObservedObject var radio: HarnessgramRadioPlayer

    var body: some View {
        // One container, so switching between the two lists (rotation, Split View) never stops the polling.
        ZStack {
            switch self.model.listStyle {
            case .tower:
                HouseCockpitTowerListView(model: self.model, radio: self.radio)
            case .towerPhone:
                HouseCockpitPhoneTowerView(model: self.model, radio: self.radio)
            case .phone:
                self.phoneList
            }
        }
        .onAppear {
            self.model.start()
        }
        .onDisappear {
            self.model.stop()
        }
    }

    /// The phone list (compact width; on any width while pairing, loading, failed or empty).
    private var phoneList: some View {
        Form {
            // The same section list as the phone tower (HarnessgramCockpitDesk.pageSections).
            ForEach(HarnessgramCockpitDesk.pageSections(state: self.model.tab.state, tower: false), id: \.self) { section in
                self.section(section)
            }
        }
        .refreshable {
            await self.model.refreshAndWait()
        }
    }

    @ViewBuilder
    private func section(_ section: HarnessgramCockpitDesk.PageSection) -> some View {
        switch section {
        case .pairing:
            if case let .notPaired(paused) = self.model.tab.state {
                self.notPairedSection(paused: paused)
            }
        case .loading:
            Section {
                HStack(spacing: 12) {
                    ProgressView()
                    Text(HouseCockpitStrings.loading)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 6)
            }
        case .unavailable:
            if case let .unavailable(reason) = self.model.tab.state {
                self.unavailableSection(reason: reason)
            }
        case .empty:
            self.emptySection
        case .decisions:
            self.decisionsSection
        case .tasks:
            self.tasksSection
        case .radio:
            self.radioSection
        case .waitingList:
            self.waitingSection
        case .fullCockpit:
            self.fullCockpitSection
        case .instruments, .agents:
            // The phone tower's own additions.
            EmptyView()
        }
    }

    // MARK: States

    private func notPairedSection(paused: Bool) -> some View {
        Section {
            VStack(spacing: 12) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 40))
                    .foregroundColor(.accentColor)
                    .accessibilityHidden(true)
                Text(HouseCockpitStrings.notPairedTitle)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                Text(paused ? HouseCockpitStrings.pausedDetail : HouseCockpitStrings.notPairedDetail)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button(action: { self.model.pair() }) {
                    Label(self.model.pairing ? HouseCockpitStrings.pairing : HouseCockpitStrings.pair, systemImage: "faceid")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.harnessgramFilled)
                .disabled(self.model.pairing)
                if let message = self.model.pairMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
    }

    /// Connected, but no snapshot came: why (the failed step's own text), and a retry that asks the Cockpit now.
    private func unavailableSection(reason: HarnessgramPairFailure?) -> some View {
        Section {
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 40))
                    .foregroundColor(.orange)
                    .accessibilityHidden(true)
                Text(HouseCockpitStrings.unavailableTitle)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                Text(reason?.text ?? HouseCockpitStrings.unavailableNoAnswer)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button(action: { self.model.retry() }) {
                    Label(HouseCockpitStrings.retry, systemImage: "arrow.clockwise")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.harnessgramFilled)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
    }

    private var emptySection: some View {
        Section {
            VStack(spacing: 10) {
                Image(systemName: "checkmark.seal")
                    .font(.system(size: 40))
                    .foregroundColor(.green)
                    .accessibilityHidden(true)
                Text(HouseCockpitStrings.emptyTitle)
                    .font(.title3.weight(.semibold))
                Text(HouseCockpitStrings.emptyDetail)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
    }

    // MARK: Decisions

    private var decisionsSection: some View {
        let decisions = self.model.tab.decisions
        return Section(header: Text(HouseCockpitStrings.header(HouseCockpitStrings.decisionsHeader, count: self.model.tab.waitingCount)).textCase(nil)) {
            if decisions.isEmpty {
                Text(HouseCockpitStrings.decisionsEmpty)
                    .foregroundColor(.secondary)
            } else {
                ForEach(decisions) { decision in
                    HouseCockpitDecisionRow(model: self.model, decision: decision)
                }
            }
        }
    }

    // MARK: Tasks

    private var tasksSection: some View {
        let tasks = self.model.tab.tasks
        return Section(header: Text(HouseCockpitStrings.header(HouseCockpitStrings.tasksHeader, count: tasks.filter { !$0.finished }.count)).textCase(nil)) {
            if tasks.isEmpty {
                Text(HouseCockpitStrings.tasksEmpty)
                    .foregroundColor(.secondary)
            } else {
                ForEach(tasks) { task in
                    VStack(alignment: .leading, spacing: 6) {
                        Button(action: { self.model.openTask(task) }) {
                            HouseCockpitTaskRow(task: task)
                        }
                        .disabled(!self.model.canOpenTask(task))
                        .foregroundColor(.primary)
                        if task.hasOriginalText {
                            DisclosureGroup(HouseCockpitStrings.originalText) {
                                VStack(alignment: .leading, spacing: 4) {
                                    if let value = task.originalTitle, value != task.title { Text(value) }
                                    if let value = task.originalTopic, value != task.topic, !value.isEmpty { Text(value) }
                                    if let value = task.originalStep, value != task.step, !value.isEmpty { Text(value) }
                                }
                                .font(.footnote)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .environment(\.layoutDirection, .leftToRight)
                            }
                            .font(.footnote)
                        }
                    }
                }
            }
        }
    }

    // MARK: Radio, waiting list, full Cockpit

    private var radioSection: some View {
        Section(header: Text(HouseCockpitStrings.radioHeader).textCase(nil)) {
            HStack(spacing: 12) {
                Button(action: { self.model.toggleRadio() }) {
                    Image(systemName: self.radio.state == .playing ? "pause.circle.fill" : (self.radio.state == .connecting ? "xmark.circle.fill" : "play.circle.fill"))
                        .font(.system(size: 34))
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text(self.radio.buttonTitle))
                Button(action: { self.model.openRadio() }) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(HouseCockpitStrings.radioStation)
                                .foregroundColor(.primary)
                            Text(self.radio.hasListenLink ? (self.radio.state == .playing ? (self.radio.liveTitle ?? self.radio.stateText) : self.radio.stateText) : HouseCockpitStrings.radioNoLink)
                                .font(.footnote)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }
                        Spacer()
                        Image(systemName: "chevron.forward")
                            .foregroundColor(.secondary)
                            .accessibilityHidden(true)
                    }
                }
                .buttonStyle(.borderless)
            }
            .padding(.vertical, 2)
        }
    }

    private var waitingSection: some View {
        Section {
            Button(action: { self.model.openWaitingList() }) {
                HStack(spacing: 12) {
                    Image(systemName: "tray.full")
                        .foregroundColor(.accentColor)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(HouseCockpitStrings.waitingRow)
                            .foregroundColor(.primary)
                        Text(HouseCockpitStrings.waitingRowDetail)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    if self.model.tab.waitingCount > 0 {
                        Text("\(self.model.tab.waitingCount)")
                            .foregroundColor(.secondary)
                            .accessibilityLabel(Text(HouseCockpitStrings.waitingLabel(self.model.tab.waitingCount)))
                    }
                    Image(systemName: "chevron.forward")
                        .foregroundColor(.secondary)
                        .accessibilityHidden(true)
                }
            }
        }
    }

    private var fullCockpitSection: some View {
        Section {
            Button(action: { self.model.openFullCockpit() }) {
                Label {
                    Text(self.model.openingCockpit ? HouseCockpitStrings.fullCockpitOpening : HouseCockpitStrings.fullCockpit)
                } icon: {
                    // Takes off toward the reading direction (to the left in Hebrew), not against it.
                    Image(systemName: "airplane.departure")
                        .flipsForRightToLeftLayoutDirection(true)
                }
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.harnessgramFilled(busy: self.model.openingCockpit))
            .disabled(self.model.openingCockpit)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
        }
    }
}

/// One decision: the question, its room, and the buttons the widget rule allows (`HouseWaitingRowPlan`).
struct HouseCockpitDecisionRow: View {
    @ObservedObject var model: HouseCockpitTabModel
    let decision: HarnessgramCockpitSnapshot.Decision
    /// The question mark's colour (the tower passes its mint; the phone list keeps the app's accent).
    var iconColor: Color = .accentColor
    /// 50 in the phone tower: the bordered buttons grow past the 44-point touch target too, with the filled button's
    /// corner (40, the default, keeps the phone list's buttons as they were).
    @Environment(\.harnessgramMinimumTapHeight) private var minimumTapHeight

    var body: some View {
        let plan = self.model.plan(for: self.decision)
        let state = self.model.rowStates[self.decision.id]
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: self.decision.sensitive ? "lock.shield" : "questionmark.bubble")
                    .foregroundColor(self.decision.sensitive ? .orange : self.iconColor)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(self.decision.title)
                        .fixedSize(horizontal: false, vertical: true)
                    if !self.decision.topic.isEmpty {
                        Text(self.decision.topic)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                    if let detail = self.decision.detail, !detail.isEmpty {
                        Text(detail)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if self.decision.hasOriginalText {
                        DisclosureGroup(HouseCockpitStrings.originalText) {
                            VStack(alignment: .leading, spacing: 4) {
                                if let value = self.decision.originalTitle, value != self.decision.title { Text(value) }
                                if let value = self.decision.originalTopic, value != self.decision.topic, !value.isEmpty { Text(value) }
                                if let value = self.decision.originalDetail, value != self.decision.detail, !value.isEmpty { Text(value) }
                                if let value = self.decision.originalYesLabel, value != self.decision.yesLabel {
                                    // Hebrew caption inside the left-to-right original block: keep it on the right.
                                    Text(HouseCockpitStrings.originalYes)
                                        .frame(maxWidth: .infinity, alignment: .trailing)
                                    Text(value)
                                }
                                if let value = self.decision.originalNoLabel, value != self.decision.noLabel {
                                    // Hebrew caption inside the left-to-right original block: keep it on the right.
                                    Text(HouseCockpitStrings.originalNo)
                                        .frame(maxWidth: .infinity, alignment: .trailing)
                                    Text(value)
                                }
                                if let options = self.decision.originalOptions, options != self.decision.options {
                                    ForEach(Array(options.enumerated()), id: \.offset) { _, value in
                                        Text(value)
                                    }
                                }
                            }
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .environment(\.layoutDirection, .leftToRight)
                        }
                        .font(.footnote)
                    }
                }
            }
            HStack(spacing: 8) {
                switch plan.style {
                case .answerInPlace, .answerViaApp:
                    Button(plan.yesLabel) {
                        self.model.answer(self.decision, .yes)
                    }
                    .buttonStyle(.harnessgramFilled)
                    Button(plan.noLabel) {
                        self.model.answer(self.decision, .no)
                    }
                    .buttonStyle(.bordered)
                    .modifier(HouseCockpitTapTarget(height: self.minimumTapHeight))
                case .approveWithFaceID:
                    Button(action: { self.model.approveWithFaceID(self.decision) }) {
                        Label(HouseCockpitStrings.approve, systemImage: "faceid")
                    }
                    .buttonStyle(.harnessgramFilled)
                    .accessibilityLabel(Text(HouseCockpitStrings.approveFaceIDHint))
                    if self.model.canOpenRoom(self.decision) {
                        Button(HouseCockpitStrings.seeFirst) {
                            self.model.openRoom(self.decision)
                        }
                        .buttonStyle(.bordered)
                        .modifier(HouseCockpitTapTarget(height: self.minimumTapHeight))
                    }
                case .chooseInRoom:
                    Button(HouseCockpitStrings.choose) {
                        self.model.openRoom(self.decision)
                    }
                    .buttonStyle(.bordered)
                    .modifier(HouseCockpitTapTarget(height: self.minimumTapHeight))
                    .disabled(!self.model.canOpenRoom(self.decision))
                }
            }
            .disabled(state == .sending)
            if state == .sending {
                Text(HouseCockpitStrings.sending)
                    .font(.footnote)
                    .foregroundColor(.secondary)
            } else if case let .failed(text)? = state {
                Text(text)
                    .font(.footnote)
                    .foregroundColor(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }
}

/// A bordered button as tall as the house filled button beside it, with the same corner (the phone tower asks for 50;
/// at the default 40 the system bordered button stays exactly as it was).
private struct HouseCockpitTapTarget: ViewModifier {
    let height: CGFloat

    func body(content: Content) -> some View {
        if self.height > 40.0 {
            content
                .buttonBorderShape(.roundedRectangle(radius: 12.0))
                .controlSize(.large)
        } else {
            content
        }
    }
}

/// One task card: title, the step it is on (or "landed"), the bar and the percent.
struct HouseCockpitTaskRow: View {
    let task: HarnessgramCockpitTabViewModel.Task

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: self.task.finished ? "airplane.arrival" : "airplane")
                    .flipsForRightToLeftLayoutDirection(true)
                    .foregroundColor(self.task.finished ? .green : .accentColor)
                    .accessibilityHidden(true)
                Text(self.task.title)
                    .lineLimit(2)
                Spacer()
                Text("\(self.task.percent)%")
                    .font(.footnote.monospacedDigit())
                    .foregroundColor(.secondary)
            }
            ProgressView(value: self.task.fraction)
                .tint(self.task.finished ? .green : .accentColor)
            Text(self.task.finished ? HouseCockpitStrings.taskLanded : (self.task.step.isEmpty ? self.task.topic : self.task.step))
                .font(.footnote)
                .foregroundColor(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

/// The Cockpit tab's screen: a Harnessgram page with its own tab bar item (an SF Symbol in the cockpit spirit).
public func makeHouseCockpitTabController(context: AccountContext, openWaitingList: (() -> Void)? = nil) -> ViewController {
    let model = HouseCockpitTabModel(context: context)
    model.openWaitingListScreen = openWaitingList
    let view = HouseCockpitTabView(model: model, radio: .shared)
    let controller = HarnessgramHostingScreen(context: context, title: HouseCockpitStrings.screenTitle, content: view)
    model.controller = controller
    controller.layoutUpdated = { [weak model] layout in
        model?.updateLayout(layout)
    }
    // The phone tower is a full-bleed dark page (its own header under the status bar); the other looks keep the
    // theme's page with its navigation bar.
    model.listStyleChanged = { [weak controller] style in
        controller?.setFullBleed(background: style == .towerPhone ? HouseTowerPalette.backgroundUIColor : nil)
    }
    // The first look follows the window's width class (Telegram's own rule), not the phone default.
    model.seedWidthClass(windowSize: context.sharedContext.mainWindow?.hostView.containerView.bounds.size)
    model.applyListStyle()
    let configuration = UIImage.SymbolConfiguration(pointSize: 21.0, weight: .regular)
    let icon = (UIImage(systemName: "gauge.with.dots.needle.67percent", withConfiguration: configuration) ?? UIImage(systemName: "airplane", withConfiguration: configuration))?.withRenderingMode(.alwaysTemplate)
    controller.tabBarItem.title = HouseCockpitStrings.tabTitle
    controller.tabBarItem.image = icon
    controller.tabBarItem.selectedImage = icon
    return controller
}

/// Whether a root tab is the Cockpit tab.
public func isHouseCockpitTabController(_ controller: ViewController) -> Bool {
    return controller is HarnessgramHostingScreen<HouseCockpitTabView>
}
