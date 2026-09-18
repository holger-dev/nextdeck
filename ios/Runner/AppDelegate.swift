import Flutter
import UIKit
import WidgetKit
import QuickLook

/// UIScene-Migration (Flutter 3.38+ Lifecycle):
/// * Plugin-Registrierung + Method-Channels laufen über
///   `didInitializeImplicitFlutterEngine` — unter Scenes initialisiert
///   Flutter die Engine erst NACH `application(_:didFinishLaunching…)`,
///   der alte Registrierungsort wäre zu früh.
/// * Deep-Links (nextdeck://) kommen nicht mehr über
///   `application(_:open:options:)` / `launchOptions[.url]` (beide sind
///   unter Scenes tot), sondern über die SceneDelegate unten.
@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let appGroupId = "group.com.example.nextdeck"
  private let widgetPayloadKey = "nextdeck_widget_payload"
  /// Cold-Start-Link: gesetzt von der SceneDelegate, abgeholt von Dart
  /// via getInitialLink.
  var initialLink: String?
  private var linkChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let messenger = engineBridge.applicationRegistrar.messenger()

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

    // Issue #86.3: nativer QuickLook-Markup-Editor für Anhänge (PDFs).
    // Dart ruft editFile(path); wir zeigen QLPreviewController mit
    // Bearbeiten-Modus (.updateContents — schreibt in dieselbe Datei)
    // und melden nach dem Schließen zurück, ob der Inhalt geändert wurde.
    let quickLookChannel = FlutterMethodChannel(
      name: "nextdeck/quicklook",
      binaryMessenger: messenger
    )
    quickLookChannel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return }
      if call.method == "editFile" {
        guard
          let args = call.arguments as? [String: Any],
          let path = args["path"] as? String
        else {
          result(FlutterError(code: "bad_args", message: "Missing path", details: nil))
          return
        }
        self.presentQuickLookEditor(path: path, flutterResult: result)
        return
      }
      result(FlutterMethodNotImplemented)
    }
  }

  /// Von der SceneDelegate gerufen — Warm-Link an Dart durchreichen,
  /// oder (falls der Channel noch nicht steht, Cold-Start) puffern.
  func handleDeepLink(_ url: URL) {
    if let channel = linkChannel {
      channel.invokeMethod("onDeepLink", arguments: url.absoluteString)
    } else {
      initialLink = url.absoluteString
    }
  }

  // ---- QuickLook-Editor (Issue #86.3) -------------------------------------

  /// Starke Referenz auf den laufenden Editor-Handler — QLPreviewController
  /// hält Delegate/DataSource nur weak.
  private var quickLookHandler: QuickLookEditHandler?

  private func presentQuickLookEditor(
    path: String, flutterResult: @escaping FlutterResult
  ) {
    // UIScene-kompatibel: Root-ViewController der aktiven Window-Scene.
    let rootVC = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }
      .first { $0.isKeyWindow }?.rootViewController
    guard let presenter = rootVC else {
      flutterResult(FlutterError(
        code: "no_vc", message: "No root view controller", details: nil))
      return
    }
    let handler = QuickLookEditHandler(
      fileURL: URL(fileURLWithPath: path)
    ) { [weak self] modified in
      flutterResult(modified)
      self?.quickLookHandler = nil
    }
    quickLookHandler = handler
    let controller = QLPreviewController()
    controller.dataSource = handler
    controller.delegate = handler
    // Oberstes präsentiertes VC finden (Karten-Detail liegt in Flutter,
    // aber ggf. sind native Sheets offen).
    var top = presenter
    while let presented = top.presentedViewController {
      top = presented
    }
    top.present(controller, animated: true)
  }
}

/// DataSource + Delegate für den QuickLook-Editor. Meldet über
/// `onDismiss(modified)`, ob die Datei bearbeitet wurde.
class QuickLookEditHandler: NSObject, QLPreviewControllerDataSource,
  QLPreviewControllerDelegate {
  private let fileURL: URL
  private let onDismiss: (Bool) -> Void
  private var modified = false

  init(fileURL: URL, onDismiss: @escaping (Bool) -> Void) {
    self.fileURL = fileURL
    self.onDismiss = onDismiss
  }

  func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
    return 1
  }

  func previewController(
    _ controller: QLPreviewController, previewItemAt index: Int
  ) -> QLPreviewItem {
    return fileURL as NSURL
  }

  func previewController(
    _ controller: QLPreviewController,
    editingModeFor previewItem: QLPreviewItem
  ) -> QLPreviewItemEditingMode {
    // .updateContents: QuickLook schreibt Änderungen direkt in die Datei.
    return .updateContents
  }

  func previewController(
    _ controller: QLPreviewController,
    didUpdateContentsOf previewItem: QLPreviewItem
  ) {
    modified = true
  }

  func previewControllerDidDismiss(_ controller: QLPreviewController) {
    onDismiss(modified)
  }
}

/// Scene-Lebenszyklus. Erbt das komplette Flutter-Forwarding von
/// FlutterSceneDelegate und ergänzt nur das Deep-Link-Handling.
/// Registriert in Info.plist als $(PRODUCT_MODULE_NAME).SceneDelegate.
class SceneDelegate: FlutterSceneDelegate {
  private var appDelegate: AppDelegate? {
    return UIApplication.shared.delegate as? AppDelegate
  }

  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    // Cold-Start über nextdeck://-Link: URL puffern, Dart holt sie
    // nach dem Engine-Start via getInitialLink ab.
    if let url = connectionOptions.urlContexts.first?.url {
      appDelegate?.initialLink = url.absoluteString
    }
  }

  override func scene(
    _ scene: UIScene,
    openURLContexts URLContexts: Set<UIOpenURLContext>
  ) {
    super.scene(scene, openURLContexts: URLContexts)
    if let url = URLContexts.first?.url {
      appDelegate?.handleDeepLink(url)
    }
  }
}
