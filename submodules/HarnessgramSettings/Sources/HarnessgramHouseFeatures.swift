import Foundation

/// The House: one switch per screen. Each reads from the app group defaults (so widgets see it too), is off in code
/// at first ("preview for me", the owner turns a screen on in Settings > Harnessgram), and follows the
/// `agentQuickActions` "chosen" pattern: a stored value counts only when the owner chose it himself, so turning a
/// default on later never overrides a choice he made.
public enum HouseFeature: String, CaseIterable, Sendable {
    case theme
    case homeTab
    case radioTab
    case knock
    case waitingList
    case room
    case readingView
    case liveSurfaces
    case radioScreen
    case carPlay
    case connect
    case lifeRooms
    case onboarding
    case settingsRestyle
    /// The native Cockpit: the Cockpit tab drawn by the app instead of the tower page, and its home screen.
    case nativeCockpit
    /// The native Cockpit answers decisions itself (Face ID for anything not routine). Off: it lists them only.
    case nativeDecisions

    var key: HarnessgramSettings.Key {
        switch self {
        case .theme: return .houseTheme
        case .homeTab: return .houseHomeTab
        case .radioTab: return .houseRadioTab
        case .knock: return .houseKnock
        case .waitingList: return .houseWaitingList
        case .room: return .houseRoom
        case .readingView: return .houseReadingView
        case .liveSurfaces: return .houseLiveSurfaces
        case .radioScreen: return .houseRadioScreen
        case .carPlay: return .houseCarPlay
        case .connect: return .houseConnect
        case .lifeRooms: return .houseLifeRooms
        case .onboarding: return .houseOnboarding
        case .settingsRestyle: return .houseSettingsRestyle
        case .nativeCockpit: return .houseNativeCockpit
        case .nativeDecisions: return .houseNativeDecisions
        }
    }

    var chosenKey: HarnessgramSettings.Key {
        switch self {
        case .theme: return .houseThemeChosen
        case .homeTab: return .houseHomeTabChosen
        case .radioTab: return .houseRadioTabChosen
        case .knock: return .houseKnockChosen
        case .waitingList: return .houseWaitingListChosen
        case .room: return .houseRoomChosen
        case .readingView: return .houseReadingViewChosen
        case .liveSurfaces: return .houseLiveSurfacesChosen
        case .radioScreen: return .houseRadioScreenChosen
        case .carPlay: return .houseCarPlayChosen
        case .connect: return .houseConnectChosen
        case .lifeRooms: return .houseLifeRoomsChosen
        case .onboarding: return .houseOnboardingChosen
        case .settingsRestyle: return .houseSettingsRestyleChosen
        case .nativeCockpit: return .houseNativeCockpitChosen
        case .nativeDecisions: return .houseNativeDecisionsChosen
        }
    }
}

extension HarnessgramSettings {
    /// The screens that are on for everyone who has not chosen. Owner-first (coordinator, build 18 fix): the owner is
    /// the only user, so every House screen built so far is on; a switch he turned off himself stays off (its chosen
    /// mark wins). The home tab joins when lane A lands. Build 34: the native Cockpit is on by default (owner: the new
    /// features must be one tap from the main screen); its answering switch stays separate.
    public static let houseDefaultsOn: Set<HouseFeature> = [.theme, .radioScreen, .knock, .waitingList, .nativeCockpit]

    /// Whether a House screen is on: the owner's own choice when he made one, otherwise `houseDefaultsOn`.
    public func houseFeature(_ feature: HouseFeature) -> Bool {
        return self.houseFeature(feature, defaultsOn: HarnessgramSettings.houseDefaultsOn)
    }

    /// The same with an explicit default set (tests flip the default without touching the shipped one).
    public func houseFeature(_ feature: HouseFeature, defaultsOn: Set<HouseFeature>) -> Bool {
        let fallback = defaultsOn.contains(feature)
        guard self.bool(feature.chosenKey, default: false) else {
            return fallback
        }
        return self.bool(feature.key, default: fallback)
    }

    /// The owner's choice. It sets the chosen mark, so a later change of the default never overrides it.
    public func setHouseFeature(_ feature: HouseFeature, _ on: Bool) {
        self.defaults.set(true, forKey: feature.chosenKey.rawValue)
        self.set(on, for: feature.key)
    }

    /// Forgets the owner's choice: the screen follows `houseDefaultsOn` again.
    public func resetHouseFeature(_ feature: HouseFeature) {
        self.defaults.removeObject(forKey: feature.chosenKey.rawValue)
        self.set(nil, for: feature.key)
    }
}
