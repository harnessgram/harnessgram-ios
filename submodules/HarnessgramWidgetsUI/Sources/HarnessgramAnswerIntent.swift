import Foundation
import AppIntents
import WidgetKit
import HarnessgramCockpitKit

/// Approve or Decline on the widget. iOS runs it only on an unlocked phone (authenticationPolicy), the
/// login it needs cannot be read while the phone is locked, and HarnessgramWidgetAnswer refuses any
/// sensitive decision, so nothing sensitive is ever approved from the widget.
@available(iOS 17.0, *)
public struct HarnessgramAnswerIntent: AppIntent {
    public static let title: LocalizedStringResource = "תשובה להחלטה"
    public static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    public static let isDiscoverable: Bool = false

    @Parameter(title: "החלטה")
    public var decisionId: String

    @Parameter(title: "תשובה")
    public var choice: String

    public init() {
    }

    public init(decisionId: String, choice: HarnessgramCockpitLinks.Choice) {
        self.decisionId = decisionId
        self.choice = choice.rawValue
    }

    public func perform() async throws -> some IntentResult {
        // The answer runner validates the decision ID and current real session.
        _ = await HarnessgramWidgetAnswer.run(id: self.decisionId, choice: self.choice, store: .shared, client: HarnessgramCockpitClient(), now: Date())
        WidgetCenter.shared.reloadTimelines(ofKind: HarnessgramWidgetKind.waiting)
        return .result()
    }
}
