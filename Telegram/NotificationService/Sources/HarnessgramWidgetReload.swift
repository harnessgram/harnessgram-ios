import Foundation
import WidgetKit
import TelegramCore
import HarnessgramAgent
import HarnessgramCockpitKit

/// A notification from the bridge: the pinned bridge bot's private chat or a forum group the bridge runs agent sessions in.
func harnessgramIsBridgeNotification(_ peerId: EnginePeer.Id) -> Bool {
    let id = peerId.id._internalGetInt64Value()
    if peerId.namespace == Namespaces.Peer.CloudUser {
        return HarnessgramAgentChat.isBridgeBot(userId: id)
    }
    if peerId.namespace == Namespaces.Peer.CloudChannel {
        return HarnessgramAgentGroups.current().contains(channelId: id)
    }
    return false
}

/// Asks WidgetKit to reload the Cockpit widgets (Today and "ממתין לך") after an allowed bridge notification, at most
/// once per widget every five minutes (HarnessgramWidgetReloadThrottle); the widgets' 15-minute timeline stays the fallback.
func harnessgramReloadBridgeWidgets(peerId: EnginePeer.Id, allowed: Bool) {
    guard allowed, harnessgramIsBridgeNotification(peerId) else {
        return
    }
    if #available(iOS 17.0, *) {
        for kind in HarnessgramWidgetReloadThrottle().claimBridgeKinds() {
            WidgetCenter.shared.reloadTimelines(ofKind: kind)
        }
    }
}
