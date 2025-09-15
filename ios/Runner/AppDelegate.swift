import UIKit
import Flutter

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
    private var activeURLs: [String: URL] = [:]
    private var pickResult: FlutterResult?

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        let controller: FlutterViewController = window?.rootViewController as! FlutterViewController
        let channel = FlutterMethodChannel(name: "bookmarks", binaryMessenger: controller.binaryMessenger)

        channel.setMethodCallHandler { [weak self] call, result in
            guard let self = self else { return }

            switch call.method {
            case "createBookmark":
                if let args = call.arguments as? [String: Any],
                   let path = args["path"] as? String {
                    self.createBookmark(path: path, result: result)
                } else {
                    result(FlutterError(code: "bad_args", message: "path missing", details: nil))
                }
            case "resolveBookmark":
                if let args = call.arguments as? [String: Any],
                   let bookmark = args["bookmark"] as? String {
                    self.resolveBookmark(bookmarkB64: bookmark, result: result)
                } else {
                    result(FlutterError(code: "bad_args", message: "bookmark missing", details: nil))
                }
            default:
                result(FlutterMethodNotImplemented)
            }
        }

        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    // MARK: - Bookmark creation
    private func createBookmark(path: String, result: @escaping FlutterResult) {
        let url = URL(fileURLWithPath: path)
        do {
            let bookmarkData = try url.bookmarkData(options: .minimalBookmark,
                                                    includingResourceValuesForKeys: nil,
                                                    relativeTo: nil)
            let b64 = bookmarkData.base64EncodedString()
            result(b64)
        } catch {
            result(FlutterError(code: "bookmark_failed", message: "Failed to create bookmark: \(error)", details: nil))
        }
    }

    // MARK: - Bookmark resolution
    private func resolveBookmark(bookmarkB64: String, result: @escaping FlutterResult) {
        guard let data = Data(base64Encoded: bookmarkB64) else {
            result(FlutterError(code: "bad_bookmark", message: "Cannot decode base64", details: nil))
            return
        }

        var isStale = false
        do {
            let url = try URL(resolvingBookmarkData: data,
                              bookmarkDataIsStale: &isStale)

            if isStale {
                result(FlutterError(code: "stale_bookmark", message: "Bookmark is stale", details: nil))
                return
            }

            activeURLs[bookmarkB64] = url
            result(url.path)
        } catch {
            result(FlutterError(code: "resolve_failed", message: "Failed to resolve bookmark: \(error)", details: nil))
        }
    }
}
