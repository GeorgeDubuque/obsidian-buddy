// lib/parser/vault_parser.dart

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:obsidian_buddy/databaseManager.dart';
import 'package:obsidian_buddy/task.dart';
import 'package:security_scoped_resource/security_scoped_resource.dart';
import 'package:sqflite/sqflite.dart';

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
  Future<Map<int, Task>> parseTasksFromFile(File file) async {
    List<String> lines = await file.readAsLines();
    Map<int, Task> tasks = {};

    // Regex breakdown:
    // ^- \[ \]      : matches the start of a task "- [ ]"
    // (.*?)         : lazily captures task text
    // ⏳\s*         : matches the hourglass emoji and optional whitespace
    // (\d{4}-\d{2}-\d{2}) : captures the date
    // (?:\s+(\d{2}:\d{2}))? : optionally captures the time
    final taskRegex = RegExp(
      r'^- \[ \]\s*(.*?)\s*⏳\s*(\d{4}-\d{2}-\d{2})(?:\s+(\d{2}:\d{2}))?',
    );

    for (var line in lines) {
      final match = taskRegex.firstMatch(line);
      if (match != null) {
        final taskText = match.group(1)!; // the actual task text
        final dateString = match.group(2)!;
        final timeString = match.group(3);

        DateTime dueDate;
        // TODO: make it so we do something with tasks that just have a scheduled date and no time
        if (timeString != null) {
          dueDate = DateTime.parse('$dateString $timeString:00');
          Task currTask = Task(
            task: taskText,
            filePath: file.path,
            reminderDate: dueDate,
          );

          tasks[currTask.id] = currTask;

          print('Task: $taskText');
          print('Due Date: $dueDate');
        } else {
          dueDate = DateTime.parse(dateString);
        }
      }
    }

    return tasks;
  }

  List<File> getFilesInFolder(String folderPath) {
    final vaultDirectory = Directory(folderPath);
    final List<File> files = [];

    void walkDir(Directory dir) {
      try {
        final entities = dir.listSync(recursive: false);
        for (final e in entities) {
          if (e is File &&
              e.path.endsWith('.md') &&
              !e.path.endsWith('.excalidraw.md')) {
            files.add(e);
          } else if (e is Directory) {
            walkDir(e); // recurse manually
          }
        }
      } catch (e) {
        debugPrint('Cannot access directory ${dir.path}: $e');
        // ignore this folder, iOS sandbox prevents access
      }
    }

    walkDir(vaultDirectory);

    debugPrint('Found ${files.length} markdown files.');
    return files;
  }

  // You can add helper methods here
}
