# Harnessgram "The House": the knock and the waiting list (step 3, lane D)

This document describes the room interface and its integration boundaries.

## What runs where
- **Hook** (`TelegramUI/Sources/HarnessgramHouseKnockHook.swift`): `ApplicationContext` calls it before Telegram's banner. It
  reads the message and applies `HouseKnockRule` (HarnessgramHouseCore): the pinned bridge bot (by user id), not a
  forward, not "via" another bot, in the bot's private chat or a topic of an agent group, and the message carries inline
  buttons or a bridge widget. True means "no banner"; the knock center takes over.
- **Center** (`HarnessgramHouseUI/Knock/HouseKnockCenter`): forces a Cockpit refresh, compares the open decisions
  (`HarnessgramCockpitStore.loadOpenDecisions`) with the ledger (`HouseKnockLedger`: ids that already knocked, in
  UserDefaults per account, kept 14 days, capped at 400) and shows one sheet per new decision, at most 3 per poke, one at a
  time. A decision knocks once, also after a relaunch. "אחר כך" is the same as knocked: it stays in the list.
  The first comparison on a phone (no history) knocks only the newest open decision and records the rest silently.
- **Fallback for the banner**: if the Cockpit lists nothing new within 2.5 s (not paired, slow refresh), the sheet shows the
  bridge message's first line with "לפתוח את החדר" only, so the question is never lost. A decision that arrives later
  (within 20 s) still knocks.
- **Sheet** (`HouseKnockSheetController`, SwiftUI inside a Display overlay): arched cedar top, knocker drawn in code,
  room chip, question on a parchment card, Approve / "אחר כך" / "לפתוח את החדר". Two light haptic taps 120 ms apart,
  then a 320 ms spring; Reduce Motion gives a 150 ms fade. Swipe down, tap outside or VoiceOver escape = later.
- **Face ID**: `HouseWaitingRowPlan` (HarnessgramHouseCore) follows the widget's `HarnessgramDecisionGate`. A sensitive
  decision (and every decision without the bridge's mark: fail closed) is never answered in place; its Approve button
  carries the Face ID glyph and opens the app flow (`harnessgram://widget/decide?id=...`, same as the widgets: fresh Cockpit
  lookup, alert, then Face ID or passcode through `HarnessgramOwnerConfirmation`, then the answer). A plain yes/no decision is
  answered in place (`HouseDecisionActions.answer`, with a fresh login when the stored one is too old); if that cannot be
  done the app flow answers with the same choice. A question with more than two answers opens its room ("לבחור").
- **Waiting list** (`HarnessgramHouseUI/Waiting`, `makeHouseWaitingListController(context:)`,
  `openHouseWaitingList(context:)`): a pushed screen under Telegram's own navigation bar, SwiftUI rows with the room art,
  window dot, question and the actions above. It shows every open decision from the app-only full list, refreshes through
  `HarnessgramCockpitSync.pollWhileVisible` while on screen and follows `snapshotDidChangeNotification`.

## For the other lanes
Home's doorway calls `openHouseWaitingList(context:)` while `.waitingList` is on (with it off, the doorway opens the bridge
bot's chat). HouseHostingController could set `accessibilityLanguage = "he-IL"` on its hosting view so VoiceOver reads the
waiting list in Hebrew on an English phone (the knock sheet sets it itself).

## Not done
- 3b, the long-press notification view (optional in the plan).
- The agent's name in "{agent} דופק בדלת" needs the bridge to send it; the title is "דפיקה בדלת" until then
  (`HouseKnockItem.agentName`).
- Decisions beyond the Cockpit snapshot's newest five cannot be answered by the widget deep link (it looks the decision
  up in the capped snapshot); the in-place answer does not have that limit.
