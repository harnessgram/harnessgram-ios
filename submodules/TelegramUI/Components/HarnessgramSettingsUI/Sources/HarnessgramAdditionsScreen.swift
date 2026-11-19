import Foundation
import UIKit
import SwiftUI
import Display
import AccountContext
import HarnessgramSettings
import HarnessgramAgent
import HarnessgramCockpitSync
import HarnessgramHouseCore

/// Settings > Harnessgram > "מה Harnessgram מוסיף" (build 20): every addition on top of Telegram, one plain line each,
/// with its switch or a link to its own page. Build 21: right to left like the rest of Harnessgram (SwiftUI in
/// HarnessgramHostingScreen, not Telegram's item list). Ground rule: every custom addition is visible and can be turned
/// off, except the filter's rules (build 21: off only through the committee).
enum HarnessgramAddition: CaseIterable {
    case filter
    case cockpitTab
    case nativeCockpit
    case nativeDecisions
    case cockpitFloatingButton
    case cockpitAppBadge
    case houseColours
    case theme
    case appFont
    case radioScreen
    case knock
    case waitingList
    case radio
    case quickButtons
    case statusDots
    case sensitiveFaceID
    case textLayout
    case widgets
    case houseIcon

    var title: String {
        switch self {
        case .filter: return HarnessgramFilterStrings.filterTitle
        case .cockpitTab: return "לשונית קוקפיט"
        case .nativeCockpit: return NativeCockpitStrings.t(.settingNativeCockpit)
        case .nativeDecisions: return NativeCockpitStrings.t(.settingNativeDecisions)
        case .cockpitFloatingButton: return "כפתור קוקפיט צף"
        case .cockpitAppBadge: return "סימון על סמל האפליקציה"
        case .houseColours: return "צבעי הבית"
        case .theme: return HarnessgramThemeStrings.title
        case .appFont: return HarnessgramAppFontStrings.title
        case .radioScreen: return "מסך השידורים ופס הנגינה"
        case .knock: return "איתות קשר"
        case .waitingList: return "מעגל ההמתנה"
        case .radio: return HarnessgramNowPlaying.Strings.title
        case .quickButtons: return "כפתורים מהירים בצ׳אטים של הסוכנים"
        case .statusDots: return "נקודות מצב בנושאים"
        case .sensitiveFaceID: return "זיהוי פנים לפעולות רגישות"
        case .textLayout: return "יישור הטקסט לשני הצדדים"
        case .widgets: return "ווידג׳טים וחיבור לגשר"
        case .houseIcon: return "סמל הבית"
        }
    }

    /// Build 23: every row has its icon (an SF Symbol on a tinted square, Telegram's settings look).
    var icon: String {
        switch self {
        case .filter: return "line.3.horizontal.decrease.circle"
        case .cockpitTab: return "gauge.with.dots.needle.67percent"
        case .nativeCockpit: return "list.bullet.rectangle"
        case .nativeDecisions: return "checkmark.seal"
        case .cockpitFloatingButton: return "smallcircle.filled.circle"
        case .cockpitAppBadge: return "app.badge"
        case .houseColours: return "house"
        case .theme: return "paintpalette"
        case .appFont: return "textformat"
        case .radioScreen: return "radio"
        case .knock: return "hand.raised"
        case .waitingList: return "tray.full"
        case .radio: return "dot.radiowaves.left.and.right"
        case .quickButtons: return "rectangle.3.group.bubble"
        case .statusDots: return "circle.hexagongrid"
        case .sensitiveFaceID: return "faceid"
        case .textLayout: return "text.justify"
        case .widgets: return "rectangle.on.rectangle.angled"
        case .houseIcon: return "app.gift"
        }
    }

    var tint: Color {
        switch self {
        case .filter: return HarnessgramRowTint.filter
        case .cockpitTab, .nativeCockpit, .nativeDecisions, .cockpitFloatingButton, .cockpitAppBadge: return HarnessgramRowTint.cockpit
        case .houseColours, .theme, .houseIcon: return HarnessgramRowTint.look
        case .appFont, .textLayout: return HarnessgramRowTint.text
        case .radioScreen, .radio: return HarnessgramRowTint.radio
        case .knock, .waitingList, .quickButtons, .statusDots, .sensitiveFaceID: return HarnessgramRowTint.agents
        case .widgets: return HarnessgramRowTint.connect
        }
    }

    var explanation: String {
        switch self {
        case .filter: return "מה מוסתר ומה מוצג. כל כלל מוסבר בדף שלו; כיבוי רק דרך הוועדה."
        case .cockpitTab: return "לשונית ליד הצ׳אטים עם אישורי ההמראה, לוח הטיסה והשידורים."
        case .nativeCockpit: return NativeCockpitStrings.t(.settingNativeCockpitDetail)
        case .nativeDecisions: return NativeCockpitStrings.t(.settingNativeDecisionsDetail)
        case .cockpitFloatingButton: return "כפתור עגול קטן מעל רשימת הצ׳אטים שפותח את הקוקפיט. אפשר לגרור אותו לצד השני."
        case .cockpitAppBadge: return "המספר על סמל האפליקציה סופר גם את מה שמחכה לך בקוקפיט, לא רק הודעות שלא נקראו."
        case .houseColours: return "צבעי אבן חמים במקום הכחול של טלגרם."
        case .theme: return "ערכות צבעים בהשראת תא הטייס. ״ללא״ מחזיר את ערכת הנושא של טלגרם."
        case .appFont: return "גופן עברי לבחירה לכל האפליקציה. גופן המערכת מחזיר את המראה של טלגרם."
        case .radioScreen: return "מסך שידורים מעוצב, ופס נגינה למעלה שמראה מה מתנגן."
        case .knock: return "כשסוכן שואל שאלה, האיתות קופץ בחלון קטן גם כשאתה בצ׳אט אחר. כבוי: רק ההתראה הרגילה."
        case .waitingList: return "כל אישורי ההמראה שמחכים לך, ברשימה אחת."
        case .radio: return "השידור החי של הצוות, מתוך האפליקציה."
        case .quickButtons: return "שורת כפתורים מעל המקלדת לפקודות של הסוכן."
        case .statusDots: return "נקודה צבעונית ליד כל נושא: עובד, מחכה לך או סיים."
        case .sensitiveFaceID: return "כפתור רגיש של הגשר מבקש זיהוי פנים לפני שהוא נשלח."
        case .textLayout: return "הודעות ארוכות מיושרות לשני הצדדים, כמו בספר."
        case .widgets: return "ווידג׳טים במסך הבית שמראים מה מחכה לך. החיבור לגשר נמצא בהגדרות, בחלק ״חיבורים״."
        case .houseIcon: return "סמל האפליקציה בעיצוב הבית במקום הסמל הרגיל. המערכת מודיעה כשהסמל מתחלף."
        }
    }
}

/// What each addition shows now (pure: the screen and the tests read the same table).
struct HarnessgramAdditionsState: Equatable {
    var filterRulesOn: Int
    var cockpitTab: Bool
    var nativeCockpit: Bool = false
    var nativeDecisions: Bool = false
    var cockpitFloatingButton: Bool
    var cockpitAppBadge: Bool
    var houseColours: Bool
    var theme: HarnessgramSettings.Theme
    var appFont: HarnessgramSettings.AppFont
    var radioScreen: Bool
    var knock: Bool
    var waitingList: Bool
    var quickButtons: Bool
    var statusDots: Bool
    var sensitiveFaceID: Bool
    var textLayout: Bool
    var widgetsConnected: Bool
    var houseIcon: Bool = false
    var floatingRightEdge: Bool = HarnessgramCockpitFloatingButtonLayout.defaultRightEdge

    static func current(settings: HarnessgramSettings = .shared, filter: HarnessgramFilterSettings = .shared, widgetsConnected: Bool) -> HarnessgramAdditionsState {
        return HarnessgramAdditionsState(
            filterRulesOn: HarnessgramFilterRule.allCases.filter { filter.isOn($0) }.count,
            cockpitTab: settings.cockpitTab,
            nativeCockpit: settings.houseFeature(.nativeCockpit),
            nativeDecisions: settings.houseFeature(.nativeDecisions),
            cockpitFloatingButton: settings.cockpitFloatingButton,
            cockpitAppBadge: settings.cockpitAppBadge,
            houseColours: settings.houseFeature(.theme),
            theme: settings.theme,
            appFont: settings.appFont,
            radioScreen: settings.houseFeature(.radioScreen),
            knock: settings.houseFeature(.knock),
            waitingList: settings.houseFeature(.waitingList),
            quickButtons: settings.agentQuickActions,
            statusDots: settings.topicStatusDots,
            sensitiveFaceID: settings.confirmSensitiveButtons,
            textLayout: settings.justifiedText,
            widgetsConnected: widgetsConnected,
            houseIcon: HarnessgramAdditionsState.houseIconOn(),
            floatingRightEdge: settings.cockpitFloatingButtonPosition?.rightEdge ?? HarnessgramCockpitFloatingButtonLayout.defaultRightEdge
        )
    }

    /// The alternate icon's name: the folder name of HouseIcon.alticon in Telegram/Telegram-iOS.
    static let houseIconName = "HouseIcon"

    static func houseIconOn() -> Bool {
        guard Thread.isMainThread else {
            return false
        }
        return UIApplication.shared.alternateIconName == HarnessgramAdditionsState.houseIconName
    }
}

/// What a row of the additions page is: a switch, or a link with its value ("11/11", "מחוברים").
enum HarnessgramAdditionRow: Equatable {
    case toggle(Bool)
    case link(String)
}

extension HarnessgramAdditionsState {
    func row(_ addition: HarnessgramAddition) -> HarnessgramAdditionRow {
        switch addition {
        case .filter:
            return .link("\(self.filterRulesOn)/\(HarnessgramFilterRule.allCases.count)")
        case .radio:
            return .link("")
        case .theme:
            return .link(HarnessgramThemeStrings.name(self.theme))
        case .appFont:
            return .link(HarnessgramAppFontStrings.name(self.appFont))
        case .widgets:
            return .link(self.widgetsConnected ? "מחוברים" : "לא מחוברים")
        case .cockpitTab:
            return .toggle(self.cockpitTab)
        case .nativeCockpit:
            return .toggle(self.nativeCockpit)
        case .nativeDecisions:
            return .toggle(self.nativeDecisions)
        case .cockpitFloatingButton:
            return .toggle(self.cockpitFloatingButton)
        case .cockpitAppBadge:
            return .toggle(self.cockpitAppBadge)
        case .houseColours:
            return .toggle(self.houseColours)
        case .radioScreen:
            return .toggle(self.radioScreen)
        case .knock:
            return .toggle(self.knock)
        case .waitingList:
            return .toggle(self.waitingList)
        case .quickButtons:
            return .toggle(self.quickButtons)
        case .statusDots:
            return .toggle(self.statusDots)
        case .sensitiveFaceID:
            return .toggle(self.sensitiveFaceID)
        case .textLayout:
            return .toggle(self.textLayout)
        case .houseIcon:
            return .toggle(self.houseIcon)
        }
    }
}

final class HarnessgramAdditionsModel: ObservableObject {
    private let settings: HarnessgramSettings
    private let gate: HarnessgramGateSwitch
    private var observers: [NSObjectProtocol] = []

    @Published private(set) var state: HarnessgramAdditionsState
    /// Bumped on every change: a switch whose change was refused or is waiting for Face ID redraws from the settings.
    @Published private(set) var revision = 0

    /// Set by the controller.
    var open: ((HarnessgramAddition) -> Void)?

    init(settings: HarnessgramSettings = .shared) {
        self.settings = settings
        self.gate = HarnessgramGateSwitch(settings: settings, reason: HarnessgramStrings.t(.confirmSensitiveOffReason))
        self.state = HarnessgramAdditionsState.current(settings: settings, widgetsConnected: HarnessgramCockpitSync.shared.isConnected)
        self.gate.onChange = { [weak self] in
            self?.refresh()
        }
        let center = NotificationCenter.default
        self.observers = [HarnessgramSettings.didChangeNotification, HarnessgramFilterSettings.didChangeNotification].map { name in
            center.addObserver(forName: name, object: nil, queue: .main, using: { [weak self] _ in
                self?.refresh()
            })
        }
    }

    deinit {
        for observer in self.observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func refresh() {
        self.state = HarnessgramAdditionsState.current(settings: self.settings, widgetsConnected: HarnessgramCockpitSync.shared.isConnected)
        self.revision += 1
    }

    func toggle(_ addition: HarnessgramAddition, _ value: Bool) {
        switch addition {
        case .cockpitTab:
            self.settings.cockpitTab = value
        case .nativeCockpit:
            self.settings.setHouseFeature(.nativeCockpit, value)
        case .nativeDecisions:
            self.settings.setHouseFeature(.nativeDecisions, value)
        case .cockpitFloatingButton:
            self.settings.cockpitFloatingButton = value
        case .cockpitAppBadge:
            self.settings.cockpitAppBadge = value
        case .houseColours:
            self.settings.setHouseFeature(.theme, value)
        case .radioScreen:
            self.settings.setHouseFeature(.radioScreen, value)
        case .knock:
            self.settings.setHouseFeature(.knock, value)
        case .waitingList:
            self.settings.setHouseFeature(.waitingList, value)
        case .quickButtons:
            self.settings.agentQuickActions = value
        case .statusDots:
            self.settings.topicStatusDots = value
        case .sensitiveFaceID:
            // Turning it off asks for Face ID first (the same gate as the Settings row).
            self.gate.set(value)
        case .textLayout:
            self.settings.justifiedText = value
        case .houseIcon:
            // The system shows its own "icon changed" alert; off sets the primary icon back.
            UIApplication.shared.setAlternateIconName(value ? HarnessgramAdditionsState.houseIconName : nil, completionHandler: { [weak self] _ in
                DispatchQueue.main.async {
                    self?.refresh()
                }
            })
        case .filter, .radio, .widgets, .appFont, .theme:
            break
        }
        self.refresh()
    }
}

struct HarnessgramAdditionsView: View {
    @ObservedObject var model: HarnessgramAdditionsModel

    var body: some View {
        Form {
            Section(header: Text(HarnessgramFilterStrings.additionsIntro).textCase(nil)) {
                ForEach(HarnessgramAddition.allCases.filter { $0 != .nativeDecisions || NativeCockpitModel.answersAvailable }, id: \.self) { addition in
                    switch self.model.state.row(addition) {
                    case let .toggle(isOn):
                        HarnessgramToggleRow(icon: addition.icon, tint: addition.tint, title: addition.title, detail: addition.explanation, isOn: Binding(get: { isOn }, set: { self.model.toggle(addition, $0) }), preview: {
                            self.preview(addition)
                        })
                        .id(self.model.revision)
                    case let .link(value):
                        HarnessgramLinkRow(icon: addition.icon, tint: addition.tint, title: addition.title, detail: addition.explanation, value: value, action: {
                            self.model.open?(addition)
                        }, preview: {
                            self.preview(addition)
                        })
                    }
                }
            }
        }
    }

    /// The small live previews for the additions whose effect is visual.
    @ViewBuilder
    private func preview(_ addition: HarnessgramAddition) -> some View {
        switch addition {
        case .houseColours:
            HarnessgramHouseColoursPreview(on: self.model.state.houseColours)
        case .theme:
            HarnessgramThemeSwatchPreview(theme: self.model.state.theme, name: HarnessgramThemeStrings.name(self.model.state.theme))
        case .appFont:
            HarnessgramAppFontSample(font: self.model.state.appFont, name: HarnessgramAppFontStrings.name(self.model.state.appFont))
        case .quickButtons:
            HarnessgramAgentButtonsPreview(on: self.model.state.quickButtons)
        case .statusDots:
            HarnessgramStatusDotsPreview(on: self.model.state.statusDots)
        case .cockpitFloatingButton:
            HarnessgramFloatingButtonPreview(on: self.model.state.cockpitFloatingButton, rightEdge: self.model.state.floatingRightEdge)
        default:
            EmptyView()
        }
    }
}

public func harnessgramAdditionsController(context: AccountContext, openWidgets: @escaping () -> Void) -> ViewController {
    let model = HarnessgramAdditionsModel()
    let controller = HarnessgramHostingScreen(context: context, title: HarnessgramFilterStrings.additionsTitle, content: HarnessgramAdditionsView(model: model))
    model.open = { [weak controller] addition in
        let push: (ViewController) -> Void = { c in
            (controller?.navigationController as? NavigationController)?.pushViewController(c)
        }
        switch addition {
        case .filter:
            push(harnessgramFilterController(context: context))
        case .radio:
            push(harnessgramRadioController(context: context))
        case .theme:
            push(harnessgramThemeController(context: context))
        case .appFont:
            push(harnessgramAppFontController(context: context))
        case .widgets:
            openWidgets()
        default:
            break
        }
    }
    return controller
}
