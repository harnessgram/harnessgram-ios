import Foundation
import UIKit
import SwiftUI
import Display
import TelegramCore
import AccountContext

final class HarnessgramMediaLevelModel: ObservableObject {
    let peerId: EnginePeer.Id
    let accountPeerId: EnginePeer.Id
    @Published private(set) var level: HarnessgramPolicy.MediaLevel?

    init(peerId: EnginePeer.Id, accountPeerId: EnginePeer.Id) {
        self.peerId = peerId
        self.accountPeerId = accountPeerId
        self.level = HarnessgramPolicyStore.shared.configurableMediaLevel(forChat: peerId, accountPeerId: accountPeerId)
    }

    func select(_ level: HarnessgramPolicy.MediaLevel) {
        guard self.level != nil else {
            return
        }
        // The default level is "all"; choosing it clears the chat's own setting.
        HarnessgramPolicyStore.shared.setMediaLevel(level == HarnessgramPolicy.approvedChatMedia ? nil : level, forChat: self.peerId, accountPeerId: self.accountPeerId)
        self.level = HarnessgramPolicyStore.shared.configurableMediaLevel(forChat: self.peerId, accountPeerId: self.accountPeerId)
    }
}

func harnessgramMediaLevelTitle(_ level: HarnessgramPolicy.MediaLevel) -> String {
    switch level {
    case .textOnly:
        return HarnessgramStrings.t(.mediaLevelTextOnly)
    case .photos:
        return HarnessgramStrings.t(.mediaLevelPhotos)
    case .documents:
        return HarnessgramStrings.t(.mediaLevelDocuments)
    case .all:
        return HarnessgramStrings.t(.mediaLevelAll)
    }
}

struct HarnessgramMediaLevelView: View {
    @ObservedObject var model: HarnessgramMediaLevelModel
    private let levels: [HarnessgramPolicy.MediaLevel] = [.all, .documents, .photos, .textOnly]

    var body: some View {
        Form {
            if let current = self.model.level {
                Section(footer: Text(HarnessgramStrings.t(.mediaLevelFooter))) {
                    ForEach(self.levels, id: \.self) { level in
                        Button(action: {
                            self.model.select(level)
                        }) {
                            HStack {
                                Text(harnessgramMediaLevelTitle(level) + (level == HarnessgramPolicy.approvedChatMedia ? " (" + HarnessgramStrings.t(.mediaLevelDefault) + ")" : ""))
                                    .foregroundColor(.primary)
                                Spacer()
                                if level == current {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.accentColor)
                                }
                            }
                        }
                    }
                }
            } else {
                Section {
                    Text(HarnessgramStrings.t(.mediaLevelNotApproved))
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

/// The chat info page's "Media level" row. It only tightens or loosens an approved chat's own media
/// level for this account; an unapproved chat gets no choice (the store never approves a chat).
public func harnessgramChatMediaLevelController(context: AccountContext, peerId: EnginePeer.Id) -> ViewController {
    let model = HarnessgramMediaLevelModel(peerId: peerId, accountPeerId: context.account.peerId)
    return HarnessgramHostingScreen(context: context, title: HarnessgramStrings.t(.mediaLevelTitle), content: HarnessgramMediaLevelView(model: model))
}

/// The row's label: this chat's current level, or nil when no choice is offered.
public func harnessgramChatMediaLevelLabel(context: AccountContext, peerId: EnginePeer.Id) -> String? {
    return HarnessgramPolicyStore.shared.configurableMediaLevel(forChat: peerId, accountPeerId: context.account.peerId).map(harnessgramMediaLevelTitle)
}

public let harnessgramChatMediaLevelRowTitle: String = HarnessgramStrings.t(.mediaLevelTitle)
public let harnessgramSettingsRowTitle: String = HarnessgramStrings.t(.settingsTitle)
