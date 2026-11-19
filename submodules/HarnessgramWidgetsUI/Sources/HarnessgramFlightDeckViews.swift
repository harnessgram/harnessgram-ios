import Foundation
import SwiftUI
import WidgetKit
import HarnessgramCockpitKit

/// The lock screen pack's instruments, drawn in SwiftUI (no images: widget memory is tight and every shape stays
/// sharp at any size). The tower glyph, the "active task" badge, the glass card, the right-to-left progress bar, the
/// altimeter tape and dial, the radar scope and the runway lights.

// MARK: Tower glyph

/// The control tower: antenna, a cab wider at the top with its window band, the shaft and a footing.
struct HarnessgramTowerShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let x0 = rect.minX
        let y0 = rect.minY
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            return CGPoint(x: x0 + x * w, y: y0 + y * h)
        }
        var path = Path()
        // Antenna.
        path.addRect(CGRect(origin: p(0.47, 0.0), size: CGSize(width: w * 0.06, height: h * 0.12)))
        // Roof.
        path.move(to: p(0.22, 0.17))
        path.addLine(to: p(0.78, 0.17))
        path.addLine(to: p(0.70, 0.11))
        path.addLine(to: p(0.30, 0.11))
        path.closeSubpath()
        // Cab: wider at the top, its window band cut out below.
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
        // Window mullions between the two cab bands.
        for x in [0.24, 0.40, 0.56, 0.72] as [CGFloat] {
            path.addRect(CGRect(origin: p(x, 0.24), size: CGSize(width: w * 0.04, height: h * 0.12)))
        }
        // Shaft, slightly tapered.
        path.move(to: p(0.36, 0.44))
        path.addLine(to: p(0.64, 0.44))
        path.addLine(to: p(0.68, 0.90))
        path.addLine(to: p(0.32, 0.90))
        path.closeSubpath()
        // Footing.
        path.addRoundedRect(in: CGRect(origin: p(0.16, 0.90), size: CGSize(width: w * 0.68, height: h * 0.10)), cornerSize: CGSize(width: w * 0.04, height: w * 0.04))
        return path
    }
}

@available(iOS 17.0, *)
struct HarnessgramTowerGlyph: View {
    var color: Color

    var body: some View {
        HarnessgramTowerShape()
            .fill(self.color)
            .aspectRatio(0.78, contentMode: .fit)
            .accessibilityHidden(true)
    }
}

// MARK: Badge

/// "משימה פעילה" with the live signal, in a hairline glass capsule.
@available(iOS 17.0, *)
struct HarnessgramStatusPill: View {
    let text: String
    let systemImage: String
    let color: Color
    let textColor: Color

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: self.systemImage)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(self.color)
            Text(self.text)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(self.textColor)
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.06))
                .overlay(Capsule().strokeBorder(self.color.opacity(0.45), lineWidth: 1))
        )
    }
}

// MARK: Progress bar

/// The progress bar, filling from the right (it reads right to left with the layout): a mint fill brightening toward
/// its head, a soft glow and a bright head mark. Drawn, so it renders in every host.
@available(iOS 17.0, *)
struct HarnessgramTaskBar: View {
    let fraction: Double
    let finished: Bool
    let palette: HarnessgramTaskActivityPalette
    var height: CGFloat = 6
    var glows: Bool = false

    var body: some View {
        let fill = Color(self.finished ? self.palette.approve : self.palette.accent)
        let share = min(1, max(0, self.fraction))
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(self.palette.track))
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [fill.opacity(self.palette.fillTailOpacity), fill],
                            // The fill grows from the right in this RTL layout, so its head is its left end.
                            startPoint: .trailing,
                            endPoint: .leading
                        )
                    )
                    .frame(width: max(self.height, proxy.size.width * share))
                    .shadow(color: self.glows ? fill.opacity(0.55) : .clear, radius: self.glows ? 5 : 0)
            }
        }
        .frame(height: self.height)
        .environment(\.layoutDirection, .rightToLeft)
        .accessibilityElement()
        .accessibilityLabel(HarnessgramWidgetStrings.percent(Int((share * 100).rounded())))
    }
}

// MARK: Altimeter tape

/// The vertical altimeter tape: ticks every 250 ft, labels every 1,000 ft, the readout box in the middle with its
/// pointer, fading out at the top and bottom like a real tape window. The value follows the task's progress
/// (HarnessgramAltimeter). Drawn left to right whatever the layout direction, as an instrument is.
@available(iOS 17.0, *)
struct HarnessgramAltimeterTape: View {
    let fraction: Double
    let finished: Bool
    let colors: HarnessgramTaskActivityColors

    var body: some View {
        let altitude = HarnessgramAltimeter.altitude(fraction: self.fraction)
        let ticks = HarnessgramAltimeter.ticks(around: altitude)
        let palette = self.colors.instruments
        let accent = Color(self.finished ? palette.approve : palette.accent)
        let scale = self.colors.secondaryText
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            let mid = h / 2
            let scaleX: CGFloat = 9
            ZStack(alignment: .topLeading) {
                // The scale (spine, ticks, labels), fading out at the top and bottom of the window.
                ZStack(alignment: .topLeading) {
                    Path { path in
                        path.move(to: CGPoint(x: scaleX, y: 0))
                        path.addLine(to: CGPoint(x: scaleX, y: h))
                        for tick in ticks {
                            let y = mid - CGFloat(tick.offset) * mid
                            path.move(to: CGPoint(x: scaleX, y: y))
                            path.addLine(to: CGPoint(x: scaleX + (tick.major ? 11 : 6), y: y))
                        }
                    }
                    .stroke(scale.opacity(0.75), lineWidth: 1)
                    ForEach(ticks.filter { $0.major && abs($0.offset) > 0.2 }, id: \.value) { tick in
                        Text(HarnessgramAltimeter.label(tick.value))
                            .font(.system(size: 10, weight: .medium).monospacedDigit())
                            .foregroundStyle(scale)
                            .fixedSize()
                            .position(x: scaleX + 16 + (w - scaleX - 16) / 2, y: mid - CGFloat(tick.offset) * mid)
                    }
                }
                .frame(width: w, height: h)
                .mask(
                    LinearGradient(
                        stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.2), .init(color: .black, location: 0.8), .init(color: .clear, location: 1)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                // Keep the readout and its text paired over either system surface.
                HarnessgramReadoutShape(pointer: 7)
                    .fill(Color(palette.background))
                    // The adaptive edge keeps 3:1 on a light or dark system surface; the mint line sits inside it.
                    .overlay(HarnessgramReadoutShape(pointer: 7).stroke(scale, lineWidth: 2.2))
                    .overlay(HarnessgramReadoutShape(pointer: 7).stroke(accent, lineWidth: 1.0))
                    .frame(width: w - 1, height: 22)
                    .position(x: (w - 1) / 2 + 0.5, y: mid)
                    .shadow(color: accent.opacity(0.35), radius: 4)
                Group {
                    if self.finished {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .heavy))
                    } else {
                        Text(HarnessgramAltimeter.label(altitude))
                            .font(.system(size: 13, weight: .bold, design: .rounded).monospacedDigit())
                            .minimumScaleFactor(0.7)
                            .lineLimit(1)
                    }
                }
                .foregroundStyle(Color(palette.primaryText))
                .frame(width: w - 16, height: 22)
                .position(x: 8 + (w - 8) / 2, y: mid)
            }
        }
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityElement()
        .accessibilityLabel(HarnessgramWidgetStrings.altitude(HarnessgramAltimeter.label(altitude)))
    }
}

/// The altimeter readout: a rounded box with a pointer on its left side (toward the scale).
struct HarnessgramReadoutShape: Shape {
    let pointer: CGFloat

    func path(in rect: CGRect) -> Path {
        let r: CGFloat = 5
        let left = rect.minX + self.pointer
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: left, y: rect.midY - self.pointer * 0.8))
        path.addLine(to: CGPoint(x: left, y: rect.minY + r))
        path.addQuadCurve(to: CGPoint(x: left + r, y: rect.minY), control: CGPoint(x: left, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + r), control: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - r, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: left + r, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: left, y: rect.maxY - r), control: CGPoint(x: left, y: rect.maxY))
        path.addLine(to: CGPoint(x: left, y: rect.midY + self.pointer * 0.8))
        path.closeSubpath()
        return path
    }
}

// MARK: Altimeter dial

/// The round altimeter for the Dynamic Island: a 270° scale with ticks, the progress arc, the needle and, when
/// large enough, the percent under the hub. The compact island draws the same dial without ticks or text.
@available(iOS 17.0, *)
struct HarnessgramAltimeterDial: View {
    let fraction: Double
    let finished: Bool
    let palette: HarnessgramTaskActivityPalette
    var detailed: Bool = true

    var body: some View {
        let accent = Color(self.finished ? self.palette.approve : self.palette.accent)
        let share = min(1, max(0, self.fraction))
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let line = max(1.5, side * (self.detailed ? 0.045 : 0.11))
            ZStack {
                if self.detailed {
                    Circle()
                        .fill(Color(self.palette.background))
                    Circle()
                        .strokeBorder(Color(self.palette.track), lineWidth: 1)
                    // Ticks: 28 around the 270° scale, every 4th longer.
                    ForEach(0 ..< 28, id: \.self) { index in
                        let major = index % 4 == 0
                        Capsule()
                            .fill(Color(self.palette.secondaryText).opacity(major ? 0.85 : 0.4))
                            .frame(width: major ? 1.6 : 1, height: side * (major ? 0.09 : 0.055))
                            .offset(y: -side * 0.39)
                            .rotationEffect(.degrees(-135 + 270 * Double(index) / 27))
                    }
                }
                Circle()
                    .trim(from: 0.125, to: 0.875)
                    .stroke(Color(self.palette.track), style: StrokeStyle(lineWidth: line, lineCap: .round))
                    .rotationEffect(.degrees(90))
                    .padding(self.detailed ? side * 0.16 : line / 2)
                Circle()
                    .trim(from: 0.125, to: 0.125 + 0.75 * max(0.02, share))
                    .stroke(accent, style: StrokeStyle(lineWidth: line, lineCap: .round))
                    .rotationEffect(.degrees(90))
                    .padding(self.detailed ? side * 0.16 : line / 2)
                    .shadow(color: self.detailed ? accent.opacity(0.5) : .clear, radius: 3)
                // The needle.
                Capsule()
                    .fill(self.detailed ? Color(self.palette.primaryText) : accent)
                    .frame(width: max(1.4, side * (self.detailed ? 0.035 : 0.1)), height: side * (self.detailed ? 0.30 : 0.36))
                    .offset(y: -side * (self.detailed ? 0.15 : 0.16))
                    .rotationEffect(.degrees(HarnessgramAltimeter.needleDegrees(fraction: share)))
                Circle()
                    .fill(accent)
                    .frame(width: side * (self.detailed ? 0.09 : 0.2), height: side * (self.detailed ? 0.09 : 0.2))
                if self.detailed {
                    Text(HarnessgramWidgetStrings.percent(Int((share * 100).rounded())))
                        .font(.system(size: side * 0.17, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(Color(self.palette.primaryText))
                        .offset(y: side * 0.3)
                }
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityElement()
        .accessibilityLabel(HarnessgramWidgetStrings.percent(Int((share * 100).rounded())))
    }
}

/// The minimal island: the progress ring with a glowing head.
@available(iOS 17.0, *)
struct HarnessgramTaskRing: View {
    let fraction: Double
    let finished: Bool
    let palette: HarnessgramTaskActivityPalette

    var body: some View {
        let fill = Color(self.finished ? self.palette.approve : self.palette.accent)
        let share = max(0.02, min(1, self.fraction))
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let line = max(2, side * 0.14)
            ZStack {
                Circle()
                    .stroke(Color(self.palette.track), lineWidth: line)
                Circle()
                    .trim(from: 0, to: share)
                    .stroke(fill, style: StrokeStyle(lineWidth: line, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                if self.finished {
                    Image(systemName: "checkmark")
                        .font(.system(size: side * 0.42, weight: .heavy))
                        .foregroundStyle(fill)
                } else {
                    Circle()
                        .fill(fill)
                        .frame(width: side * 0.3, height: side * 0.3)
                        .shadow(color: fill.opacity(0.8), radius: 2)
                }
            }
            .padding(line / 2)
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityElement()
        .accessibilityLabel(HarnessgramWidgetStrings.percent(Int((min(1, max(0, self.fraction)) * 100).rounded())))
    }
}

// MARK: Radar

/// A wedge from the centre: the radar sweep's trail.
struct HarnessgramSweepShape: Shape {
    let bearing: Double
    let width: Double

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        var path = Path()
        path.move(to: center)
        // 0° is up and bearings run clockwise; Path angles start at 3 o'clock.
        path.addArc(center: center, radius: radius, startAngle: .degrees(self.bearing - self.width - 90), endAngle: .degrees(self.bearing - 90), clockwise: false)
        path.closeSubpath()
        return path
    }
}

/// The tower radar: range rings, crosshair, the sweep and one blip per agent at work (dots) and per decision waiting
/// for the owner (ringed dots, which also stand out in the lock screen's one-colour rendering).
@available(iOS 17.0, *)
struct HarnessgramRadarScope: View {
    let summary: HarnessgramTowerSummary?
    let sweep: Double
    var gridColor: Color = .primary
    var runningColor: Color = .primary
    var waitingColor: Color = .primary

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let radius = side / 2
            ZStack {
                ForEach([1.0, 0.66, 0.33], id: \.self) { ring in
                    Circle()
                        .stroke(self.gridColor.opacity(ring == 1.0 ? 0.45 : 0.25), lineWidth: ring == 1.0 ? 1.2 : 0.8)
                        .frame(width: side * ring, height: side * ring)
                }
                Path { path in
                    path.move(to: CGPoint(x: radius, y: 0))
                    path.addLine(to: CGPoint(x: radius, y: side))
                    path.move(to: CGPoint(x: 0, y: radius))
                    path.addLine(to: CGPoint(x: side, y: radius))
                }
                .stroke(self.gridColor.opacity(0.2), lineWidth: 0.7)
                // The sweep's trail: thin wedges fading behind the beam.
                ForEach(0 ..< 7, id: \.self) { step in
                    HarnessgramSweepShape(bearing: self.sweep - Double(step) * 10, width: 10)
                        .fill(self.gridColor.opacity(0.42 * (1.0 - Double(step) / 7.0)))
                }
                // The sweep's leading edge.
                Path { path in
                    let angle = (self.sweep - 90) * .pi / 180
                    path.move(to: CGPoint(x: radius, y: radius))
                    path.addLine(to: CGPoint(x: radius + cos(angle) * radius, y: radius + sin(angle) * radius))
                }
                .stroke(self.gridColor.opacity(0.9), lineWidth: 1.2)
                ForEach(Array((self.summary?.blips ?? []).enumerated()), id: \.offset) { _, blip in
                    let angle = (blip.bearing - 90) * .pi / 180
                    let distance = blip.distance * radius * 0.92
                    Group {
                        if blip.waiting {
                            ZStack {
                                Circle().stroke(self.waitingColor, lineWidth: 1.2).frame(width: side * 0.17, height: side * 0.17)
                                Circle().fill(self.waitingColor).frame(width: side * 0.07, height: side * 0.07)
                            }
                            .widgetAccentable()
                        } else {
                            Circle().fill(self.runningColor).frame(width: side * 0.09, height: side * 0.09)
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

// MARK: Runway lights

/// A row of runway edge lights, brightest nearest the viewer (the leading end): the rectangular widget's footer.
@available(iOS 17.0, *)
struct HarnessgramRunwayLights: View {
    var count: Int = 9

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0 ..< self.count, id: \.self) { index in
                let t = Double(index) / Double(max(1, self.count - 1))
                Circle()
                    .fill(Color.primary.opacity(0.95 - 0.7 * t))
                    .frame(width: 3.2 - 1.6 * t, height: 3.2 - 1.6 * t)
                if index < self.count - 1 {
                    Spacer(minLength: 2)
                }
            }
        }
        .accessibilityHidden(true)
    }
}
