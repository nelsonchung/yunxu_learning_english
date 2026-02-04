import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    let channel = FlutterMethodChannel(name: "cloud_sync", binaryMessenger: flutterViewController.engine.binaryMessenger)
    channel.setMethodCallHandler { call, result in
      guard let args = call.arguments as? [String: Any],
            let containerId = args["containerId"] as? String else {
        result(FlutterError(code: "bad_args", message: "Missing containerId", details: nil))
        return
      }

      let handler = CloudSyncHandler(containerId: containerId)

      switch call.method {
      case "pushChanges":
        let records = args["records"] as? [[String: Any]] ?? []
        handler.pushChanges(records: records) { outcome in
          DispatchQueue.main.async {
            switch outcome {
            case .success:
              result(true)
            case .failure(let error):
              result(FlutterError(code: "push_failed", message: error.localizedDescription, details: nil))
            }
          }
        }
      case "fetchChanges":
        let sinceMillis = args["since"] as? Int ?? 0
        let sinceDate = Date(timeIntervalSince1970: Double(sinceMillis) / 1000.0)
        handler.fetchChanges(since: sinceDate) { outcome in
          DispatchQueue.main.async {
            switch outcome {
            case .success(let records):
              result(records)
            case .failure(let error):
              result(FlutterError(code: "fetch_failed", message: error.localizedDescription, details: nil))
            }
          }
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    super.awakeFromNib()
  }
}
