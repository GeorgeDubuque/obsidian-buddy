import UIKit
import Flutter

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    let controller: FlutterViewController = window?.rootViewController as! FlutterViewController
    let channel = FlutterMethodChannel(name: "security_scoped_bookmarks", binaryMessenger: controller.binaryMessenger)

    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "createBookmark":
        guard let args = call.arguments as? [String: Any],
              let path = args["path"] as? String else {
          result(FlutterError(code: "bad_args", message: "path missing", details: nil))
          return
        }
        self.createBookmark(path: path, result: result)

      case "resolveBookmark":
        guard let args = call.arguments as? [String: Any],
              let bookmarkB64 = args["bookmark"] as? String else {
          result(FlutterError(code: "bad_args", message: "bookmark missing", details: nil))
          return
        }
        self.resolveBookmark(bookmarkB64: bookmarkB64, result: result)

      default:
        result(FlutterMethodNotImplemented)
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func createBookmark(path: String, result: FlutterResult) {
    let url = URL(fileURLWithPath: path)
    do {
      let data = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
      let b64 = data.base64EncodedString()
      result(b64)
    } catch {
      result(FlutterError(code: "bookmark_failed", message: "\(error)", details: nil))
    }
  }

  private func resolveBookmark(bookmarkB64: String, result: FlutterResult) {
    guard let data = Data(base64Encoded: bookmarkB64) else {
      result(FlutterError(code: "bad_bookmark", message: "Cannot decode base64", details: nil))
      return
    }
    do {
      var isStale = false
      let url = try URL(resolvingBookmarkData: data, bookmarkDataIsStale: &isStale)
      if isStale {
        result(FlutterError(code: "stale_bookmark", message: "Bookmark is stale", details: nil))
        return
      }
      result(url.path)
    } catch {
      result(FlutterError(code: "resolve_failed", message: "\(error)", details: nil))
    }
  }
}
