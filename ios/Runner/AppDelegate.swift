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
      case "startAccessing":
        guard let args = call.arguments as? [String: Any],
              let path = args["path"] as? String else {
          result(FlutterError(code: "bad_args", message: "path missing", details: nil))
          return
        }
        self.startAccessingSecurityScopedResource(path: path, result: result)
      case "stopAccessing":
        guard let args = call.arguments as? [String: Any],
              let path = args["path"] as? String else {
          result(FlutterError(code: "bad_args", message: "path missing", details: nil))
          return
        }
        self.stopAccessingSecurityScopedResource(path: path, result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
  
  // Store active security scoped URLs to properly stop accessing them later
  private var activeSecurityScopedURLs: [String: URL] = [:]
  
  private func createBookmark(path: String, result: FlutterResult) {
    let url = URL(fileURLWithPath: path)
    do {
      // For bookmark creation, use default options (security scope is preserved automatically for user-selected URLs)
      let data = try url.bookmarkData(
        options: [],
        includingResourceValuesForKeys: nil,
        relativeTo: nil
      )
      let b64 = data.base64EncodedString()
      print("Created security-scoped bookmark for: \(path)")
      result(b64)
    } catch {
      print("Failed to create bookmark: \(error)")
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
      // On iOS, use empty options - security scope is handled automatically
      let url = try URL(
        resolvingBookmarkData: data,
        options: [],  // iOS doesn't have withSecurityScope - use empty options
        relativeTo: nil,
        bookmarkDataIsStale: &isStale
      )
      
      if isStale {
        print("Bookmark is stale for path: \(url.path)")
        result(FlutterError(code: "stale_bookmark", message: "Bookmark is stale", details: nil))
        return
      }
      
      print("Successfully resolved bookmark to: \(url.path)")
      result(url.path)
    } catch {
      print("Failed to resolve bookmark: \(error)")
      result(FlutterError(code: "resolve_failed", message: "\(error)", details: nil))
    }
  }
  
  private func startAccessingSecurityScopedResource(path: String, result: FlutterResult) {
    let url = URL(fileURLWithPath: path)
    let granted = url.startAccessingSecurityScopedResource()
    
    if granted {
      // Store the URL so we can properly stop accessing it later
      activeSecurityScopedURLs[path] = url
      print("Started accessing security-scoped resource: \(path)")
    } else {
      print("Failed to start accessing security-scoped resource: \(path)")
    }
    
    result(granted)
  }
  
  private func stopAccessingSecurityScopedResource(path: String, result: FlutterResult) {
    if let url = activeSecurityScopedURLs[path] {
      url.stopAccessingSecurityScopedResource()
      activeSecurityScopedURLs.removeValue(forKey: path)
      print("Stopped accessing security-scoped resource: \(path)")
      result(true)
    } else {
      print("No active security-scoped resource found for path: \(path)")
      result(false)
    }
  }
}
