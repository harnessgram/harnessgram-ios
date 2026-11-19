import Foundation
import Display
import AccountContext
import HarnessgramSettingsUI

/// Harnessgram: the home-screen quick action "שידורי הקוקפיט" (long-press the app icon). One tap opens the Radio
/// screen and starts the saved listen link; without a saved link the screen opens and explains where to get one.
/// Lock screen and Control Center controls are the radio's own (HarnessgramRadioPlayer).
func harnessgramOpenRadioFromShortcut(context: AccountContext, navigationController: NavigationController) {
    navigationController.pushViewController(harnessgramRadioController(context: context))
    if HarnessgramRadioPlayer.shared.state != .playing {
        HarnessgramRadioPlayer.shared.play(audioSession: context.sharedContext.mediaManager.audioSession)
    }
}

/// The quick action's title (Hebrew, as the rest of the Harnessgram copy).
let harnessgramRadioShortcutTitle = "שידורי הקוקפיט"
