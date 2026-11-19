import Foundation
import UIKit
import SwiftUI
import HarnessgramCockpitKit

/// The wide and phone Cockpit's instruments ("מגדל פיקוח"), drawn in SwiftUI: the night sky (dark appearance, the lock
/// screen pack's flight deck colours) or the day sky (light appearance) behind the tower, the glass cards, the
/// right-to-left progress bar, the altimeter tape and the radar. Every colour comes from HouseTowerPalette.

/// The sky behind the tower (night or day, with the appearance): the sky colour at the top, the page colour below and
/// a low glow on the horizon.
struct HouseTowerBackground: View {
    var body: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(colors: [HouseTowerPalette.skyTop, HouseTowerPalette.background], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [HouseTowerPalette.horizonGlow.opacity(0.10), .clear], center: .bottom, startRadius: 0, endRadius: 420)
        }
        .accessibilityHidden(true)
    }
}

/// A frosted glass card: padding 14, a soft sky fill and a hairline edge; a selected card glows mint.
struct HouseTowerCard: ViewModifier {
    var selected = false
    var padding: CGFloat = 14.0

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 16.0, style: .continuous)
        content
            .padding(self.padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                shape.fill(LinearGradient(colors: [HouseTowerPalette.skyTop.opacity(self.selected ? 1.0 : 0.85), HouseTowerPalette.background.opacity(0.9)], startPoint: .top, endPoint: .bottom))
            )
            .overlay(shape.stroke(self.selected ? HouseTowerPalette.accent : HouseTowerPalette.glassEdge.opacity(0.18), lineWidth: self.selected ? 1.6 : 1.0))
            .shadow(color: self.selected ? HouseTowerPalette.accent.opacity(0.35) : .clear, radius: 10)
    }
}

extension View {
    func houseTowerCard(selected: Bool = false, padding: CGFloat = 14.0) -> some View {
        return self.modifier(HouseTowerCard(selected: selected, padding: padding))
    }
}

/// The control tower glyph (the same drawing as the lock screen's): antenna, cab with its window band, shaft, footing.
struct HouseTowerShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            return CGPoint(x: rect.minX + x * w, y: rect.minY + y * h)
        }
        var path = Path()
        path.addRect(CGRect(origin: p(0.47, 0.0), size: CGSize(width: w * 0.06, height: h * 0.12)))
        path.move(to: p(0.22, 0.17))
        path.addLine(to: p(0.78, 0.17))
        path.addLine(to: p(0.70, 0.11))
        path.addLine(to: p(0.30, 0.11))
        path.closeSubpath()
        path.move(to: p(0.08, 0.20))
        path.addLine(to: p(0.92, 0.20))
        path.addLine(to: p(0.82, 0.24))
        path.addLine(to: p(0.18, 0.24))
        path.closeSubpath()
        path.move(to: p(0.18, 0.36))
        path.addLine(to: p(0.82, 0.36))
        path.addLine(to: p(0.74, 0.44))
        path.addLine(to: p(0.26, 0.44))
        path.closeSubpath()
        for x in [0.24, 0.40, 0.56, 0.72] as [CGFloat] {
            path.addRect(CGRect(origin: p(x, 0.24), size: CGSize(width: w * 0.04, height: h * 0.12)))
        }
        path.move(to: p(0.36, 0.44))
        path.addLine(to: p(0.64, 0.44))
        path.addLine(to: p(0.68, 0.90))
        path.addLine(to: p(0.32, 0.90))
        path.closeSubpath()
        path.addRoundedRect(in: CGRect(origin: p(0.16, 0.90), size: CGSize(width: w * 0.68, height: h * 0.10)), cornerSize: CGSize(width: w * 0.04, height: w * 0.04))
        return path
    }
}

/// The tower glyph in its mint tile (the header's badge).
struct HouseTowerBadge: View {
    var size: CGFloat = 44.0

    var body: some View {
        RoundedRectangle(cornerRadius: self.size * 0.28, style: .continuous)
            .fill(HouseTowerPalette.skyTop)
            .overlay(RoundedRectangle(cornerRadius: self.size * 0.28, style: .continuous).stroke(HouseTowerPalette.accent.opacity(0.55), lineWidth: 1.0))
            .overlay(
                HouseTowerShape()
                    .fill(HouseTowerPalette.accent)
                    .aspectRatio(0.78, contentMode: .fit)
                    .padding(self.size * 0.2)
            )
            .frame(width: self.size, height: self.size)
            .accessibilityHidden(true)
    }
}

/// The progress bar, filling from the start edge (the right in Hebrew), mint while flying and green once landed.
struct HouseTowerBar: View {
    let fraction: Double
    let finished: Bool
    var height: CGFloat = 8.0

    var body: some View {
        GeometryReader { proxy in
            let value = CGFloat(min(max(self.fraction.isFinite ? self.fraction : 0.0, 0.0), 1.0))
            ZStack(alignment: .leading) {
                Capsule().fill(HouseTowerPalette.track)
                Capsule()
                    .fill(self.finished ? HouseTowerPalette.approve : HouseTowerPalette.accent)
                    .frame(width: max(value > 0 ? self.height : 0.0, proxy.size.width * value))
                    .shadow(color: (self.finished ? HouseTowerPalette.approve : HouseTowerPalette.accent).opacity(0.5), radius: 4)
            }
        }
        .frame(height: self.height)
        .accessibilityHidden(true)
    }
}

/// The task's altimeter tape: the progress drawn as a climb to cruise altitude (HarnessgramAltimeter, the same rule
/// as the lock screen card), the scale fading at both ends and the readout box at the middle.
struct HouseTowerAltimeterTape: View {
    let fraction: Double
    let finished: Bool

    var body: some View {
        let altitude = HarnessgramAltimeter.altitude(fraction: self.fraction)
        let ticks = HarnessgramAltimeter.ticks(around: altitude)
        let accent = self.finished ? HouseTowerPalette.approve : HouseTowerPalette.accent
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            let mid = h / 2
            let scaleX: CGFloat = 10
            ZStack(alignment: .topLeading) {
                ZStack(alignment: .topLeading) {
                    Path { path in
                        path.move(to: CGPoint(x: scaleX, y: 0))
                        path.addLine(to: CGPoint(x: scaleX, y: h))
                        for tick in ticks {
                            let y = mid - CGFloat(tick.offset) * mid
                            path.move(to: CGPoint(x: scaleX, y: y))
                            path.addLine(to: CGPoint(x: scaleX + (tick.major ? 14 : 7), y: y))
                        }
                    }
                    .stroke(HouseTowerPalette.secondaryText.opacity(0.75), lineWidth: 1)
                    ForEach(ticks.filter { $0.major && abs($0.offset) > 0.18 }, id: \.value) { tick in
                        Text(HarnessgramAltimeter.label(tick.value))
                            .font(.system(size: 12, weight: .medium).monospacedDigit())
                            .foregroundColor(HouseTowerPalette.secondaryText)
                            .fixedSize()
                            .position(x: scaleX + 20 + (w - scaleX - 20) / 2, y: mid - CGFloat(tick.offset) * mid)
                    }
                }
                .frame(width: w, height: h)
                .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.18), .init(color: .black, location: 0.82), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(HouseTowerPalette.background.opacity(0.95))
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(accent, lineWidth: 1.4))
                    .frame(width: w - 4, height: 28)
                    .position(x: w / 2 + 2, y: mid)
                    .shadow(color: accent.opacity(0.4), radius: 5)
                Group {
                    if self.finished {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .heavy))
                    } else {
                        Text(HarnessgramAltimeter.label(altitude))
                            .font(.system(size: 15, weight: .bold, design: .rounded).monospacedDigit())
                            .minimumScaleFactor(0.7)
                            .lineLimit(1)
                    }
                }
                .foregroundColor(HouseTowerPalette.primaryText)
                .frame(width: w - 12, height: 28)
                .position(x: w / 2 + 2, y: mid)
            }
        }
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityElement()
        .accessibilityLabel(Text(HarnessgramWidgetStrings.altitude(HarnessgramAltimeter.label(altitude))))
    }
}

/// A wedge from the centre: the radar sweep's trail.
private struct HouseTowerSweepShape: Shape {
    let bearing: Double
    let width: Double

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        var path = Path()
        path.move(to: center)
        path.addArc(center: center, radius: radius, startAngle: .degrees(self.bearing - self.width - 90), endAngle: .degrees(self.bearing - 90), clockwise: false)
        path.closeSubpath()
        return path
    }
}

/// The tower radar: range rings, crosshair, the sweep and a mint blip per agent at work and a ringed amber blip per
/// decision waiting (HarnessgramTowerSummary's fixed bearings, the lock screen's picture).
struct HouseTowerRadar: View {
    let summary: HarnessgramTowerSummary?
    let sweep: Double

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let radius = side / 2
            ZStack {
                Circle().fill(HouseTowerPalette.background.opacity(0.6))
                ForEach([1.0, 0.66, 0.33], id: \.self) { ring in
                    Circle()
                        .stroke(HouseTowerPalette.accent.opacity(ring == 1.0 ? 0.55 : 0.28), lineWidth: ring == 1.0 ? 1.4 : 0.9)
                        .frame(width: side * ring, height: side * ring)
                }
                Path { path in
                    path.move(to: CGPoint(x: radius, y: 0))
                    path.addLine(to: CGPoint(x: radius, y: side))
                    path.move(to: CGPoint(x: 0, y: radius))
                    path.addLine(to: CGPoint(x: side, y: radius))
                }
                .stroke(HouseTowerPalette.accent.opacity(0.22), lineWidth: 0.8)
                ForEach(0 ..< 8, id: \.self) { step in
                    HouseTowerSweepShape(bearing: self.sweep - Double(step) * 9, width: 9)
                        .fill(HouseTowerPalette.accent.opacity(0.38 * (1.0 - Double(step) / 8.0)))
                }
                Path { path in
                    let angle = (self.sweep - 90) * .pi / 180
                    path.move(to: CGPoint(x: radius, y: radius))
                    path.addLine(to: CGPoint(x: radius + cos(angle) * radius, y: radius + sin(angle) * radius))
                }
                .stroke(HouseTowerPalette.accent.opacity(0.95), lineWidth: 1.4)
                ForEach(Array((self.summary?.blips ?? []).enumerated()), id: \.offset) { _, blip in
                    let angle = (blip.bearing - 90) * .pi / 180
                    let distance = blip.distance * radius * 0.92
                    Group {
                        if blip.waiting {
                            ZStack {
                                Circle().stroke(HouseTowerPalette.horizonGlow, lineWidth: 1.4).frame(width: side * 0.12, height: side * 0.12)
                                Circle().fill(HouseTowerPalette.horizonGlow).frame(width: side * 0.05, height: side * 0.05)
                            }
                        } else {
                            Circle()
                                .fill(HouseTowerPalette.accent)
                                .frame(width: side * 0.06, height: side * 0.06)
                                .shadow(color: HouseTowerPalette.accent.opacity(0.8), radius: 4)
                        }
                    }
                    .position(x: radius + cos(angle) * distance, y: radius + sin(angle) * distance)
                }
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityHidden(true)
    }
}

/// The airplane symbols point toward the reading direction (to the left in Hebrew), never against it.
struct HouseTowerPlane: View {
    let finished: Bool
    var color: Color = HouseTowerPalette.accent

    var body: some View {
        Image(systemName: self.finished ? "airplane.arrival" : "airplane")
            .flipsForRightToLeftLayoutDirection(true)
            .foregroundColor(self.finished ? HouseTowerPalette.approve : self.color)
            .accessibilityHidden(true)
    }
}

/// The tower pages' scroll view. Snapshot renders draw the content as it is (ImageRenderer draws no scroll view
/// content), with the page below it.
struct HouseTowerScroll<Content: View>: View {
    var scrolls: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        if self.scrolls {
            ScrollView {
                self.content()
            }
        } else {
            VStack(spacing: 0) {
                self.content()
                Spacer(minLength: 0)
            }
        }
    }
}
