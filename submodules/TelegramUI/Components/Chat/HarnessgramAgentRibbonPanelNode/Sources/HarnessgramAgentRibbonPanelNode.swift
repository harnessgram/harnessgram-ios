import Foundation
import UIKit
import AsyncDisplayKit
import Display
import TelegramCore
import TelegramPresentationData
import TelegramUIPreferences
import AccountContext
import ChatPresentationInterfaceState
import ChatControllerInteraction
import ChatInputContextPanelNode
import HarnessgramAgent
import HarnessgramSettings

/// Harnessgram: a slim row of agent shortcuts (Continue, Status, Summary, Stop) just above the composer,
/// in session topics of the bridge's groups. Each tap sends the bridge's own short text into the topic.
/// It sits above all input panels (reply preview included); the chat reserves `reservedHeight` below its
/// history, so the newest messages and their buttons stay above the row. Only the buttons take touches.
public final class HarnessgramAgentRibbonPanelNode: ChatInputContextPanelNode {
    /// Sends one text into the current topic (the chat's normal send path).
    public var sendText: ((String) -> Void)?
    /// Asks the owner before an action that needs confirmation (Stop); `send` runs only on his yes. Without
    /// it such an action sends nothing.
    public var confirmAction: ((HarnessgramAgentRibbon.Action, @escaping () -> Void) -> Void)?
    /// Asks the chat to lay out again: the ribbon goes away at once when its switch is turned off.
    public var requestRelayout: (() -> Void)?

    private static let rowHeight: CGFloat = HarnessgramAgentRibbon.Layout.rowHeight

    /// The height the chat keeps free above its input panels while the ribbon shows.
    public static let reservedHeight: CGFloat = HarnessgramAgentRibbon.Layout.reservedHeight
    private static let sideMargin: CGFloat = 16.0
    private static let spacing: CGFloat = 8.0

    private var buttons: [UIButton] = []
    private var rowFrame = CGRect()
    private var styledTheme: PresentationTheme?
    private var hasValidLayout = false
    private var settingsObserver: NSObjectProtocol?

    override public init(context: AccountContext, theme: PresentationTheme, strings: PresentationStrings, fontSize: PresentationFontSize, chatPresentationContext: ChatPresentationContext) {
        super.init(context: context, theme: theme, strings: strings, fontSize: fontSize, chatPresentationContext: chatPresentationContext)

        // Over all panels: `updateLayout`'s bottomInset is then the top of the input panels.
        self.placement = .overPanels
        self.isOpaque = false

        self.settingsObserver = NotificationCenter.default.addObserver(forName: HarnessgramSettings.didChangeNotification, object: nil, queue: .main, using: { [weak self] _ in
            guard let self, !HarnessgramSettings.shared.agentQuickActions else {
                return
            }
            self.requestRelayout?()
        })
    }

    deinit {
        if let settingsObserver = self.settingsObserver {
            NotificationCenter.default.removeObserver(settingsObserver)
        }
    }

    private func makeButtonsIfNeeded() {
        if !self.buttons.isEmpty {
            return
        }
        for (index, action) in HarnessgramAgentRibbon.Action.ordered.enumerated() {
            let button = UIButton(type: .custom)
            button.tag = index
            button.setTitle(action.label, for: .normal)
            button.titleLabel?.font = UIFont.systemFont(ofSize: 14.0, weight: .medium)
            button.titleLabel?.adjustsFontSizeToFitWidth = true
            button.titleLabel?.minimumScaleFactor = 0.75
            button.titleLabel?.lineBreakMode = .byTruncatingTail
            button.layer.cornerRadius = HarnessgramAgentRibbonPanelNode.rowHeight / 2.0
            button.layer.borderWidth = UIScreenPixel
            button.accessibilityLabel = action.accessibilityLabel
            button.semanticContentAttribute = .forceRightToLeft
            button.addTarget(self, action: #selector(self.buttonPressed(_:)), for: .touchUpInside)
            self.view.addSubview(button)
            self.buttons.append(button)
        }
    }

    private func applyTheme(_ theme: PresentationTheme) {
        if self.styledTheme === theme {
            return
        }
        self.styledTheme = theme
        for (index, button) in self.buttons.enumerated() {
            let action = HarnessgramAgentRibbon.Action.ordered[index]
            button.backgroundColor = theme.list.plainBackgroundColor.withAlphaComponent(0.94)
            button.layer.borderColor = theme.list.itemPlainSeparatorColor.cgColor
            let titleColor = action.isDestructive ? theme.list.itemDestructiveColor : theme.list.itemPrimaryTextColor
            button.setTitleColor(titleColor, for: .normal)
            button.setTitleColor(titleColor.withAlphaComponent(0.5), for: .highlighted)
        }
    }

    @objc private func buttonPressed(_ button: UIButton) {
        guard button.tag >= 0, button.tag < HarnessgramAgentRibbon.Action.ordered.count else {
            return
        }
        let action = HarnessgramAgentRibbon.Action.ordered[button.tag]
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let text = action.sentText
        if action.needsConfirmation {
            self.confirmAction?(action, { [weak self] in
                self?.sendText?(text)
            })
            return
        }
        self.sendText?(text)
    }

    override public func updateLayout(size: CGSize, leftInset: CGFloat, rightInset: CGFloat, bottomInset: CGFloat, transition: ContainedViewLayoutTransition, interfaceState: ChatPresentationInterfaceState) {
        self.makeButtonsIfNeeded()
        self.applyTheme(interfaceState.theme)

        let height = HarnessgramAgentRibbonPanelNode.rowHeight
        let sideLeft = HarnessgramAgentRibbonPanelNode.sideMargin + leftInset
        let sideRight = HarnessgramAgentRibbonPanelNode.sideMargin + rightInset
        let spacing = HarnessgramAgentRibbonPanelNode.spacing
        let count = CGFloat(self.buttons.count)
        let rowWidth = max(0.0, size.width - sideLeft - sideRight)
        let buttonWidth = max(0.0, floor((rowWidth - spacing * (count - 1.0)) / count))
        // bottomInset is the input panels' top edge; the row keeps its own gap above it.
        self.rowFrame = CGRect(x: sideLeft, y: HarnessgramAgentRibbon.Layout.rowOriginY(containerHeight: size.height, panelsTopInset: bottomInset), width: rowWidth, height: height)

        for (index, button) in self.buttons.enumerated() {
            // Right to left: the first action sits at the right edge.
            let slot = HarnessgramAgentStrings.isRightToLeft ? (self.buttons.count - 1 - index) : index
            let frame = CGRect(x: self.rowFrame.minX + CGFloat(slot) * (buttonWidth + spacing), y: self.rowFrame.minY, width: buttonWidth, height: height)
            transition.updateFrame(view: button, frame: frame)
        }

        if !self.hasValidLayout {
            self.hasValidLayout = true
            self.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.2)
        }
    }

    override public func animateOut(completion: @escaping () -> Void) {
        self.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.2, removeOnCompletion: false, completion: { _ in
            completion()
        })
    }

    override public func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if !self.rowFrame.contains(point) {
            return nil
        }
        for button in self.buttons where button.frame.contains(point) {
            return button
        }
        return nil
    }
}
