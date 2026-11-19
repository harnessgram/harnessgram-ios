import Foundation
import UIKit
import SwiftUI
import Display
import AccountContext
import HarnessgramCockpitKit
import HarnessgramCockpitSync
import HarnessgramHouseCore

/// The native Cockpit's pages. They are Telegram navigation screens (HarnessgramHostingScreen) whose lists take the
/// presentation theme's list colours and Telegram's grouped-list metrics; the list body is SwiftUI because Telegram's
/// own list nodes lay out left to right only, and these pages are Hebrew, right to left (leading/trailing only).
enum NativeCockpitMetrics {
    /// The page gutter and the card padding.
    static let gutter: CGFloat = 16.0
    static let cardPadding: CGFloat = 12.0
    static let rowMinHeight: CGFloat = 44.0
}

/// The theme's page and row colours on a grouped list.
private struct NativeCockpitListStyle: ViewModifier {
    let palette: NativeCockpitPalette

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 16.0, *) {
            content
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .background(Color(self.palette.page))
        } else {
            content
                .listStyle(.insetGrouped)
                .background(Color(self.palette.page))
        }
    }
}

/// One plain row: an icon square, the title, and the value on the trailing side.
struct NativeCockpitValueRow: View {
    let icon: String
    let tint: Color
    let title: String
    let value: String
    let palette: NativeCockpitPalette

    var body: some View {
        HStack(spacing: 12.0) {
            HarnessgramRowIcon(systemName: self.icon, tint: self.tint)
            Text(self.title)
                .foregroundColor(Color(self.palette.primary))
                .lineLimit(2)
            Spacer(minLength: 8.0)
            Text(self.value)
                .font(.body.monospacedDigit())
                .foregroundColor(Color(self.palette.secondary))
        }
        .frame(minHeight: NativeCockpitMetrics.rowMinHeight)
        .accessibilityElement(children: .combine)
    }
}

/// A row that opens a page: the value and the chevron (it points the way the page opens).
struct NativeCockpitLinkRow: View {
    let icon: String
    let tint: Color
    let title: String
    let value: String
    let palette: NativeCockpitPalette
    let action: () -> Void

    var body: some View {
        Button(action: self.action) {
            HStack(spacing: 12.0) {
                HarnessgramRowIcon(systemName: self.icon, tint: self.tint)
                Text(self.title)
                    .foregroundColor(Color(self.palette.primary))
                    .lineLimit(2)
                Spacer(minLength: 8.0)
                Text(self.value)
                    .font(.body.monospacedDigit())
                    .foregroundColor(Color(self.palette.secondary))
                Image(systemName: "chevron.forward")
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(Color(self.palette.secondary))
                    .accessibilityHidden(true)
            }
            .frame(minHeight: NativeCockpitMetrics.rowMinHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: Home

@MainActor
struct NativeCockpitHomeView: View {
    @ObservedObject var model: NativeCockpitModel

    var body: some View {
        List {
            self.stateSections
            Section(header: Text(NativeCockpitStrings.t(.fullCockpitHeader)).textCase(nil), footer: Text(NativeCockpitStrings.t(.fullCockpitFooter) + "\n" + NativeCockpitStrings.t(.siriTip))) {
                NativeCockpitLinkRow(icon: "gauge.with.dots.needle.67percent", tint: HarnessgramRowTint.cockpit, title: NativeCockpitStrings.t(.fullCockpit), value: "", palette: self.model.palette, action: {
                    self.model.openFullCockpit()
                })
                .listRowBackground(Color(self.model.palette.row))
            }
        }
        .modifier(NativeCockpitListStyle(palette: self.model.palette))
        .refreshable {
            await self.model.refresh()
        }
        .onAppear {
            self.model.appeared()
        }
        .onDisappear {
            self.model.disappeared()
        }
    }

    @ViewBuilder
    private var stateSections: some View {
        switch self.model.home {
        case let .disconnected(paused):
            Section {
                NativeCockpitStateCard(icon: "antenna.radiowaves.left.and.right", title: NativeCockpitStrings.t(.disconnectedTitle), detail: NativeCockpitStrings.t(paused ? .pausedDetail : .disconnectedDetail), palette: self.model.palette, buttonTitle: NativeCockpitStrings.t(self.model.pairing ? .connecting : .connect), buttonIcon: "faceid", buttonEnabled: !self.model.pairing, footnote: self.model.pairMessage, action: {
                    self.model.pair()
                })
                .listRowBackground(Color(self.model.palette.row))
            }
        case .loading:
            Section {
                HStack(spacing: 12.0) {
                    ProgressView()
                    Text(NativeCockpitStrings.t(.loading))
                        .foregroundColor(Color(self.model.palette.secondary))
                }
                .frame(minHeight: NativeCockpitMetrics.rowMinHeight)
                .listRowBackground(Color(self.model.palette.row))
            }
        case let .unavailable(reason, retryIn):
            Section {
                NativeCockpitStateCard(icon: "exclamationmark.triangle", title: NativeCockpitStrings.t(.unavailableTitle), detail: reason, palette: self.model.palette, buttonTitle: NativeCockpitStrings.t(.retry), buttonIcon: "arrow.clockwise", buttonEnabled: (retryIn ?? 0.0) <= 0.0, footnote: retryIn.flatMap { $0 > 0.0 ? NativeCockpitStrings.t(.busyRetryIn) + " " + NativeCockpitFormat.seconds($0) : nil }, action: {
                    self.model.retry()
                })
                .listRowBackground(Color(self.model.palette.row))
            }
        case let .content(content):
            self.contentSections(content)
        }
    }

    @ViewBuilder
    private func contentSections(_ content: NativeCockpitHome.Content) -> some View {
        let palette = self.model.palette
        Section(header: Text(NativeCockpitStrings.t(.sessionsHeader)).textCase(nil)) {
            NativeCockpitValueRow(icon: "bolt.fill", tint: HarnessgramRowTint.agents, title: NativeCockpitStrings.t(.sessionsWorking), value: NativeCockpitFormat.count(content.working), palette: palette)
                .listRowBackground(Color(palette.row))
            NativeCockpitValueRow(icon: "hand.raised.fill", tint: HarnessgramRowTint.cockpit, title: NativeCockpitStrings.t(.sessionsWaiting), value: NativeCockpitFormat.count(content.waitingSessions), palette: palette)
                .listRowBackground(Color(palette.row))
            NativeCockpitValueRow(icon: "moon.zzz.fill", tint: HarnessgramRowTint.text, title: NativeCockpitStrings.t(.sessionsIdle), value: NativeCockpitFormat.count(content.idle), palette: palette)
                .listRowBackground(Color(palette.row))
        }
        Section(header: Text(NativeCockpitStrings.t(.decisionsHeader)).textCase(nil)) {
            NativeCockpitLinkRow(icon: "checkmark.seal.fill", tint: HarnessgramRowTint.cockpit, title: NativeCockpitStrings.t(.decisionsRow), value: content.decisions > 0 ? NativeCockpitFormat.count(content.decisions) : NativeCockpitStrings.t(.decisionsNone), palette: palette, action: {
                self.model.showDecisions()
            })
            .listRowBackground(Color(palette.row))
            if let total = content.waitingTotal {
                NativeCockpitValueRow(icon: "tray.full.fill", tint: HarnessgramRowTint.agents, title: NativeCockpitStrings.t(.waitingTotal), value: NativeCockpitFormat.count(total), palette: palette)
                    .listRowBackground(Color(palette.row))
            }
        }
        Section(header: Text(NativeCockpitStrings.t(.quotaHeader)).textCase(nil)) {
            if content.quota.isEmpty {
                Text(NativeCockpitStrings.t(.quotaNone))
                    .foregroundColor(Color(palette.secondary))
                    .frame(minHeight: NativeCockpitMetrics.rowMinHeight)
                    .listRowBackground(Color(palette.row))
            }
            ForEach(content.quota) { row in
                NativeCockpitQuotaRow(row: row, palette: palette)
                    .listRowBackground(Color(palette.row))
            }
        }
        Section(header: Text(NativeCockpitStrings.t(.radioHeader)).textCase(nil), footer: Text(NativeCockpitStrings.t(.updated) + " " + NativeCockpitFormat.relative(content.updated, now: Date()))) {
            NativeCockpitValueRow(icon: "dot.radiowaves.left.and.right", tint: HarnessgramRowTint.radio, title: NativeCockpitStrings.t(.radioHeader), value: self.radioText(content.radio), palette: palette)
                .listRowBackground(Color(palette.row))
        }
    }

    private func radioText(_ radio: NativeCockpitHome.Radio) -> String {
        switch radio {
        case .on: return NativeCockpitStrings.t(.radioOn)
        case .off: return NativeCockpitStrings.t(.radioOff)
        case .notSetUp: return NativeCockpitStrings.t(.radioDisabled)
        case .unknown: return NativeCockpitStrings.t(.radioUnknown)
        }
    }
}

/// One account's weekly quota: label, percent and a bar that fills from the leading (right) side.
struct NativeCockpitQuotaRow: View {
    let row: NativeCockpitHome.QuotaRow
    let palette: NativeCockpitPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 6.0) {
            HStack {
                Text(self.row.label)
                    .foregroundColor(Color(self.palette.primary))
                    .lineLimit(2)
                Spacer(minLength: 8.0)
                Text(self.row.used)
                    .font(.body.monospacedDigit())
                    .foregroundColor(Color((self.row.fraction ?? 0.0) >= 0.9 ? self.palette.destructive : self.palette.secondary))
            }
            if let fraction = self.row.fraction {
                ProgressView(value: fraction)
                    .tint(Color(fraction >= 0.9 ? self.palette.destructive : self.palette.accent))
                    .accessibilityHidden(true)
            }
            if !self.row.detail.isEmpty {
                Text(self.row.detail)
                    .font(.footnote)
                    .foregroundColor(Color(self.palette.secondary))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 6.0)
        .accessibilityElement(children: .combine)
    }
}

/// A state card (not connected, not answering): icon, title, text, one action.
struct NativeCockpitStateCard: View {
    let icon: String
    let title: String
    let detail: String
    let palette: NativeCockpitPalette
    let buttonTitle: String
    let buttonIcon: String
    let buttonEnabled: Bool
    let footnote: String?
    let action: () -> Void

    var body: some View {
        VStack(spacing: 12.0) {
            Image(systemName: self.icon)
                .font(.system(size: 36.0))
                .foregroundColor(Color(self.palette.accent))
                .accessibilityHidden(true)
            Text(self.title)
                .font(.title3.weight(.semibold))
                .foregroundColor(Color(self.palette.primary))
                .multilineTextAlignment(.center)
            Text(self.detail)
                .font(.subheadline)
                .foregroundColor(Color(self.palette.secondary))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: self.action) {
                Label(self.buttonTitle, systemImage: self.buttonIcon)
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: NativeCockpitMetrics.rowMinHeight)
            }
            .buttonStyle(.harnessgramFilled)
            .disabled(!self.buttonEnabled)
            if let footnote = self.footnote {
                Text(footnote)
                    .font(.footnote)
                    .foregroundColor(Color(self.palette.secondary))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, NativeCockpitMetrics.cardPadding)
    }
}

// MARK: Decisions

@MainActor
struct NativeDecisionsView: View {
    @ObservedObject var model: NativeCockpitModel

    var body: some View {
        let palette = self.model.palette
        let open = self.model.openDecisions
        let fresh = open.filter { !$0.isOld }
        let old = open.filter { $0.isOld }
        List {
            if !self.model.answerOn {
                Section {
                    Text(NativeCockpitStrings.t(.decisionsAnswerOff))
                        .font(.footnote)
                        .foregroundColor(Color(palette.secondary))
                        .fixedSize(horizontal: false, vertical: true)
                        .listRowBackground(Color(palette.row))
                }
            }
            if open.isEmpty {
                Section {
                    Text(NativeCockpitStrings.t(.decisionsEmpty))
                        .foregroundColor(Color(palette.secondary))
                        .frame(minHeight: NativeCockpitMetrics.rowMinHeight)
                        .listRowBackground(Color(palette.row))
                }
            }
            if !fresh.isEmpty {
                Section(header: Text(NativeCockpitStrings.t(.decisionsFresh)).textCase(nil)) {
                    ForEach(fresh) { decision in
                        NativeDecisionListRow(decision: decision, palette: palette, action: { self.model.openDecision(decision) })
                            .listRowBackground(Color(palette.row))
                    }
                }
            }
            if !old.isEmpty {
                Section(header: Text(NativeCockpitStrings.t(.decisionsOld)).textCase(nil)) {
                    ForEach(old) { decision in
                        NativeDecisionListRow(decision: decision, palette: palette, action: { self.model.openDecision(decision) })
                            .listRowBackground(Color(palette.row))
                    }
                }
            }
        }
        .modifier(NativeCockpitListStyle(palette: palette))
        .refreshable {
            await self.model.refresh()
        }
        .onAppear {
            self.model.appeared()
        }
        .onDisappear {
            self.model.disappeared()
        }
    }
}

/// A decision in the list: the full question (up to three lines here), its topic, age and whether it needs Face ID.
struct NativeDecisionListRow: View {
    let decision: HarnessgramCockpitScreen.Decision
    let palette: NativeCockpitPalette
    let action: () -> Void

    var body: some View {
        Button(action: self.action) {
            HStack(alignment: .top, spacing: 12.0) {
                VStack(alignment: .leading, spacing: 4.0) {
                    Text(self.decision.base.title)
                        .foregroundColor(Color(self.palette.primary))
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(NativeDecisionMeta.line(self.decision, now: Date()))
                        .font(.footnote)
                        .foregroundColor(Color(self.palette.secondary))
                        .lineLimit(2)
                }
                Spacer(minLength: 8.0)
                Image(systemName: self.decision.requiresOwnerCheck ? "faceid" : "chevron.forward")
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(Color(self.decision.requiresOwnerCheck ? self.palette.accent : self.palette.secondary))
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 6.0)
            .frame(minHeight: NativeCockpitMetrics.rowMinHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

enum NativeDecisionMeta {
    /// "נושא · לפני 5 דקות · רגישה".
    static func line(_ decision: HarnessgramCockpitScreen.Decision, now: Date) -> String {
        var parts: [String] = []
        if !decision.base.topic.isEmpty {
            parts.append(decision.base.topic)
        }
        if let asked = decision.base.askedAt {
            parts.append(NativeCockpitFormat.relative(asked, now: now))
        }
        if decision.permissionRequest != nil {
            parts.append(NativeCockpitStrings.t(.decisionPermission))
        } else {
            parts.append(NativeCockpitStrings.t(decision.requiresOwnerCheck ? .decisionNeedsFaceID : .decisionRoutine))
        }
        return parts.joined(separator: " · ")
    }
}

/// One decision: the whole question and detail, the note, Yes and No, and what happened after the answer.
@MainActor
struct NativeDecisionView: View {
    @ObservedObject var model: NativeCockpitModel
    let id: String

    var body: some View {
        let palette = self.model.palette
        List {
            if let decision = self.model.decision(id: self.id) {
                self.sections(decision, palette: palette)
            } else {
                Section {
                    Text(NativeCockpitStrings.t(.resultClosed))
                        .foregroundColor(Color(palette.secondary))
                        .listRowBackground(Color(palette.row))
                }
            }
        }
        .modifier(NativeCockpitListStyle(palette: palette))
        .onAppear {
            self.model.appeared()
        }
        .onDisappear {
            self.model.disappeared()
        }
    }

    @ViewBuilder
    private func sections(_ decision: HarnessgramCockpitScreen.Decision, palette: NativeCockpitPalette) -> some View {
        let state = self.model.answerState(decision)
        Section(header: Text(NativeCockpitStrings.t(.decisionQuestion)).textCase(nil), footer: Text(NativeDecisionMeta.line(decision, now: Date()))) {
            Text(decision.base.title)
                .font(.headline)
                .foregroundColor(Color(palette.primary))
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .padding(.vertical, 4.0)
                .listRowBackground(Color(palette.row))
        }
        if let detail = decision.base.detail, !detail.isEmpty {
            Section(header: Text(NativeCockpitStrings.t(.decisionDetail)).textCase(nil)) {
                Text(detail)
                    .foregroundColor(Color(palette.primary))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .padding(.vertical, 4.0)
                    .listRowBackground(Color(palette.row))
            }
        }
        if let context = decision.extras.context {
            Section(header: Text(NativeCockpitStrings.t(.decisionContext)).textCase(nil)) {
                Text(context)
                    .foregroundColor(Color(palette.primary))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .padding(.vertical, 4.0)
                    .listRowBackground(Color(palette.row))
            }
        }
        if !decision.extras.imageIds.isEmpty {
            Section(header: Text(NativeCockpitStrings.t(.decisionImages)).textCase(nil)) {
                ForEach(decision.extras.imageIds, id: \.self) { id in
                    NativeDecisionImage(id: id, palette: palette)
                        .listRowBackground(Color(palette.row))
                }
            }
        }
        if !decision.extras.links.isEmpty {
            Section(header: Text(NativeCockpitStrings.t(.decisionLinks)).textCase(nil)) {
                ForEach(decision.extras.links, id: \.url) { link in
                    // Links open outside the app (Safari), where the home filter applies; nothing loads in here.
                    Link(destination: link.url) {
                        HStack(spacing: 8.0) {
                            Image(systemName: "link")
                                .accessibilityHidden(true)
                            Text(link.title)
                                .lineLimit(2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(minHeight: 44.0)
                    }
                    .foregroundColor(Color(palette.accent))
                    .listRowBackground(Color(palette.row))
                }
            }
        }
        if decision.extras.commentAllowed && decision.permissionRequest == nil {
            if !decision.extras.replies.isEmpty {
                Section(header: Text(NativeCockpitStrings.t(.commentEarlier)).textCase(nil)) {
                    ForEach(Array(decision.extras.replies.enumerated()), id: \.offset) { _, reply in
                        Text(reply)
                            .foregroundColor(Color(palette.secondary))
                            .fixedSize(horizontal: false, vertical: true)
                            .listRowBackground(Color(palette.row))
                    }
                }
            }
            let commentState = self.model.commentState(decision)
            Section(header: Text(NativeCockpitStrings.t(.commentHeader)).textCase(nil), footer: Text(commentState.line ?? NativeCockpitStrings.t(.commentFooter))) {
                NativeCockpitNoteField(text: self.model.commentBinding(decision.id), placeholder: NativeCockpitStrings.t(.commentPlaceholder), palette: palette)
                    .listRowBackground(Color(palette.row))
                Button(action: {
                    self.model.sendComment(decision)
                }) {
                    HStack(spacing: 8.0) {
                        Image(systemName: "text.bubble")
                            .accessibilityHidden(true)
                        Text(NativeCockpitStrings.t(.commentSend))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(minHeight: 44.0)
                }
                .disabled(commentState == .sending)
                .foregroundColor(Color(palette.accent))
                .listRowBackground(Color(palette.row))
            }
        }
        if let request = decision.permissionRequest {
            Section(header: Text(NativeCockpitStrings.t(.decisionPermission)).textCase(nil), footer: Text(NativeCockpitStrings.t(.decisionPermissionFooter))) {
                // The request is shown exactly as the agent wrote it (often code), left to right.
                Text(request)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundColor(Color(palette.primary))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .environment(\.layoutDirection, .leftToRight)
                    .listRowBackground(Color(palette.row))
            }
        }
        if case let .finished(result, choice) = state {
            Section(header: Text(NativeCockpitStrings.t(.resultHeader)).textCase(nil)) {
                NativeDecisionResultView(result: result, choice: choice, live: self.liveDelivery(result), palette: palette)
                    .listRowBackground(Color(palette.row))
            }
        }
        if self.model.answerOn && decision.answerableHere && self.mayAnswer(state) {
            Section(header: Text(NativeCockpitStrings.t(.decisionNote)).textCase(nil), footer: Text(NativeCockpitStrings.t(.decisionNoteFooter))) {
                NativeCockpitNoteField(text: self.model.noteBinding(decision.id), placeholder: NativeCockpitStrings.t(.decisionNotePlaceholder), palette: palette)
                    .listRowBackground(Color(palette.row))
            }
            Section(header: Text(NativeCockpitStrings.t(.decisionAnswerHeader)).textCase(nil), footer: decision.requiresOwnerCheck ? Text(NativeCockpitStrings.t(.decisionNeedsFaceID)) : nil) {
                NativeDecisionButtons(decision: decision, state: state, block: self.model.timedAnswerBlock(decision), palette: palette, answer: { choice in
                    self.model.answer(decision, choice)
                })
                .listRowBackground(Color(palette.row))
            }
        }
        Section {
            if self.model.canOpenTopic(decision) {
                NativeCockpitLinkRow(icon: "bubble.left.and.bubble.right.fill", tint: HarnessgramRowTint.agents, title: NativeCockpitStrings.t(.decisionOpenTopic), value: "", palette: palette, action: {
                    self.model.openTopic(decision)
                })
                .listRowBackground(Color(palette.row))
            }
            if !self.model.answerOn || !decision.answerableHere {
                NativeCockpitLinkRow(icon: "gauge.with.dots.needle.67percent", tint: HarnessgramRowTint.cockpit, title: NativeCockpitStrings.t(.decisionOpenFull), value: "", palette: palette, action: {
                    self.model.openFullCockpit()
                })
                .listRowBackground(Color(palette.row))
            }
        }
    }

    private func mayAnswer(_ state: NativeDecisionAnswerState) -> Bool {
        switch state {
        case .idle, .sending:
            return true
        case let .finished(result, _):
            return NativeDecisionAnswerState.mayRetry(result)
        }
    }

    private func liveDelivery(_ result: HarnessgramDecisionAnswer.Result) -> HarnessgramCockpitScreen.Delivery? {
        if case let .sent(key?, _) = result {
            return self.model.delivery(key: key)
        }
        return nil
    }
}

struct NativeDecisionButtons: View {
    let decision: HarnessgramCockpitScreen.Decision
    let state: NativeDecisionAnswerState
    let block: HarnessgramAnswerGuard.TimedBlock?
    let palette: NativeCockpitPalette
    let answer: (HarnessgramCockpitLinks.Choice) -> Void

    @ViewBuilder
    var body: some View {
        if let block = self.block {
            TimelineView(.explicit([Date(), block.until])) { context in
                self.controls(block: context.date < block.until ? block : nil)
            }
        } else {
            self.controls(block: nil)
        }
    }

    private func controls(block: HarnessgramAnswerGuard.TimedBlock?) -> some View {
        VStack(spacing: 10.0) {
            if case let .sending(choice) = self.state {
                HStack(spacing: 10.0) {
                    ProgressView()
                    Text(NativeCockpitStrings.t(.sending) + " " + NativeDecisionAnswerState.answer(choice))
                        .foregroundColor(Color(self.palette.secondary))
                }
                .frame(maxWidth: .infinity, minHeight: NativeCockpitMetrics.rowMinHeight)
            } else {
                HStack(spacing: 12.0) {
                    if !self.decision.declineOnly {
                        Button(action: { self.answer(.yes) }) {
                            Label(self.decision.base.yesLabel, systemImage: self.decision.requiresOwnerCheck ? "faceid" : "checkmark")
                                .font(.headline)
                                .frame(maxWidth: .infinity, minHeight: NativeCockpitMetrics.rowMinHeight)
                        }
                        .buttonStyle(.harnessgramFilled)
                    }
                    Button(action: { self.answer(.no) }) {
                        Label(self.decision.base.noLabel, systemImage: "xmark")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: NativeCockpitMetrics.rowMinHeight)
                    }
                    .buttonStyle(.bordered)
                    .tint(Color(self.palette.destructive))
                }
                .disabled(block != nil)
                if let block {
                    self.blockMessage(block)
                        .font(.footnote)
                        .foregroundColor(Color(self.palette.secondary))
                }
                if self.decision.declineOnly {
                    Text(NativeCockpitStrings.t(.decisionDeclineOnly))
                        .font(.footnote)
                        .foregroundColor(Color(self.palette.secondary))
                }
            }
        }
        .padding(.vertical, 6.0)
    }

    private func blockMessage(_ block: HarnessgramAnswerGuard.TimedBlock) -> Text {
        switch block {
        case let .busy(until):
            return Text("\(NativeCockpitStrings.t(.busyRetryIn)) \(until, style: .timer)")
        case .uncertain:
            return Text(NativeCockpitStrings.t(.answerUncertain))
        }
    }
}

struct NativeDecisionResultView: View {
    let result: HarnessgramDecisionAnswer.Result
    let choice: HarnessgramCockpitLinks.Choice
    let live: HarnessgramCockpitScreen.Delivery?
    let palette: NativeCockpitPalette

    var body: some View {
        let lines = NativeDecisionAnswerState.lines(result: self.result, choice: self.choice, live: self.live)
        HStack(alignment: .top, spacing: 12.0) {
            Image(systemName: self.icon)
                .font(.title3)
                .foregroundColor(Color(self.good ? self.palette.constructive : self.palette.destructive))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4.0) {
                ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                    Text(line)
                        .font(index == 0 ? .body.weight(.semibold) : .footnote)
                        .foregroundColor(Color(index == 0 ? self.palette.primary : self.palette.secondary))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0.0)
        }
        .padding(.vertical, 6.0)
        .accessibilityElement(children: .combine)
    }

    private var good: Bool {
        switch self.result {
        case .sent, .alreadyClosed:
            return true
        default:
            return false
        }
    }

    private var icon: String {
        switch self.result {
        case .sent:
            return "checkmark.circle.fill"
        case .alreadyClosed:
            return "checkmark.circle"
        case .notConfirmed:
            return "faceid"
        default:
            return "exclamationmark.triangle.fill"
        }
    }
}

/// The note field. While empty it is laid out in the page's direction (right to left), so the Hebrew placeholder sits
/// on the right; once it holds text, its first strong letter decides (`NativeCockpitTextDirection`).
struct NativeCockpitNoteField: View {
    let text: Binding<String>
    let placeholder: String
    let palette: NativeCockpitPalette

    var body: some View {
        let direction = NativeCockpitTextDirection.of(self.text.wrappedValue)
        TextField(self.placeholder, text: self.text)
            .foregroundColor(Color(self.palette.primary))
            .multilineTextAlignment(.leading)
            .environment(\.layoutDirection, direction == .rightToLeft ? .rightToLeft : .leftToRight)
            .frame(minHeight: NativeCockpitMetrics.rowMinHeight)
    }
}

// MARK: Screens

/// The native Cockpit tab: its home, with the tab bar item of the Cockpit tab.
public func makeNativeCockpitTabController(context: AccountContext) -> ViewController {
    // Legacy tab factories already call here on the main queue.
    return MainActor.assumeIsolated {
        let model = NativeCockpitModel(context: context)
        let controller = HarnessgramHostingScreen(context: context, title: NativeCockpitStrings.t(.homeTitle), content: NativeCockpitHomeView(model: model))
        model.controller = controller
        #if targetEnvironment(simulator)
        NativeCockpitModel.demoModels.append(model)
        #endif
        let configuration = UIImage.SymbolConfiguration(pointSize: 21.0, weight: .regular)
        let icon = (UIImage(systemName: "gauge.with.dots.needle.67percent", withConfiguration: configuration) ?? UIImage(systemName: "airplane", withConfiguration: configuration))?.withRenderingMode(.alwaysTemplate)
        controller.tabBarItem.title = NativeCockpitStrings.t(.tabTitle)
        controller.tabBarItem.image = icon
        controller.tabBarItem.selectedImage = icon
        return controller
    }
}

/// Simulator demo only: opens a page of the native Cockpit shown in `controller` ("decisions", or "decision" for the
/// first decision's page). Does nothing on a device.
@MainActor
public func nativeCockpitDemoOpen(_ controller: ViewController, page: String) {
    #if targetEnvironment(simulator)
    guard let model = NativeCockpitModel.demoModels.first(where: { $0.controller === controller }) else {
        return
    }
    if page == "decision", let first = model.openDecisions.first {
        model.openDecision(first)
    } else {
        model.showDecisions()
    }
    #endif
}

public func isNativeCockpitTabController(_ controller: ViewController) -> Bool {
    return controller is HarnessgramHostingScreen<NativeCockpitHomeView>
}

@MainActor
func makeNativeDecisionsController(context: AccountContext, model: NativeCockpitModel) -> ViewController {
    return HarnessgramHostingScreen(context: context, title: NativeCockpitStrings.t(.decisionsTitle), content: NativeDecisionsView(model: model))
}

@MainActor
func makeNativeDecisionController(context: AccountContext, model: NativeCockpitModel, id: String) -> ViewController {
    return HarnessgramHostingScreen(context: context, title: NativeCockpitStrings.t(.decisionTitle), content: NativeDecisionView(model: model, id: id))
}

/// One picture of a rich decision, loaded on demand through the bridge's card-media token; a neutral line when it
/// cannot load. Fitted to the row width, never cropped.
struct NativeDecisionImage: View {
    let id: String
    let palette: NativeCockpitPalette
    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image = self.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 10.0, style: .continuous))
                    .accessibilityLabel(Text(NativeCockpitStrings.t(.decisionImages)))
            } else if self.failed {
                Text(NativeCockpitStrings.t(.decisionImageUnavailable))
                    .font(.footnote)
                    .foregroundColor(Color(self.palette.secondary))
                    .frame(maxWidth: .infinity, minHeight: 44.0, alignment: .leading)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 120.0)
            }
        }
        .padding(.vertical, 6.0)
        .task(id: self.id) {
            let data = await HarnessgramCockpitSync.shared.decisionImage(id: self.id)
            if let data, let image = UIImage(data: data) {
                self.image = image
            } else {
                self.failed = true
            }
        }
    }
}
