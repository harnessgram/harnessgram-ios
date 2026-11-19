import XCTest
import UIKit
import Display
@testable import HarnessgramSettingsUI

final class HouseCockpitDeskNavigationTests: XCTestCase {
    private func navigation(root: ViewController) -> NavigationController {
        let bar = NavigationBarTheme(overallDarkAppearance: false, buttonColor: .blue, disabledButtonColor: .gray, primaryTextColor: .black, badgeBackgroundColor: .red, badgeTextColor: .white, accentButtonColor: .blue, accentDisabledButtonColor: .gray, accentForegroundColor: .white)
        let navigation = NavigationController(mode: .automaticMasterDetail, theme: NavigationControllerTheme(statusBar: .black, navigationBar: bar, emptyAreaColor: .white, separatorColor: .gray, opaqueBackgroundColor: .white))
        navigation.setViewControllers([root], animated: false)
        return navigation
    }

    private func layout(regular: Bool) -> ContainerViewLayout {
        return ContainerViewLayout(size: CGSize(width: regular ? 1_024 : 390, height: 844), metrics: LayoutMetrics(widthClass: regular ? .regular : .compact, heightClass: .regular, orientation: nil), deviceMetrics: .iPadPro11Inch, intrinsicInsets: .zero, safeInsets: .zero, reservedCorners: .none, division: nil, additionalInsets: .zero, statusBarHeight: nil, inputHeight: nil, inputHeightIsInteractivellyChanging: false, inVoiceOver: false, presentedInFormSheet: false)
    }

    private func finishLayoutPass() {
        let finished = self.expectation(description: "navigation changes after layout")
        DispatchQueue.main.async { finished.fulfill() }
        self.wait(for: [finished], timeout: 2)
    }

    func testDetailWidthTransitionRemovesDeskWhileTheTabIsCovered() {
        for radioIsOpen in [false, true] {
            let root = ViewController(navigationBarPresentationData: nil)
            let navigation = self.navigation(root: root)
            let coordinator = HouseCockpitDeskNavigation(navigation: { navigation })
            let desk = ViewController(navigationBarPresentationData: nil)
            let show = { coordinator.showDesk(in: navigation, replacingDetail: false, makeDesk: { desk }) }
            coordinator.updateLayout(self.layout(regular: true), showIfEmpty: show)
            self.finishLayoutPass()
            XCTAssertTrue(navigation.viewControllers.last === desk)
            let radio = ViewController(navigationBarPresentationData: nil)
            if radioIsOpen {
                navigation.pushViewController(radio, animated: false)
            }
            // Only the detail reports compact, exactly as when the covered tab receives no layout.
            coordinator.updateLayout(self.layout(regular: false), showIfEmpty: show)
            XCTAssertTrue(navigation.viewControllers.contains(where: { $0 === desk }), "no mutation inside the layout pass")
            self.finishLayoutPass()
            XCTAssertEqual(navigation.viewControllers.count, radioIsOpen ? 2 : 1)
            XCTAssertTrue(navigation.viewControllers.first === root)
            XCTAssertFalse(navigation.viewControllers.contains(where: { $0 === desk }))
            XCTAssertTrue(navigation.viewControllers.last === (radioIsOpen ? radio : root))
            if radioIsOpen {
                _ = navigation.popToViewController(root, animated: false)
            }
            coordinator.updateLayout(self.layout(regular: true), showIfEmpty: show)
            self.finishLayoutPass()
            XCTAssertTrue(navigation.viewControllers.last === desk)
        }
    }

    func testSelectingATaskReturnsToTheExistingDeskAboveRadio() {
        let root = ViewController(navigationBarPresentationData: nil)
        let navigation = self.navigation(root: root)
        let coordinator = HouseCockpitDeskNavigation(navigation: { navigation })
        let desk = ViewController(navigationBarPresentationData: nil)
        coordinator.showDesk(in: navigation, replacingDetail: true, makeDesk: { desk })
        let radio = ViewController(navigationBarPresentationData: nil)
        navigation.pushViewController(radio, animated: false)
        coordinator.showDesk(in: navigation, replacingDetail: false, makeDesk: { XCTFail("must reuse desk"); return desk })
        XCTAssertTrue(navigation.viewControllers.last === radio)
        coordinator.showDesk(in: navigation, replacingDetail: true, makeDesk: { XCTFail("must reuse desk"); return desk })
        XCTAssertEqual(navigation.viewControllers.count, 2)
        XCTAssertTrue(navigation.viewControllers.first === root)
        XCTAssertTrue(navigation.viewControllers.last === desk)
    }
}
