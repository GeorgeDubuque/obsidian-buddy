import 'package:flutter/services.dart';

class Bookmarks {
  static const MethodChannel _channel = MethodChannel('bookmarks');

  /// Create a minimal bookmark from a path
  static Future<String> createBookmark(String path) async {
    final String bookmark = await _channel.invokeMethod('createBookmark', {
      'path': path,
    });
    return bookmark;
  }

  /// Resolve a bookmark back into a path
  static Future<String> resolveBookmark(String bookmark) async {
    final String path = await _channel.invokeMethod('resolveBookmark', {
      'bookmark': bookmark,
    });
    return path;
  }
}
