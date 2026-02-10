import Flutter
import UIKit
import CloudKit

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
                result(Self.cloudFlutterError(error, fallbackCode: "push_failed"))
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
                result(Self.cloudFlutterError(error, fallbackCode: "fetch_failed"))
              }
            }
          }
        case "pushSettings":
          let settings = args["settings"] as? [String: Any] ?? [:]
          handler.pushSettings(settings: settings) { outcome in
            DispatchQueue.main.async {
              switch outcome {
              case .success:
                result(true)
              case .failure(let error):
                result(Self.cloudFlutterError(error, fallbackCode: "push_settings_failed"))
              }
            }
          }
        case "fetchSettings":
          handler.fetchSettings { outcome in
            DispatchQueue.main.async {
              switch outcome {
              case .success(let settings):
                result(settings)
              case .failure(let error):
                result(Self.cloudFlutterError(error, fallbackCode: "fetch_settings_failed"))
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

  private static func cloudFlutterError(_ error: Error, fallbackCode: String) -> FlutterError {
    if let ckError = error as? CKError {
      let mappedCode: String
      switch ckError.code {
      case .notAuthenticated:
        mappedCode = "icloud_not_signed_in"
      case .permissionFailure, .missingEntitlement:
        mappedCode = "icloud_permission_denied"
      case .quotaExceeded:
        mappedCode = "quota_exceeded"
      case .networkUnavailable, .networkFailure:
        mappedCode = "network_unavailable"
      case .serviceUnavailable, .requestRateLimited, .zoneBusy:
        mappedCode = "server_error"
      default:
        mappedCode = "sync_failed"
      }
      return FlutterError(
        code: mappedCode,
        message: error.localizedDescription,
        details: ["fallbackCode": fallbackCode, "ckErrorCode": ckError.code.rawValue]
      )
    }

    return FlutterError(
      code: "sync_failed",
      message: error.localizedDescription,
      details: ["fallbackCode": fallbackCode]
    )
  }
}
