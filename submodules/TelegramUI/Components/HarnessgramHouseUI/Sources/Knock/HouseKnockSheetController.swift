import Foundation
import UIKit
import SwiftUI
import AsyncDisplayKit
import Display
import HarnessgramHouseCore
import HarnessgramHouseKit

/// The knock sheet as a Telegram overlay: a Display `ViewController` presented on the main window (like Telegram's own
/// alerts and action sheets), with a dimmed background, the SwiftUI sheet at the bottom, a swipe down for "later" and
/// the arrival from the design: two light taps about 120 ms apart, then a 320 ms spring. With Reduce Motion, a 150 ms fade.
final class HouseKnockSheetController: ViewController, StandalonePresentableController {
    enum Dismissal {
        case later
        case approve
        case openRoom
        case openWaitingList
    }

    private let model: HouseKnockSheetModel
    private let hostingController: UIHostingController<AnyView>
    private var dimView: UIView?
    private var currentLayout: ContainerViewLayout?
    /// Off screen until the arrival; 0 is the sheet in place.
    private var sheetOffset: CGFloat = 10_000.0
    private var hasArrived = false
    private var isDismissing = false
    private var panStart: CGFloat = 0.0

    /// Called once, after the sheet has left the screen, with how it ended.
    var onDismissed: ((Dismissal) -> Void)?

    init(model: HouseKnockSheetModel) {
        self.model = model
        self.hostingController = UIHostingController(rootView: AnyView(HouseKnockSheetView(model: model)))
        super.init(navigationBarPresentationData: nil)
        self.statusBar.statusBarStyle = .Ignore
        self.blocksBackgroundWhenInOverlay = true

        model.onLater = { [weak self] in
            self?.dismissAnimated(.later)
        }
        model.onOpenRoom = { [weak self] in
            self?.dismissAnimated(.openRoom)
        }
        model.onApprove = { [weak self] in
            self?.dismissAnimated(.approve)
        }
        if model.onOpenWaitingList != nil {
            let open = model.onOpenWaitingList
            model.onOpenWaitingList = { [weak self] in
                open?()
                self?.dismissAnimated(.openWaitingList)
            }
        }
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadDisplayNode() {
        self.displayNode = ASDisplayNode()
        self.displayNode.backgroundColor = .clear

        let dim = UIView()
        dim.backgroundColor = UIColor.black.withAlphaComponent(0.0)
        dim.isAccessibilityElement = false
        dim.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(self.dimTapped)))
        self.displayNode.view.addSubview(dim)
        self.dimView = dim

        self.addChild(self.hostingController)
        let sheetView = self.hostingController.view!
        sheetView.backgroundColor = .clear
        sheetView.semanticContentAttribute = .forceRightToLeft
        // VoiceOver reads the sheet in Hebrew even when the phone is set to English, and stays inside it.
        sheetView.accessibilityLanguage = HouseKnockStrings.speechLanguage
        sheetView.accessibilityViewIsModal = true
        sheetView.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(self.panned(_:))))
        self.displayNode.view.addSubview(sheetView)
        self.hostingController.didMove(toParent: self)
        self.displayNodeDidLoad()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        self.arrive()
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        self.currentLayout = layout
        self.layoutSheet(layout, transition: transition)
    }

    private func sheetFrame(_ layout: ContainerViewLayout) -> CGRect {
        let width = min(layout.size.width, 560.0)
        let bottomInset = max(layout.intrinsicInsets.bottom, layout.safeInsets.bottom)
        if self.model.bottomInset != bottomInset {
            self.model.bottomInset = bottomInset
        }
        let maxHeight = max(200.0, layout.size.height - max(layout.safeInsets.top, layout.statusBarHeight ?? 0.0) - HouseTokens.Space.lg)
        // UIHostingController.sizeThatFits needs iOS 16; the view's own fitting size works from iOS 13.
        let fitted = self.hostingController.view.systemLayoutSizeFitting(CGSize(width: width, height: UIView.layoutFittingCompressedSize.height), withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height
        let height = min(maxHeight, max(fitted, 160.0))
        return CGRect(x: floor((layout.size.width - width) / 2.0), y: layout.size.height - height + self.sheetOffset, width: width, height: height)
    }

    private func layoutSheet(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        self.dimView?.frame = CGRect(origin: .zero, size: layout.size)
        transition.updateFrame(view: self.hostingController.view, frame: self.sheetFrame(layout))
    }

    private func updateOffset(_ offset: CGFloat) {
        self.sheetOffset = offset
        if let layout = self.currentLayout {
            self.hostingController.view.frame = self.sheetFrame(layout)
        }
    }

    // MARK: Arrival and leaving

    private func arrive() {
        guard !self.hasArrived, let layout = self.currentLayout else {
            return
        }
        self.hasArrived = true
        UIAccessibility.post(notification: .screenChanged, argument: self.model.item.question)
        let height = self.sheetFrame(layout).height
        let reduceMotion = UIAccessibility.isReduceMotionEnabled
        if reduceMotion {
            self.updateOffset(0.0)
            self.hostingController.view.alpha = 0.0
        } else {
            self.updateOffset(height + 40.0)
        }
        // The knock: two light taps, then the sheet rises.
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            generator.impactOccurred()
            guard let self, !self.isDismissing else {
                return
            }
            if reduceMotion {
                UIView.animate(withDuration: HouseTokens.Motion.reduceMotionFade, animations: {
                    self.hostingController.view.alpha = 1.0
                    self.dimView?.backgroundColor = UIColor.black.withAlphaComponent(0.45)
                })
            } else {
                UIView.animate(withDuration: HouseTokens.Motion.knock, delay: 0.0, usingSpringWithDamping: CGFloat(HouseTokens.Motion.knockDamping), initialSpringVelocity: 0.0, options: [.allowUserInteraction], animations: {
                    self.updateOffset(0.0)
                    self.dimView?.backgroundColor = UIColor.black.withAlphaComponent(0.45)
                })
            }
        }
    }

    func dismissAnimated(_ how: Dismissal) {
        guard !self.isDismissing else {
            return
        }
        self.isDismissing = true
        let finish: () -> Void = { [weak self] in
            guard let self else {
                return
            }
            self.presentingViewController?.dismiss(animated: false)
            self.onDismissed?(how)
            self.onDismissed = nil
        }
        if UIAccessibility.isReduceMotionEnabled {
            UIView.animate(withDuration: HouseTokens.Motion.reduceMotionFade, animations: {
                self.hostingController.view.alpha = 0.0
                self.dimView?.backgroundColor = UIColor.black.withAlphaComponent(0.0)
            }, completion: { _ in
                finish()
            })
        } else {
            let distance = (self.currentLayout.map { self.sheetFrame($0).height } ?? 400.0) + 40.0
            UIView.animate(withDuration: 0.24, delay: 0.0, options: [.curveEaseIn], animations: {
                self.updateOffset(distance)
                self.dimView?.backgroundColor = UIColor.black.withAlphaComponent(0.0)
            }, completion: { _ in
                finish()
            })
        }
    }

    override func dismiss(completion: (() -> Void)? = nil) {
        if !self.isDismissing {
            self.isDismissing = true
            self.onDismissed?(.later)
            self.onDismissed = nil
        }
        self.presentingViewController?.dismiss(animated: false, completion: completion)
    }

    // MARK: Gestures

    @objc private func dimTapped() {
        self.dismissAnimated(.later)
    }

    @objc private func panned(_ recognizer: UIPanGestureRecognizer) {
        guard self.hasArrived, !self.isDismissing else {
            return
        }
        switch recognizer.state {
        case .began:
            self.panStart = self.sheetOffset
        case .changed:
            let translation = recognizer.translation(in: self.displayNode.view).y
            self.updateOffset(max(0.0, self.panStart + translation))
        case .ended, .cancelled:
            let velocity = recognizer.velocity(in: self.displayNode.view).y
            if self.sheetOffset > 80.0 || velocity > 700.0 {
                self.dismissAnimated(.later)
            } else {
                UIView.animate(withDuration: HouseTokens.Motion.knock, delay: 0.0, usingSpringWithDamping: CGFloat(HouseTokens.Motion.knockDamping), initialSpringVelocity: 0.0, options: [.allowUserInteraction], animations: {
                    self.updateOffset(0.0)
                })
            }
        default:
            break
        }
    }
}
