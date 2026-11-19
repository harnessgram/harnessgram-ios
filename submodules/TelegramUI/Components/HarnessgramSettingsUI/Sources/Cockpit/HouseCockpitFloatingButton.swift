import Foundation
import UIKit
import Display
import HarnessgramSettings
import HarnessgramHouseCore
import HarnessgramCockpitKit
import HarnessgramCockpitSync

/// The optional floating Cockpit button (build 23, off by default): a small round button over the chat list, draggable,
/// resting against the left or right edge, clear of the status bar, the tab bar and the keyboard. It lives in a
/// transparent layer over the chat list's view, so it shows only on the chat list; touches outside the button pass
/// through. A tap opens the Cockpit.
public final class HouseCockpitFloatingLayer: UIView {
    private let button = UIButton(type: .custom)
    /// The waiting count, as on the Cockpit tab (none at 0).
    private let badge = UILabel()
    private let open: () -> Void
    /// What the host covers (its navigation bar on top, Telegram's tab bar at the bottom), read on each layout.
    private let insets: () -> UIEdgeInsets
    private var keyboardTop: CGFloat?
    private var dragOffset: CGPoint = .zero
    private var observers: [NSObjectProtocol] = []

    public init(insets: @escaping () -> UIEdgeInsets, open: @escaping () -> Void) {
        self.insets = insets
        self.open = open
        super.init(frame: .zero)
        self.backgroundColor = .clear
        self.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        let d = HarnessgramCockpitFloatingButtonLayout.diameter
        self.button.frame = CGRect(x: 0.0, y: 0.0, width: d, height: d)
        self.button.layer.cornerRadius = d / 2.0
        self.button.layer.shadowColor = UIColor.black.cgColor
        self.button.layer.shadowOpacity = 0.25
        self.button.layer.shadowRadius = 6.0
        self.button.layer.shadowOffset = CGSize(width: 0.0, height: 2.0)
        let configuration = UIImage.SymbolConfiguration(pointSize: 22.0, weight: .semibold)
        let icon = UIImage(systemName: "gauge.with.dots.needle.67percent", withConfiguration: configuration) ?? UIImage(systemName: "airplane", withConfiguration: configuration)
        self.button.setImage(icon?.withRenderingMode(.alwaysTemplate), for: .normal)
        self.button.tintColor = .white
        self.button.accessibilityLabel = HouseCockpitStrings.floatingButton
        self.button.accessibilityHint = HouseCockpitStrings.floatingButtonHint
        self.button.addTarget(self, action: #selector(self.tapped), for: .touchUpInside)
        self.button.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(self.panned(_:))))
        self.addSubview(self.button)

        self.badge.backgroundColor = .systemRed
        self.badge.textColor = .white
        self.badge.font = UIFont.systemFont(ofSize: 13.0, weight: .semibold)
        self.badge.textAlignment = .center
        self.badge.layer.cornerRadius = 10.0
        self.badge.layer.masksToBounds = true
        self.badge.isUserInteractionEnabled = false
        self.badge.isAccessibilityElement = false
        self.button.addSubview(self.badge)

        let center = NotificationCenter.default
        self.observers.append(center.addObserver(forName: UIResponder.keyboardWillChangeFrameNotification, object: nil, queue: .main, using: { [weak self] notification in
            self?.keyboardChanged(notification)
        }))
        self.observers.append(center.addObserver(forName: UIResponder.keyboardWillHideNotification, object: nil, queue: .main, using: { [weak self] _ in
            self?.keyboardTop = nil
            self?.setNeedsLayout()
        }))
        self.observers.append(center.addObserver(forName: HarnessgramSettings.didChangeNotification, object: nil, queue: .main, using: { [weak self] _ in
            self?.applySwitch()
        }))
        for name in [HarnessgramCockpitSync.snapshotDidChangeNotification, UIApplication.didBecomeActiveNotification] {
            self.observers.append(center.addObserver(forName: name, object: nil, queue: .main, using: { [weak self] _ in
                self?.updateBadge()
            }))
        }
        self.applySwitch()
        self.updateBadge()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        for observer in self.observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    /// The button's fill: the theme's accent (the host sets it).
    public func setAccentColor(_ color: UIColor) {
        self.button.backgroundColor = color
    }

    private func updateBadge() {
        let count = HarnessgramCockpitWaiting.count(state: HarnessgramCockpitSync.shared.viewState)
        let text = HarnessgramCockpitWaiting.badgeText(count)
        self.badge.text = text
        self.badge.isHidden = text == nil
        let width = max(20.0, (self.badge.intrinsicContentSize.width) + 10.0)
        // The badge sits on the button's top trailing corner (the right one; Telegram's badges stay on that side).
        self.badge.frame = CGRect(x: HarnessgramCockpitFloatingButtonLayout.diameter - width + 4.0, y: -4.0, width: width, height: 20.0)
        self.button.accessibilityValue = text.map { _ in HouseCockpitStrings.waitingLabel(count) }
    }

    private func applySwitch() {
        self.isHidden = !HarnessgramSettings.shared.cockpitFloatingButton
        self.setNeedsLayout()
    }

    private func keyboardChanged(_ notification: Notification) {
        guard let frame = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue, let window = self.window else {
            return
        }
        let local = self.convert(frame, from: window.screen.coordinateSpace)
        self.keyboardTop = local.minY < self.bounds.height ? local.minY : nil
        self.setNeedsLayout()
    }

    private var area: CGRect {
        let host = self.insets()
        var bottom = max(host.bottom, self.safeAreaInsets.bottom)
        if let keyboardTop = self.keyboardTop {
            bottom = max(bottom, self.bounds.height - keyboardTop)
        }
        let top = max(host.top, self.safeAreaInsets.top)
        return HarnessgramCockpitFloatingButtonLayout.centerArea(bounds: self.bounds.size, top: top, bottom: bottom, left: self.safeAreaInsets.left, right: self.safeAreaInsets.right)
    }

    override public func layoutSubviews() {
        super.layoutSubviews()
        self.superview?.bringSubviewToFront(self)
        guard self.dragOffset == .zero else {
            return
        }
        let stored = HarnessgramSettings.shared.cockpitFloatingButtonPosition
        self.button.center = HarnessgramCockpitFloatingButtonLayout.center(rightEdge: stored?.rightEdge ?? HarnessgramCockpitFloatingButtonLayout.defaultRightEdge, y: stored?.y ?? HarnessgramCockpitFloatingButtonLayout.defaultY, area: self.area)
    }

    override public func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        return !self.isHidden && self.button.frame.insetBy(dx: -6.0, dy: -6.0).contains(point)
    }

    @objc private func tapped() {
        self.open()
    }

    @objc private func panned(_ recognizer: UIPanGestureRecognizer) {
        let location = recognizer.location(in: self)
        switch recognizer.state {
        case .began:
            self.dragOffset = CGPoint(x: self.button.center.x - location.x, y: self.button.center.y - location.y)
            if self.dragOffset == .zero {
                self.dragOffset = CGPoint(x: 0.001, y: 0.0)
            }
        case .changed:
            self.button.center = CGPoint(x: location.x + self.dragOffset.x, y: location.y + self.dragOffset.y)
        case .ended, .cancelled, .failed:
            let area = self.area
            let target = HarnessgramCockpitFloatingButtonLayout.snapped(self.button.center, area: area)
            self.dragOffset = .zero
            UIView.animate(withDuration: 0.25, delay: 0.0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0.0, options: [.allowUserInteraction], animations: {
                self.button.center = target
            })
            HarnessgramSettings.shared.cockpitFloatingButtonPosition = HarnessgramCockpitFloatingButtonLayout.position(of: target, area: area)
        default:
            break
        }
    }
}
