import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }

        // The scene layer only hosts the window; the coordinator owns screen switching.
        let window = UIWindow(windowScene: windowScene)
        self.window = window
        DemoAppCoordinator.shared.attach(window: window)
        DemoAppCoordinator.shared.start()
    }
}
