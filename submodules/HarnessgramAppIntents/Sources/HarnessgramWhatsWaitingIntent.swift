import Foundation
import AppIntents
import HarnessgramCockpitKit

/// Linked into the main app (Telegram/BUILD app_intents), where App Shortcuts must live.
/// CarPlay phase 1 (issue #4, no CarPlay entitlement needed): Siri answers "what waits for me" by voice, in the car
/// too. It only reads: nothing is answered, opened or sent. Sensitive decisions are never read by title
/// (HarnessgramCarSummary). Runs only on an unlocked phone (authenticationPolicy), like the widget's answers, so a
/// locked phone never reads the owner's decisions aloud to whoever holds it.
@available(iOS 17.0, *)
public struct HarnessgramWhatsWaitingIntent: AppIntent {
    public static let title: LocalizedStringResource = "מה מחכה לי"
    public static let description = IntentDescription("מקריא כמה דברים מחכים לך בגשר, בלי פרטים רגישים.")
    public static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    public static let openAppWhenRun: Bool = false

    public init() {
    }

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let now = Date()
        // One locked read of session, snapshot and login (the widgets' rule); nothing read means "connect the bridge".
        let context = HarnessgramCockpitStore.shared.answerContext()
        let text = HarnessgramCarSummary.spokenSummary(snapshot: context?.snapshot, paired: context != nil, now: now)
        return .result(dialog: IntentDialog(stringLiteral: text))
    }
}

/// Siri phrases (each must name the app). In the car: "Hey Siri, מה מחכה לי ב־HarnessGram".
@available(iOS 17.0, *)
public struct HarnessgramAppShortcuts: AppShortcutsProvider {
    public static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: HarnessgramWhatsWaitingIntent(),
            phrases: [
                "מה מחכה לי ב־\(.applicationName)",
                "מה חדש ב־\(.applicationName)",
                "\(.applicationName) מה מחכה לי"
            ],
            shortTitle: "מה מחכה לי",
            systemImageName: "tray.full"
        )
    }
}
