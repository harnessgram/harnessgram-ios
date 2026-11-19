import Foundation
import UIKit
import SwiftUI
import AsyncDisplayKit
import Display
import SwiftSignalKit
import TelegramPresentationData
import AccountContext

/// A Telegram navigation screen that shows one SwiftUI view, for the few House parts Telegram has no component for.
/// It is a Display `ViewController`, so it sits in Telegram's navigation stack like any other screen. It can hide the
/// navigation bar (Home draws its own header), gives the SwiftUI view the tab-bar and safe-area insets of the layout,
/// and follows the theme: unlike the settings hosting screen, which sets the interface style once, it updates
/// `overrideUserInterfaceStyle`, the status bar and the background every time Telegram's theme changes. Views are laid
/// out right to left (Hebrew); Telegram's own bars stay left to right.
public final class HouseHostingController<Content: View>: ViewController {
    private let hostingController: UIHostingController<AnyView>
    private let hidesNavigationBar: Bool
    private var presentationData: PresentationData
    private var presentationDataDisposable: Disposable?

    public init(context: AccountContext, title: String?, hidesNavigationBar: Bool, content: Content) {
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        self.presentationData = presentationData
        self.hidesNavigationBar = hidesNavigationBar
        self.hostingController = UIHostingController(rootView: AnyView(content.environment(\.layoutDirection, .rightToLeft)))
        super.init(navigationBarPresentationData: hidesNavigationBar ? nil : NavigationBarPresentationData(presentationData: presentationData))
        self.title = title
        self.apply(presentationData: presentationData)

        self.presentationDataDisposable = (context.sharedContext.presentationData
        |> deliverOnMainQueue).start(next: { [weak self] presentationData in
            guard let self else {
                return
            }
            self.presentationData = presentationData
            self.apply(presentationData: presentationData)
            if !self.hidesNavigationBar {
                self.navigationBar?.updatePresentationData(NavigationBarPresentationData(presentationData: presentationData), transition: .immediate)
            }
        })
    }

    required public init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        self.presentationDataDisposable?.dispose()
    }

    private func apply(presentationData: PresentationData) {
        self.statusBar.statusBarStyle = presentationData.theme.rootController.statusBarStyle.style
        self.hostingController.overrideUserInterfaceStyle = presentationData.theme.overallDarkAppearance ? .dark : .light
        if self.isNodeLoaded {
            self.displayNode.backgroundColor = presentationData.theme.list.blocksBackgroundColor
        }
    }

    override public func loadDisplayNode() {
        self.displayNode = ASDisplayNode()
        self.displayNode.backgroundColor = self.presentationData.theme.list.blocksBackgroundColor
        // Build 23: a UIKit child only once this controller has its view (viewDidLoad); a tab's display node can be loaded
        // first, and a child added here would trip UIViewControllerHierarchyInconsistency (HarnessgramHostingScreen).
        self.hostingController.view.backgroundColor = .clear
        self.hostingController.view.semanticContentAttribute = .forceRightToLeft
        self.displayNode.view.addSubview(self.hostingController.view)
        self.displayNodeDidLoad()
    }

    override public func viewDidLoad() {
        super.viewDidLoad()
        if self.hostingController.parent == nil {
            self.addChild(self.hostingController)
            self.hostingController.didMove(toParent: self)
        }
    }

    override public func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)

        // The SwiftUI view runs under the status bar and the tab bar; the insets tell it where content may sit.
        let top: CGFloat
        if self.hidesNavigationBar {
            top = 0.0
        } else {
            top = self.navigationLayout(layout: layout).navigationFrame.maxY
        }
        transition.updateFrame(view: self.hostingController.view, frame: CGRect(x: 0.0, y: top, width: layout.size.width, height: max(0.0, layout.size.height - top)))

        let desiredTop: CGFloat = self.hidesNavigationBar ? max(layout.safeInsets.top, layout.statusBarHeight ?? 0.0) : 0.0
        let desiredBottom = max(layout.intrinsicInsets.bottom, layout.safeInsets.bottom)
        self.hostingController.additionalSafeAreaInsets = .zero
        let current = self.hostingController.view.safeAreaInsets
        self.hostingController.additionalSafeAreaInsets = UIEdgeInsets(top: max(0.0, desiredTop - current.top), left: 0.0, bottom: max(0.0, desiredBottom - current.bottom), right: 0.0)
    }
}
