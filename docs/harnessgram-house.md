# Harnessgram "The House": groundwork (step 0) and colours, fonts, icon (step 1)

This document describes the room interface and its integration boundaries.

## Switches
`HarnessgramSettings.houseFeature(_:)` (HarnessgramHouseFeatures.swift). One per screen (`HouseFeature`), off in code
(`houseDefaultsOn` is empty), stored in the app group with a "chosen" mark like `agentQuickActions`, so flipping a default
later never overrides the owner. Settings > Harnessgram has a "preview for me" section
(`HarnessgramHousePreviewSection`); a lane adds its case to `HarnessgramHousePreviewModel.built` when its screen exists.

## Modules
- `HarnessgramHouseCore` (Foundation only): `HouseColors` palette (equal to tokens.json, held by a HouseKit test),
  `HouseRoom`, `HouseRoomsResolver`, `HouseHomeState`, `HouseWaitingItem`, `HouseGreeting`, `HouseRoomsSummary`.
- `HarnessgramHouseKit` (SwiftUI/UIKit, app + widget): `HouseTokens`, `HouseFont` and `.houseFont(_:)` (UIFontMetrics),
  `ArchShape`, `WindowStatusView`, `ProgressRuler`, `LanternBadge`, `HouseButtonStyle`, `HouseCard`, `HouseArtStore`,
  `HouseArtFitter`. Art catalog: `Resources/HarnessgramHouse.xcassets`, rebuilt by `Resources/make-house-assets.sh`.
- `HarnessgramHouseUI` (app only, `TelegramUI/Components`): one subfolder per lane; `Shared/HouseHostingController`.

## Native first
Use Telegram's own components and the presentation theme (ItemListController, chat-list nodes, sheets, context menus).
SwiftUI only where Telegram has no equivalent. Compare every screen with the concept and a neighbouring stock screen.

## Theme (step 1)
`TelegramPresentationData/Sources/HarnessgramHouseTheme.swift`: `makeHousePresentationTheme(base:)` recolours the theme
Telegram already resolved (stone for light, night for dark; sunset auto-night included), keeping `name`, `index` and
`referenceTheme`. `harnessgramHouseApply(_:)` wraps the four `PresentationData` return paths in `PresentationData.swift`;
`harnessgramHouseRefreshing(_:)` re-emits when the `.theme` switch changes, so no restart is needed.

## Upstream hook lines (all no-ops until a lane fills them in)
- `TelegramRootController.addRootControllers` / `updateRootControllers`: `harnessgramHouseTabs(...)`.
- `ApplicationContext`: `harnessgramHouseObserveTabs`, `harnessgramHouseKnockIntercept`, `harnessgramHouseOnboardingIfNeeded`.
- `ChatController`: `harnessgramHouseReading(...)` before `isFirstTime`.
- `PresentationData.swift`: `harnessgramHouseApply`, `harnessgramHouseRefreshing`.
- Hook bodies: `HarnessgramHouseTabsHook.swift`, `...KnockHook.swift`, `...OnboardingHook.swift`, `...ReadingHook.swift`.

## Cockpit additions
`roomChannelId` on Decision, Agent and Progress; optional `kind` and `options` on Decision (the bridge fills them later);
`HarnessgramCockpitStore.loadOpenDecisions()` (app-only, uncapped; the widget snapshot keeps 5);
`HarnessgramCockpitSync.snapshotDidChangeNotification`, `pollWhileVisible(context:)`, and the simulator demo feed
`HARNESSGRAM_DEMO_HOUSE=1` (`startHouseDemoIfRequested()`, to be called next to the Live Activity demo).

## Icon
`Telegram/Telegram-iOS/HouseIcon.alticon` is offered from the preview section (`setAlternateIconName("HouseIcon")`). The
primary icon is unchanged: the owner approves the swap, then `HarnessgramAppIcon.xcassets` takes `assets/app-icon.png`
and Telegram's alternates are removed (build plan, step 1).

## Open items
- Welcome screen (step 8, onboarding): the subtitle runs edge to edge with no side gutter (owner rule: at least 16 pt
  on phones), and its copy is English. Step 8 gives it Hebrew copy and proper gutters. Seen in the build 16/17
  simulator shots.
- The "H" letter on the welcome screen is a placeholder until the icon art is approved.
