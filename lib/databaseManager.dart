// lib/parser/vault_parser.dart

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:obsidian_buddy/task.dart';
import 'package:sqflite/sqflite.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart';

class DatabaseManager {
  // Private constructor
  DatabaseManager._internal() {
    db = _initDb();
  }

  // The single instance
  static final DatabaseManager _instance = DatabaseManager._internal();

  // Factory constructor returns the single instance
  factory DatabaseManager() => _instance;

  late Future<Database> db;

  Future<Database> _initDb() async {
    WidgetsFlutterBinding.ensureInitialized();
    debugPrint('opening db');
    return openDatabase(
      join(await getDatabasesPath(), 'tasks_database.db'),
      version: 2,
      onCreate: (db, version) async {
        // Tasks table
        await db.execute('''
        CREATE TABLE tasks(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          task TEXT,
          file_path TEXT,
          last_read TEXT,
          reminder_date TEXT
        )
      ''');

        // Files table to store last read timestamp per file
        await db.execute('''
        CREATE TABLE files(
          file_path TEXT PRIMARY KEY,
          last_read TEXT
        )
      ''');
      },
    );
  }

  Future<void> updateFileLastRead(String filePath, DateTime lastRead) async {
    final database = await db;
    await database.insert(
      'files',
      {'file_path': filePath, 'last_read': lastRead.toIso8601String()},
      conflictAlgorithm: ConflictAlgorithm.replace, // overwrite if exists
    );
  }

  Future<DateTime?> getFileLastRead(String filePath) async {
    final database = await db;
    final result = await database.query(
      'files',
      where: 'file_path = ?',
      whereArgs: [filePath],
    );

    if (result.isNotEmpty) {
      return DateTime.parse(result.first['last_read'] as String);
    }
    return null; // file not found
  }

  Future<void> insertTask(Task task) async {
    final database = await db;
    await database.insert(
      'tasks',
      task.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Task?> getTaskById(int id) async {
    final database = await db;

    final result = await database.query(
      'tasks',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (result.isNotEmpty) {
      return Task.fromMap(result.first);
    }

    return null; // task not found
  }

  Future<List<Task>> getAllTasks() async {
    final database = await db;

    final results = await database.query(
      'tasks',
      orderBy: 'reminder_date ASC', // optional: sort by reminder
    );

    return results.map((map) => Task.fromMap(map)).toList();
  }
}
