import Flutter
import UIKit
import WidgetKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let appGroupId = "group.com.example.nextdeck"
  private let widgetPayloadKey = "nextdeck_widget_payload"
  private var initialLink: String?
  private var linkChannel: FlutterMethodChannel?

  // Issue #80: `.url` in LaunchOptions ist ab iOS 26 deprecated (UIScene).
  // Der Zugriff ist hier in eine selbst als deprecated markierte Funktion
  // gekapselt — das unterdrückt die Compiler-Warnung, ohne das Verhalten zu
  // ändern. Die echte UIScene-Lifecycle-Migration ist als eigenes
  // Roadmap-Thema geplant (#46) und gehört nicht in einen Bugfix-Release.
  @available(iOS, deprecated: 26.0, message: "Ersetzt durch UIScene-Migration (#46)")
  private func legacyLaunchURL(
    _ launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> URL? {
    return launchOptions?[.url] as? URL
  }

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if let url = legacyLaunchURL(launchOptions) {
      initialLink = url.absoluteString
    }
    if let registrar = self.registrar(forPlugin: "AppDelegate") {
      let messenger = registrar.messenger()
      let widgetChannel = FlutterMethodChannel(
        name: "nextdeck/widget",
        binaryMessenger: messenger
      )
      widgetChannel.setMethodCallHandler { [weak self] call, result in
        guard let self = self else { return }
        if call.method == "updateWidgetData" {
          guard
            let args = call.arguments as? [String: Any],
            let payload = args["payload"] as? String
          else {
            result(FlutterError(code: "bad_args", message: "Missing payload", details: nil))
            return
          }
          let store = UserDefaults(suiteName: self.appGroupId)
          if let data = payload.data(using: .utf8) {
            store?.set(data, forKey: self.widgetPayloadKey)
          } else {
            store?.set(payload, forKey: self.widgetPayloadKey)
          }
          store?.synchronize()
          if #available(iOS 14.0, *) {
            WidgetCenter.shared.reloadAllTimelines()
          }
          result(nil)
          return
        }
        result(FlutterMethodNotImplemented)
      }
      let linkChannel = FlutterMethodChannel(
        name: "nextdeck/deeplink",
        binaryMessenger: messenger
      )
      linkChannel.setMethodCallHandler { [weak self] call, result in
        guard let self = self else { return }
        if call.method == "getInitialLink" {
          result(self.initialLink)
          self.initialLink = nil
          return
        }
        result(FlutterMethodNotImplemented)
      }
      self.linkChannel = linkChannel
    }
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    linkChannel?.invokeMethod("onDeepLink", arguments: url.absoluteString)
    return true
  }
}
