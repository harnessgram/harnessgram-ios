import Foundation
import UIKit
import SwiftUI
import HarnessgramSettings
import HarnessgramFonts
import HarnessgramHouseCore

/// Small live previews under the settings whose effect is visual (build 23, owner: "illustrate everything"). Drawn in
/// SwiftUI, no images, about 60-90 pt high, right to left, each with a VoiceOver line saying what it shows. They redraw
/// as the control changes.
enum HarnessgramPreviewStrings {
    static let sample = "בראשית ברא אלקים את השמים ואת הארץ"
    static let sampleSecond = "והארץ הייתה תהו ובהו"
    static let reply = "הבנייה הסתיימה, אפשר לבדוק"

    static let bubbleNormal = "תצוגה: בועה ברוחב רגיל"
    static let bubbleWide = "תצוגה: בועה רחבה, פחות שורות קצרות"
    static let spacingNormal = "תצוגה: שתי שורות בריווח רגיל"
    static let spacingComfortable = "תצוגה: שתי שורות בריווח נוח"
    static func font(_ name: String) -> String { return "תצוגה: הודעה בגופן " + name }
    static func theme(_ name: String) -> String { return "תצוגה: רשימת צ׳אטים ובועה בערכה " + name }
    static let houseColours = "תצוגה: צבעי הבית, אבן חמה וזית"
    static let agentButtons = "תצוגה: שורת המשך, מצב, סיכום ועצור מעל שדה הכתיבה"
    static let statusDots = "תצוגה: נושאים עם נקודה כחולה, כתומה וירוקה"
    static func floating(rightEdge: Bool) -> String { return rightEdge ? "תצוגה: הכפתור הצף בצד ימין של רשימת הצ׳אטים" : "תצוגה: הכפתור הצף בצד שמאל של רשימת הצ׳אטים" }
    static let agentButtonTitles = ["המשך", "מצב", "סיכום", "עצור"]
    static let topicWorking = "בונה את המסך"
    static let topicWaiting = "מחכה לך"
    static let topicDone = "נחת בשלום"
}

/// The frame every preview sits in: a soft card the width of the row.
private struct HarnessgramPreviewCard<Content: View>: View {
    let label: String
    let height: CGFloat
    let content: Content

    init(label: String, height: CGFloat, @ViewBuilder content: () -> Content) {
        self.label = label
        self.height = height
        self.content = content()
    }

    var body: some View {
        self.content
            .frame(maxWidth: .infinity, minHeight: self.height, maxHeight: self.height)
            .background(RoundedRectangle(cornerRadius: 12.0, style: .continuous).fill(Color(UIColor.secondarySystemFill).opacity(0.5)))
            .clipShape(RoundedRectangle(cornerRadius: 12.0, style: .continuous))
            .environment(\.layoutDirection, .rightToLeft)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(self.label))
    }
}

/// A message bubble with the sample text in the message font, weight and size.
struct HarnessgramFontPreview: View {
    let font: HarnessgramSettings.MessageFont
    let weight: HarnessgramSettings.FontWeight
    let sizeSteps: Int
    let lineSpacing: HarnessgramSettings.LineSpacing
    let name: String

    var body: some View {
        let size = 15.0 + CGFloat(self.sizeSteps) * HarnessgramSettings.textSizeStepPoints
        HarnessgramPreviewCard(label: HarnessgramPreviewStrings.font(self.name), height: 84.0) {
            HStack {
                Text(HarnessgramPreviewStrings.sample)
                    .font(Font(HarnessgramFonts.font(self.font, weight: self.weight.value, size: size)))
                    .lineSpacing(self.lineSpacing == .comfortable ? 5.0 : 1.5)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 12.0)
                    .padding(.vertical, 8.0)
                    .background(RoundedRectangle(cornerRadius: 16.0, style: .continuous).fill(Color(UIColor.systemBackground)))
                Spacer(minLength: 40.0)
            }
            .padding(.horizontal, 10.0)
        }
    }
}

/// An app-font sample line (the font page and the settings row).
struct HarnessgramAppFontSample: View {
    let font: HarnessgramSettings.AppFont
    let name: String

    var body: some View {
        HarnessgramPreviewCard(label: HarnessgramPreviewStrings.font(self.name), height: 60.0) {
            Text(HarnessgramPreviewStrings.sample)
                .font(Font(HarnessgramAppFontModel.previewFont(self.font, size: 17.0, weight: 400.0)))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 12.0)
        }
    }
}

/// The same reply in a bubble at the normal and at the wide width.
struct HarnessgramBubbleWidthPreview: View {
    let width: HarnessgramSettings.BubbleWidth

    var body: some View {
        HarnessgramPreviewCard(label: self.width == .wide ? HarnessgramPreviewStrings.bubbleWide : HarnessgramPreviewStrings.bubbleNormal, height: 76.0) {
            GeometryReader { geometry in
                let fraction: CGFloat = self.width == .wide ? 0.88 : 0.62
                HStack {
                    VStack(alignment: .leading, spacing: 5.0) {
                        ForEach(0 ..< (self.width == .wide ? 2 : 3), id: \.self) { line in
                            Capsule()
                                .fill(Color.secondary.opacity(0.45))
                                .frame(height: 6.0)
                                .frame(maxWidth: line == (self.width == .wide ? 1 : 2) ? 60.0 : .infinity, alignment: .leading)
                        }
                    }
                    .padding(10.0)
                    .frame(width: geometry.size.width * fraction, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 14.0, style: .continuous).fill(Color(UIColor.systemBackground)))
                    .animation(.easeInOut(duration: 0.2), value: self.width)
                    Spacer(minLength: 0.0)
                }
                .padding(.horizontal, 10.0)
                .frame(maxHeight: .infinity)
            }
        }
    }
}

/// Two lines of sample Hebrew at the chosen line spacing.
struct HarnessgramLineSpacingPreview: View {
    let spacing: HarnessgramSettings.LineSpacing

    var body: some View {
        HarnessgramPreviewCard(label: self.spacing == .comfortable ? HarnessgramPreviewStrings.spacingComfortable : HarnessgramPreviewStrings.spacingNormal, height: 70.0) {
            Text(HarnessgramPreviewStrings.sample + "\n" + HarnessgramPreviewStrings.sampleSecond)
                .font(.system(size: 15.0))
                .lineSpacing(self.spacing == .comfortable ? 8.0 : 1.0)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12.0)
                .animation(.easeInOut(duration: 0.2), value: self.spacing)
        }
    }
}

/// A mini chat list and a bubble in the theme's colours (Telegram's own colours for "none").
struct HarnessgramThemeSwatchPreview: View {
    let theme: HarnessgramSettings.Theme
    let name: String

    var body: some View {
        let palette = HarnessgramThemePalettes.palette(self.theme)?.palette
        let page = palette?.bg.swiftUIColor ?? Color(UIColor.systemGroupedBackground)
        let card = palette?.surface.swiftUIColor ?? Color(UIColor.secondarySystemGroupedBackground)
        let ink = palette?.ink.swiftUIColor ?? Color.primary
        let ink2 = palette?.ink3.swiftUIColor ?? Color.secondary
        let accent = palette?.olive.swiftUIColor ?? Color.accentColor
        let onAccent = palette?.onOlive.swiftUIColor ?? Color.white
        HarnessgramPreviewCard(label: HarnessgramPreviewStrings.theme(self.name), height: 86.0) {
            HStack(spacing: 8.0) {
                VStack(spacing: 6.0) {
                    ForEach(0 ..< 2, id: \.self) { _ in
                        HStack(spacing: 6.0) {
                            Circle().fill(accent.opacity(0.8)).frame(width: 18.0, height: 18.0)
                            VStack(alignment: .leading, spacing: 3.0) {
                                Capsule().fill(ink).frame(width: 54.0, height: 5.0)
                                Capsule().fill(ink2).frame(width: 74.0, height: 4.0)
                            }
                            Spacer(minLength: 0.0)
                        }
                        .padding(6.0)
                        .background(RoundedRectangle(cornerRadius: 6.0).fill(card))
                    }
                }
                .frame(maxWidth: .infinity)
                VStack(alignment: .trailing, spacing: 6.0) {
                    Text("שלום")
                        .font(.system(size: 12.0))
                        .foregroundColor(ink)
                        .padding(.horizontal, 8.0)
                        .padding(.vertical, 4.0)
                        .background(Capsule().fill(card))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("המראה!")
                        .font(.system(size: 12.0, weight: .semibold))
                        .foregroundColor(onAccent)
                        .padding(.horizontal, 8.0)
                        .padding(.vertical, 4.0)
                        .background(Capsule().fill(accent))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(8.0)
            .background(page)
        }
    }
}

/// The House's warm stone and olive.
struct HarnessgramHouseColoursPreview: View {
    let on: Bool

    var body: some View {
        let palette = HouseColors.light
        let colours: [Color] = self.on ? [palette.bg.swiftUIColor, palette.surface.swiftUIColor, palette.cedar.swiftUIColor, palette.amber.swiftUIColor, palette.olive.swiftUIColor] : [Color(UIColor.systemGroupedBackground), Color(UIColor.secondarySystemGroupedBackground), Color.blue, Color.blue.opacity(0.6), Color.accentColor]
        HarnessgramPreviewCard(label: HarnessgramPreviewStrings.houseColours, height: 60.0) {
            HStack(spacing: 8.0) {
                ForEach(0 ..< colours.count, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 8.0, style: .continuous)
                        .fill(colours[index])
                        .overlay(RoundedRectangle(cornerRadius: 8.0, style: .continuous).stroke(Color.secondary.opacity(0.25), lineWidth: 1.0))
                        .frame(width: 34.0, height: 34.0)
                }
            }
            .opacity(self.on ? 1.0 : 0.6)
        }
    }
}

/// The agent buttons row above a mini input field.
struct HarnessgramAgentButtonsPreview: View {
    let on: Bool

    var body: some View {
        HarnessgramPreviewCard(label: HarnessgramPreviewStrings.agentButtons, height: 78.0) {
            VStack(spacing: 6.0) {
                if self.on {
                    HStack(spacing: 6.0) {
                        ForEach(HarnessgramPreviewStrings.agentButtonTitles, id: \.self) { title in
                            Text(title)
                                .font(.system(size: 11.0, weight: .medium))
                                .padding(.horizontal, 8.0)
                                .padding(.vertical, 4.0)
                                .background(Capsule().fill(title == "עצור" ? Color.red.opacity(0.18) : Color.accentColor.opacity(0.18)))
                        }
                    }
                }
                HStack(spacing: 8.0) {
                    Capsule()
                        .stroke(Color.secondary.opacity(0.4), lineWidth: 1.0)
                        .frame(height: 26.0)
                    Circle().fill(Color.accentColor).frame(width: 26.0, height: 26.0)
                }
                .padding(.horizontal, 12.0)
            }
        }
    }
}

/// Topic rows with their state dots.
struct HarnessgramStatusDotsPreview: View {
    let on: Bool

    var body: some View {
        let rows: [(Color, String)] = [(.blue, HarnessgramPreviewStrings.topicWorking), (.orange, HarnessgramPreviewStrings.topicWaiting), (.green, HarnessgramPreviewStrings.topicDone)]
        HarnessgramPreviewCard(label: HarnessgramPreviewStrings.statusDots, height: 72.0) {
            VStack(alignment: .leading, spacing: 4.0) {
                ForEach(0 ..< rows.count, id: \.self) { index in
                    HStack(spacing: 6.0) {
                        if self.on {
                            Circle().fill(rows[index].0).frame(width: 8.0, height: 8.0)
                        }
                        Text(rows[index].1)
                            .font(.system(size: 12.0))
                        Spacer(minLength: 0.0)
                    }
                }
            }
            .padding(.horizontal, 12.0)
        }
    }
}

/// A mini phone screen with the floating button where it rests.
struct HarnessgramFloatingButtonPreview: View {
    let on: Bool
    let rightEdge: Bool

    var body: some View {
        HarnessgramPreviewCard(label: HarnessgramPreviewStrings.floating(rightEdge: self.rightEdge), height: 90.0) {
            ZStack(alignment: .bottom) {
                VStack(spacing: 6.0) {
                    ForEach(0 ..< 4, id: \.self) { _ in
                        HStack(spacing: 6.0) {
                            Circle().fill(Color.secondary.opacity(0.35)).frame(width: 10.0, height: 10.0)
                            Capsule().fill(Color.secondary.opacity(0.35)).frame(height: 5.0)
                        }
                    }
                    Spacer(minLength: 0.0)
                }
                .padding(8.0)
                Rectangle().fill(Color.secondary.opacity(0.2)).frame(height: 12.0)
                if self.on {
                    HStack {
                        // The preview is drawn right to left, so "leading" is the right edge.
                        if !self.rightEdge {
                            Spacer()
                        }
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 18.0, height: 18.0)
                            .overlay(Image(systemName: "airplane").font(.system(size: 9.0, weight: .bold)).foregroundColor(.white))
                        if self.rightEdge {
                            Spacer()
                        }
                    }
                    .padding(.horizontal, 6.0)
                    .padding(.bottom, 18.0)
                }
            }
            .frame(width: 70.0)
            .background(RoundedRectangle(cornerRadius: 10.0).fill(Color(UIColor.systemBackground)))
            .padding(.vertical, 4.0)
        }
    }
}
