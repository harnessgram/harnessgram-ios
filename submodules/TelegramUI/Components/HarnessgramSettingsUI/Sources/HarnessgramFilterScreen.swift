import Foundation
import UIKit
import SwiftUI
import Display
import TelegramPresentationData
import PresentationDataUtils
import AccountContext
import HarnessgramSettings
import HarnessgramAgent

/// Settings > Harnessgram > "הסינון" (build 19): every filter rule, one plain line each, with its own switch. Build 21:
/// right to left like the rest of Harnessgram (SwiftUI in HarnessgramHostingScreen, not Telegram's item list, which
/// follows the English app language). Rules turn on only; turning one off shows "only through the committee" at once
/// (no Face ID). With personal off allowed (build 19 behaviour) it shows a short warning, then asks for Face ID or the
/// passcode. While a committee lock is in force every switch is read-only ("נעול על ידי הוועדה").
final class HarnessgramFilterModel: ObservableObject {
    let filter: HarnessgramFilterSettings
    private let filterSwitch: HarnessgramFilterSwitch
    private var observer: NSObjectProtocol?

    /// Bumped on every change and every outcome: the switches redraw from the filter (a refusal leaves a rule on).
    @Published private(set) var revision = 0

    /// Set by the controller: Telegram's alert with one OK button.
    var presentNotice: ((String) -> Void)?
    /// Set by the controller: the short warning before Face ID (personal off only); `confirm` runs on "כיבוי".
    var presentOffWarning: ((HarnessgramFilterRule, @escaping () -> Void, @escaping () -> Void) -> Void)?

    init(filter: HarnessgramFilterSettings = .shared) {
        self.filter = filter
        self.filterSwitch = HarnessgramFilterSwitch(filter: filter)
        self.observer = NotificationCenter.default.addObserver(forName: HarnessgramFilterSettings.didChangeNotification, object: nil, queue: .main, using: { [weak self] _ in
            self?.refresh()
        })
    }

    deinit {
        if let observer = self.observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    var isLocked: Bool {
        return self.filter.isLocked
    }

    func isOn(_ rule: HarnessgramFilterRule) -> Bool {
        return self.filter.isOn(rule)
    }

    func isRuleLocked(_ rule: HarnessgramFilterRule) -> Bool {
        return self.filter.source(rule) == .locked
    }

    func refresh() {
        self.revision += 1
    }

    private func finish(_ outcome: HarnessgramFilterSwitch.Outcome) {
        switch outcome {
        case .locked:
            self.presentNotice?(HarnessgramFilterStrings.lockedExplanation)
        case .committeeOnly:
            self.presentNotice?(HarnessgramFilterStrings.committeeOnly)
        case .changed, .unchanged, .notConfirmed:
            break
        }
        self.refresh()
    }

    func set(_ rule: HarnessgramFilterRule, on: Bool) {
        let finish: (HarnessgramFilterSwitch.Outcome) -> Void = { [weak self] outcome in
            self?.finish(outcome)
        }
        if on || self.filter.isLocked || !self.filter.allowsPersonalOff {
            // On at once; off is refused at once (.committeeOnly, no warning and no Face ID); a lock refuses both.
            self.filterSwitch.set(rule, on: on, reason: HarnessgramFilterStrings.offReason, completion: finish)
            return
        }
        // Personal off allowed: a short warning first, then Face ID or the passcode.
        guard let presentOffWarning = self.presentOffWarning else {
            self.refresh()
            return
        }
        presentOffWarning(rule, { [weak self] in
            self?.filterSwitch.set(rule, on: false, reason: HarnessgramFilterStrings.offReason, completion: finish)
        }, { [weak self] in
            self?.refresh()
        })
    }
}

struct HarnessgramFilterView: View {
    @ObservedObject var model: HarnessgramFilterModel

    var body: some View {
        Form {
            Section(header: Text(self.model.isLocked ? HarnessgramFilterStrings.lockedExplanation : HarnessgramFilterStrings.filterIntro).textCase(nil)) {
                ForEach(HarnessgramFilterRule.allCases, id: \.self) { rule in
                    let isLocked = self.model.isRuleLocked(rule)
                    Toggle(isOn: Binding(get: { self.model.isOn(rule) }, set: { self.model.set(rule, on: $0) })) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            if isLocked {
                                Image(systemName: "lock.fill")
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                            }
                            HarnessgramSettingsRowLabel(title: HarnessgramFilterStrings.title(rule), detail: HarnessgramFilterStrings.explanation(rule) + (isLocked ? "\n" + HarnessgramFilterStrings.locked : ""))
                        }
                    }
                    // A refused change redraws the switch from the filter (it stays on); the list keeps its scroll.
                    .id(self.model.revision)
                }
            }
        }
    }
}

public func harnessgramFilterController(context: AccountContext) -> ViewController {
    let model = HarnessgramFilterModel()
    let controller = HarnessgramHostingScreen(context: context, title: HarnessgramFilterStrings.filterTitle, content: HarnessgramFilterView(model: model))
    model.presentNotice = { [weak controller] text in
        controller?.present(textAlertController(context: context, title: nil, text: text, actions: [TextAlertAction(type: .defaultAction, title: context.sharedContext.currentPresentationData.with { $0 }.strings.Common_OK, action: {})]), in: .window(.root))
    }
    model.presentOffWarning = { [weak controller] rule, confirm, cancel in
        guard let controller else {
            cancel()
            return
        }
        controller.present(textAlertController(context: context, title: HarnessgramFilterStrings.offWarningTitle, text: HarnessgramFilterStrings.offWarning(rule), actions: [
            TextAlertAction(type: .genericAction, title: HarnessgramFilterStrings.cancel, action: cancel),
            TextAlertAction(type: .destructiveAction, title: HarnessgramFilterStrings.offConfirm, action: confirm)
        ]), in: .window(.root))
    }
    return controller
}
