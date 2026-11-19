import SwiftUI
import Display
import AccountContext
import TelegramCore

private final class HarnessgramAccountPrivacyActions {
    var choose: ((HarnessgramPolicyStore.AccountPrivacyConsent) -> Void)?
}

private struct HarnessgramAccountPrivacyView: View {
    let consent: HarnessgramPolicyStore.AccountPrivacyConsent
    let actions: HarnessgramAccountPrivacyActions
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 24) {
                    self.explanation(
                        title: HarnessgramAccountPrivacyStrings.title,
                        status: HarnessgramAccountPrivacyStrings.approved,
                        paragraphs: HarnessgramAccountPrivacyStrings.details
                    )
                    self.explanation(
                        title: HarnessgramAccountPrivacyStrings.englishTitle,
                        status: HarnessgramAccountPrivacyStrings.englishApproved,
                        paragraphs: HarnessgramAccountPrivacyStrings.englishDetails
                    )
                    .environment(\.layoutDirection, .leftToRight)

                    if self.dynamicTypeSize.isAccessibilitySize {
                        self.decisionButtons
                    }
                }
                .frame(maxWidth: 520)
                .padding(24)
                .frame(maxWidth: .infinity)
            }
            if !self.dynamicTypeSize.isAccessibilitySize {
                Divider()
                self.decisionButtons
                    .frame(maxWidth: 520)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private var decisionButtons: some View {
        VStack(spacing: 8) {
            if self.consent == .granted {
                Button {
                    self.actions.choose?(.declined)
                } label: {
                    self.actionTitle(HarnessgramAccountPrivacyStrings.withdraw, english: HarnessgramAccountPrivacyStrings.englishWithdraw)
                }
                .buttonStyle(.borderless)
            } else {
                Button {
                    self.actions.choose?(.granted)
                } label: {
                    self.actionTitle(HarnessgramAccountPrivacyStrings.enable, english: HarnessgramAccountPrivacyStrings.englishEnable)
                }
                .buttonStyle(.harnessgramFilled)

                Button {
                    self.actions.choose?(.declined)
                } label: {
                    self.actionTitle(HarnessgramAccountPrivacyStrings.skip, english: HarnessgramAccountPrivacyStrings.englishSkip)
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private func explanation(title: String, status: String, paragraphs: [String]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title2.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            if self.consent == .granted {
                Text(status)
                    .font(.callout.weight(.semibold))
            }
            ForEach(paragraphs, id: \.self) { paragraph in
                Text(paragraph)
            }
        }
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func actionTitle(_ hebrew: String, english: String) -> some View {
        VStack(spacing: 4) {
            Text(hebrew).font(.body.weight(.semibold))
            Text(english)
                .font(.footnote)
                .environment(\.layoutDirection, .leftToRight)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, minHeight: 44)
        .contentShape(Rectangle())
    }
}

/// The same screen handles the first decision and later changes from Filter settings.
public func harnessgramAccountPrivacyController(context: AccountContext, firstLaunch: Bool = false) -> ViewController {
    let accountId = context.account.id
    let store = HarnessgramPolicyStore.shared
    let actions = HarnessgramAccountPrivacyActions()
    let controller = HarnessgramHostingScreen(
        context: context,
        title: HarnessgramAccountPrivacyStrings.title,
        content: HarnessgramAccountPrivacyView(consent: store.accountPrivacyConsent(accountId: accountId), actions: actions)
    )
    if firstLaunch {
        controller.setDisplayNavigationBar(false)
        controller.attemptNavigation = { _ in false }
    }
    actions.choose = { [weak controller] consent in
        guard let controller, controller.navigationController != nil else {
            return
        }
        store.setAccountPrivacyConsent(consent, accountId: accountId)
        controller.dismiss()
    }
    return controller
}
