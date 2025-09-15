import 'dart:io';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:security_scoped_resource/security_scoped_resource.dart';

class VaultBookmarkManager {
  static const _prefsKey = 'vaultBookmark';
  static const MethodChannel _channel = MethodChannel(
    'security_scoped_bookmarks',
  );

  /// Saves a bookmark for the selected directory
  static Future<void> createAndSaveBookmark(Directory directory) async {
    // Ask iOS to create a minimal bookmark
    final String bookmarkB64 =
        await _channel.invokeMethod<String>('createBookmark', {
          'path': directory.path,
        }) ??
        '';

    if (bookmarkB64.isEmpty) {
      throw Exception('Failed to create bookmark for ${directory.path}');
    }

    // Save bookmark in SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, bookmarkB64);
  }

  /// Resolves the saved bookmark into a Directory
  static Future<Directory> resolveSavedBookmark() async {
    final prefs = await SharedPreferences.getInstance();
    final bookmarkB64 = prefs.getString(_prefsKey);
    if (bookmarkB64 == null) {
      throw Exception('No vault bookmark found. Pick a folder first.');
    }

    final String path =
        await _channel.invokeMethod<String>('resolveBookmark', {
          'bookmark': bookmarkB64,
        }) ??
        '';

    if (path.isEmpty) {
      throw Exception('Failed to resolve bookmark');
    }

    return Directory(path);
  }

  /// Clears the saved bookmark
  static Future<void> clearBookmark() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
  }
}
