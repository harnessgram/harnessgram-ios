import Foundation
import SwiftUI
import WidgetKit
import HarnessgramCockpitKit
#if canImport(ActivityKit)
import ActivityKit
#endif

/// The task Live Activity's spacing system (build 21): the lock screen banner and the expanded island keep 16 pt from
/// their edges, 12 pt between blocks and 8 pt between items in a row; the compact and minimal island regions keep their
/// content clear of the pill's rounded ends.
public enum HarnessgramTaskActivityLayout {
    /// Padding of the lock screen banner and the expanded island's content margins.
    public static let outer: CGFloat = 16
    /// Between blocks: the header, the bar, the step line, the step dots.
    public static let inner: CGFloat = 12
    /// Between items in one row.
    public static let gap: CGFloat = 8
    /// Compact regions: toward the pill's rounded end.
    public static let compactOuter: CGFloat = 8
    /// Compact regions: toward the camera.
    public static let compactInner: CGFloat = 4
    /// Around the ring in the minimal (round) region.
    public static let minimalInset: CGFloat = 2
    /// Expanded island: extra inset for the top and bottom rows, which sit inside the island's big rounded
    /// corners; the content margins alone left the step line clipped at the edge (owner, build 23).
    public static let islandCorner: CGFloat = 12
}

extension Color {
    init(_ rgb: HarnessgramRGB) {
        self.init(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue, opacity: 1.0)
    }
}

/// Foreground roles shared by the lock screen and expanded Dynamic Island. The progress bar and readout have their
/// own paired fills. Text on the lock screen's system surface uses semantic colours resolved by the renderer.
struct HarnessgramTaskActivityColors {
    let instruments: HarnessgramTaskActivityPalette
    var usesSystemForeground = false

    static func lockScreen(luminanceReduced: Bool) -> HarnessgramTaskActivityColors {
        return HarnessgramTaskActivityColors(
            instruments: HarnessgramTaskActivityPalette.palette(luminanceReduced: luminanceReduced),
            usesSystemForeground: true
        )
    }

    var primaryText: Color {
        return self.usesSystemForeground ? .primary : Color(self.instruments.primaryText)
    }

    var secondaryText: Color {
        return self.usesSystemForeground ? Color.primary.opacity(0.9) : Color(self.instruments.secondaryText)
    }

    func taskMark(finished: Bool) -> Color {
        return self.usesSystemForeground ? .primary : Color(finished ? self.instruments.approve : self.instruments.accent)
    }

    var waitingMark: Color {
        return self.usesSystemForeground ? .primary : Color(self.instruments.glow)
    }
}

/// The lock screen face of the agent task Live Activity (lock screen pack, "flight deck") with the
/// tower and "Harnessgram", the "משימה פעילה" badge with the live signal, "<topic>: <title>", "שלב X מתוך Y · <step>",
/// the mint bar filling from the right with the percent, and the altimeter tape climbing with the progress. The overflow
/// summary ("+N", overflowCount != nil) gets the same card with the radar instead of the bar and tape. Public so the
/// snapshot tests render it. ActivityKit supplies the card surface.
@available(iOS 17.0, *)
public struct HarnessgramTaskLockScreenView: View {
    let state: HarnessgramTaskState
    let isStale: Bool
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    public init(state: HarnessgramTaskState, isStale: Bool = false) {
        self.state = state
        self.isStale = isStale
    }

    /// The card's instrument row (title, step, bar beside the tape): fits the lock screen's 160 pt banner with the header.
    static let instrumentHeight: CGFloat = 86
    static let tapeWidth: CGFloat = 78

    public var body: some View {
        let colors = HarnessgramTaskActivityColors.lockScreen(luminanceReduced: self.isLuminanceReduced)
        VStack(alignment: .leading, spacing: HarnessgramTaskActivityLayout.inner) {
            HarnessgramTaskCardHeader(state: self.state, isStale: self.isStale, colors: colors)
            if self.state.overflowCount != nil {
                HarnessgramTaskSummaryBody(state: self.state, colors: colors)
            } else {
                HStack(alignment: .center, spacing: 14) {
                    HarnessgramTaskTextColumn(state: self.state, colors: colors, titleSize: 17, showsBar: true, glows: !self.isLuminanceReduced)
                    HarnessgramAltimeterTape(fraction: self.state.fraction, finished: self.state.finished, colors: colors)
                        .frame(width: HarnessgramTaskLockScreenView.tapeWidth)
                }
                .frame(height: HarnessgramTaskLockScreenView.instrumentHeight)
            }
        }
        .padding(HarnessgramTaskActivityLayout.outer)
        .environment(\.layoutDirection, .rightToLeft)
    }
}

/// The tower and the brand on the right, the badge on the left.
@available(iOS 17.0, *)
struct HarnessgramTaskCardHeader: View {
    let state: HarnessgramTaskState
    let isStale: Bool
    let colors: HarnessgramTaskActivityColors

    var body: some View {
        let accent = self.colors.taskMark(finished: self.state.finished)
        HStack(spacing: HarnessgramTaskActivityLayout.gap) {
            HarnessgramTowerGlyph(color: accent)
                .frame(height: 20)
            Text(HarnessgramWidgetStrings.brandName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(self.colors.primaryText)
                .lineLimit(1)
            Spacer(minLength: HarnessgramTaskActivityLayout.gap)
            if self.state.overflowCount == nil {
                HarnessgramStatusPill(
                    text: self.state.badge(isStale: self.isStale),
                    systemImage: self.state.finished ? "checkmark" : (self.isStale ? "antenna.radiowaves.left.and.right.slash" : "dot.radiowaves.left.and.right"),
                    color: self.isStale && !self.state.finished ? self.colors.secondaryText : accent,
                    textColor: self.colors.primaryText
                )
            } else {
                let pill = HarnessgramTaskSummaryPill(state: self.state)
                HarnessgramStatusPill(text: pill.text, systemImage: pill.systemImage, color: pill.waiting ? self.colors.waitingMark : accent, textColor: self.colors.primaryText)
            }
        }
    }
}

/// Title (with the topic), the step line and, when asked, the bar with the percent. Shared by the lock screen card and
/// the expanded Dynamic Island.
@available(iOS 17.0, *)
struct HarnessgramTaskTextColumn: View {
    let state: HarnessgramTaskState
    let colors: HarnessgramTaskActivityColors
    let titleSize: CGFloat
    let showsBar: Bool
    let glows: Bool
    /// The percent beside the bar; the island shows it in its dial instead.
    var showsPercent: Bool = true

    var body: some View {
        let headline = self.state.headline
        let accent = self.colors.taskMark(finished: self.state.finished)
        VStack(alignment: .leading, spacing: 6) {
            if let eyebrow = headline.eyebrow {
                Text(eyebrow)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(self.colors.secondaryText)
                    .lineLimit(1)
            }
            Text(headline.line)
                .font(.system(size: self.titleSize, weight: .bold))
                .foregroundStyle(self.colors.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity, alignment: .leading)
            if !self.state.stepLine.isEmpty {
                // Separate runs: the step count and the step's name never share one bidi line.
                HStack(spacing: 5) {
                    Text(self.state.stepLine)
                        .font(.system(size: 13, weight: .medium).monospacedDigit())
                        .foregroundStyle(self.colors.secondaryText)
                        .layoutPriority(1)
                    if let current = self.state.currentStep {
                        Text("·")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(accent)
                        Text(current)
                            .font(.system(size: 13))
                            .foregroundStyle(self.colors.secondaryText)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .lineLimit(1)
            }
            if self.showsBar {
                Spacer(minLength: 0)
                HStack(spacing: 10) {
                    HarnessgramTaskBar(fraction: self.state.fraction, finished: self.state.finished, palette: self.colors.instruments, height: 8, glows: self.glows)
                    if self.showsPercent {
                        Text(HarnessgramWidgetStrings.percent(self.state.percentShown))
                            .font(.system(size: 17, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(accent)
                            .fixedSize()
                    }
                }
            }
        }
    }
}

/// The overflow summary's badge: "מחכה לך" when its first row is a decision waiting for the owner, otherwise
/// "עוד משימות".
struct HarnessgramTaskSummaryPill {
    let text: String
    let systemImage: String
    let waiting: Bool

    init(state: HarnessgramTaskState) {
        let waiting = HarnessgramTaskSummaryRow.decode(state).first?.kind == .waiting
        self.waiting = waiting
        self.text = waiting ? HarnessgramWidgetStrings.summaryWaitingBadge : HarnessgramWidgetStrings.moreTasksBadge
        self.systemImage = waiting ? "hand.raised.fill" : "airplane"
    }
}

/// The overflow summary's body: up to three flight-strip lines (what waits for the owner first, then the hidden
/// tasks, most recently updated first, each with its percent) and "+K" for hidden tasks beyond them. An older summary
/// without rows keeps the plain "עוד N משימות באוויר" card with the radar.
@available(iOS 17.0, *)
struct HarnessgramTaskSummaryBody: View {
    let state: HarnessgramTaskState
    let colors: HarnessgramTaskActivityColors
    var rowSize: CGFloat = 14

    var body: some View {
        let rows = HarnessgramTaskSummaryRow.decode(self.state)
        let count = self.state.overflowCount ?? 0
        if rows.isEmpty {
            self.plain(count: count)
        } else {
            let extra = HarnessgramTaskSummaryRow.extraCount(self.state)
            let accent = self.colors.taskMark(finished: false)
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        HarnessgramTaskSummaryLine(row: row, colors: self.colors, size: self.rowSize)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if extra > 0 {
                    VStack(spacing: 2) {
                        Text("+\(extra)")
                            .font(.system(size: 15, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(accent)
                            .frame(width: 38, height: 38)
                            .background(Circle().strokeBorder(accent.opacity(0.6), lineWidth: 1.5))
                        Text(HarnessgramWidgetStrings.summaryMoreInCockpit)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(self.colors.secondaryText)
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
            }
        }
    }

    private func plain(count: Int) -> some View {
        let palette = self.colors.instruments
        let accent = self.colors.taskMark(finished: false)
        return HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(HarnessgramWidgetStrings.moreTasksInAir(count))
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(self.colors.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text(HarnessgramWidgetStrings.openCockpit)
                    .font(.system(size: 13))
                    .foregroundStyle(self.colors.secondaryText)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            ZStack {
                HarnessgramRadarScope(
                    summary: HarnessgramTowerSummary(running: count, waiting: 0, nextTitle: nil, nextSensitive: false, nextAskedAt: nil, moreWaiting: 0),
                    sweep: 50,
                    gridColor: accent,
                    runningColor: accent
                )
                .opacity(0.8)
                Text("+\(count)")
                    .font(.system(size: 15, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(Color(palette.primaryText))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color(palette.background)))
                    .overlay(Capsule().strokeBorder(Color(palette.accent).opacity(0.6), lineWidth: 1))
                    .offset(y: 22)
            }
            .frame(width: 60, height: 60)
        }
    }
}

/// One summary line, a compact flight strip: the status dot (mint for a task, sunset amber for what waits), the text
/// on one line (a lock before a sensitive decision's title) and the percent at the end.
@available(iOS 17.0, *)
struct HarnessgramTaskSummaryLine: View {
    let row: HarnessgramTaskSummaryRow
    let colors: HarnessgramTaskActivityColors
    let size: CGFloat

    var body: some View {
        let waiting = self.row.kind == .waiting
        let accent = self.colors.taskMark(finished: false)
        let dot = waiting ? self.colors.waitingMark : accent
        HStack(spacing: 7) {
            Circle()
                .fill(dot)
                .frame(width: 7, height: 7)
                .shadow(color: dot.opacity(0.7), radius: 3)
            if waiting && self.row.sensitive {
                Image(systemName: "lock.fill")
                    .font(.system(size: self.size - 4, weight: .bold))
                    .foregroundStyle(self.colors.secondaryText)
                    .accessibilityLabel(HarnessgramWidgetStrings.needsFaceID)
            }
            Text(self.row.text)
                .font(.system(size: self.size, weight: waiting ? .semibold : .regular))
                .foregroundStyle(self.colors.primaryText)
                .lineLimit(1)
                .truncationMode(.tail)
                .privacySensitive(waiting)
            Spacer(minLength: 4)
            if let percent = self.row.percent {
                Text(HarnessgramWidgetStrings.percent(percent))
                    .font(.system(size: self.size, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(accent)
                    .fixedSize()
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// The small supplemental family: the Apple Watch Smart Stack, CarPlay and the Mac menu bar (iOS 18 and later; the
/// family switch below reads `activityFamily`). Built to be read at watch size: the tower and a short title on top,
/// "שלב X/Y" with the step's name, and on the left a progress ring that fills counter-clockwise (right to left, like
/// the bar on the lock screen) with the percent inside. It sits on the system's own tile, light or dark like the
/// widgets around it, so its colours follow the appearance (HarnessgramTaskActivityPalette.smallLight / smallDark,
/// both AA). The overflow summary shows "+N" in the ring's place.
@available(iOS 17.0, *)
public struct HarnessgramTaskSmallView: View {
    let state: HarnessgramTaskState
    @Environment(\.colorScheme) private var colorScheme

    public init(state: HarnessgramTaskState) {
        self.state = state
    }

    public var body: some View {
        let palette = HarnessgramTaskActivityPalette.small(dark: self.colorScheme == .dark)
        let accent = Color(self.state.finished ? palette.approve : palette.accent)
        HStack(alignment: .center, spacing: HarnessgramTaskActivityLayout.gap) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    HarnessgramTowerGlyph(color: accent)
                        .frame(height: 13)
                    Text(self.state.title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color(palette.primaryText))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                if self.state.overflowCount != nil {
                    Text(HarnessgramWidgetStrings.moreTasksBadge)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color(palette.secondaryText))
                        .lineLimit(1)
                } else if let short = self.state.stepShort {
                    Text(short)
                        .font(.system(size: 13, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Color(palette.primaryText))
                        .lineLimit(1)
                    if let current = self.state.currentStep {
                        Text(current)
                            .font(.system(size: 12))
                            .foregroundStyle(Color(palette.secondaryText))
                            .lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let overflow = self.state.overflowCount {
                Text("+\(overflow)")
                    .font(.system(size: 16, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(accent)
                    .frame(width: 40, height: 40)
                    .background(Circle().strokeBorder(accent.opacity(0.6), lineWidth: 2))
            } else {
                HarnessgramSmallRing(fraction: self.state.fraction, finished: self.state.finished, palette: palette)
                    .frame(width: 40, height: 40)
            }
        }
        .padding(HarnessgramTaskActivityLayout.inner)
        .environment(\.layoutDirection, .rightToLeft)
    }
}

/// The small family's ring: fills from the top counter-clockwise (right to left), the percent inside, a check when
/// the task landed.
@available(iOS 17.0, *)
struct HarnessgramSmallRing: View {
    let fraction: Double
    let finished: Bool
    let palette: HarnessgramTaskActivityPalette

    var body: some View {
        let accent = Color(self.finished ? self.palette.approve : self.palette.accent)
        let share = min(1, max(0, self.fraction))
        ZStack {
            Circle()
                .stroke(Color(self.palette.track), lineWidth: 4)
            Circle()
                .trim(from: 0, to: max(0.02, share))
                .stroke(accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                // Mirrored: the arc grows from 12 o'clock toward the left, as Hebrew reads.
                .scaleEffect(x: -1, y: 1)
            if self.finished {
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(accent)
            } else {
                Text(HarnessgramWidgetStrings.percent(Int((share * 100).rounded())))
                    .font(.system(size: 11, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(Color(self.palette.primaryText))
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                    .padding(4)
            }
        }
        .padding(2)
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityElement()
        .accessibilityLabel(HarnessgramWidgetStrings.percent(Int((share * 100).rounded())))
    }
}

#if canImport(ActivityKit)
/// The banner content for every host. iOS 18 and later: the small family (CarPlay, Smart Stack) gets the light/dark
/// system tile. The medium family uses the lock screen layout. iOS 17 has only the lock screen.
@available(iOS 17.0, *)
struct HarnessgramTaskActivityContent: View {
    let state: HarnessgramTaskState
    var isStale: Bool = false

    var body: some View {
        if #available(iOS 18.0, *) {
            HarnessgramTaskFamilyContent(state: self.state, isStale: self.isStale)
        } else {
            HarnessgramTaskLockScreenBanner(state: self.state, isStale: self.isStale)
        }
    }
}

/// Let ActivityKit choose the surface and dismiss button in both stack presentations.
/// Build 31 painted over the system surface with a palette selected by the content's `colorScheme`. That value
/// can describe the Lock Screen rendering context instead of the device appearance (Apple FB20187110).
/// https://developer.apple.com/documentation/activitykit/creating-custom-views-for-live-activities
/// https://developer.apple.com/forums/thread/799684
@available(iOS 17.0, *)
struct HarnessgramTaskLockScreenBanner: View {
    let state: HarnessgramTaskState
    let isStale: Bool

    var body: some View {
        HarnessgramTaskLockScreenView(state: self.state, isStale: self.isStale)
            .activityBackgroundTint(nil)
    }
}

@available(iOS 18.0, *)
struct HarnessgramTaskFamilyContent: View {
    let state: HarnessgramTaskState
    let isStale: Bool
    @Environment(\.activityFamily) private var activityFamily

    var body: some View {
        switch self.activityFamily {
        case .small:
            // Apple Watch Smart Stack, CarPlay, the Mac menu bar: the system tile (nil tint), like the widgets around it.
            HarnessgramTaskSmallView(state: self.state)
                .activityBackgroundTint(nil)
        default:
            HarnessgramTaskLockScreenBanner(state: self.state, isStale: self.isStale)
        }
    }
}

/// The agent task Live Activity: lock screen banner and Dynamic Island. Started and updated by the app
/// (HarnessgramCockpitSync) while it runs; a bridge push can update it later with the same state.
@available(iOS 17.0, *)
public struct HarnessgramTaskLiveActivityWidget: Widget {
    public init() {
    }

    public var body: some WidgetConfiguration {
        harnessgramTaskActivityConfiguration()
    }
}

/// iOS 18 and later: the same activity, also offered to CarPlay and the Apple Watch Smart Stack (the small family;
/// medium is the lock screen). The extension's entry point picks this bundle on iOS 18 (one activity configuration
/// per attributes type, never both).
@available(iOS 18.0, *)
public struct HarnessgramTaskLiveActivityWidgetWithSupplementalFamilies: Widget {
    public init() {
    }

    public var body: some WidgetConfiguration {
        harnessgramTaskActivityConfiguration()
            .supplementalActivityFamilies([.small, .medium])
    }
}

@available(iOS 17.0, *)
@MainActor
private func harnessgramTaskActivityConfiguration() -> some WidgetConfiguration {
    return ActivityConfiguration(for: HarnessgramTaskActivityAttributes.self) { context in
        HarnessgramTaskActivityContent(state: context.state, isStale: context.isStale)
            .widgetURL(context.attributes.cardId.hasPrefix(HarnessgramSampleStore.activityIDPrefix) ? HarnessgramSampleStore.openURL : HarnessgramCockpitLinks.openURL)
    } dynamicIsland: { context in
        // The island is always black; the standard palette passes AA on black too.
        let palette = HarnessgramTaskActivityPalette.standard
        let colors = HarnessgramTaskActivityColors(instruments: palette)
        let state = context.state
        let accent = Color(state.finished ? palette.approve : palette.accent)
        return DynamicIsland {
            DynamicIslandExpandedRegion(.leading) {
                HStack(spacing: 6) {
                    HarnessgramTowerGlyph(color: accent)
                        .frame(height: 16)
                    Text(HarnessgramWidgetStrings.brandName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color(palette.primaryText))
                        .lineLimit(1)
                        .fixedSize()
                }
                .padding(.leading, HarnessgramTaskActivityLayout.gap)
                .padding(.top, HarnessgramTaskActivityLayout.compactInner)
            }
            DynamicIslandExpandedRegion(.trailing) {
                let pill = HarnessgramTaskSummaryPill(state: state)
                HarnessgramStatusPill(
                    text: state.overflowCount == nil ? state.badge(isStale: context.isStale) : pill.text,
                    systemImage: state.overflowCount != nil ? pill.systemImage : (state.finished ? "checkmark" : "dot.radiowaves.left.and.right"),
                    color: state.overflowCount != nil && pill.waiting ? Color(HarnessgramTaskActivityPalette.horizonGlow) : accent,
                    textColor: Color(palette.primaryText)
                )
                .padding(.trailing, HarnessgramTaskActivityLayout.gap)
                .padding(.top, HarnessgramTaskActivityLayout.compactInner)
            }
            DynamicIslandExpandedRegion(.bottom) {
                Group {
                    if state.overflowCount != nil {
                        HarnessgramTaskSummaryBody(state: state, colors: colors, rowSize: 13)
                    } else {
                        HStack(alignment: .center, spacing: 14) {
                            HarnessgramTaskTextColumn(state: state, colors: colors, titleSize: 16, showsBar: true, glows: true, showsPercent: false)
                            HarnessgramAltimeterDial(fraction: state.fraction, finished: state.finished, palette: palette)
                                .frame(width: 66, height: 66)
                        }
                        .frame(height: 70)
                    }
                }
                .environment(\.layoutDirection, .rightToLeft)
                .padding(.top, HarnessgramTaskActivityLayout.gap)
                .padding(.horizontal, HarnessgramTaskActivityLayout.islandCorner)
                .padding(.bottom, HarnessgramTaskActivityLayout.inner)
            }
        } compactLeading: {
            Group {
                if state.overflowCount != nil {
                    Image(systemName: "airplane")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(accent)
                } else if state.finished {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(accent)
                } else {
                    HarnessgramAltimeterDial(fraction: state.fraction, finished: false, palette: palette, detailed: false)
                        .frame(width: 18, height: 18)
                }
            }
            // Clear of the pill's rounded end (the leading region sits at the leading end in either direction).
            .padding(.leading, HarnessgramTaskActivityLayout.compactOuter)
            .padding(.trailing, HarnessgramTaskActivityLayout.compactInner)
        } compactTrailing: {
            Text(state.overflowCount.map { "+\($0)" } ?? HarnessgramWidgetStrings.percent(state.percentShown))
                .font(.system(size: 14, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(accent)
                .padding(.leading, HarnessgramTaskActivityLayout.compactInner)
                .padding(.trailing, HarnessgramTaskActivityLayout.compactOuter)
        } minimal: {
            Group {
                if state.overflowCount != nil {
                    Image(systemName: "airplane")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(accent)
                } else {
                    HarnessgramTaskRing(fraction: state.fraction, finished: state.finished, palette: palette)
                }
            }
            .padding(HarnessgramTaskActivityLayout.minimalInset)
        }
        .contentMargins(.horizontal, HarnessgramTaskActivityLayout.outer, for: .expanded)
        .widgetURL(context.attributes.cardId.hasPrefix(HarnessgramSampleStore.activityIDPrefix) ? HarnessgramSampleStore.openURL : HarnessgramCockpitLinks.openURL)
        .keylineTint(accent)
    }
    .configurationDisplayName(HarnessgramWidgetStrings.activityGalleryName)
}
#endif
