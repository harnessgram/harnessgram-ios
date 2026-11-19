import Foundation
import UIKit
import SwiftUI
import Display
import AccountContext
import HarnessgramSettings
import HarnessgramHouseCore

/// Settings > Harnessgram > "ערכת נושא" (build 22): built-in themes in the cockpit spirit. Each row shows a small
/// preview (the page, their bubble, your bubble and the accent) in the theme's own colours. A choice applies at once;
/// "ללא" returns to the owner's Telegram theme (Telegram's theme settings are never changed).
enum HarnessgramThemeStrings {
    static let title = "ערכת נושא"
    static let rowDetail = "צבעים בהשראת תא הטייס לכל האפליקציה."
    static let footer = "הערכה חלה מיד על כל האפליקציה. כל עוד נבחרה ערכה, היא גוברת על צבעי הבית. ״ללא״ מחזיר את ערכת הנושא שבחרת בטלגרם."
    static let theirMessage = "מה המצב בתא הטייס?"
    static let yourMessage = "ממריאים בעוד רגע!"
    static let telegramTheme = "ערכת הנושא של טלגרם"

    static func name(_ theme: HarnessgramSettings.Theme) -> String {
        switch theme {
        case .none:
            return "ללא"
        case .cockpitNight:
            return "לילה בקוקפיט"
        case .runwayDawn:
            return "שחר על המסלול"
        case .openSky:
            return "שמיים פתוחים"
        case .instruments:
            return "מכשירים"
        }
    }

    static func detail(_ theme: HarnessgramSettings.Theme) -> String {
        switch theme {
        case .none:
            return "ערכת הנושא שבחרת בטלגרם."
        case .cockpitNight:
            return "כחול כהה של לילה, מחוונים בכתום ענבר."
        case .runwayDawn:
            return "בהיר וחם, עם כתום של זריחה."
        case .openSky:
            return "בהיר ואוורירי, עם כחול של שמיים."
        case .instruments:
            return "כהה, עם ירוק של לוח מכשירים."
        }
    }
}

private extension HouseColor {
    var swiftUI: Color {
        return Color(.sRGB, red: Double((self.rgb >> 16) & 0xff) / 255.0, green: Double((self.rgb >> 8) & 0xff) / 255.0, blue: Double(self.rgb & 0xff) / 255.0, opacity: self.alpha)
    }
}

final class HarnessgramThemeModel: ObservableObject {
    private let settings: HarnessgramSettings
    @Published private(set) var selected: HarnessgramSettings.Theme

    init(settings: HarnessgramSettings = .shared) {
        self.settings = settings
        self.selected = settings.theme
    }

    func select(_ theme: HarnessgramSettings.Theme) {
        self.settings.theme = theme
        self.selected = theme
    }
}

/// A theme's thumbnail: its page with their bubble, your bubble and an accent bar.
struct HarnessgramThemePreview: View {
    let theme: HarnessgramSettings.Theme

    var body: some View {
        if let palette = HarnessgramThemePalettes.palette(self.theme)?.palette {
            VStack(alignment: .leading, spacing: 6) {
                Capsule()
                    .fill(palette.olive.swiftUI)
                    .frame(width: 36, height: 4)
                HStack {
                    Text(HarnessgramThemeStrings.theirMessage)
                        .font(.caption)
                        .foregroundColor(palette.ink.swiftUI)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(palette.surface.swiftUI))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(palette.border.swiftUI, lineWidth: 1))
                    Spacer(minLength: 0)
                }
                HStack {
                    Spacer(minLength: 0)
                    Text(HarnessgramThemeStrings.yourMessage)
                        .font(.caption)
                        .foregroundColor(palette.onOlive.swiftUI)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(palette.olive.swiftUI))
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(palette.bg.swiftUI))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(palette.borderStrong.swiftUI, lineWidth: 1))
            .environment(\.layoutDirection, .rightToLeft)
            .accessibilityHidden(true)
        } else {
            Text(HarnessgramThemeStrings.telegramTheme)
                .font(.footnote)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                .accessibilityHidden(true)
        }
    }
}

struct HarnessgramThemeView: View {
    @ObservedObject var model: HarnessgramThemeModel

    var body: some View {
        Form {
            Section(footer: Text(HarnessgramThemeStrings.footer)) {
                ForEach(HarnessgramSettings.Theme.allCases, id: \.self) { theme in
                    Button(action: { self.model.select(theme) }) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .center, spacing: 12) {
                                HarnessgramSettingsRowLabel(title: HarnessgramThemeStrings.name(theme), detail: HarnessgramThemeStrings.detail(theme))
                                    .foregroundColor(.primary)
                                Spacer(minLength: 8)
                                if self.model.selected == theme {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.accentColor)
                                        .accessibilityHidden(true)
                                }
                            }
                            HarnessgramThemePreview(theme: theme)
                        }
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .accessibilityAddTraits(self.model.selected == theme ? .isSelected : [])
                }
            }
        }
    }
}

public func harnessgramThemeController(context: AccountContext) -> ViewController {
    return HarnessgramHostingScreen(context: context, title: HarnessgramThemeStrings.title, content: HarnessgramThemeView(model: HarnessgramThemeModel()))
}
