import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var cloudSyncHandler: CloudSyncHandler?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(name: "cloud_sync", binaryMessenger: controller.binaryMessenger)
      channel.setMethodCallHandler { [weak self] call, result in
        guard let args = call.arguments as? [String: Any],
              let containerId = args["containerId"] as? String else {
          result(FlutterError(code: "bad_args", message: "Missing containerId", details: nil))
          return
        }

        if self?.cloudSyncHandler == nil || self?.cloudSyncHandler?.containerId != containerId {
          self?.cloudSyncHandler = CloudSyncHandler(containerId: containerId)
        }

        guard let handler = self?.cloudSyncHandler else {
          result(FlutterError(code: "init_failed", message: "CloudSyncHandler unavailable", details: nil))
          return
        }

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
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
