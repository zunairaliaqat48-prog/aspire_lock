import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // The Dart side (notification_service.dart) talks to Android's
    // MainActivity.kt over this same channel name, just to fetch the
    // device's real IANA timezone id — without this, `getDeviceTimeZone`
    // would throw on iOS and Dart would silently fall back to UTC (see
    // NotificationService._setDeviceLocalTimeZone's catch block).
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "AspireLockNativeChannel") else {
      return
    }
    let channel = FlutterMethodChannel(
      name: "com.aspirelock/native",
      binaryMessenger: registrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "getDeviceTimeZone":
        result(TimeZone.current.identifier)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
