import Foundation
import UIKit
import Display
import TelegramCore
import HarnessgramSettings
import HarnessgramAgent

/// Harnessgram: a topic of an agent group gets a small coloured dot before its name, from the state icon
/// the bridge puts there (working, waiting for you, done). Any other topic, or the switch off, keeps
/// Telegram's plain title. The name itself is never changed.
func harnessgramTopicTitle(_ title: String, chatPeer: EnginePeer?, font: UIFont, textColor: UIColor) -> NSAttributedString {
    let plain = NSAttributedString(string: title, font: font, textColor: textColor)
    guard HarnessgramSettings.shared.topicStatusDots, case let .channel(channel) = chatPeer, channel.flags.contains(.isForum) else {
        return plain
    }
    guard HarnessgramAgentGroups.current().contains(channelId: channel.id.id._internalGetInt64Value()), let status = HarnessgramTopicStatus.from(title: title) else {
        return plain
    }
    let dotFont = UIFont.systemFont(ofSize: floor(font.pointSize * 0.7))
    let result = NSMutableAttributedString(string: HarnessgramTopicStatus.dotText, attributes: [
        .font: dotFont,
        .foregroundColor: UIColor(rgb: harnessgramTopicDotRGB(status, textColor: textColor)),
        .baselineOffset: floor((font.pointSize - dotFont.pointSize) * 0.3),
    ])
    result.append(plain)
    return result
}

/// The dot's colour: Telegram's own, or the House palette (working green, waiting amber, done olive) while the House
/// theme is on. Light text on the row means a night theme, dark text a light one.
private func harnessgramTopicDotRGB(_ status: HarnessgramTopicStatus, textColor: UIColor) -> UInt32 {
    var red: CGFloat = 0.0
    var green: CGFloat = 0.0
    var blue: CGFloat = 0.0
    textColor.getRed(&red, green: &green, blue: &blue, alpha: nil)
    return status.rgb(house: HarnessgramSettings.shared.houseFeature(.theme), darkAppearance: (red + green + blue) / 3.0 > 0.5)
}
