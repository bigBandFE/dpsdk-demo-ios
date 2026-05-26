import UIKit

final class DemoAppCoordinator {
    static let shared = DemoAppCoordinator()

    private weak var window: UIWindow?

    private init() {}

    func attach(window: UIWindow) {
        self.window = window
        window.backgroundColor = .systemBackground
    }

    func start() {
        showContent(animated: false)
    }

    func showContent(animated: Bool = true) {
        let controller = DemoDPSDKHomeViewController()
        setRoot(controller, animated: animated)
    }

    private func setRoot(_ controller: UIViewController, animated: Bool) {
        guard let window else { return }

        let navigationController = UINavigationController(rootViewController: controller)
        navigationController.navigationBar.isHidden = true
        navigationController.view.backgroundColor = .systemBackground

        if animated {
            UIView.transition(
                with: window,
                duration: 0.25,
                options: .transitionCrossDissolve,
                animations: {
                    window.rootViewController = navigationController
                }
            )
        } else {
            window.rootViewController = navigationController
        }

        window.makeKeyAndVisible()
    }
}
