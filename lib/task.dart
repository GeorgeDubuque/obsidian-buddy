import 'dart:convert';
import 'package:crypto/crypto.dart';

int generateTaskIdInt(String task, String filePath) {
  final input = '$task|$filePath';
  final digest = sha1.convert(utf8.encode(input)).bytes;

  // Take first 4 bytes of SHA1 and convert to int
  int id = 0;
  for (int i = 0; i < 4; i++) {
    id = (id << 8) | digest[i];
  }

  return id & 0x7FFFFFFF; // ensure positive 32-bit integer
}

class Task {
  final int id; // deterministic int hash
  final String task;
  final String filePath;
  final DateTime lastRead;
  final DateTime reminderDate;

  Task({
    required this.task,
    required this.filePath,
    DateTime? lastRead,
    required this.reminderDate,
  }) : lastRead = lastRead ?? DateTime.now(),
       id = generateTaskIdInt(task, filePath);

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'task': task,
      'file_path': filePath,
      'last_read': lastRead.toIso8601String(),
      'reminder_date': reminderDate.toIso8601String(),
    };
  }

  factory Task.fromMap(Map<String, dynamic> map) {
    return Task(
      task: map['task'],
      filePath: map['file_path'],
      lastRead: map['last_read'] != null
          ? DateTime.parse(map['last_read'])
          : null,
      reminderDate: DateTime.parse(map['reminder_date']),
    );
    // Note: The ID will be recalculated automatically in the constructor
    // This should match the stored ID if the task and filePath are the same
  }
}
