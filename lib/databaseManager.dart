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
      version: 3, // Increment version for schema change
      onCreate: (db, version) async {
        // Tasks table - remove AUTOINCREMENT since Task class generates its own IDs
        await db.execute('''
        CREATE TABLE tasks(
          id INTEGER PRIMARY KEY,
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
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 3) {
          // Drop the old table and recreate it without AUTOINCREMENT
          await db.execute('DROP TABLE IF EXISTS tasks_backup');
          await db.execute('ALTER TABLE tasks RENAME TO tasks_backup');

          // Create new table without AUTOINCREMENT
          await db.execute('''
          CREATE TABLE tasks(
            id INTEGER PRIMARY KEY,
            task TEXT,
            file_path TEXT,
            last_read TEXT,
            reminder_date TEXT
          )
        ''');

          // Migrate data - this will recalculate IDs using the Task class logic
          final oldTasks = await db.query('tasks_backup');
          for (final taskMap in oldTasks) {
            final task = Task.fromMap(taskMap);
            await db.insert(
              'tasks',
              task.toMap(),
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }

          // Drop the backup table
          await db.execute('DROP TABLE tasks_backup');
        }
      },
    );
  }

  Future<void> updateFileLastRead(String filePath, DateTime lastRead) async {
    final database = await db;
    await database.insert('files', {
      'file_path': filePath,
      'last_read': lastRead.toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
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
    return null;
  }

  Future<void> insertTask(Task task) async {
    final database = await db;
    await database.insert(
      'tasks',
      task.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> updateTask(Task task) async {
    final database = await db;
    await database.update(
      'tasks',
      task.toMap(),
      where: 'id = ?',
      whereArgs: [task.id],
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
    return null;
  }

  Future<List<Task>> getAllTasks() async {
    final database = await db;
    final results = await database.query('tasks', orderBy: 'reminder_date ASC');
    return results.map((map) => Task.fromMap(map)).toList();
  }

  Future<int> deleteTaskById(int id) async {
    final database = await db;
    return await database.delete('tasks', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Task>> getTasksByPath(String filePath) async {
    final database = await db;
    final results = await database.query(
      'tasks',
      where: 'file_path = ?',
      whereArgs: [filePath],
      orderBy: 'reminder_date ASC',
    );
    return results.map((map) => Task.fromMap(map)).toList();
  }

  // Helper method to clean up and debug
  Future<void> debugDatabase() async {
    final database = await db;
    final results = await database.query('tasks');
    print("=== DATABASE DEBUG ===");
    print("Total tasks in database: ${results.length}");
    for (final taskMap in results) {
      final task = Task.fromMap(taskMap);
      print("ID: ${task.id}, Task: ${task.task}, File: ${task.filePath}");
    }
    print("=== END DEBUG ===");
  }

  Future<void> clearAllTasks() async {
    final database = await db;
    await database.delete('tasks');
    print("All tasks cleared from database");
  }
}
