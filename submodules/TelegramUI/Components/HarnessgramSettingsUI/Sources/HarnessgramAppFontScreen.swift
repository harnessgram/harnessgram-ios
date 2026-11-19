import Foundation
import UIKit
import SwiftUI
import Display
import AccountContext
import HarnessgramSettings
import HarnessgramFonts

/// Settings > Harnessgram > "גופן" (build 22, one font since build 23): the whole app's font family, the messages
/// included unless "גופן שונה להודעות" is on. Each option shows its name and a sample line drawn in that font. Build 23:
/// a choice is swapped into Display's `Font` helpers at once and the screens rebuild; text a screen drew earlier keeps the
/// old family until the app is opened again, so the restart banner (HarnessgramSettingApply) offers that.
enum HarnessgramAppFontStrings {
    static let title = "גופן"
    static let rowDetail = "גופן אחד לכל האפליקציה: הרשימות, ההגדרות, הניווט וגם ההודעות."
    static let footer = "ההודעות ושדה הכתיבה באותו גופן, אלא אם הדלקת ״גופן שונה להודעות״ בהגדרות. אות שחסרה בגופן, כמו אימוג׳י, מוצגת בגופן המערכת."
    static let sample = "שלום! כך ייראו התפריטים, הרשימות והצ׳אטים."
    static let nextLaunch = "השינוי ייכנס לתוקף בפתיחה הבאה של האפליקציה."
    static let howToRelaunch = "כדי לפתוח מחדש: מחליקים את האפליקציה למעלה ממחליף האפליקציות, ופותחים אותה שוב."
    static let unavailable = "הגופן הזה לא נטען במכשיר, ולכן האפליקציה נשארת עם גופן המערכת."

    static func name(_ font: HarnessgramSettings.AppFont) -> String {
        switch font {
        case .system:
            return "גופן המערכת"
        case .heebo:
            return "\u{2068}Heebo\u{2069}"
        case .assistant:
            return "\u{2068}Assistant\u{2069}"
        case .rubik:
            return "\u{2068}Rubik\u{2069}"
        case .frankRuhlLibre:
            return "\u{2068}Frank Ruhl Libre\u{2069}"
        case .secularOne:
            return "\u{2068}Secular One\u{2069}"
        }
    }

    static func detail(_ font: HarnessgramSettings.AppFont) -> String {
        switch font {
        case .system:
            return "כמו בטלגרם. ברירת המחדל."
        case .heebo:
            return "נקי ומודרני."
        case .assistant:
            return "קליל וצר."
        case .rubik:
            return "מעוגל וידידותי."
        case .frankRuhlLibre:
            return "קלאסי עם תגים, כמו בספר."
        case .secularOne:
            return "כותרתי ונועז, במשקל אחד."
        }
    }
}

final class HarnessgramAppFontModel: ObservableObject {
    private let settings: HarnessgramSettings
    /// The font this launch draws with.
    let launched: HarnessgramSettings.AppFont
    @Published private(set) var selected: HarnessgramSettings.AppFont

    init(settings: HarnessgramSettings = .shared, launched: HarnessgramSettings.AppFont = HarnessgramFonts.launchedAppFont) {
        self.settings = settings
        self.launched = launched
        self.selected = settings.appFont
    }

    /// Build 23: the choice differs from the launch value, so the restart banner shows.
    var waitsForRestart: Bool {
        return self.settings.waitsForRestart(.appFont)
    }

    /// Whether the chosen font waits for the next launch.
    var waitsForNextLaunch: Bool {
        return self.selected != self.launched
    }

    func select(_ font: HarnessgramSettings.AppFont) {
        // Build 23: swap the family at once (new screens draw in it), then store the choice; storing it rebuilds the
        // presentation data, so open screens redraw too.
        Display.Font.setAppFamily(HarnessgramFonts.liveAppFamily(font))
        self.settings.appFont = font
        self.selected = font
    }

    /// The font a row's name and sample are drawn in: the option's own family, or the system font when it is the
    /// system option or did not load.
    static func previewFont(_ font: HarnessgramSettings.AppFont, size: CGFloat, weight: CGFloat) -> UIFont {
        if let bundled = HarnessgramFonts.appFont(font, weight: weight, size: size) {
            return bundled
        }
        return UIFont.systemFont(ofSize: size, weight: weight >= 600.0 ? .semibold : .regular)
    }
}

struct HarnessgramAppFontView: View {
    @ObservedObject var model: HarnessgramAppFontModel
    var restart: () -> Void = {}

    var body: some View {
        Form {
            if self.model.waitsForRestart {
                Section {
                    HarnessgramRestartBanner(key: .appFont, text: HarnessgramRestartStrings.fontBanner, restart: self.restart)
                }
            }
            Section(footer: Text(HarnessgramAppFontStrings.footer)) {
                ForEach(HarnessgramSettings.AppFont.allCases, id: \.self) { font in
                    Button(action: { self.model.select(font) }) {
                        HStack(alignment: .center, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(HarnessgramAppFontStrings.name(font))
                                    .font(SwiftUI.Font(HarnessgramAppFontModel.previewFont(font, size: 20.0, weight: 600.0)))
                                    .foregroundColor(.primary)
                                Text(HarnessgramAppFontStrings.sample)
                                    .font(SwiftUI.Font(HarnessgramAppFontModel.previewFont(font, size: 15.0, weight: 400.0)))
                                    .foregroundColor(.primary)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(HarnessgramFonts.isAvailable(font) ? HarnessgramAppFontStrings.detail(font) : HarnessgramAppFontStrings.unavailable)
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 8)
                            if self.model.selected == font {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.accentColor)
                                    .accessibilityHidden(true)
                            }
                        }
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .accessibilityAddTraits(self.model.selected == font ? .isSelected : [])
                }
            }
        }
    }
}

public func harnessgramAppFontController(context: AccountContext) -> ViewController {
    var restart: (() -> Void)?
    var view = HarnessgramAppFontView(model: HarnessgramAppFontModel())
    view.restart = {
        restart?()
    }
    let controller = HarnessgramHostingScreen(context: context, title: HarnessgramAppFontStrings.title, content: view)
    restart = { [weak controller] in
        harnessgramRestartApp(from: controller)
    }
    return controller
}
