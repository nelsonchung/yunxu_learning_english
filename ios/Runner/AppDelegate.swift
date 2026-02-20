import Flutter
import UIKit
import CloudKit
import Security

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var cloudSyncHandler: CloudSyncHandler?
  private static let installMarkerService = "com.yunxu.yunxulearn.install"
  private static let installMarkerAccount = "has_launched_before"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    if let controller = window?.rootViewController as? FlutterViewController {
      let installChannel = FlutterMethodChannel(name: "install_state", binaryMessenger: controller.binaryMessenger)
      installChannel.setMethodCallHandler { call, result in
        switch call.method {
        case "shouldAutoRestoreOnEmptyData":
          result(Self.shouldAutoRestoreOnEmptyData())
        default:
          result(FlutterMethodNotImplemented)
        }
      }

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

  private static func shouldAutoRestoreOnEmptyData() -> Bool {
    if hasInstallMarker() {
      return true
    }
    _ = saveInstallMarker()
    return false
  }

  private static func installMarkerQuery() -> [String: Any] {
    return [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: installMarkerService,
      kSecAttrAccount as String: installMarkerAccount
    ]
  }

  private static func hasInstallMarker() -> Bool {
    var query = installMarkerQuery()
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    query[kSecReturnData as String] = true

    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    return status == errSecSuccess
  }

  private static func saveInstallMarker() -> Bool {
    let valueData = Data("1".utf8)
    var addQuery = installMarkerQuery()
    addQuery[kSecValueData as String] = valueData

    let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
    if addStatus == errSecSuccess {
      return true
    }
    if addStatus == errSecDuplicateItem {
      let updateQuery = installMarkerQuery()
      let updateAttrs = [kSecValueData as String: valueData] as CFDictionary
      let updateStatus = SecItemUpdate(updateQuery as CFDictionary, updateAttrs)
      return updateStatus == errSecSuccess
    }
    return false
  }
}
