// lib/parser/vault_parser.dart

import 'dart:io';

import 'package:flutter/material.dart';

class VaultParser {
  // Private constructor
  VaultParser._internal();

  // The single instance
  static final VaultParser _instance = VaultParser._internal();
  String vaultPath = '';

  // Factory constructor returns the single instance
  factory VaultParser(String vaultPath) {
    return _instance;
  }

  // Public methods
  Future<List<dynamic>> parseTasksFromFile(File file) async {
    List<String> lines = await file.readAsLines();
    for (var line in lines) {
      if (line.startsWith('- [ ]')) {
        final dateTimeRegex = RegExp(
          r'⏳\s*(\d{4}-\d{2}-\d{2})(?:\s+(\d{2}:\d{2}))?',
        );

        final match = dateTimeRegex.firstMatch(line);
        if (match != null) {
          print('Found scheduled task in ${file.path}');
          print(line);
          final dateString = match.group(1)!; // "2025-10-01"
          final timeString = match.group(2); // "14:30" or null

          print('Found date: $dateString');
          print('Found time: $timeString');
          DateTime dueDate;
          if (timeString != null) {
            dueDate = DateTime.parse(
              '$dateString $timeString:00',
            ); // add seconds
          } else {
            dueDate = DateTime.parse(dateString);
          }

          print('Parsed DateTime: $dueDate');
        }
      }
    }
    return [];
  }

  List<File> getFilesInFolder(String folderPath) {
    // TODO: implement vault-wide parsing
    debugPrint("Parsing files from vault path: $folderPath");
    final vaultDirectory = Directory(folderPath);

    final files = Directory(vaultPath)
        .listSync(recursive: true)
        .where(
          (e) =>
              e is File &&
              !e.path.endsWith('.excalidraw.md') &&
              e.path.endsWith('.md'),
        )
        .cast<File>()
        .toList();

    debugPrint("Found ${files.length} files.");

    return files;
  }

  // You can add helper methods here
}
