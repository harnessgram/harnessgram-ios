import Foundation
import TelegramCore
import AccountContext
import ChatPresentationInterfaceState
import ChatInterfaceState
import ChatControllerInteraction
import UIKit
import ChatInputContextPanelNode
import HarnessgramSettings
import HarnessgramAgent
import HarnessgramAgentRibbonPanelNode
import Display
import PresentationDataUtils

/// Harnessgram: the agent quick-action ribbon, offered while no input suggestion panel is up. Nil keeps
/// Telegram's behaviour (no panel).
func harnessgramAgentRibbonPanel(_ state: ChatPresentationInterfaceState, context: AccountContext, currentPanel: ChatInputContextPanelNode?, interfaceInteraction: ChatPanelInterfaceInteraction?, chatPresentationContext: ChatPresentationContext) -> ChatInputContextPanelNode? {
    var channelId: Int64?
    var isForum = false
    if let channel = state.renderedPeer?.peer as? TelegramChannel {
        channelId = channel.id.id._internalGetInt64Value()
        isForum = channel.flags.contains(.isForum)
    }
    var isInputPanelOccupied = false
    switch state.inputMode {
    case .none, .text:
        break
    case .media, .inputButtons:
        isInputPanelOccupied = true
    }
    let ribbonContext = HarnessgramAgentRibbon.Context(
        channelId: channelId,
        isForum: isForum,
        threadId: state.chatLocation.threadId,
        composeTextIsEmpty: state.interfaceState.composeInputState.content.plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
        isEditingMessage: state.editMessageState != nil,
        isRecordingMedia: state.inputTextPanelState.mediaRecordingState != nil,
        isSearching: state.search != nil,
        isSelectingMessages: state.interfaceState.selectionState != nil,
        hasSubject: state.subject != nil,
        isInputPanelOccupied: isInputPanelOccupied
    )
    guard HarnessgramAgentRibbon.isShown(ribbonContext, enabled: HarnessgramSettings.shared.agentQuickActions, groups: HarnessgramAgentGroups.current()) else {
        return nil
    }
    if let currentPanel = currentPanel as? HarnessgramAgentRibbonPanelNode {
        return currentPanel
    }
    let panel = HarnessgramAgentRibbonPanelNode(context: context, theme: state.theme, strings: state.strings, fontSize: state.fontSize, chatPresentationContext: chatPresentationContext)
    panel.sendText = { [weak interfaceInteraction] text in
        (interfaceInteraction?.chatController() as? ChatControllerImpl)?.harnessgramSendAgentText(text)
    }
    panel.confirmAction = { [weak interfaceInteraction] _, send in
        // Stop asks first: a mistaken tap on the row must not stop a running session.
        guard let controller = interfaceInteraction?.chatController() as? ChatControllerImpl else {
            return
        }
        controller.present(textAlertController(context: context, title: nil, text: HarnessgramAgentStrings.string(.ribbonStopConfirmText), actions: [
            TextAlertAction(type: .genericAction, title: HarnessgramAgentStrings.string(.ribbonStopCancel), action: {}),
            TextAlertAction(type: .destructiveAction, title: HarnessgramAgentStrings.string(.ribbonStopConfirm), action: send)
        ]), in: .window(.root))
    }
    panel.requestRelayout = { [weak interfaceInteraction] in
        // The layout asks for the context panel again; with the switch off it gets none and drops the ribbon.
        (interfaceInteraction?.chatController() as? ChatControllerImpl)?.chatDisplayNode.requestLayout(.animated(duration: 0.2, curve: .easeInOut))
    }
    return panel
}

/// The room the chat keeps free above its input panels for the ribbon (0 when it is not shown).
func harnessgramAgentRibbonReservedHeight(_ panel: ChatInputContextPanelNode?) -> CGFloat {
    return panel is HarnessgramAgentRibbonPanelNode ? HarnessgramAgentRibbonPanelNode.reservedHeight : 0.0
}

extension ChatControllerImpl {
    /// Sends one ribbon text into the open topic, never as a reply: the owner's pending reply stays as it is.
    func harnessgramSendAgentText(_ text: String) {
        guard canSendMessagesToChat(self.presentationInterfaceState) else {
            return
        }
        self.sendMessages([.message(text: text, attributes: [], inlineStickers: [:], mediaReference: nil, threadId: self.chatLocation.threadId, replyToMessageId: nil, replyToStoryId: nil, localGroupingKey: nil, correlationId: nil, bubbleUpEmojiOrStickersets: [])])
    }
}
