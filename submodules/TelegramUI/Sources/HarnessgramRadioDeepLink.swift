import Foundation
import Display
import AccountContext
import PresentationDataUtils
import HarnessgramSettings
import HarnessgramSettingsUI
import HarnessgramAgent
import HarnessgramCockpitSync

/// Harnessgram: a radio deep link from the bridge (harnessgram://radio?link=... or
/// tg://harnessgram/radio?link=...). Only a link on the configured private network (or the host trusted on first
/// use) is taken. A first link is saved in the Keychain; a different one replaces the saved link only
/// after the owner taps Replace on a prompt that names its host. With no screen to show, nothing is
/// saved. Playback starts only when the owner taps play. Returns false for any other link.
func harnessgramOpenRadioDeepLink(context: AccountContext, url: String, navigationController: NavigationController?) -> Bool {
    let decision = HarnessgramRadioLink.deepLinkDecision(url, currentLink: HarnessgramRadioLink.load(), trustedHost: HarnessgramRadioLink.trustedHost(), canPresent: navigationController != nil, pairedOrigin: HarnessgramCockpitSync.shared.viewState?.bridgeOrigin)
    let openRadio: () -> Void = { [weak navigationController] in
        navigationController?.pushViewController(harnessgramRadioController(context: context))
    }
    switch decision {
    case .notRadioLink:
        return false
    case .drop:
        return true
    case .refuse, .unchanged:
        openRadio()
    case let .save(link):
        if HarnessgramRadioLink.save(link, pairedOrigin: HarnessgramCockpitSync.shared.viewState?.bridgeOrigin) {
            openRadio()
        }
    case let .confirmReplace(link, host):
        let alert = textAlertController(
            context: context,
            title: HarnessgramAgentStrings.string(.radioReplaceTitle),
            text: HarnessgramAgentStrings.string(.radioReplaceText, ["host": host]),
            actions: [
                TextAlertAction(type: .genericAction, title: HarnessgramAgentStrings.string(.radioKeep), action: {}),
                TextAlertAction(type: .defaultAction, title: HarnessgramAgentStrings.string(.radioReplace), action: {
                    if HarnessgramRadioLink.save(link, pairedOrigin: HarnessgramCockpitSync.shared.viewState?.bridgeOrigin) {
                        openRadio()
                    }
                }),
            ]
        )
        context.sharedContext.presentGlobalController(alert, nil)
    }
    return true
}
