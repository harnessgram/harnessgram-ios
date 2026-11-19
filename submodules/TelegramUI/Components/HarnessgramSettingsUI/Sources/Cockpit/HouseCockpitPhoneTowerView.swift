import Foundation
import SwiftUI
import HarnessgramSettings
import HarnessgramCockpitKit
import HarnessgramHouseCore

// MARK: The phone tower (the Cockpit tab on compact width, switch "towerPhone")

/// The Cockpit tab on the phone as the control tower at night (the concept's phone): a full-bleed dark page with the
/// tower header and its runway, the instruments (radar with the counts, the lead flight's altimeter), what waits for
/// the owner first (the same rows and answers as the phone list: routine ones in one tap, sensitive ones through the
/// usual Face ID flow), the lead flight and the flight strips (a tap opens the task's room), the agents at work, the
/// radio, the waiting list and the full Cockpit. Every element of the phone list stays here; the pairing, loading,
/// error and empty states are the same pages in the tower's colours.
struct HouseCockpitPhoneTowerView: View {
    @ObservedObject var model: HouseCockpitTabModel
    @ObservedObject var radio: HarnessgramRadioPlayer
    /// false only for snapshot renders (ImageRenderer draws no scroll view content).
    var scrolls = true

    var body: some View {
        ZStack(alignment: .top) {
            HouseTowerBackground().ignoresSafeArea()
            HouseTowerScroll(scrolls: self.scrolls) {
                VStack(alignment: .leading, spacing: 16) {
                    HouseTowerPhoneHeader(model: self.model)
                    // Every section of the phone list, in its order, plus the instruments and the agents
                    // (HarnessgramCockpitDesk.pageSections).
                    ForEach(HarnessgramCockpitDesk.pageSections(state: self.model.tab.state, tower: true), id: \.self) { section in
                        self.section(section)
                    }
                }
                .padding(.horizontal, 16)
                // Clear of the floating tab bar: the safe area ends at its top edge, and this keeps the last button
                // (the full Cockpit) a full gutter above it when the list is scrolled to the end.
                .padding(.bottom, 24)
            }
            .modifier(HouseTowerPhoneRefreshable(model: self.model))
            // The night sky closes over the content under the status bar, so the clock and the cards never mix.
            VStack(spacing: 0) {
                LinearGradient(stops: [.init(color: HouseTowerPalette.skyTop, location: 0), .init(color: HouseTowerPalette.skyTop.opacity(0.96), location: self.scrimSolidPart), .init(color: HouseTowerPalette.skyTop.opacity(0), location: 1)], startPoint: .top, endPoint: .bottom)
                    .frame(height: self.model.statusBarHeight + 16)
                Spacer(minLength: 0)
            }
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        // The large system button height (about 50 points): the filled and bordered buttons of a row stand equally tall,
        // above the 44-point touch target.
        .environment(\.harnessgramMinimumTapHeight, 50.0)
        .tint(HouseTowerPalette.accent)
    }

    /// The share of the scrim that stays solid: the status bar itself, then a short fade.
    private var scrimSolidPart: CGFloat {
        let top = self.model.statusBarHeight
        return top / max(1.0, top + 16.0)
    }

    @ViewBuilder
    private func section(_ section: HarnessgramCockpitDesk.PageSection) -> some View {
        let tab = self.model.tab
        switch section {
        case .pairing:
            if case let .notPaired(paused) = tab.state {
                self.pairingCard(paused: paused)
            }
        case .loading:
            HStack(spacing: 12) {
                ProgressView()
                Text(HouseCockpitStrings.loading)
                    .foregroundColor(HouseTowerPalette.secondaryText)
            }
            .frame(minHeight: 44)
            .houseTowerCard()
        case .unavailable:
            if case let .unavailable(reason) = tab.state {
                self.unavailableCard(reason: reason)
            }
        case .empty:
            HouseTowerPhoneStateCard(systemImage: "checkmark.seal", color: HouseTowerPalette.approve, title: HouseCockpitStrings.emptyTitle, detail: HouseCockpitStrings.emptyDetail) {
                EmptyView()
            }
        case .instruments:
            HouseTowerPhoneInstruments(model: self.model, lead: HarnessgramCockpitDesk.leadTask(tab.tasks))
        case .decisions:
            self.decisions
        case .tasks:
            self.flightBoard
        case .agents:
            HouseTowerPhoneAgents(agents: tab.agents)
        case .radio:
            HouseCockpitTowerRadioCard(model: self.model, radio: self.radio)
        case .waitingList:
            HouseCockpitTowerWaitingRow(model: self.model)
        case .fullCockpit:
            HouseCockpitTowerFullCockpitButton(model: self.model)
        }
    }

    private func pairingCard(paused: Bool) -> some View {
        HouseTowerPhoneStateCard(systemImage: "antenna.radiowaves.left.and.right", color: HouseTowerPalette.accent, title: HouseCockpitStrings.notPairedTitle, detail: paused ? HouseCockpitStrings.pausedDetail : HouseCockpitStrings.notPairedDetail) {
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
                    .foregroundColor(HouseTowerPalette.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func unavailableCard(reason: HarnessgramPairFailure?) -> some View {
        HouseTowerPhoneStateCard(systemImage: "exclamationmark.triangle", color: HouseTowerPalette.horizonGlow, title: HouseCockpitStrings.unavailableTitle, detail: reason?.text ?? HouseCockpitStrings.unavailableNoAnswer) {
            Button(action: { self.model.retry() }) {
                Label(HouseCockpitStrings.retry, systemImage: "arrow.clockwise")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.harnessgramFilled)
        }
    }

    /// What waits for the owner, first.
    @ViewBuilder
    private var decisions: some View {
        let tab = self.model.tab
        HouseTowerPhoneSectionTitle(text: HouseCockpitStrings.header(HouseCockpitStrings.decisionsHeader, count: tab.waitingCount), systemImage: "hand.raised.fill", color: HouseTowerPalette.horizonGlow)
        if tab.decisions.isEmpty {
            Label(HouseCockpitStrings.decisionsEmpty, systemImage: "checkmark.circle")
                .font(.subheadline)
                .foregroundColor(HouseTowerPalette.secondaryText)
                .frame(minHeight: 28, alignment: .leading)
                .houseTowerCard()
        } else {
            ForEach(tab.decisions) { decision in
                HouseCockpitDecisionRow(model: self.model, decision: decision, iconColor: HouseTowerPalette.accent)
                    .houseTowerPhoneWaitingCard()
            }
        }
    }

    /// The flight board: the lead flight, then the other strips.
    @ViewBuilder
    private var flightBoard: some View {
        let tab = self.model.tab
        let lead = HarnessgramCockpitDesk.leadTask(tab.tasks)
        let strips = HarnessgramCockpitDesk.stripTasks(tab.tasks)
        let waitingByTask = HarnessgramCockpitDesk.waitingByTask(tasks: tab.tasks, decisions: tab.decisions)
        HouseTowerPhoneSectionTitle(text: HouseCockpitStrings.header(HouseCockpitStrings.tasksHeader, count: tab.tasks.filter { !$0.finished }.count), systemImage: "airplane", color: HouseTowerPalette.accent)
        if tab.tasks.isEmpty {
            Text(HouseCockpitStrings.tasksEmpty)
                .foregroundColor(HouseTowerPalette.secondaryText)
                .houseTowerCard()
        } else {
            if let lead {
                HouseTowerPhoneLeadCard(model: self.model, task: lead, waiting: waitingByTask[lead.id] ?? 0)
            }
            ForEach(strips) { task in
                HouseTowerPhoneStrip(model: self.model, task: task, waiting: waitingByTask[task.id] ?? 0)
            }
        }
    }
}

// MARK: Header

/// The tower at dusk: the badge and the title at the start edge, the lit tower at the end edge, the runway lights
/// along the bottom. Drawn in SwiftUI (no photo yet), so it scales and stays sharp.
private struct HouseTowerPhoneHeader: View {
    @ObservedObject var model: HouseCockpitTabModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let tab = self.model.tab
        ZStack(alignment: .bottom) {
            HouseTowerPhoneRunway()
                .frame(height: 26)
                .padding(.horizontal, -16)
            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    HouseTowerBadge(size: 40)
                        .padding(.bottom, 6)
                    Text(HouseCockpitStrings.towerTitle)
                        .font(.system(.largeTitle, design: .rounded).weight(.bold))
                        .foregroundColor(HouseTowerPalette.primaryText)
                        // Accessibility sizes wrap to a second line instead of shrinking the title away.
                        .lineLimit(self.dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                        .minimumScaleFactor(self.dynamicTypeSize.isAccessibilitySize ? 0.85 : 0.7)
                        .fixedSize(horizontal: false, vertical: self.dynamicTypeSize.isAccessibilitySize)
                        .accessibilityAddTraits(.isHeader)
                    if case .content = tab.state {
                        Text(HouseCockpitStrings.towerLine(flying: tab.tasks.filter { !$0.finished }.count, waiting: tab.waitingCount))
                            .font(.subheadline)
                            .foregroundColor(HouseTowerPalette.secondaryText)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.bottom, 30)
                Spacer(minLength: 0)
                if !self.dynamicTypeSize.isAccessibilitySize {
                    HouseTowerPhoneTowerArt()
                        .frame(width: 92, height: 132)
                        .padding(.bottom, 14)
                }
            }
        }
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
    }
}

/// The lit control tower: the shared tower glyph in steel, its cab windows glowing amber, a beacon on the antenna.
private struct HouseTowerPhoneTowerArt: View {
    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            ZStack(alignment: .topLeading) {
                // The cab's window band, lit from inside (it shows through the gaps between the mullions).
                RoundedRectangle(cornerRadius: 2)
                    .fill(LinearGradient(colors: [HouseTowerPalette.cabWindow, HouseTowerPalette.horizonGlow], startPoint: .top, endPoint: .bottom))
                    .frame(width: w * 0.60, height: h * 0.12)
                    .offset(x: w * 0.20, y: h * 0.24)
                    .shadow(color: HouseTowerPalette.horizonGlow.opacity(0.9), radius: 10)
                HouseTowerShape()
                    .fill(LinearGradient(colors: [HouseTowerPalette.towerSteelTop, HouseTowerPalette.towerSteelBottom], startPoint: .top, endPoint: .bottom))
                HouseTowerShape()
                    .stroke(HouseTowerPalette.glassEdge.opacity(0.25), lineWidth: 0.8)
                Circle()
                    .fill(HouseTowerPalette.horizonGlow)
                    .frame(width: 5, height: 5)
                    .shadow(color: HouseTowerPalette.horizonGlow, radius: 4)
                    .offset(x: w * 0.5 - 2.5, y: -3)
            }
        }
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityHidden(true)
    }
}

/// The runway at the foot of the header: the horizon glow and two rows of lights converging on the tower's side.
private struct HouseTowerPhoneRunway: View {
    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            ZStack(alignment: .topLeading) {
                LinearGradient(colors: [HouseTowerPalette.horizonGlow.opacity(0.18), .clear], startPoint: .top, endPoint: .bottom)
                Rectangle()
                    .fill(HouseTowerPalette.horizonGlow.opacity(0.35))
                    .frame(width: w, height: 1)
                ForEach(0 ..< 18, id: \.self) { index in
                    let t = CGFloat(index) / 17.0
                    Circle()
                        .fill(index % 3 == 0 ? HouseTowerPalette.accent : HouseTowerPalette.runwayLight)
                        .frame(width: 2.0 + t * 2.4, height: 2.0 + t * 2.4)
                        .shadow(color: HouseTowerPalette.horizonGlow.opacity(0.8), radius: 3)
                        .position(x: w * (0.06 + 0.9 * t), y: h * (0.25 + 0.15 * t))
                    Circle()
                        .fill(HouseTowerPalette.runwayLight.opacity(0.85))
                        .frame(width: 1.6 + t * 2.0, height: 1.6 + t * 2.0)
                        .position(x: w * (0.10 + 0.86 * t), y: h * (0.55 + 0.35 * t))
                }
            }
        }
        // 36 glowing dots: one flattened layer instead of 36 shadowed views on every scroll frame.
        .drawingGroup()
        // Drawn in screen space: the runway's perspective does not mirror with the reading direction.
        .environment(\.layoutDirection, .leftToRight)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: Instruments

/// The radar card (agents at work, what waits, flights in the air) beside the lead flight's altimeter dial; one
/// above the other at the largest text sizes.
private struct HouseTowerPhoneInstruments: View {
    @ObservedObject var model: HouseCockpitTabModel
    let lead: HarnessgramCockpitTabViewModel.Task?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if self.dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 12) {
                self.radarCard
                self.altimeterCard
            }
        } else {
            HStack(alignment: .top, spacing: 12) {
                self.radarCard
                self.altimeterCard
                    .frame(width: 136)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var radarCard: some View {
        let tab = self.model.tab
        return HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 8) {
                Text(HouseCockpitStrings.phoneOverview)
                    .font(.headline)
                    .foregroundColor(HouseTowerPalette.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .accessibilityAddTraits(.isHeader)
                self.count(HouseCockpitStrings.deskRunning(tab.tower?.running ?? 0), color: HouseTowerPalette.accent)
                self.count(HouseCockpitStrings.phoneFlying(tab.tasks.filter { !$0.finished }.count), color: HouseTowerPalette.accent)
                if tab.waitingCount > 0 {
                    self.count(HouseCockpitStrings.deskWaiting(tab.waitingCount), color: HouseTowerPalette.horizonGlow)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !self.dynamicTypeSize.isAccessibilitySize {
                HouseTowerRadar(summary: tab.tower, sweep: HarnessgramTowerSummary.sweepBearing(at: Date()))
                    .frame(width: 76, height: 76)
            }
        }
        .frame(maxHeight: .infinity)
        .houseTowerCard(padding: 12)
        .accessibilityElement(children: .combine)
    }

    private func count(_ text: String, color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7).accessibilityHidden(true)
            Text(text)
                .font(.footnote)
                .foregroundColor(HouseTowerPalette.primaryText)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var altimeterCard: some View {
        VStack(spacing: 6) {
            Text(HouseCockpitStrings.deskAltitude)
                .font(.caption.weight(.semibold))
                .foregroundColor(HouseTowerPalette.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if let lead = self.lead {
                HouseTowerPhoneDial(fraction: lead.fraction)
                    .frame(width: 96, height: 96)
            } else {
                Image(systemName: "airplane.arrival")
                    .flipsForRightToLeftLayoutDirection(true)
                    .font(.title)
                    .foregroundColor(HouseTowerPalette.approve)
                    .frame(height: 60)
                    .accessibilityHidden(true)
                Text(HouseCockpitStrings.phoneNoFlight)
                    .font(.footnote)
                    .foregroundColor(HouseTowerPalette.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .houseTowerCard(padding: 12)
    }
}

/// The altimeter dial: the progress as a climb (HarnessgramAltimeter, the lock screen's rule) on a round gauge with
/// its scale, a mint arc for the climb, the needle and the reading in feet.
private struct HouseTowerPhoneDial: View {
    let fraction: Double
    // The reading follows Dynamic Type (its line still shrinks to fit the dial).
    @ScaledMetric(relativeTo: .headline) private var readingSize: CGFloat = 17.0
    @ScaledMetric(relativeTo: .caption2) private var unitSize: CGFloat = 11.0

    var body: some View {
        let value = min(max(self.fraction.isFinite ? self.fraction : 0.0, 0.0), 1.0)
        let altitude = HarnessgramAltimeter.altitude(fraction: value)
        // The arc runs 270 degrees, from the lower left round the top to the lower right.
        let start = 135.0
        let sweep = 270.0
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let radius = side / 2
            ZStack {
                Circle().fill(HouseTowerPalette.background.opacity(0.7))
                Circle()
                    .trim(from: 0, to: 0.75)
                    .stroke(HouseTowerPalette.track, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(start))
                Circle()
                    .trim(from: 0, to: 0.75 * value)
                    .stroke(HouseTowerPalette.accent, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(start))
                    .shadow(color: HouseTowerPalette.accent.opacity(0.6), radius: 4)
                Path { path in
                    for tick in 0 ... 10 {
                        let angle = (start + sweep * Double(tick) / 10.0) * .pi / 180
                        let outer = radius - 10
                        let inner = radius - (tick % 5 == 0 ? 18 : 14)
                        path.move(to: CGPoint(x: radius + cos(angle) * inner, y: radius + sin(angle) * inner))
                        path.addLine(to: CGPoint(x: radius + cos(angle) * outer, y: radius + sin(angle) * outer))
                    }
                }
                .stroke(HouseTowerPalette.secondaryText.opacity(0.7), lineWidth: 1)
                Path { path in
                    let angle = (start + sweep * value) * .pi / 180
                    path.move(to: CGPoint(x: radius, y: radius))
                    path.addLine(to: CGPoint(x: radius + cos(angle) * (radius - 26), y: radius + sin(angle) * (radius - 26)))
                }
                .stroke(HouseTowerPalette.horizonGlow, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                Circle().fill(HouseTowerPalette.horizonGlow).frame(width: 6, height: 6)
                VStack(spacing: 0) {
                    Text(HarnessgramAltimeter.label(altitude))
                        .font(.system(size: self.readingSize, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundColor(HouseTowerPalette.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(HouseCockpitStrings.phoneFeet)
                        .font(.system(size: self.unitSize, weight: .medium))
                        .foregroundColor(HouseTowerPalette.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .padding(.top, side * 0.42)
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityElement()
        .accessibilityLabel(Text(HarnessgramWidgetStrings.altitude(HarnessgramAltimeter.label(altitude))))
    }
}

// MARK: Waiting for you

private extension View {
    /// A decision's card: the glass card with an amber edge at the start side (what waits for the owner).
    func houseTowerPhoneWaitingCard() -> some View {
        return self
            .padding(.leading, 6)
            .houseTowerCard(padding: 12)
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(HouseTowerPalette.horizonGlow)
                    .frame(width: 4)
                    .padding(.vertical, 12)
                    .padding(.leading, 6)
                    .accessibilityHidden(true)
            }
    }
}

private struct HouseTowerPhoneSectionTitle: View {
    let text: String
    let systemImage: String
    let color: Color
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: self.systemImage)
                .flipsForRightToLeftLayoutDirection(true)
                .foregroundColor(self.color)
                .accessibilityHidden(true)
            Text(self.text)
                .font(.title3.weight(.bold))
                .foregroundColor(HouseTowerPalette.primaryText)
            if !self.dynamicTypeSize.isAccessibilitySize {
                HouseTowerHazardStripes()
                    .frame(width: 28, height: 10)
                    .opacity(0.8)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 4)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// The hazard stripes at a strip's edge (the concept's amber and slate chevrons).
struct HouseTowerHazardStripes: View {
    var body: some View {
        GeometryReader { proxy in
            let h = proxy.size.height
            let step = h * 0.9
            let count = Int(proxy.size.width / step) + 2
            ZStack(alignment: .topLeading) {
                ForEach(0 ..< count, id: \.self) { index in
                    Path { path in
                        let x = CGFloat(index) * step
                        path.move(to: CGPoint(x: x, y: h))
                        path.addLine(to: CGPoint(x: x + step * 0.55, y: h))
                        path.addLine(to: CGPoint(x: x + step * 0.55 + h * 0.6, y: 0))
                        path.addLine(to: CGPoint(x: x + h * 0.6, y: 0))
                        path.closeSubpath()
                    }
                    .fill(index % 2 == 0 ? HouseTowerPalette.runwayAmber : HouseTowerPalette.secondaryText.opacity(0.45))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 2))
        }
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityHidden(true)
    }
}

// MARK: The flight board

/// The lead flight (the first task still in the air): the state, its name in two lines at most, the step, the
/// progress with its percent, and what waits in its room. A tap opens the room, as the phone list's task row does.
private struct HouseTowerPhoneLeadCard: View {
    @ObservedObject var model: HouseCockpitTabModel
    let task: HarnessgramCockpitTabViewModel.Task
    let waiting: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: { self.model.openTask(self.task) }) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .center, spacing: 8) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(HouseTowerPalette.accent)
                                .frame(width: 8, height: 8)
                                .shadow(color: HouseTowerPalette.accent, radius: 3)
                            Text(HouseCockpitStrings.phoneLeadFlight)
                                .font(.caption.weight(.semibold))
                                .foregroundColor(HouseTowerPalette.accent)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(HouseTowerPalette.background.opacity(0.7)))
                        .overlay(Capsule().stroke(HouseTowerPalette.accent.opacity(0.6), lineWidth: 1))
                        Spacer(minLength: 0)
                        HouseTowerHazardStripes()
                            .frame(width: 44, height: 10)
                    }
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(self.task.title)
                                .font(.title3.weight(.bold))
                                .foregroundColor(HouseTowerPalette.primaryText)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                            let line = HouseCockpitStrings.phoneStepLine(position: HarnessgramCockpitDesk.stepPosition(self.task), step: self.task.step, finished: self.task.finished)
                            if !line.isEmpty {
                                Text(line)
                                    .font(.subheadline)
                                    .foregroundColor(HouseTowerPalette.secondaryText)
                                    .lineLimit(2)
                            }
                            if !self.task.topic.isEmpty {
                                Label(self.task.topic, systemImage: "bubble.left.and.bubble.right")
                                    .font(.footnote)
                                    .foregroundColor(HouseTowerPalette.secondaryText)
                                    .lineLimit(1)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        HouseTowerPhonePlaneTile(finished: false, size: 44)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(HouseCockpitStrings.deskProgress)
                                .font(.subheadline)
                                .foregroundColor(HouseTowerPalette.secondaryText)
                            Spacer()
                            Text("\(self.task.percent)%")
                                .font(.headline.monospacedDigit())
                                .foregroundColor(HouseTowerPalette.accent)
                        }
                        HouseTowerBar(fraction: self.task.fraction, finished: false, height: 10)
                    }
                    if self.waiting > 0 {
                        Label(HouseCockpitStrings.deskWaiting(self.waiting), systemImage: "hand.raised.fill")
                            .font(.footnote.weight(.semibold))
                            .foregroundColor(HouseTowerPalette.horizonGlow)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!self.model.canOpenTask(self.task))
            .accessibilityElement(children: .combine)
            .accessibilityHint(Text(HouseCockpitStrings.phoneOpenRoomHint))
            HouseTowerPhoneOriginalText(task: self.task)
        }
        .houseTowerCard(selected: true, padding: 16)
    }
}

/// One flight strip on the phone: the name (two lines at most) with its state dot, the step and percent with the
/// room, the bar, what waits in its room, and the plane in its tile over the hazard stripes. A tap opens the room.
private struct HouseTowerPhoneStrip: View {
    @ObservedObject var model: HouseCockpitTabModel
    let task: HarnessgramCockpitTabViewModel.Task
    let waiting: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: { self.model.openTask(self.task) }) {
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
                        Text(HouseCockpitStrings.stripLine(position: HarnessgramCockpitDesk.stepPosition(self.task), percent: self.task.percent, finished: self.task.finished) + (self.task.finished || self.task.step.isEmpty ? "" : " · " + self.task.step))
                            .font(.footnote)
                            .foregroundColor(HouseTowerPalette.secondaryText)
                            .lineLimit(2)
                        if !self.task.topic.isEmpty {
                            Text(self.task.topic)
                                .font(.caption)
                                .foregroundColor(HouseTowerPalette.secondaryText)
                                .lineLimit(1)
                        }
                        HouseTowerBar(fraction: self.task.fraction, finished: self.task.finished, height: 5)
                        if self.waiting > 0 {
                            Label(HouseCockpitStrings.deskWaiting(self.waiting), systemImage: "hand.raised.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(HouseTowerPalette.horizonGlow)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    VStack(spacing: 6) {
                        HouseTowerPhonePlaneTile(finished: self.task.finished, size: 40)
                        HouseTowerHazardStripes()
                            .frame(width: 40, height: 8)
                    }
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!self.model.canOpenTask(self.task))
            .accessibilityElement(children: .combine)
            .accessibilityHint(Text(HouseCockpitStrings.phoneOpenRoomHint))
            HouseTowerPhoneOriginalText(task: self.task)
        }
        .houseTowerCard(padding: 12)
    }
}

/// The plane in its rounded tile (mint in the air, green once landed), pointing toward the reading direction.
private struct HouseTowerPhonePlaneTile: View {
    let finished: Bool
    let size: CGFloat

    var body: some View {
        let color = self.finished ? HouseTowerPalette.approve : HouseTowerPalette.accent
        RoundedRectangle(cornerRadius: self.size * 0.28, style: .continuous)
            .fill(HouseTowerPalette.background.opacity(0.75))
            .overlay(RoundedRectangle(cornerRadius: self.size * 0.28, style: .continuous).stroke(color.opacity(0.45), lineWidth: 1))
            .overlay(
                HouseTowerPlane(finished: self.finished)
                    .font(.system(size: self.size * 0.45, weight: .semibold))
            )
            .frame(width: self.size, height: self.size)
            .accessibilityHidden(true)
    }
}

/// A task's original (untranslated) text, folded, left to right (the phone list's disclosure).
private struct HouseTowerPhoneOriginalText: View {
    let task: HarnessgramCockpitTabViewModel.Task

    var body: some View {
        if self.task.hasOriginalText {
            DisclosureGroup(HouseCockpitStrings.originalText) {
                VStack(alignment: .leading, spacing: 4) {
                    if let value = self.task.originalTitle, value != self.task.title { Text(value) }
                    if let value = self.task.originalTopic, value != self.task.topic, !value.isEmpty { Text(value) }
                    if let value = self.task.originalStep, value != self.task.step, !value.isEmpty { Text(value) }
                }
                .font(.footnote)
                .foregroundColor(HouseTowerPalette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .environment(\.layoutDirection, .leftToRight)
            }
            .font(.footnote)
            .foregroundColor(HouseTowerPalette.secondaryText)
            .frame(minHeight: 44)
        }
    }
}

// MARK: Agents

/// The agents at work as tiles (the concept's "סוכנים פעילים"): a plane and the agent's name, two lines at most.
private struct HouseTowerPhoneAgents: View {
    let agents: [HarnessgramCockpitSnapshot.Agent]
    private static let shown = 6
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "scope")
                    .foregroundColor(HouseTowerPalette.accent)
                    .accessibilityHidden(true)
                Text(HouseCockpitStrings.deskAgents)
                    .font(.headline)
                    .foregroundColor(HouseTowerPalette.primaryText)
                Spacer(minLength: 0)
                if self.agents.count > 0 {
                    Text("\(self.agents.count)")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundColor(HouseTowerPalette.secondaryText)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            if self.agents.isEmpty {
                Text(HouseCockpitStrings.deskNoAgents)
                    .font(.footnote)
                    .foregroundColor(HouseTowerPalette.secondaryText)
            } else {
                // One tile per row at the largest text sizes, so the names keep their words.
                LazyVGrid(columns: [GridItem(.adaptive(minimum: self.dynamicTypeSize.isAccessibilitySize ? 260 : 92), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(self.agents.prefix(HouseTowerPhoneAgents.shown)) { agent in
                        VStack(spacing: 6) {
                            HouseTowerPlane(finished: false)
                                .font(.title3)
                            Text(agent.name.isEmpty ? HouseCockpitStrings.deskUnnamedAgent : agent.name)
                                .font(.footnote.weight(.semibold))
                                .foregroundColor(HouseTowerPalette.primaryText)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                            if !agent.step.isEmpty {
                                Text(agent.step)
                                    .font(.caption2)
                                    .foregroundColor(HouseTowerPalette.secondaryText)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(1)
                            }
                        }
                        .padding(.vertical, 10)
                        .padding(.horizontal, 6)
                        .frame(maxWidth: .infinity, minHeight: 72)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(HouseTowerPalette.background.opacity(0.6)))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(HouseTowerPalette.glassEdge.opacity(0.15), lineWidth: 1))
                        .accessibilityElement(children: .combine)
                    }
                }
                if self.agents.count > HouseTowerPhoneAgents.shown {
                    Text(HouseCockpitStrings.phoneMoreAgents(self.agents.count - HouseTowerPhoneAgents.shown))
                        .font(.footnote)
                        .foregroundColor(HouseTowerPalette.secondaryText)
                }
            }
        }
        .houseTowerCard()
    }
}

// MARK: States

/// The pairing, error and empty pages as one glass card: the symbol, the title, the detail and the action.
private struct HouseTowerPhoneStateCard<Actions: View>: View {
    let systemImage: String
    let color: Color
    let title: String
    let detail: String
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: self.systemImage)
                .font(.system(size: 40))
                .foregroundColor(self.color)
                .accessibilityHidden(true)
            Text(self.title)
                .font(.title3.weight(.semibold))
                .foregroundColor(HouseTowerPalette.primaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text(self.detail)
                .font(.subheadline)
                .foregroundColor(HouseTowerPalette.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            self.actions()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .houseTowerCard(padding: 16)
    }
}

/// Pull to refresh on the phone tower (a scroll view refreshes from iOS 16).
private struct HouseTowerPhoneRefreshable: ViewModifier {
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
