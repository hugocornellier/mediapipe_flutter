import Cocoa
import FlutterMacOS
import IOKit.ps

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    if ProcessInfo.processInfo.arguments.contains("--mediapipe-benchmark") {
      let channel = FlutterMethodChannel(
        name: "mediapipe_gallery/benchmark",
        binaryMessenger: flutterViewController.engine.binaryMessenger
      )
      channel.setMethodCallHandler { call, result in
        guard call.method == "deviceInfo" else {
          result(FlutterMethodNotImplemented)
          return
        }
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("hw.model", &model, &size, nil, 0)
        let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let source = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String? ?? "unknown"
        var level = -1.0
        if let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] {
          for entry in list {
            if let description = IOPSGetPowerSourceDescription(info, entry)?.takeUnretainedValue() as? [String: Any],
               let capacity = description[kIOPSCurrentCapacityKey] as? Int {
              level = Double(capacity) / 100.0
            }
          }
        }
        var lowPowerMode = false
        if #available(macOS 12.0, *) {
          lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
        result([
          "machine": String(cString: model),
          "macos": ProcessInfo.processInfo.operatingSystemVersionString,
          "thermal_state": ProcessInfo.processInfo.thermalState.rawValue,
          "low_power_mode": lowPowerMode,
          "power_source": source,
          "battery_level": level,
          "arguments": ProcessInfo.processInfo.arguments,
        ])
      }
    }

    super.awakeFromNib()
  }
}
