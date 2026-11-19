import Foundation
import UIKit
import SwiftUI
import Display
import HarnessgramSettings

/// Build 23 (PART G): "להפעיל מחדש עכשיו". Saves what is pending, shows a short countdown sheet that says what will
/// happen, then closes the app cleanly (to the home screen first, then the process ends). The owner opens it again
/// from the home screen.
///
/// TODO(App Store review): closing the app on purpose is fine for TestFlight builds but Apple's guidelines discourage
/// it in App Store builds; before an App Store submission, replace the close with the banner alone ("open the app again").
enum HarnessgramRestartStrings {
    static let fontBanner = "הגופן החדש יוחל במלואו אחרי פתיחה מחדש של האפליקציה."
    static let genericBanner = "השינוי יוחל במלואו אחרי פתיחה מחדש של האפליקציה."
    static let button = "להפעיל מחדש עכשיו"
    static let sheetTitle = "חוזרים למגדל"
    static let sheetBody = "האפליקציה תיסגר. פתח אותה שוב מהמסך הראשי."
    static let cancel = "ביטול"
    static func countdown(_ seconds: Int) -> String {
        return "נסגרת בעוד " + "\(seconds)"
    }
}

final class HarnessgramRestartModel: ObservableObject {
    @Published var seconds = 3
    var cancelled = false
}

struct HarnessgramRestartSheet: View {
    @ObservedObject var model: HarnessgramRestartModel
    let cancel: () -> Void

    var body: some View {
        VStack(spacing: 16.0) {
            Image(systemName: "arrow.clockwise.circle.fill")
                .font(.system(size: 46.0))
                .foregroundColor(.orange)
                .accessibilityHidden(true)
            Text(HarnessgramRestartStrings.sheetTitle)
                .font(.title2.weight(.semibold))
            Text(HarnessgramRestartStrings.sheetBody)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text(HarnessgramRestartStrings.countdown(self.model.seconds))
                .font(.headline.monospacedDigit())
                .foregroundColor(.secondary)
            Button(HarnessgramRestartStrings.cancel, action: self.cancel)
                .buttonStyle(.bordered)
        }
        .padding(24.0)
        .environment(\.layoutDirection, .rightToLeft)
    }
}

/// Shows the countdown over `controller` and closes the app when it ends (unless cancelled).
func harnessgramRestartApp(from controller: UIViewController?) {
    guard let controller else {
        return
    }
    let model = HarnessgramRestartModel()
    weak var sheet: UIHostingController<HarnessgramRestartSheet>?
    let host = UIHostingController(rootView: HarnessgramRestartSheet(model: model, cancel: {
        model.cancelled = true
        sheet?.dismiss(animated: true)
    }))
    sheet = host
    host.modalPresentationStyle = .formSheet
    if let presentation = host.sheetPresentationController {
        presentation.detents = [.medium()]
    }
    controller.present(host, animated: true)

    func tick() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: {
            guard !model.cancelled else {
                return
            }
            if model.seconds > 1 {
                model.seconds -= 1
                tick()
            } else {
                harnessgramCloseApp()
            }
        })
    }
    tick()
}

private func harnessgramCloseApp() {
    // Everything Harnessgram keeps is in the app group's defaults; write it out before the process ends.
    HarnessgramSettings.appGroupDefaults().synchronize()
    UserDefaults.standard.synchronize()
    // To the home screen first (as the home button does), so the close looks like leaving the app, then end.
    UIControl().sendAction(#selector(URLSessionTask.suspend), to: UIApplication.shared, for: nil)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: {
        exit(0)
    })
}
