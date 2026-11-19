import Foundation
import UIKit
import TelegramPresentationData
import DeviceAccess

enum ApplicationShortcutItemType: String {
    case search
    case compose
    case camera
    case savedMessages
    case account
    case appIcon
    /// Harnessgram: opens the Radio screen and plays the team radio.
    case radio
}

struct ApplicationShortcutItem: Equatable {
    let type: ApplicationShortcutItemType
    let title: String
    let subtitle: String?
}

@available(iOS 9.1, *)
extension ApplicationShortcutItem {
    func shortcutItem() -> UIApplicationShortcutItem {
        let icon: UIApplicationShortcutIcon
        switch self.type {
            case .search:
                icon = UIApplicationShortcutIcon(type: .search)
            case .compose:
                icon = UIApplicationShortcutIcon(type: .compose)
            case .camera:
                icon = UIApplicationShortcutIcon(templateImageName: "Shortcuts/Camera")
            case .savedMessages:
                icon = UIApplicationShortcutIcon(templateImageName: "Shortcuts/SavedMessages")
            case .account:
                icon = UIApplicationShortcutIcon(templateImageName: "Shortcuts/Account")
            case .appIcon:
                icon = UIApplicationShortcutIcon(templateImageName: "Shortcuts/AppIcon")
            case .radio:
                icon = UIApplicationShortcutIcon(systemImageName: "radio")
        }
        return UIApplicationShortcutItem(type: self.type.rawValue, localizedTitle: self.title, localizedSubtitle: self.subtitle, icon: icon, userInfo: nil)
    }
}

func applicationShortcutItems(strings: PresentationStrings, otherAccountName: String?) -> [ApplicationShortcutItem] {
    // Harnessgram: the team radio comes first (iOS shows four quick actions); New Message gives way, the
    // compose button stays one tap away in the chat list.
    let radio = ApplicationShortcutItem(type: .radio, title: harnessgramRadioShortcutTitle, subtitle: nil)
    if let otherAccountName = otherAccountName {
        return [
            radio,
            ApplicationShortcutItem(type: .search, title: strings.Common_Search, subtitle: nil),
            ApplicationShortcutItem(type: .savedMessages, title: strings.Conversation_SavedMessages, subtitle: nil),
            ApplicationShortcutItem(type: .account, title: strings.Shortcut_SwitchAccount, subtitle: otherAccountName)
        ]
    } else {
        return [
            radio,
            ApplicationShortcutItem(type: .search, title: strings.Common_Search, subtitle: nil),
            ApplicationShortcutItem(type: .compose, title: strings.Compose_NewMessage, subtitle: nil),
            ApplicationShortcutItem(type: .savedMessages, title: strings.Conversation_SavedMessages, subtitle: nil)
        ]
    }
}
