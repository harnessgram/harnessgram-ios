import Foundation

/// When a Harnessgram setting takes effect (build 23, owner: "applying the font requires restarting, I didn't know"). Every
/// key declares it (an exhaustive switch, so a new key does not build without one), and the settings pages show the
/// restart banner by themselves for the keys that need it.
public enum HarnessgramSettingApply: String, Sendable {
    /// Shows at once, everywhere.
    case live
    /// Shows at once in new screens; a chat that is already open shows it after it is opened again.
    case reopenChat
    /// Shows in part at once; fully only after the app is opened again (the restart banner offers that).
    case restart
    /// Not a choice the owner sees (stored places, identities, marks).
    case internalState
}

extension HarnessgramSettings.Key {
    public var apply: HarnessgramSettingApply {
        switch self {
        case .appFont:
            // Display's font helpers are swapped at once and the screens rebuild, but text that a screen drew earlier with
            // its own cached font keeps the old family until the next launch.
            return .restart
        case .messageFont, .separateMessageFont, .fontWeight, .textSizeSteps, .bubbleWidth, .lineSpacing, .justifiedText:
            return .reopenChat
        case .theme, .houseTheme, .cockpitTab, .cockpitFloatingButton, .cockpitAppBadge, .agentQuickActions, .topicStatusDots,
             .confirmSensitiveButtons, .recordWithBuiltInMic, .autoDownloadInApprovedChats, .connectThroughHomeRelay,
             .houseHomeTab, .houseRadioTab, .houseKnock, .houseWaitingList, .houseRoom, .houseReadingView, .houseLiveSurfaces,
             .houseRadioScreen, .houseCarPlay, .houseConnect, .houseLifeRooms, .houseOnboarding, .houseSettingsRestyle,
             .houseNativeCockpit, .houseNativeDecisions:
            return .live
        case .agentQuickActionsChosen, .agentProjectGroups, .bridgeBotId, .bridgeBotPendingId, .bridgeBotIdSource,
             .houseThemeChosen, .houseHomeTabChosen, .houseRadioTabChosen, .houseKnockChosen, .houseWaitingListChosen,
             .houseRoomChosen, .houseReadingViewChosen, .houseLiveSurfacesChosen, .houseRadioScreenChosen, .houseCarPlayChosen,
             .houseConnectChosen, .houseLifeRoomsChosen, .houseOnboardingChosen, .houseSettingsRestyleChosen,
             .houseNativeCockpitChosen, .houseNativeDecisionsChosen,
             .cockpitFloatingButtonSide, .cockpitFloatingButtonY, .oneFontMigrated:
            return .internalState
        }
    }
}

extension HarnessgramSettings {
    private func launchValue(_ key: Key) -> String {
        return self.defaults.object(forKey: key.rawValue).map { "\($0)" } ?? ""
    }

    /// Takes the launch snapshot of the restart-needing keys (the app calls it at start; later calls do nothing).
    public func rememberLaunchValues() {
        self.restartLaunchLock.lock()
        defer { self.restartLaunchLock.unlock() }
        guard self.restartLaunchValues == nil else {
            return
        }
        var values: [Key: String] = [:]
        for key in Key.allCases where key.apply == .restart {
            values[key] = self.launchValue(key)
        }
        self.restartLaunchValues = values
    }

    /// Whether `key` changed since launch and needs the app to be opened again to show fully.
    public func waitsForRestart(_ key: Key) -> Bool {
        guard key.apply == .restart else {
            return false
        }
        self.rememberLaunchValues()
        self.restartLaunchLock.lock()
        let launched = self.restartLaunchValues?[key]
        self.restartLaunchLock.unlock()
        return launched != nil && launched != self.launchValue(key)
    }

    /// Any restart-needing setting changed since launch.
    public var waitsForRestart: Bool {
        return Key.allCases.contains { self.waitsForRestart($0) }
    }
}
