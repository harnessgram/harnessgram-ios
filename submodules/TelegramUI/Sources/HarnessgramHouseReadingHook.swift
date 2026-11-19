import Foundation
import AccountContext
import TelegramCore
import TelegramPresentationData

/// Harnessgram House (plan step 0 hook): the presentation data a chat is built with. ChatController calls this just
/// before it stores the data; step 4b returns the reading-view variant (agent reports without bubbles) for agent
/// rooms behind `.readingView`. Until then, and with the switch off, it returns `presentationData` as is. Lane B owns
/// the body.
func harnessgramHouseReading(_ presentationData: PresentationData, chatLocation: ChatLocation, peer: EngineRawPeer?) -> PresentationData {
    return presentationData
}
