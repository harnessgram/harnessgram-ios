import Foundation
import UIKit
import SwiftUI
import HarnessgramHouseCore

/// The arch (brand kit, "Shape"): a circular arc over straight jambs. `rise` is the height of the curved part; nil, or
/// anything above half the width, is the full semicircle. The doorway card, the room niches, the window status and the
/// knock sheet's top edge (a shallow arch, `HouseTokens.Radius.knockArchRise`) all use it.
public struct ArchShape: Shape {
    public var rise: CGFloat?

    public init(rise: CGFloat? = nil) {
        self.rise = rise
    }

    public func path(in rect: CGRect) -> Path {
        var path = Path()
        guard rect.width > 0.0, rect.height > 0.0 else {
            return path
        }
        let halfWidth = rect.width / 2.0
        let rise = max(0.5, min(self.rise ?? halfWidth, halfWidth, rect.height))
        // The circle through the two shoulders and the crown.
        let radius = (halfWidth * halfWidth + rise * rise) / (2.0 * rise)
        let center = CGPoint(x: rect.midX, y: rect.minY + radius)
        let start = atan2(Double(rise - radius), Double(-halfWidth))
        let end = atan2(Double(rise - radius), Double(halfWidth))
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + rise))
        // SwiftUI measures "clockwise" in the unflipped plane: false is clockwise on screen, over the crown.
        path.addArc(center: center, radius: radius, startAngle: .radians(start), endAngle: .radians(end), clockwise: false)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// A room's window (20 pt in a row, 44 pt on a widget): lit with a soft amber glow, dim, or amber while something
/// waits. The state is never shown by colour alone: a lit window also glows, a waiting one carries a small dot, and
/// the accessibility label names it (the caller supplies the label from its strings).
public struct WindowStatusView: View {
    public let state: HouseRoomState
    public let accessibilityText: String
    @Environment(\.colorScheme) private var colorScheme

    public init(state: HouseRoomState, accessibilityText: String) {
        self.state = state
        self.accessibilityText = accessibilityText
    }

    public var body: some View {
        let palette = HouseTokens.colors(darkAppearance: self.colorScheme == .dark)
        let fill: HouseColor
        switch self.state {
        case .lit:
            fill = palette.statusWorking
        case .waiting:
            fill = palette.statusWaiting
        case .dim:
            fill = palette.statusIdle
        }
        return ZStack {
            ArchShape()
                .fill(fill.color)
                .shadow(color: self.state == .dim ? .clear : palette.amberGlow.color.opacity(self.colorScheme == .dark ? 0.45 : 0.35), radius: 4.0)
            ArchShape()
                .stroke(palette.borderStrong.color, lineWidth: 1.0)
        }
        .aspectRatio(HouseTokens.Radius.windowAspect, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel(self.accessibilityText)
    }
}

/// The progress ruler: a thin track that fills from the starting edge (the right edge in Hebrew), 500 ms ease-out.
public struct ProgressRuler: View {
    public let fraction: Double
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(fraction: Double) {
        self.fraction = min(1.0, max(0.0, fraction.isFinite ? fraction : 0.0))
    }

    public var body: some View {
        let palette = HouseTokens.colors(darkAppearance: self.colorScheme == .dark)
        return GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(palette.border.color)
                Capsule()
                    .fill(palette.amber.color)
                    .frame(width: proxy.size.width * CGFloat(self.fraction))
                    .animation(self.reduceMotion ? .easeInOut(duration: HouseTokens.Motion.reduceMotionFade) : .easeOut(duration: HouseTokens.Motion.progressFill), value: self.fraction)
            }
        }
        .frame(height: 6.0)
        .accessibilityElement()
        .accessibilityValue(Text(self.fraction, format: .percent.precision(.fractionLength(0))))
    }
}

/// The waiting count on its amber-deep lantern badge (Rubik, tabular figures).
public struct LanternBadge: View {
    public let count: Int
    @Environment(\.colorScheme) private var colorScheme

    public init(count: Int) {
        self.count = count
    }

    public var body: some View {
        let palette = HouseTokens.colors(darkAppearance: self.colorScheme == .dark)
        return Text(self.count, format: .number.locale(Locale(identifier: "he_IL")))
            .houseFont(.badge)
            .foregroundColor(palette.onAmberDeep.color)
            .padding(.horizontal, HouseTokens.Space.sm)
            .frame(minWidth: HouseTokens.Space.xxl, minHeight: HouseTokens.Space.xxl)
            .background(Capsule().fill(palette.amberDeep.color))
    }
}

/// The primary (olive) or secondary (outlined) House button; 44 pt tall at least.
public struct HouseButtonStyle: ButtonStyle {
    public enum Kind {
        case olive
        case outline
    }

    public let kind: Kind

    public init(_ kind: Kind = .olive) {
        self.kind = kind
    }

    public func makeBody(configuration: Configuration) -> some View {
        return HouseButtonBody(kind: self.kind, configuration: configuration)
    }
}

private struct HouseButtonBody: View {
    let kind: HouseButtonStyle.Kind
    let configuration: ButtonStyleConfiguration
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = HouseTokens.colors(darkAppearance: self.colorScheme == .dark)
        let shape = RoundedRectangle(cornerRadius: HouseTokens.Radius.button, style: .continuous)
        return self.configuration.label
            .houseFont(.button)
            .foregroundColor(self.kind == .olive ? palette.onOlive.color : palette.olive.color)
            .frame(maxWidth: .infinity, minHeight: HouseTokens.Space.minTapTarget)
            .padding(.horizontal, HouseTokens.Space.lg)
            .background(shape.fill(self.kind == .olive ? (self.configuration.isPressed ? palette.oliveDeep.color : palette.olive.color) : Color.clear))
            .overlay(shape.stroke(self.kind == .outline ? palette.olive.color : Color.clear, lineWidth: 1.0))
            .contentShape(shape)
    }
}

/// A House card: surface colour, 20 pt corners, 14 pt padding; a hairline in the night theme and a soft shadow in the
/// stone theme (tokens.json, "shadow").
public struct HouseCard<Content: View>: View {
    private let content: Content
    @Environment(\.colorScheme) private var colorScheme

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        let dark = self.colorScheme == .dark
        let palette = HouseTokens.colors(darkAppearance: dark)
        let shape = RoundedRectangle(cornerRadius: HouseTokens.Radius.card, style: .continuous)
        return self.content
            .padding(HouseTokens.Space.cardPadding)
            .background(shape.fill(palette.surface.color))
            .overlay(shape.stroke(dark ? palette.border.color : Color.clear, lineWidth: 1.0))
            .shadow(color: dark ? .clear : Color(red: 60.0 / 255.0, green: 40.0 / 255.0, blue: 20.0 / 255.0).opacity(0.10), radius: 8.0, x: 0.0, y: 3.0)
    }
}
