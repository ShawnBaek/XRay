import UIKit
import XRay

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        // Main.storyboard supplies this scene's window and root controller.
        guard let window else { return }
        XRay.install(in: window)
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        if let window { XRay.uninstall(from: window) }
    }
}
