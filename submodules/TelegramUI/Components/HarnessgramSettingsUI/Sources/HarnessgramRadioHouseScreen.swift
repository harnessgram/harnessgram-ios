import Foundation
import UIKit
import Combine
import AsyncDisplayKit
import Display
import AccountContext
import TelegramPresentationData
import SwiftSignalKit
import HarnessgramSettings

/// A Telegram navigation controller with native controls and the existing radio player.
final class HarnessgramRadioHouseScreen: ViewController {
    private let context: AccountContext
    private let radio = HarnessgramRadioPlayer.shared
    private var presentationData: PresentationData
    private var presentationDisposable: Disposable?
    private var subscriptions = Set<AnyCancellable>()
    private let scroll = UIScrollView()
    private let stack = UIStackView()
    private let art = UIImageView()
    private let station = UILabel()
    private let detail = UILabel()
    private let playButton = UIButton(type: .system)
    private let linkButton = UIButton(type: .system)

    init(context: AccountContext) {
        self.context = context
        self.presentationData = context.sharedContext.currentPresentationData.with { $0 }
        super.init(navigationBarPresentationData: NavigationBarPresentationData(presentationData: self.presentationData))
        self.title = HarnessgramRadioHouseStrings.title
        self.statusBar.statusBarStyle = self.presentationData.theme.rootController.statusBarStyle.style
        self.presentationDisposable = (context.sharedContext.presentationData |> deliverOnMainQueue).start(next: { [weak self] data in
            guard let self else { return }
            self.presentationData = data
            if self.isNodeLoaded { self.applyTheme() }
        })
    }

    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { self.presentationDisposable?.dispose() }

    override func loadDisplayNode() {
        self.displayNode = ASDisplayNode()
        self.displayNodeDidLoad()
        self.scroll.translatesAutoresizingMaskIntoConstraints = false
        self.scroll.alwaysBounceVertical = true
        self.scroll.semanticContentAttribute = .forceRightToLeft
        self.displayNode.view.addSubview(self.scroll)
        self.stack.translatesAutoresizingMaskIntoConstraints = false
        self.stack.axis = .vertical
        self.stack.alignment = .center
        self.stack.spacing = 16
        self.scroll.addSubview(self.stack)
        NSLayoutConstraint.activate([
            self.scroll.leadingAnchor.constraint(equalTo: self.displayNode.view.leadingAnchor),
            self.scroll.trailingAnchor.constraint(equalTo: self.displayNode.view.trailingAnchor),
            self.scroll.bottomAnchor.constraint(equalTo: self.displayNode.view.bottomAnchor),
            self.scroll.topAnchor.constraint(equalTo: self.displayNode.view.topAnchor),
            self.stack.topAnchor.constraint(equalTo: self.scroll.contentLayoutGuide.topAnchor, constant: 24),
            self.stack.bottomAnchor.constraint(equalTo: self.scroll.contentLayoutGuide.bottomAnchor, constant: -24),
            self.stack.leadingAnchor.constraint(equalTo: self.scroll.frameLayoutGuide.leadingAnchor, constant: 16),
            self.stack.trailingAnchor.constraint(equalTo: self.scroll.frameLayoutGuide.trailingAnchor, constant: -16)
        ])
        self.art.contentMode = .scaleAspectFill
        self.art.clipsToBounds = true
        self.art.layer.cornerRadius = 28.0
        self.art.layer.cornerCurve = .continuous
        self.art.isAccessibilityElement = false
        self.stack.addArrangedSubview(self.art)
        NSLayoutConstraint.activate([self.art.widthAnchor.constraint(equalToConstant: 240), self.art.heightAnchor.constraint(equalToConstant: 240), self.art.widthAnchor.constraint(lessThanOrEqualTo: self.stack.widthAnchor)])
        for label in [self.station, self.detail] {
            label.textAlignment = .center
            label.numberOfLines = 0
            label.adjustsFontForContentSizeCategory = true
            self.stack.addArrangedSubview(label)
            label.widthAnchor.constraint(equalTo: self.stack.widthAnchor).isActive = true
        }
        self.station.font = UIFont.preferredFont(forTextStyle: .title2)
        self.detail.font = UIFont.preferredFont(forTextStyle: .body)
        self.station.text = HarnessgramRadioHouseStrings.title
        for button in [self.playButton, self.linkButton] {
            button.titleLabel?.font = UIFont.preferredFont(forTextStyle: .headline)
            button.titleLabel?.adjustsFontForContentSizeCategory = true
            self.stack.addArrangedSubview(button)
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
            button.widthAnchor.constraint(equalTo: self.stack.widthAnchor).isActive = true
        }
        self.playButton.addTarget(self, action: #selector(self.toggle), for: .touchUpInside)
        self.linkButton.setTitle(HarnessgramRadioHouseStrings.link, for: .normal)
        self.linkButton.addTarget(self, action: #selector(self.manageLink), for: .touchUpInside)
        self.radio.$state.receive(on: DispatchQueue.main).sink { [weak self] _ in self?.refresh() }.store(in: &self.subscriptions)
        self.radio.$liveTitle.receive(on: DispatchQueue.main).sink { [weak self] _ in self?.refresh() }.store(in: &self.subscriptions)
        self.applyTheme()
        self.refresh()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if self.isNodeLoaded { self.refresh() }
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        let top = self.navigationLayout(layout: layout).navigationFrame.maxY
        self.scroll.contentInset.top = top
        self.scroll.verticalScrollIndicatorInsets.top = top
        self.scroll.contentInset.bottom = layout.intrinsicInsets.bottom
    }

    private func applyTheme() {
        let theme = self.presentationData.theme
        self.displayNode.backgroundColor = theme.list.blocksBackgroundColor
        self.station.textColor = theme.list.itemPrimaryTextColor
        self.detail.textColor = theme.list.itemSecondaryTextColor
        self.playButton.tintColor = theme.list.itemAccentColor
        self.linkButton.tintColor = theme.list.itemAccentColor
    }

    private func refresh() {
        let active = self.radio.state == .playing
        let hasLink = HarnessgramRadioLink.load() != nil
        // Build 23: the header is the owner's control tower at sunset; the old radio pictures stay as the fallback.
        self.art.image = UIImage(named: HarnessgramRadioArtwork.bundledImageName) ?? UIImage(named: active ? "House/Radio/radio-playing-large" : "House/Radio/radio-paused-large")
        self.art.alpha = active ? 1.0 : 0.85
        self.detail.text = hasLink ? (active ? (self.radio.liveTitle ?? HarnessgramRadioHouseStrings.live) : self.radio.stateText) : HarnessgramRadioHouseStrings.noLink
        let title = self.radio.buttonTitle
        self.playButton.setTitle(title, for: .normal)
        self.playButton.accessibilityLabel = title
        self.playButton.isEnabled = hasLink
    }

    @objc private func toggle() {
        self.radio.toggle(audioSession: self.context.sharedContext.mediaManager.audioSession)
        self.refresh()
    }

    @objc private func manageLink() {
        let view = HarnessgramRadioView(radio: self.radio, audioSession: self.context.sharedContext.mediaManager.audioSession)
        self.push(HarnessgramHostingScreen(context: self.context, title: HarnessgramStrings.t(.radioTitle), content: view))
    }
}
