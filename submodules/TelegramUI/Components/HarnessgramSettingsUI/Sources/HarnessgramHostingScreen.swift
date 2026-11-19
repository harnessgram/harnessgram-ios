import Foundation
import UIKit
import SwiftUI
import AsyncDisplayKit
import Display
import SwiftSignalKit
import TelegramPresentationData
import AccountContext

/// A Telegram navigation screen that shows one SwiftUI view, laid out right to left. It follows theme changes while it
/// is open (build 22: a Harnessgram theme picked on its page applies at once, the page included). Build 23: public, so
/// the Cockpit tab (HarnessgramHouseUI) is the same kind of page; as a tab it keeps its content clear of the tab bar.
public final class HarnessgramHostingScreen<Content: View>: ViewController {
    private let hostingController: UIHostingController<AnyView>
    /// The page with its direction and the theme's accent as the SwiftUI tint (rebuilt when the theme changes).
    private let makeRoot: (UIColor) -> AnyView
    private var presentationData: PresentationData
    private var presentationDisposable: Disposable?
    /// Called with every layout the screen gets (the Cockpit tab reads its width class: Telegram splits into a list and
    /// a detail column in the regular one).
    public var layoutUpdated: ((ContainerViewLayout) -> Void)?
    /// A full-bleed dark page (the Cockpit tab's phone tower): no navigation bar (the page draws its own header under
    /// the status bar), a light status bar and the page's own dark colour behind it, whatever the Telegram theme is.
    private var fullBleedBackground: UIColor?

    public init(context: AccountContext, title: String, content: Content) {
        self.presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let makeRoot: (UIColor) -> AnyView = { accent in
            return AnyView(content.environment(\.layoutDirection, .rightToLeft).tint(SwiftUI.Color(accent)))
        }
        self.makeRoot = makeRoot
        self.hostingController = UIHostingController(rootView: makeRoot(self.presentationData.theme.list.itemAccentColor))
        super.init(navigationBarPresentationData: NavigationBarPresentationData(presentationData: self.presentationData))
        self.statusBar.statusBarStyle = self.presentationData.theme.rootController.statusBarStyle.style
        self.title = title
        self.hostingController.overrideUserInterfaceStyle = self.presentationData.theme.overallDarkAppearance ? .dark : .light
        self.presentationDisposable = (context.sharedContext.presentationData |> deliverOnMainQueue).start(next: { [weak self] presentationData in
            guard let self, presentationData.theme !== self.presentationData.theme else {
                return
            }
            self.presentationData = presentationData
            self.applyTheme()
        })
    }

    required public init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        self.presentationDisposable?.dispose()
    }

    private func applyTheme() {
        // Build 23: SwiftUI buttons, toggles and links take the theme's accent (not iOS blue), as Telegram's own lists do.
        self.hostingController.rootView = self.makeRoot(self.presentationData.theme.list.itemAccentColor)
        self.applyChrome(animated: true)
    }

    /// The full-bleed colour (a dynamic one, like the tower's page) in the theme's appearance, not the window's.
    private var resolvedFullBleedBackground: UIColor? {
        return self.fullBleedBackground?.resolvedColor(with: UITraitCollection(userInterfaceStyle: self.presentationData.theme.overallDarkAppearance ? .dark : .light))
    }

    /// The status bar, the interface style and the colour behind the page: the theme's, or the full-bleed page's.
    private func applyChrome(animated: Bool = false) {
        let fullBleed = self.fullBleedBackground
        // The hidden bar of a full-bleed page leaves no light edge fade under the status bar.
        self.setNavigationBarPresentationData(fullBleed != nil ? NavigationBarPresentationData(presentationData: self.presentationData, hideBackground: true, hideBadge: false) : NavigationBarPresentationData(presentationData: self.presentationData), animated: animated)
        // A full-bleed page (the phone tower) follows the theme too (build 31: light and dark): its own sky behind a
        // status bar of the theme's style.
        let dark = self.presentationData.theme.overallDarkAppearance
        let style: StatusBarStyle = fullBleed != nil ? (dark ? .White : .Black) : self.presentationData.theme.rootController.statusBarStyle.style
        self.statusBar.statusBarStyle = style
        // The tab bar shows its current tab's status bar style; it copies it only when the tab changes.
        if let parent = self.parent as? TabBarController, parent.currentController === self {
            parent.statusBar.statusBarStyle = style
        }
        self.hostingController.overrideUserInterfaceStyle = dark ? .dark : .light
        if self.isNodeLoaded {
            self.displayNode.backgroundColor = self.resolvedFullBleedBackground ?? self.presentationData.theme.list.blocksBackgroundColor
        }
    }

    /// Turns the full-bleed dark page on (with its background colour) or off (nil: the theme's page with its
    /// navigation bar, exactly as before).
    public func setFullBleed(background: UIColor?) {
        guard background != self.fullBleedBackground else {
            return
        }
        self.fullBleedBackground = background
        self.applyChrome()
        self.setDisplayNavigationBar(background == nil, transition: .immediate)
    }

    override public func loadDisplayNode() {
        self.displayNode = ASDisplayNode()
        self.displayNode.backgroundColor = self.resolvedFullBleedBackground ?? self.presentationData.theme.list.blocksBackgroundColor
        // Build 23 (Cockpit tab crash): the hosting view goes in here, but it becomes a UIKit child only in viewDidLoad.
        // Telegram's tab bar loads a tab's display node before UIKit gives the controller its view; a child added here
        // would then sit under the tab bar controller's view while its parent is this screen, and UIKit throws
        // UIViewControllerHierarchyInconsistency as it moves to the window. HarnessgramHostingContainmentGuardTests.
        self.hostingController.view.backgroundColor = .clear
        self.hostingController.view.semanticContentAttribute = .forceRightToLeft
        self.displayNode.view.addSubview(self.hostingController.view)
        self.displayNodeDidLoad()
    }

    override public func viewDidLoad() {
        super.viewDidLoad()
        // The display node's view is this controller's view now, so the containment is consistent wherever it sits.
        if self.hostingController.parent == nil {
            self.addChild(self.hostingController)
            self.hostingController.didMove(toParent: self)
        }
    }

    override public func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        let top = self.navigationLayout(layout: layout).navigationFrame.maxY
        transition.updateFrame(view: self.hostingController.view, frame: CGRect(x: 0.0, y: top, width: layout.size.width, height: max(0.0, layout.size.height - top)))
        // In the tab bar the view runs under Telegram's tab bar (intrinsic bottom inset): the list scrolls clear of it.
        // A pushed page has no such inset and keeps only the system's safe area.
        let desiredBottom = max(layout.intrinsicInsets.bottom, layout.safeInsets.bottom)
        // A full-bleed page starts at the top of the screen: its safe area starts below the status bar (the window
        // does not always pass that inset down to the hosting view inside Telegram's node tree).
        let desiredTop: CGFloat = self.fullBleedBackground != nil ? max(layout.statusBarHeight ?? 0.0, layout.safeInsets.top) : 0.0
        self.hostingController.additionalSafeAreaInsets = .zero
        let current = self.hostingController.view.safeAreaInsets
        self.hostingController.additionalSafeAreaInsets = UIEdgeInsets(top: max(0.0, desiredTop - current.top), left: 0.0, bottom: max(0.0, desiredBottom - current.bottom), right: 0.0)
        self.layoutUpdated?(layout)
    }
}
