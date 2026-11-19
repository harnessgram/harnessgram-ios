#if arch(arm64) || arch(x86_64)

import SwiftUI
import WidgetKit
import HarnessgramWidgetsUI

/// Harnessgram: Telegram's chat-list widget limited to the bridge's chats (build 18, HarnessgramChatWidget), the
/// "waiting for you" and Today widgets, and the agent task Live Activity (submodules/HarnessgramWidgetsUI). The avatars widget is
/// not offered. iOS 17 and later.
@available(iOSApplicationExtension 17.0, iOS 17.0, *)
struct HarnessgramAllWidgets: WidgetBundle {
    var body: some Widget {
        Static_Widget()
        HarnessgramWaitingWidget()
        HarnessgramTodayWidget()
        HarnessgramTaskLiveActivityWidget()
    }
}

/// iOS 18 and later: the same widgets, with the task Live Activity also offered to CarPlay and the Apple Watch Smart
/// Stack (its small family, build 22). A bundle of its own because a WidgetBundle cannot choose one of two widgets by
/// OS version, and both must never be registered (one activity configuration per attributes type).
@available(iOSApplicationExtension 18.0, iOS 18.0, *)
struct HarnessgramAllWidgetsWithSupplementalFamilies: WidgetBundle {
    var body: some Widget {
        Static_Widget()
        HarnessgramWaitingWidget()
        HarnessgramTodayWidget()
        HarnessgramTaskLiveActivityWidgetWithSupplementalFamilies()
    }
}

#endif
