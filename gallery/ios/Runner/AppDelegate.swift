import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if ProcessInfo.processInfo.arguments.contains("--mediapipe-benchmark") {
      application.isIdleTimerDisabled = true
      UIDevice.current.isBatteryMonitoringEnabled = true
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if ProcessInfo.processInfo.arguments.contains("--mediapipe-benchmark") {
      let channel = FlutterMethodChannel(
        name: "mediapipe_gallery/benchmark",
        binaryMessenger: engineBridge.applicationRegistrar.messenger()
      )
      channel.setMethodCallHandler { call, result in
        guard call.method == "deviceInfo" else {
          result(FlutterMethodNotImplemented)
          return
        }
        var system = utsname()
        uname(&system)
        let machine = withUnsafePointer(to: &system.machine) {
          $0.withMemoryRebound(to: CChar.self, capacity: 256) { String(cString: $0) }
        }
        result([
          "machine": machine,
          "ios": UIDevice.current.systemVersion,
          "thermal_state": ProcessInfo.processInfo.thermalState.rawValue,
          "low_power_mode": ProcessInfo.processInfo.isLowPowerModeEnabled,
          "battery_level": UIDevice.current.batteryLevel,
        ])
      }
    }
  }
}
