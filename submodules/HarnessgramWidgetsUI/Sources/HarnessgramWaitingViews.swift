import Foundation
import SwiftUI
import UIKit
import WidgetKit
import HarnessgramCockpitKit

/// The waiting widget's colours, a light and a dark value each (build 31: light mode everywhere). Text colours keep
/// WCAG AA on the widget's light and dark backgrounds; the approve fill keeps AA under its white label in both
/// (HarnessgramWidgetsUITests.testWidgetColoursKeepAAInLightAndDark).
enum HarnessgramWidgetPalette {
    struct Tone {
        let light: UInt32
        let dark: UInt32

        var color: Color {
            let light = self.light
            let dark = self.dark
            return Color(uiColor: UIColor { traits in
                let hex = traits.userInterfaceStyle == .dark ? dark : light
                return UIColor(red: CGFloat((hex >> 16) & 0xff) / 255.0, green: CGFloat((hex >> 8) & 0xff) / 255.0, blue: CGFloat(hex & 0xff) / 255.0, alpha: 1.0)
            })
        }
    }

    enum Tones {
        static let accent = Tone(light: 0x2E66ED, dark: 0x6E9BFF)
        /// Also the approve button's fill under a white label.
        static let approve = Tone(light: 0x157A47, dark: 0x157A47)
        static let decline = Tone(light: 0xC0392B, dark: 0xFF6B6B)
        static let sensitive = Tone(light: 0xA85A00, dark: 0xED8C1A)
        static let radioOn = Tone(light: 0x7A3FD6, dark: 0xB08CFF)
    }

    static let accent = Tones.accent.color
    static let approve = Tones.approve.color
    static let decline = Tones.decline.color
    static let sensitive = Tones.sensitive.color
    static let radioOn = Tones.radioOn.color
}

/// The widget's whole face for one family. Public so the snapshot tests render every family.
@available(iOS 17.0, *)
public struct HarnessgramWaitingContent: View {
    let entry: HarnessgramWaitingEntry
    let family: WidgetFamily

    public init(entry: HarnessgramWaitingEntry, family: WidgetFamily) {
        self.entry = entry
        self.family = family
    }

    public var body: some View {
        Group {
            switch self.family {
            case .accessoryInline:
                self.inline
            case .accessoryCircular:
                self.circular
            case .accessoryRectangular:
                self.rectangular
            case .systemSmall:
                self.small
            case .systemLarge, .systemExtraLarge:
                self.home(lines: 3, showAgents: true)
            default:
                self.home(lines: 3, showAgents: false)
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
    }

    private var snapshot: HarnessgramCockpitSnapshot? {
        return self.entry.snapshot
    }

    private var count: Int {
        return self.snapshot?.waitingCount ?? 0
    }

    /// The top line's topic, else the app (which refreshes the widgets when it opens).
    private var tapURL: URL {
        if self.entry.needsPairing {
            // Not connected yet: the tap connects the widgets (the line on it says so).
            return HarnessgramCockpitLinks.pairURL
        }
        if let first = self.snapshot?.decisions.first, let url = HarnessgramCockpitLinks.appURL(forTopicURL: first.topicURL) {
            return url
        }
        return HarnessgramCockpitLinks.openURL
    }

    // MARK: lock screen (lock screen pack: flight strip, tower radar, inline status)

    private var summary: HarnessgramTowerSummary? {
        return HarnessgramTowerSummary(snapshot: self.snapshot)
    }

    /// "3 משימות באוויר · 1 מחכה לך" beside a plane.
    private var inline: some View {
        Group {
            if let summary = self.summary {
                Label {
                    Text(summary.inlineLine)
                } icon: {
                    Image(systemName: "airplane")
                }
            } else {
                Text(HarnessgramWidgetStrings.emptyText(needsPairing: self.entry.needsPairing, oneLine: true, unavailable: self.entry.temporarilyUnavailable))
            }
        }
        .widgetURL(self.tapURL)
        .containerBackground(for: .widget) { Color.clear }
    }

    /// The tower radar: one blip per agent at work and a ringed blip per decision waiting, the sweep moving on with each
    /// refresh, and the two counts under it. Before the first sync: the tower alone.
    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            if let summary = self.summary {
                HarnessgramRadarScope(summary: summary, sweep: HarnessgramTowerSummary.sweepBearing(at: self.entry.date))
                    .padding(5)
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    HStack(spacing: 4) {
                        HStack(spacing: 2) {
                            Circle().frame(width: 4, height: 4)
                            Text("\(summary.running)")
                        }
                        HStack(spacing: 2) {
                            Circle().strokeBorder(lineWidth: 1).frame(width: 6, height: 6)
                            Text("\(summary.waiting)")
                        }
                        .widgetAccentable()
                    }
                    .font(.system(size: 11, weight: .bold, design: .rounded).monospacedDigit())
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.black.opacity(0.55)))
                    .padding(.bottom, 6)
                }
            } else {
                HarnessgramTowerGlyph(color: .primary)
                    .frame(height: 30)
            }
        }
        .widgetURL(self.tapURL)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(self.summary?.radarAccessibility ?? HarnessgramWidgetStrings.emptyText(needsPairing: self.entry.needsPairing, oneLine: true, unavailable: self.entry.temporarilyUnavailable))
        .containerBackground(for: .widget) { Color.clear }
    }

    /// The flight strip: "הבא: <next decision>", how long it has waited and how many more, a chevron into the app and
    /// a row of runway lights. Without decisions: nothing waits, and how many are in the air.
    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Group {
                    if self.summary?.nextSensitive == true {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 10, weight: .bold))
                            .accessibilityLabel(HarnessgramWidgetStrings.needsFaceID)
                    } else {
                        HarnessgramTowerGlyph(color: .primary)
                            .frame(height: 13)
                    }
                }
                .widgetAccentable()
                if let title = self.summary?.nextTitle {
                    // Titles are hidden on a locked phone when the owner keeps lock-screen data private.
                    Text(HarnessgramWidgetStrings.next(title))
                        .font(.system(size: 14, weight: .bold))
                        .lineLimit(1)
                        .privacySensitive()
                } else {
                    Text(self.summary == nil ? HarnessgramWidgetStrings.waitingTitle : HarnessgramWidgetStrings.nothingWaiting)
                        .font(.system(size: 14, weight: .bold))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 6) {
                Text(self.rectangularDetail)
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if self.summary != nil {
                    Image(systemName: "chevron.forward")
                        .font(.system(size: 9, weight: .bold))
                        .frame(width: 18, height: 18)
                        .background(Circle().strokeBorder(Color.primary.opacity(0.5), lineWidth: 1))
                        .widgetAccentable()
                        .accessibilityHidden(true)
                }
            }
            HarnessgramRunwayLights()
                .frame(height: 4)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetURL(self.tapURL)
        .containerBackground(for: .widget) { Color.clear }
    }

    /// The flight strip's second line: the next decision's age and how many more, or the agents in the air.
    private var rectangularDetail: String {
        guard let summary = self.summary else {
            return HarnessgramWidgetStrings.emptyText(needsPairing: self.entry.needsPairing, oneLine: true, unavailable: self.entry.temporarilyUnavailable)
        }
        if summary.nextTitle != nil {
            var parts: [String] = []
            if let age = summary.nextAge(now: self.entry.date) {
                parts.append(age)
            }
            if summary.moreWaiting > 0 {
                parts.append(HarnessgramWidgetStrings.moreWaiting(summary.moreWaiting))
            }
            if parts.isEmpty {
                parts.append(HarnessgramWidgetStrings.tasksInAir(summary.running))
            }
            return parts.joined(separator: " · ")
        }
        return HarnessgramWidgetStrings.tasksInAir(summary.running)
    }

    // MARK: home screen

    private var small: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: "bell.badge.fill")
                    .foregroundStyle(HarnessgramWidgetPalette.accent)
                    .widgetAccentable()
                Text(HarnessgramWidgetStrings.waitingTitle)
                    .font(.system(size: 14, weight: .semibold))
                Spacer(minLength: 0)
            }
            Text("\(self.count)")
                .font(.system(size: 46, weight: .bold, design: .rounded))
                .foregroundStyle(self.count > 0 ? HarnessgramWidgetPalette.accent : Color.secondary)
                .widgetAccentable()
                .accessibilityLabel(HarnessgramWidgetStrings.waitingCount(self.count))
            Spacer(minLength: 0)
            if self.snapshot == nil {
                Text(HarnessgramWidgetStrings.emptyText(needsPairing: self.entry.needsPairing, oneLine: false, unavailable: self.entry.temporarilyUnavailable))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else {
                self.agentsChip
                self.radioChip
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(self.tapURL)
        .containerBackground(for: .widget) { self.background }
    }

    private func home(lines: Int, showAgents: Bool) -> some View {
        // Medium fits the count and three lines only without topics and with tighter spacing.
        let compact = !showAgents
        return VStack(alignment: .leading, spacing: compact ? 6 : 8) {
            self.header
            if let snapshot = self.snapshot {
                if snapshot.decisions.isEmpty {
                    Spacer(minLength: 0)
                    HStack {
                        Spacer(minLength: 0)
                        Label(HarnessgramWidgetStrings.nothingWaiting, systemImage: "checkmark.circle")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                    }
                    Spacer(minLength: 0)
                } else {
                    ForEach(snapshot.decisions.prefix(lines)) { decision in
                        HarnessgramDecisionRow(decision: decision, route: HarnessgramWaitingContent.route(decision, canAnswerOnWidget: self.entry.canAnswerOnWidget), showsTopic: !compact)
                    }
                }
                if showAgents {
                    Divider()
                    self.agentsList(snapshot)
                }
                Spacer(minLength: 0)
                if let notice = snapshot.notice {
                    Text(notice)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(HarnessgramWidgetPalette.sensitive)
                        .lineLimit(1)
                } else if showAgents {
                    Text(HarnessgramWidgetStrings.updated(self.entry.date.timeIntervalSince(snapshot.updatedAt)))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            } else {
                Spacer(minLength: 0)
                Text(HarnessgramWidgetStrings.emptyText(needsPairing: self.entry.needsPairing, oneLine: false, unavailable: self.entry.temporarilyUnavailable))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
        }
        .padding(compact ? 12 : 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(HarnessgramCockpitLinks.openURL)
        .containerBackground(for: .widget) { self.background }
    }

    /// In-place buttons only when the decision is plain and the login can still answer.
    public static func route(_ decision: HarnessgramCockpitSnapshot.Decision, canAnswerOnWidget: Bool) -> HarnessgramDecisionGate.Route {
        if decision.sensitive {
            return .answerInAppWithFaceID
        }
        return canAnswerOnWidget ? .answerOnWidget : .answerInApp
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "bell.badge.fill")
                .foregroundStyle(HarnessgramWidgetPalette.accent)
                .widgetAccentable()
            Text(self.snapshot == nil ? HarnessgramWidgetStrings.waitingTitle : HarnessgramWidgetStrings.waitingCount(self.count))
                .font(.system(size: 15, weight: .bold))
                .lineLimit(1)
            Spacer(minLength: 4)
            if self.snapshot != nil {
                self.agentsChip
                self.radioChip
            }
        }
    }

    @ViewBuilder
    private var agentsChip: some View {
        if let snapshot = self.snapshot {
            HStack(spacing: 3) {
                Image(systemName: "gearshape.2.fill")
                Text("\(snapshot.runningAgents)")
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(snapshot.runningAgents > 0 ? HarnessgramWidgetPalette.accent : Color.secondary)
            .widgetAccentable(snapshot.runningAgents > 0)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(HarnessgramWidgetStrings.agentsCount(snapshot.runningAgents))
        }
    }

    @ViewBuilder
    private var radioChip: some View {
        if let radio = self.snapshot?.radio, radio.enabled {
            HStack(spacing: 3) {
                Image(systemName: radio.on ? "dot.radiowaves.left.and.right" : "radio")
                Text(HarnessgramWidgetStrings.radio)
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(radio.on ? HarnessgramWidgetPalette.radioOn : Color.secondary)
            .widgetAccentable(radio.on)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(radio.on ? HarnessgramWidgetStrings.radioOn : HarnessgramWidgetStrings.radioOff)
        }
    }

    private func agentsList(_ snapshot: HarnessgramCockpitSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(HarnessgramWidgetStrings.agentsTitle)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            if snapshot.agents.isEmpty {
                Text(HarnessgramWidgetStrings.noAgents)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            ForEach(snapshot.agents.prefix(3)) { agent in
                Link(destination: HarnessgramCockpitLinks.appURL(forTopicURL: agent.topicURL) ?? HarnessgramCockpitLinks.openURL) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(HarnessgramWidgetPalette.approve)
                            .frame(width: 6, height: 6)
                            .widgetAccentable()
                        Text(agent.name)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.primary)
                            .lineLimit(1)
                        if !agent.step.isEmpty {
                            Text(agent.step)
                                .font(.system(size: 11))
                                .foregroundStyle(Color.secondary)
                                .lineLimit(1)
                                .privacySensitive()
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    private var background: some View {
        LinearGradient(
            colors: [Color(.systemBackground), HarnessgramWidgetPalette.accent.opacity(0.08)],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

/// One waiting decision: title and topic (opens the topic), then its answer buttons.
@available(iOS 17.0, *)
struct HarnessgramDecisionRow: View {
    let decision: HarnessgramCockpitSnapshot.Decision
    let route: HarnessgramDecisionGate.Route
    let showsTopic: Bool

    var body: some View {
        HStack(spacing: 8) {
            Link(destination: HarnessgramCockpitLinks.appURL(forTopicURL: self.decision.topicURL) ?? HarnessgramCockpitLinks.openURL) {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        if self.decision.sensitive {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(HarnessgramWidgetPalette.sensitive)
                                .widgetAccentable()
                                .accessibilityLabel(HarnessgramWidgetStrings.needsFaceID)
                        }
                        Text(self.decision.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.primary)
                            .lineLimit(1)
                            .privacySensitive()
                    }
                    if self.showsTopic && !self.decision.topic.isEmpty {
                        Text(self.decision.topic)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            self.buttons
        }
    }

    @ViewBuilder
    private var buttons: some View {
        switch self.route {
        case .answerOnWidget:
            HStack(spacing: 6) {
                Button(intent: HarnessgramAnswerIntent(decisionId: self.decision.id, choice: .yes)) {
                    HarnessgramAnswerLabel(text: self.decision.yesLabel, color: HarnessgramWidgetPalette.approve, filled: true)
                }
                .buttonStyle(.plain)
                Button(intent: HarnessgramAnswerIntent(decisionId: self.decision.id, choice: .no)) {
                    HarnessgramAnswerLabel(text: self.decision.noLabel, color: HarnessgramWidgetPalette.decline, filled: false)
                }
                .buttonStyle(.plain)
            }
        case .answerInApp:
            HStack(spacing: 6) {
                if let yes = HarnessgramCockpitLinks.decideURL(id: self.decision.id, choice: .yes) {
                    Link(destination: yes) {
                        HarnessgramAnswerLabel(text: self.decision.yesLabel, color: HarnessgramWidgetPalette.approve, filled: true)
                    }
                }
                if let no = HarnessgramCockpitLinks.decideURL(id: self.decision.id, choice: .no) {
                    Link(destination: no) {
                        HarnessgramAnswerLabel(text: self.decision.noLabel, color: HarnessgramWidgetPalette.decline, filled: false)
                    }
                }
            }
        case .answerInAppWithFaceID:
            if let open = HarnessgramCockpitLinks.decideURL(id: self.decision.id, choice: nil) {
                Link(destination: open) {
                    HStack(spacing: 4) {
                        Image(systemName: "faceid")
                        Text(HarnessgramWidgetStrings.openToAnswer)
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(HarnessgramWidgetPalette.sensitive)
                    .padding(.horizontal, 10)
                    .frame(minHeight: 30)
                    .background(Capsule().strokeBorder(HarnessgramWidgetPalette.sensitive, lineWidth: 1.2))
                    .accessibilityLabel(HarnessgramWidgetStrings.needsFaceID)
                }
            }
        }
    }
}

@available(iOS 17.0, *)
struct HarnessgramAnswerLabel: View {
    let text: String
    let color: Color
    let filled: Bool
    @Environment(\.widgetRenderingMode) private var renderingMode

    /// How an answer button draws in one rendering mode.
    enum Style: Equatable {
        /// White label on the colour (full colour only).
        case solid
        /// Label and border in one tone over a faint tint of it: the filled button in the tinted, Clear and lock-screen
        /// looks, where iOS draws every colour in one tone and a white label on a fill would vanish (owner, build 30).
        case tinted
        /// Coloured label and border, no fill.
        case outline
    }

    static func style(filled: Bool, renderingMode: WidgetRenderingMode) -> Style {
        guard filled else {
            return .outline
        }
        return renderingMode == .fullColor ? .solid : .tinted
    }

    var body: some View {
        let style = HarnessgramAnswerLabel.style(filled: self.filled, renderingMode: self.renderingMode)
        // In one-tone looks the label, border and tint use the primary tone (the accent group when accented).
        let tone: Color = self.renderingMode == .fullColor ? self.color : Color.primary
        Text(self.text)
            .font(.system(size: 12, weight: .semibold))
            .lineLimit(1)
            .foregroundStyle(style == .solid ? Color.white : tone)
            .padding(.horizontal, 12)
            .frame(minWidth: 44, minHeight: 30)
            .background(
                Capsule()
                    .fill(style == .solid ? self.color : (style == .tinted ? tone.opacity(0.18) : Color.clear))
                    .overlay(Capsule().strokeBorder(tone, lineWidth: style == .solid ? 0 : (style == .tinted ? 1.6 : 1.2)))
            )
            // The approve button is the key control: tinted with the owner's accent in the accented look.
            .widgetAccentable(self.filled)
    }
}
