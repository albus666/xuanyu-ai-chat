import Flutter
import UIKit

final class SceneDelegate: FlutterSceneDelegate {
  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    let appDelegate = UIApplication.shared.delegate as? AppDelegate
    appDelegate?.sceneWillConnect(
      window: window,
      initialURL: connectionOptions.urlContexts.first?.url
    )
    super.scene(scene, willConnectTo: session, options: connectionOptions)
  }

  override func scene(
    _ scene: UIScene,
    openURLContexts URLContexts: Set<UIOpenURLContext>
  ) {
    if let appDelegate = UIApplication.shared.delegate as? AppDelegate,
       URLContexts.contains(where: { appDelegate.handleSceneURL($0.url) }) {
      return
    }
    super.scene(scene, openURLContexts: URLContexts)
  }
}
