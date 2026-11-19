import ActivityKit
import HarnessgramAgent
import HarnessgramCockpitKit
import HarnessgramSettings
import SwiftUI
import TelegramCore
import UIKit
import WidgetKit

@MainActor
public func harnessgramSampleOpenError() -> UIAlertController {
    let alert = UIAlertController(title: nil, message: SampleBannerStrings.failedToOpen, preferredStyle: .alert)
    alert.view.semanticContentAttribute = .forceRightToLeft
    alert.addAction(UIAlertAction(title: SampleBannerStrings.ok, style: .default))
    return alert
}

@MainActor
public func harnessgramSampleController(store: HarnessgramSampleStore, chats: [HarnessgramDemoSeed.OfflineChat], state: HarnessgramSampleStore.State, onExit: @escaping () -> Void) -> UIViewController {
    let model = HarnessgramSampleModel(store: store, state: state, chats: chats, onExit: onExit)
    let controller = UIHostingController(rootView: HarnessgramSampleView(model: model))
    controller.modalPresentationStyle = .fullScreen
    controller.isModalInPresentation = true
    return controller
}

@MainActor
public func endHarnessgramSampleActivities() async {
    if #available(iOS 16.2, *) {
        for activity in Activity<HarnessgramTaskActivityAttributes>.activities where activity.attributes.cardId.hasPrefix(HarnessgramSampleStore.activityIDPrefix) {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}

@MainActor
private final class HarnessgramSampleModel: ObservableObject {
    @Published private(set) var state: HarnessgramSampleStore.State
    @Published private(set) var exiting = false
    @Published var error: String?

    let chats: [HarnessgramDemoSeed.OfflineChat]
    private let store: HarnessgramSampleStore
    private let onExit: () -> Void

    init(store: HarnessgramSampleStore, state: HarnessgramSampleStore.State, chats: [HarnessgramDemoSeed.OfflineChat], onExit: @escaping () -> Void) {
        self.store = store
        self.state = state
        self.chats = chats
        self.onExit = onExit
    }

    private func save(_ updated: HarnessgramSampleStore.State) -> Bool {
        guard !self.exiting else { return false }
        do {
            try self.store.write(updated)
            self.state = updated
            return true
        } catch {
            self.error = SampleBannerStrings.failedToSave
            return false
        }
    }

    func answer(_ id: String, choice: HarnessgramCockpitLinks.Choice) -> HarnessgramSampleStore.State.AnswerResult? {
        var updated = self.state
        let result = updated.answer(id, choice: choice)
        if result == .applied {
            guard self.save(updated) else { return nil }
            WidgetCenter.shared.reloadAllTimelines()
        }
        return result
    }

    func isFilterOn(_ rule: HarnessgramFilterRule) -> Bool {
        !self.state.disabledFilterRules.contains(rule.rawValue)
    }

    func setFilter(_ rule: HarnessgramFilterRule, enabled: Bool) {
        var updated = self.state
        if enabled {
            updated.disabledFilterRules.remove(rule.rawValue)
        } else {
            updated.disabledFilterRules.insert(rule.rawValue)
        }
        _ = self.save(updated)
    }

    func exit() {
        guard !self.exiting else { return }
        self.exiting = true
        do {
            try self.store.erase()
        } catch {
            self.exiting = false
            self.error = SampleBannerStrings.failedToErase
            return
        }
        WidgetCenter.shared.reloadAllTimelines()
        self.onExit()
        Task {
            await endHarnessgramSampleActivities()
        }
    }

    func showActivity(_ progress: HarnessgramCockpitSnapshot.Progress) -> Bool {
        guard !self.exiting, #available(iOS 16.2, *), ActivityAuthorizationInfo().areActivitiesEnabled else {
            return false
        }
        let id = HarnessgramSampleStore.activityIDPrefix + progress.id
        if Activity<HarnessgramTaskActivityAttributes>.activities.contains(where: { $0.attributes.cardId == id && HarnessgramTaskActivityPlan.isLive($0.activityState) }) {
            return true
        }
        var state = HarnessgramTaskState(progress: progress)
        state.topic = SampleBannerStrings.heading.hebrew
        let content = ActivityContent(state: state, staleDate: nil)
        return (try? Activity<HarnessgramTaskActivityAttributes>.request(attributes: .init(cardId: id), content: content, pushType: nil)) != nil
    }
}

private struct SampleHeadingView: View {
    let heading: SampleHeading

    init(_ heading: SampleHeading) {
        self.heading = heading
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(self.heading.hebrew)
            Text(self.heading.english)
                .font(.caption)
                .foregroundStyle(.secondary)
                .environment(\.layoutDirection, .leftToRight)
        }
        .accessibilityElement(children: .combine)
    }
}

@MainActor
private struct HarnessgramSampleView: View {
    @ObservedObject var model: HarnessgramSampleModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label {
                    SampleHeadingView(SampleBannerStrings.heading).font(.headline)
                } icon: {
                    Image(systemName: "square.stack")
                }
                Spacer()
                Button(action: self.model.exit) {
                    SampleHeadingView(SampleBannerStrings.exit).padding(.vertical, 8)
                }
                .disabled(self.model.exiting)
            }
            .padding(.horizontal, 16)
            .background(.regularMaterial)
            Divider()
            NavigationView {
                self.cockpit
            }
            .navigationViewStyle(.stack)
            .disabled(self.model.exiting)
        }
        .environment(\.layoutDirection, .rightToLeft)
        .alert(self.model.error ?? "", isPresented: Binding(
            get: { self.model.error != nil },
            set: { if !$0 { self.model.error = nil } }
        )) { Button(SampleBannerStrings.ok, role: .cancel) {} }
    }

    private var cockpit: some View {
        List {
            Section {
                NavigationLink {
                    self.waiting
                } label: {
                    self.row(SampleCockpitStrings.waiting, icon: "tray.full", count: self.model.state.snapshot.waitingCount)
                }
            }
            Section(header: SampleHeadingView(SampleCockpitStrings.agents)) {
                ForEach(self.model.state.snapshot.agents) { agent in
                    VStack(alignment: .leading) {
                        Text(agent.name)
                        Text(agent.step).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
            Section(header: SampleHeadingView(SampleCockpitStrings.progress)) {
                ForEach(self.model.state.snapshot.progress) { progress in
                    NavigationLink {
                        SampleProgressView(progress: progress, model: self.model)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(progress.title)
                            ProgressView(value: HarnessgramTaskState(progress: progress).fraction)
                        }
                    }
                }
            }
            Section {
                NavigationLink {
                    self.messages()
                } label: {
                    self.row(SampleDecisionStrings.sourceHeading, icon: "bubble.left.and.bubble.right")
                }
                NavigationLink {
                    self.settings
                } label: {
                    self.row(SampleSettingsStrings.heading, icon: "gearshape")
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .principal) { SampleHeadingView(SampleCockpitStrings.heading) } }
    }

    private var waiting: some View {
        List {
            Section(header: SampleHeadingView(SampleDecisionStrings.list)) {
                if self.model.state.snapshot.decisions.isEmpty {
                    Text(SampleDecisionStrings.empty)
                }
                ForEach(self.model.state.snapshot.decisions) { decision in
                    NavigationLink {
                        SampleDecisionView(decision: decision, model: self.model, messages: self.messages(topic: decision.topic))
                    } label: {
                        Label(decision.title, systemImage: decision.sensitive ? "lock.fill" : "doc.text")
                    }
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .principal) { SampleHeadingView(SampleCockpitStrings.waiting) } }
    }

    private func messages(topic: String? = nil) -> some View {
        let chats = topic.map { topic in self.model.chats.filter { $0.title == topic } } ?? self.model.chats
        return List {
            ForEach(chats.indices, id: \.self) { index in
                let chat = chats[index]
                Section(header: Text(chat.title)) { Text(chat.message) }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .principal) { SampleHeadingView(SampleDecisionStrings.sourceHeading) } }
    }

    private var settings: some View {
        List {
            NavigationLink {
                self.appSettings
            } label: {
                self.row(SampleSettingsStrings.app, icon: "house")
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .principal) { SampleHeadingView(SampleSettingsStrings.heading) } }
    }

    private var appSettings: some View {
        List {
            NavigationLink {
                List {
                    Label { SampleHeadingView(SampleRadioStrings.status) } icon: { Image(systemName: "radio") }
                }
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .principal) { SampleHeadingView(SampleRadioStrings.heading) } }
            } label: {
                self.row(SampleRadioStrings.heading, icon: "radio")
            }
            NavigationLink {
                self.filter
            } label: {
                self.row(SampleFilterStrings.heading, icon: "line.3.horizontal.decrease.circle")
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .principal) { SampleHeadingView(SampleSettingsStrings.app) } }
    }

    private var filter: some View {
        List {
            Text(SampleFilterStrings.intro)
            ForEach(HarnessgramFilterRule.allCases, id: \.self) { rule in
                Toggle(isOn: Binding(get: {
                    self.model.isFilterOn(rule)
                }, set: {
                    self.model.setFilter(rule, enabled: $0)
                })) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(HarnessgramFilterStrings.title(rule))
                        Text(HarnessgramFilterStrings.explanation(rule))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .principal) { SampleHeadingView(SampleFilterStrings.heading) } }
    }

    private func row(_ heading: SampleHeading, icon: String, count: Int? = nil) -> some View {
        HStack {
            Label { SampleHeadingView(heading) } icon: { Image(systemName: icon) }
            if let count {
                Spacer()
                Text(count.formatted()).foregroundStyle(.secondary)
            }
        }
    }
}

@MainActor
private struct SampleDecisionView<Messages: View>: View {
    let decision: HarnessgramCockpitSnapshot.Decision
    @ObservedObject var model: HarnessgramSampleModel
    let messages: Messages
    @State private var authenticating = false
    @State private var result: SampleHeading?
    @State private var faceIDIncomplete = false

    init(decision: HarnessgramCockpitSnapshot.Decision, model: HarnessgramSampleModel, messages: Messages) {
        self.decision = decision
        self.model = model
        self.messages = messages
    }

    var body: some View {
        List {
            Section(header: SampleHeadingView(SampleDecisionStrings.context)) {
                Text(self.decision.title).font(.headline)
                if let detail = self.decision.detail { Text(detail) }
                if self.decision.sensitive {
                    Label(SampleDecisionStrings.needsFaceID, systemImage: "lock.fill")
                }
            }
            Section(header: SampleHeadingView(SampleDecisionStrings.pictures)) {
                let artwork = self.decision.sensitive ? "room-project-b-card" : "room-project-a-card"
                Image("House/RoomCards/" + artwork)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 180)
                    .accessibilityLabel(SampleDecisionStrings.roomIllustration)
            }
            Section(header: SampleHeadingView(SampleDecisionStrings.links)) {
                NavigationLink(destination: self.messages) { SampleHeadingView(SampleDecisionStrings.source) }
            }
            Section(header: SampleHeadingView(SampleDecisionStrings.answer)) {
                if let result {
                    SampleHeadingView(result)
                }
                if self.faceIDIncomplete {
                    SampleHeadingView(SampleDecisionStrings.notConfirmed)
                }
                if self.model.state.snapshot.decisions.contains(where: { $0.id == self.decision.id }) {
                    Button {
                        self.answer(.yes)
                    } label: {
                        SampleHeadingView(.init(self.decision.yesLabel, SampleDecisionStrings.yes))
                    }
                    Button {
                        self.answer(.no)
                    } label: {
                        SampleHeadingView(.init(self.decision.noLabel, SampleDecisionStrings.no))
                    }
                }
            }
            .disabled(self.authenticating)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .principal) { SampleHeadingView(SampleDecisionStrings.detail) } }
    }

    private func answer(_ choice: HarnessgramCockpitLinks.Choice) {
        guard !self.model.exiting, !self.authenticating else { return }
        if self.decision.sensitive {
            self.authenticating = true
            HarnessgramOwnerConfirmation.deviceBiometricAuthentication(reason: SampleDecisionStrings.authenticate) { confirmed in
                self.authenticating = false
                self.result = SampleDecisionStrings.refused
                self.faceIDIncomplete = !confirmed
            }
        } else if self.model.answer(self.decision.id, choice: choice) == .applied {
            self.result = SampleDecisionStrings.answered
        }
    }
}

@MainActor
private struct SampleProgressView: View {
    let progress: HarnessgramCockpitSnapshot.Progress
    @ObservedObject var model: HarnessgramSampleModel
    @State private var activityStatus: String?

    init(progress: HarnessgramCockpitSnapshot.Progress, model: HarnessgramSampleModel) {
        self.progress = progress
        self.model = model
    }

    var body: some View {
        List {
            Section(header: Text(self.progress.title)) {
                ProgressView(value: HarnessgramTaskState(progress: self.progress).fraction)
                ForEach(self.progress.steps.indices, id: \.self) { index in
                    Label(self.progress.steps[index], systemImage: index < self.progress.done ? "checkmark.circle.fill" : "circle")
                }
            }
            Button {
                self.activityStatus = self.model.showActivity(self.progress) ? SampleCockpitStrings.activityStarted : SampleCockpitStrings.activityUnavailable
            } label: {
                SampleHeadingView(SampleCockpitStrings.activity)
            }
            if let activityStatus { Text(activityStatus).foregroundStyle(.secondary) }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .principal) { SampleHeadingView(SampleCockpitStrings.progress) } }
    }
}
