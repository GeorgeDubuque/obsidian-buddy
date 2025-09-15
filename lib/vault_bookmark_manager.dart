import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

class VaultBookmarkManager {
  static const MethodChannel _channel = MethodChannel(
    'security_scoped_bookmarks',
  );

  /// Create a bookmark for a folder and store it locally
  static Future<String> createAndSaveBookmark(String path) async {
    final String bookmark = await _channel.invokeMethod('createBookmark', {
      'path': path,
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('vault_bookmark', bookmark);
    return bookmark;
  }

  /// Retrieve the saved bookmark
  static Future<String?> getSavedBookmark() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('vault_bookmark');
  }

  static Future<String?> getOrCreateVaultPath() async {
    String? bookmark = await VaultBookmarkManager.getSavedBookmark();
    bool needsNewBookmark = false;
    debugPrint("Bookmark exists: ${bookmark != null}");

    String? vaultPath;

    if (bookmark != null) {
      try {
        // Try to resolve saved bookmark
        vaultPath = await VaultBookmarkManager.resolveBookmark(bookmark);
        debugPrint("Successfully resolved bookmark to: $vaultPath");
      } catch (e) {
        debugPrint("Failed to resolve saved bookmark: $e");
        needsNewBookmark = true;
      }
    } else {
      needsNewBookmark = true;
    }

    if (needsNewBookmark) {
      // User must pick the vault folder
      String? selectedPath = await FilePicker.platform.getDirectoryPath();
      if (selectedPath == null)
        return null; // TODO: user cancelled need to gracefully fail
      vaultPath = selectedPath;
      await createAndSaveBookmark(vaultPath);
      print("User selected new path: $vaultPath");
    }

    return vaultPath;
  }

  /// Resolve a bookmark into a path
  static Future<String> resolveBookmark(String bookmark) async {
    final String path = await _channel.invokeMethod('resolveBookmark', {
      'bookmark': bookmark,
    });
    return path;
  }

  /// Start accessing a security-scoped resource
  static Future<bool> startAccessingSecurityScopedResource(String path) async {
    try {
      final bool granted = await _channel.invokeMethod('startAccessing', {
        'path': path,
      });
      return granted;
    } catch (e) {
      print('Error starting security scoped access: $e');
      return false;
    }
  }

  /// Stop accessing a security-scoped resource
  static Future<bool> stopAccessingSecurityScopedResource(String path) async {
    try {
      final bool stopped = await _channel.invokeMethod('stopAccessing', {
        'path': path,
      });
      return stopped;
    } catch (e) {
      print('Error stopping security scoped access: $e');
      return false;
    }
  }

  /// Clear the saved bookmark
  static Future<void> clearBookmark() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('vault_bookmark');
  }
}
