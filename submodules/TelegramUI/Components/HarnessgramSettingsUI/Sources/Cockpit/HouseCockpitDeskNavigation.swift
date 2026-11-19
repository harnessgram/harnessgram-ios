import Foundation
import Display

/// Navigation only: shared by the tab and its detail, independently of account and snapshot loading.
final class HouseCockpitDeskNavigation {
    private let navigation: () -> NavigationController?
    private weak var deskController: ViewController?
    private var isRegularWidth = false

    init(navigation: @escaping () -> NavigationController?) {
        self.navigation = navigation
    }

    func updateLayout(_ layout: ContainerViewLayout, showIfEmpty: @escaping () -> Void) {
        self.isRegularWidth = layout.metrics.widthClass == .regular
        // Do not mutate navigation during the layout pass that reported the change.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.isRegularWidth {
                showIfEmpty()
            } else {
                self.removeDesk()
            }
        }
    }

    func removeDesk() {
        if let desk = self.deskController, let navigation = self.navigation() {
            navigation.filterController(desk, animated: false)
        }
        self.deskController = nil
    }

    func showDesk(in navigation: NavigationController, replacingDetail: Bool, makeDesk: () -> ViewController) {
        if let desk = self.deskController, navigation.viewControllers.contains(where: { $0 === desk }) {
            if replacingDetail {
                _ = navigation.popToViewController(desk, animated: false)
            }
            return
        }
        if !replacingDetail && navigation.viewControllers.count > 1 {
            return
        }
        let desk = makeDesk()
        self.deskController = desk
        if navigation.viewControllers.count > 1 {
            navigation.replaceAllButRootController(desk, animated: false)
        } else {
            navigation.pushViewController(desk, animated: false)
        }
    }
}
