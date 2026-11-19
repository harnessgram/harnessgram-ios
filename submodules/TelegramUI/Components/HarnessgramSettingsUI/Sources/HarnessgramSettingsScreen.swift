import Foundation
import UIKit
import SwiftUI
import Display
import TelegramCore
import AccountContext
import HarnessgramSettings
import HarnessgramFonts
import HarnessgramAgent
import HarnessgramCockpitSync
import HarnessgramCockpitKit

final class HarnessgramSettingsModel: ObservableObject {
    private let settings: HarnessgramSettings

    @Published var connectThroughHomeRelay: Bool {
        didSet { self.settings.connectThroughHomeRelay = self.connectThroughHomeRelay }
    }
    @Published var recordWithBuiltInMic: Bool {
        didSet { self.settings.recordWithBuiltInMic = self.recordWithBuiltInMic }
    }
    @Published var autoDownloadInApprovedChats: Bool {
        didSet { self.settings.autoDownloadInApprovedChats = self.autoDownloadInApprovedChats }
    }
    @Published var justifiedText: Bool {
        didSet { self.settings.justifiedText = self.justifiedText }
    }
    @Published var lineSpacing: HarnessgramSettings.LineSpacing {
        didSet { self.settings.lineSpacing = self.lineSpacing }
    }
    /// The font picked for messages alone (shown only while `separateMessageFont` is on).
    @Published var messageFontChoice: HarnessgramSettings.MessageFont {
        didSet { self.settings.messageFontChoice = self.messageFontChoice }
    }
    /// "גופן שונה להודעות" (build 23): off, the messages follow the app font.
    @Published var separateMessageFont: Bool {
        didSet {
            self.settings.separateMessageFont = self.separateMessageFont
            self.messageFontChoice = self.settings.messageFontChoice
        }
    }
    @Published var fontWeight: HarnessgramSettings.FontWeight {
        didSet { self.settings.fontWeight = self.fontWeight }
    }
    @Published var textSizeSteps: Int {
        didSet { self.settings.textSizeSteps = self.textSizeSteps }
    }
    @Published var bubbleWidth: HarnessgramSettings.BubbleWidth {
        didSet { self.settings.bubbleWidth = self.bubbleWidth }
    }
    @Published var agentQuickActions: Bool {
        didSet { self.settings.agentQuickActions = self.agentQuickActions }
    }
    @Published var topicStatusDots: Bool {
        didSet { self.settings.topicStatusDots = self.topicStatusDots }
    }
    /// The widgets' connection to the bridge (build 18): connected, and whether exactly one account is logged in.
    @Published private(set) var widgetsConnected: Bool = HarnessgramCockpitSync.shared.isConnected
    @Published private(set) var singleAccount: Bool = HarnessgramCockpitSync.shared.hasSingleAccount
    @Published private(set) var pairing = false
    @Published private(set) var pairMessage: String?

    /// Simulator demo only: shows how a failed pairing reads (HARNESSGRAM_DEMO_PAIR_FAILURE = a reason's raw value).
    func applyDemoPairFailure() {
        #if targetEnvironment(simulator)
        if let raw = ProcessInfo.processInfo.environment["HARNESSGRAM_DEMO_PAIR_FAILURE"], let reason = HarnessgramPairFailure(rawValue: raw) {
            self.pairMessage = reason.text
            self.demoNotConnected = true
            self.widgetsConnected = false
        }
        #endif
    }
    /// Set by the controller: connects with the current account context.
    var pairAction: ((@escaping (HarnessgramCockpitSync.PairResult) -> Void) -> Void)?

    /// Simulator demo only: the failed-pairing picture shows the row as not connected.
    private var demoNotConnected = false

    func refreshConnection() {
        self.widgetsConnected = HarnessgramCockpitSync.shared.isConnected && !self.demoNotConnected
        self.singleAccount = HarnessgramCockpitSync.shared.hasSingleAccount
    }

    func pairWidgets() {
        guard !self.pairing else {
            return
        }
        self.pairing = true
        self.pairMessage = nil
        self.pairAction?({ [weak self] result in
            guard let self else {
                return
            }
            self.pairing = false
            switch result {
            case .connected:
                self.pairMessage = nil
            case .needsOneAccount:
                self.pairMessage = HarnessgramStrings.t(.cockpitPausedOneAccount)
            case let .failed(reason):
                self.pairMessage = reason.text
            case .notConfirmed:
                self.pairMessage = nil
            }
            self.refreshConnection()
        })
    }

    func disconnectWidgets() {
        HarnessgramCockpitSync.shared.disconnect()
        self.pairMessage = nil
        self.refreshConnection()
    }

    /// The bridge bot's pinned identity; a change of bot waits here for the owner.
    @Published private(set) var bridgeState: HarnessgramBridgeIdentity.State = HarnessgramBridgeIdentity.shared.state
    private var isConfirmingBridge = false

    /// The owner accepts the bot the bridge username now points to, after Face ID or the passcode.
    func confirmChangedBridge() {
        guard case .changed = self.bridgeState, !self.isConfirmingBridge else {
            return
        }
        self.isConfirmingBridge = true
        HarnessgramOwnerConfirmation.shared.confirm(reason: HarnessgramStrings.t(.bridgeChangedReason), completion: { [weak self] confirmed in
            guard let self else {
                return
            }
            self.isConfirmingBridge = false
            if confirmed {
                HarnessgramBridgeIdentity.shared.confirmChangedBot()
            }
            self.bridgeState = HarnessgramBridgeIdentity.shared.state
        })
    }

    /// Changed only through `setConfirmSensitiveButtons`: turning it off needs the owner first.
    @Published private(set) var confirmSensitiveButtons: Bool
    /// The app font (build 22); its own page changes it, this screen shows the choice.
    @Published private(set) var appFont: HarnessgramSettings.AppFont
    /// The Harnessgram theme (build 22); its own page changes it.
    @Published private(set) var theme: HarnessgramSettings.Theme
    private let gateSwitch: HarnessgramGateSwitch
    private var settingsObserver: NSObjectProtocol?

    init(settings: HarnessgramSettings) {
        self.settings = settings
        self.connectThroughHomeRelay = settings.connectThroughHomeRelay
        self.recordWithBuiltInMic = settings.recordWithBuiltInMic
        self.autoDownloadInApprovedChats = settings.autoDownloadInApprovedChats
        self.justifiedText = settings.justifiedText
        self.lineSpacing = settings.lineSpacing
        self.messageFontChoice = settings.messageFontChoice
        self.separateMessageFont = settings.separateMessageFont
        self.fontWeight = settings.fontWeight
        self.textSizeSteps = settings.textSizeSteps
        self.bubbleWidth = settings.bubbleWidth
        self.agentQuickActions = settings.agentQuickActions
        self.topicStatusDots = settings.topicStatusDots
        self.confirmSensitiveButtons = settings.confirmSensitiveButtons
        self.appFont = settings.appFont
        self.theme = settings.theme
        self.gateSwitch = HarnessgramGateSwitch(settings: settings, reason: HarnessgramStrings.t(.confirmSensitiveOffReason))
        self.gateSwitch.onChange = { [weak self] in
            guard let self else {
                return
            }
            // The toggle redraws from the model: it stays on while the system asks, and after a cancel.
            self.confirmSensitiveButtons = self.gateSwitch.isOn
            self.objectWillChange.send()
        }
        self.settingsObserver = NotificationCenter.default.addObserver(forName: HarnessgramSettings.didChangeNotification, object: nil, queue: .main, using: { [weak self] _ in
            guard let self else {
                return
            }
            if self.appFont != self.settings.appFont {
                self.appFont = self.settings.appFont
            }
            if self.theme != self.settings.theme {
                self.theme = self.settings.theme
            }
            // The restart banner and the previews read the settings directly.
            self.objectWillChange.send()
        })
    }

    deinit {
        if let settingsObserver = self.settingsObserver {
            NotificationCenter.default.removeObserver(settingsObserver)
        }
    }

    /// What the messages draw in now (the app font unless a separate one is on): the preview bubble uses it.
    var effectiveMessageFont: HarnessgramSettings.MessageFont {
        return self.settings.messageFont
    }

    /// On at once; off only after Face ID or the passcode (HarnessgramGateSwitch). A cancel or a failure leaves the gate on.
    func setConfirmSensitiveButtons(_ value: Bool) {
        self.gateSwitch.set(value)
    }
}

struct HarnessgramSettingsView: View {
    @Environment(\.openURL) private var openURL
    @ObservedObject var model: HarnessgramSettingsModel
    @ObservedObject var radio: HarnessgramRadioPlayer
    let openRadio: () -> Void
    var openAdditions: () -> Void = {}
    var openFilter: () -> Void = {}
    var openAppFont: () -> Void = {}
    var openTheme: () -> Void = {}
    var restart: () -> Void = {}

    private func t(_ key: HarnessgramStrings.Key) -> String {
        return HarnessgramStrings.t(key)
    }

    /// Build 23 (owner: "it is unclear what each thing does"): one screen, six short sections, every row with an icon, a
    /// title and a line saying what it does; segmented choices inside labelled rows; previews for what is visual.
    var body: some View {
        Form {
            self.appearanceSection
            self.agentsSection
            self.radioSection
            self.filterSection
            self.connectionsSection
            Section(header: Text(HarnessgramFilterStrings.additionsTitle).textCase(nil)) {
                HarnessgramLinkRow(icon: "square.stack.3d.up", tint: HarnessgramRowTint.cockpit, title: HarnessgramFilterStrings.additionsTitle, detail: self.t(.additionsRowDetail), action: self.openAdditions)
            }
            self.aboutSection
        }
    }

    private var aboutSection: some View {
        Section(header: Text(HarnessgramAboutStrings.title).textCase(nil)) {
            HarnessgramLinkRow(icon: "chevron.left.forwardslash.chevron.right", tint: HarnessgramRowTint.neutral, title: HarnessgramAboutStrings.source, detail: HarnessgramAboutStrings.sourceDetail, action: {
                self.openURL(HarnessgramAboutStrings.sourceURL)
            })
            HarnessgramCustomRow(icon: "info.circle", tint: HarnessgramRowTint.neutral, title: HarnessgramAboutStrings.independence, detail: HarnessgramAboutStrings.license) {
                EmptyView()
            }
        }
    }

    // MARK: מראה

    private var appearanceSection: some View {
        Section(header: Text(self.t(.sectionAppearance)).textCase(nil)) {
            HarnessgramLinkRow(icon: "paintpalette", tint: HarnessgramRowTint.look, title: HarnessgramThemeStrings.title, detail: HarnessgramThemeStrings.rowDetail, value: HarnessgramThemeStrings.name(self.model.theme), action: self.openTheme, preview: {
                HarnessgramThemeSwatchPreview(theme: self.model.theme, name: HarnessgramThemeStrings.name(self.model.theme))
            })
            HarnessgramLinkRow(icon: "textformat", tint: HarnessgramRowTint.text, title: self.t(.fontRow), detail: self.t(.fontRowDetail), value: HarnessgramAppFontStrings.name(self.model.appFont), action: self.openAppFont, preview: {
                VStack(spacing: 8.0) {
                    HarnessgramFontPreview(font: self.model.effectiveMessageFont, weight: self.model.fontWeight, sizeSteps: self.model.textSizeSteps, lineSpacing: self.model.lineSpacing, name: harnessgramFontTitle(self.model.effectiveMessageFont))
                    HarnessgramRestartBanner(key: .appFont, text: HarnessgramRestartStrings.fontBanner, restart: self.restart)
                }
            })
            HarnessgramToggleRow(icon: "text.bubble", tint: HarnessgramRowTint.text, title: self.t(.separateMessageFont), detail: self.t(.separateMessageFontDetail), isOn: self.$model.separateMessageFont)
            if self.model.separateMessageFont {
                HarnessgramMenuRow(icon: "character.bubble", tint: HarnessgramRowTint.text, title: self.t(.messageFont), detail: self.t(.messageFontDetail), selection: self.$model.messageFontChoice, options: HarnessgramSettings.MessageFont.allCases.map { ($0, harnessgramFontTitle($0)) })
            }
            HarnessgramSegmentedRow(icon: "bold", tint: HarnessgramRowTint.text, title: self.t(.fontWeight), detail: self.t(.fontWeightDetail), selection: self.$model.fontWeight, options: HarnessgramSettings.FontWeight.allCases.map { ($0, harnessgramWeightTitle($0)) })
            HarnessgramStepperRow(icon: "textformat.size", tint: HarnessgramRowTint.text, title: self.t(.textSize), detail: self.t(.textSizeDetail), value: self.$model.textSizeSteps, range: HarnessgramSettings.textSizeStepRange, valueText: self.model.textSizeSteps == 0 ? self.t(.textSizeDefault) : "\u{2068}\(self.model.textSizeSteps > 0 ? "+" : "")\(self.model.textSizeSteps)\u{2069}")
            HarnessgramSegmentedRow(icon: "arrow.left.and.right", tint: HarnessgramRowTint.text, title: self.t(.bubbleWidth), detail: self.t(.bubbleWidthDetail), selection: self.$model.bubbleWidth, options: [(HarnessgramSettings.BubbleWidth.normal, self.t(.bubbleNormal)), (.wide, self.t(.bubbleWide))], preview: {
                HarnessgramBubbleWidthPreview(width: self.model.bubbleWidth)
            })
            HarnessgramSegmentedRow(icon: "line.3.horizontal", tint: HarnessgramRowTint.text, title: self.t(.lineSpacing), detail: self.t(.lineSpacingDetail), selection: self.$model.lineSpacing, options: [(HarnessgramSettings.LineSpacing.normal, self.t(.lineSpacingNormal)), (.comfortable, self.t(.lineSpacingComfortable))], preview: {
                HarnessgramLineSpacingPreview(spacing: self.model.lineSpacing)
            })
            HarnessgramToggleRow(icon: "text.justify", tint: HarnessgramRowTint.text, title: self.t(.justifiedText), detail: self.t(.justifiedTextFooter), isOn: self.$model.justifiedText)
        }
    }

    // MARK: סוכנים

    private var agentsSection: some View {
        Section(header: Text(self.t(.sectionAgents)).textCase(nil)) {
            HarnessgramToggleRow(icon: "rectangle.3.group.bubble", tint: HarnessgramRowTint.agents, title: self.t(.agentQuickActions), detail: self.t(.agentQuickActionsFooter), isOn: self.$model.agentQuickActions, preview: {
                HarnessgramAgentButtonsPreview(on: self.model.agentQuickActions)
            })
            HarnessgramToggleRow(icon: "circle.hexagongrid", tint: HarnessgramRowTint.agents, title: self.t(.topicStatusDots), detail: self.t(.topicStatusDotsFooter), isOn: self.$model.topicStatusDots, preview: {
                HarnessgramStatusDotsPreview(on: self.model.topicStatusDots)
            })
            HarnessgramToggleRow(icon: "faceid", tint: HarnessgramRowTint.agents, title: self.t(.confirmSensitiveButtons), detail: self.t(.confirmSensitiveButtonsFooter), isOn: Binding(get: { self.model.confirmSensitiveButtons }, set: { self.model.setConfirmSensitiveButtons($0) }))
        }
    }

    // MARK: שידורי הקוקפיט

    private var radioSection: some View {
        Section(header: Text(self.t(.sectionRadio)).textCase(nil)) {
            HarnessgramLinkRow(icon: "dot.radiowaves.left.and.right", tint: HarnessgramRowTint.radio, title: self.t(.radioRow), detail: self.t(.radioRowDetail), value: harnessgramRadioStateText(self.radio.state), action: self.openRadio)
        }
    }

    // MARK: הסינון

    private var filterSection: some View {
        Section(header: Text(HarnessgramFilterStrings.filterTitle).textCase(nil)) {
            HarnessgramLinkRow(icon: "line.3.horizontal.decrease.circle", tint: HarnessgramRowTint.filter, title: HarnessgramFilterStrings.filterTitle, detail: HarnessgramFilterStrings.filterRowDetail, action: self.openFilter)
            HarnessgramToggleRow(icon: "arrow.down.circle", tint: HarnessgramRowTint.filter, title: self.t(.autoDownload), detail: self.t(.autoDownloadFooter), isOn: self.$model.autoDownloadInApprovedChats)
        }
    }

    // MARK: חיבורים

    private var connectionsSection: some View {
        Section(header: Text(self.t(.sectionConnection)).textCase(nil)) {
            HarnessgramCustomRow(icon: "rectangle.on.rectangle.angled", tint: HarnessgramRowTint.connect, title: self.t(.widgetsPairTitle), detail: self.t(self.model.widgetsConnected ? .widgetsConnected : (self.model.singleAccount ? .widgetsPairDetail : .cockpitPausedOneAccount)), content: {
                if let message = self.model.pairMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                if self.model.widgetsConnected {
                    Button(action: { self.model.disconnectWidgets() }) {
                        Text(self.t(.widgetsDisconnect))
                            .foregroundColor(.red)
                    }
                } else {
                    Button(action: { self.model.pairWidgets() }) {
                        Text(self.t(self.model.pairing ? .widgetsPairing : .widgetsPair))
                    }
                    .disabled(!self.model.singleAccount || self.model.pairing)
                }
            })
            .onAppear {
                self.model.refreshConnection()
            }
            harnessgramBridgeRow(self.model)
            HarnessgramToggleRow(icon: "house", tint: HarnessgramRowTint.connect, title: self.t(.homeRelay), detail: self.t(.homeRelayFooter), isOn: self.$model.connectThroughHomeRelay)
            HarnessgramToggleRow(icon: "mic", tint: HarnessgramRowTint.connect, title: self.t(.recordWithBuiltInMic), detail: self.t(.recordWithBuiltInMicFooter), isOn: self.$model.recordWithBuiltInMic)
        }
    }
}

/// The bridge bot row: its pinned id (English digits on their own line), or a change waiting for the owner.
@ViewBuilder
func harnessgramBridgeRow(_ model: HarnessgramSettingsModel) -> some View {
    switch model.bridgeState {
    case .unknown:
        HarnessgramCustomRow(icon: "person.badge.shield.checkmark", tint: HarnessgramRowTint.connect, title: HarnessgramStrings.t(.bridgeTitle), detail: HarnessgramStrings.t(.bridgeUnknown), content: { EmptyView() })
    case let .pinned(id):
        HarnessgramCustomRow(icon: "person.badge.shield.checkmark", tint: HarnessgramRowTint.connect, title: HarnessgramStrings.t(.bridgeTitle), detail: HarnessgramStrings.t(.bridgePinned) + "\n" + "\(id)", content: { EmptyView() })
    case let .changed(pinned, seen):
        HarnessgramCustomRow(icon: "exclamationmark.shield", tint: HarnessgramRowTint.filter, title: HarnessgramStrings.t(.bridgeChangedTitle), detail: HarnessgramStrings.t(.bridgeChangedDetail) + "\n" + "\(pinned)" + "\n" + "\(seen)", content: {
            Button(action: { model.confirmChangedBridge() }) {
                Text(HarnessgramStrings.t(.bridgeChangedConfirm))
            }
        })
    }
}

/// A switch's title with its one-line explanation under it (each agent switch explains itself in place).
struct HarnessgramSettingsRowLabel: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(self.title)
            Text(self.detail)
                .font(.footnote)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
    }
}

func harnessgramFontTitle(_ font: HarnessgramSettings.MessageFont) -> String {
    switch font {
    case .system:
        return HarnessgramStrings.t(.fontSystem)
    case .assistant:
        return HarnessgramStrings.t(.fontAssistant)
    case .heebo:
        return HarnessgramStrings.t(.fontHeebo)
    case .rubik:
        return HarnessgramStrings.t(.fontRubik)
    case .frankRuhlLibre:
        return HarnessgramStrings.t(.fontFrankRuhlLibre)
    case .secularOne:
        return HarnessgramAppFontStrings.name(.secularOne)
    }
}

func harnessgramWeightTitle(_ weight: HarnessgramSettings.FontWeight) -> String {
    switch weight {
    case .light:
        return HarnessgramStrings.t(.weightLight)
    case .regular:
        return HarnessgramStrings.t(.weightRegular)
    case .medium:
        return HarnessgramStrings.t(.weightMedium)
    case .semibold:
        return HarnessgramStrings.t(.weightSemibold)
    }
}

func harnessgramRadioStateText(_ state: HarnessgramRadioPlayer.State) -> String {
    switch state {
    case .stopped:
        return HarnessgramStrings.t(.radioStopped)
    case .connecting:
        return HarnessgramStrings.t(.radioConnecting)
    case .playing:
        return HarnessgramStrings.t(.radioPlaying)
    case .paused:
        return HarnessgramStrings.t(.radioPaused)
    case .failed:
        return "החיבור לשידורים נכשל. אפשר לנסות שוב."
    }
}

/// Settings ▸ Harnessgram: one screen of comfort switches. Nothing here approves or loosens the filter.
public func harnessgramSettingsController(context: AccountContext) -> ViewController {
    var openRadio: (() -> Void)?
    let model = HarnessgramSettingsModel(settings: .shared)
    var openAdditions: (() -> Void)?
    var openFilter: (() -> Void)?
    var view = HarnessgramSettingsView(model: model, radio: .shared, openRadio: {
        openRadio?()
    })
    view.openAdditions = {
        openAdditions?()
    }
    view.openFilter = {
        openFilter?()
    }
    var openAppFont: (() -> Void)?
    view.openAppFont = {
        openAppFont?()
    }
    var openTheme: (() -> Void)?
    view.openTheme = {
        openTheme?()
    }
    model.applyDemoPairFailure()
    model.pairAction = { done in
        HarnessgramCockpitSync.shared.pair(context: context, completion: done)
    }
    var restart: (() -> Void)?
    view.restart = {
        restart?()
    }
    let controller = HarnessgramHostingScreen(context: context, title: HarnessgramStrings.t(.settingsTitle), content: view)
    restart = { [weak controller] in
        harnessgramRestartApp(from: controller)
    }
    openRadio = { [weak controller] in
        (controller?.navigationController as? NavigationController)?.pushViewController(harnessgramRadioController(context: context))
    }
    openTheme = { [weak controller] in
        (controller?.navigationController as? NavigationController)?.pushViewController(harnessgramThemeController(context: context))
    }
    openAppFont = { [weak controller] in
        (controller?.navigationController as? NavigationController)?.pushViewController(harnessgramAppFontController(context: context))
    }
    openFilter = { [weak controller] in
        (controller?.navigationController as? NavigationController)?.pushViewController(harnessgramFilterController(context: context))
    }
    openAdditions = { [weak controller] in
        (controller?.navigationController as? NavigationController)?.pushViewController(harnessgramAdditionsController(context: context, openWidgets: { [weak controller] in
            // The widget pairing row lives on the Settings screen itself: back to it.
            if let controller {
                _ = (controller.navigationController as? NavigationController)?.popToViewController(controller, animated: true)
            }
        }))
    }
    return controller
}
