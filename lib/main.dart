import 'dart:convert';
import 'dart:io';
import 'dart:async';

import 'package:external_app_launcher/external_app_launcher.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:obsidian_buddy/bookmark.dart';
import 'package:obsidian_buddy/constants.dart';
import 'package:obsidian_buddy/databaseManager.dart';
import 'package:obsidian_buddy/task.dart';
import 'package:obsidian_buddy/vault_bookmark_manager.dart';
import 'package:obsidian_buddy/vault_parser.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:security_scoped_resource/security_scoped_resource.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/standalone.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:url_launcher/url_launcher.dart';

FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // initialize timezone
  tz.initializeTimeZones();
  final String currentTimeZone = await FlutterTimezone.getLocalTimezone();
  tz.setLocalLocation(tz.getLocation(currentTimeZone));

  // initialize notifications plugin
  FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();
  flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()
      ?.requestNotificationsPermission();

  flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin
      >()
      ?.requestPermissions(
        alert: true,
        badge: true,
        critical: true,
        sound: true,
        provisional: true,
      );

  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');

  final DarwinInitializationSettings
  initializationSettingsDarwin = DarwinInitializationSettings(
    requestAlertPermission: true,
    requestSoundPermission: true,
    requestBadgePermission: true,
    requestProvisionalPermission: true,
    requestCriticalPermission: true,
    notificationCategories: [
      DarwinNotificationCategory(
        'reminder',
        actions: <DarwinNotificationAction>[
          DarwinNotificationAction.plain(snooze5SecondsId, 'Snooze 5 Seconds'),
          DarwinNotificationAction.plain(snooze1MinutesId, 'Snooze 1 Minute'),
          DarwinNotificationAction.plain(snooze5MinutesId, 'Snooze 5 Minutes'),
          DarwinNotificationAction.plain(snooze1HourId, 'Snooze 1 Hour'),
          DarwinNotificationAction.plain(snooze1DayId, 'Snooze 1 Day'),
        ],
        options: <DarwinNotificationCategoryOption>{
          DarwinNotificationCategoryOption.hiddenPreviewShowTitle,
        },
      ),
    ],
  );

  final InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
    iOS: initializationSettingsDarwin,
  );

  // bind notification callbacks
  await flutterLocalNotificationsPlugin.initialize(
    initializationSettings,
    onDidReceiveNotificationResponse: onDidReceiveNotificationResponse,
    onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
  );

  // request storage permission
  final status = await Permission.manageExternalStorage.request();
  debugPrint(
    'ManageExternalStorage permission ${status.isGranted ? "is" : "isn\'t"} granted.',
  );

  if (!status.isGranted) {
    debugPrint('We need storage permission to read the vault!');
  }

  // vault selection
  VaultBookmarkManager.getOrCreateVaultPath();

  // initialize DB
  final dbManager = DatabaseManager();
  await dbManager.db;

  runApp(const ObsidianBuddy());
}

const String vaultKey = 'vault_path';

Future<String?> getVaultPath() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString(vaultKey);
}

Future<void> setVaultPath(String path) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(vaultKey, path);
}

Future<String?> pickVaultFolder() async {
  return FilePicker.platform.getDirectoryPath();
}

Future<void> selectVault() async {
  String? vaultPath;

  if (Platform.isAndroid) {
    // Only Android needs storage permission
    final status = await Permission.storage.request();
    if (!status.isGranted) {
      debugPrint('We need storage permission to read the vault!');
      return;
    }
  }

  // Pick vault folder (works on Android & iOS)
  vaultPath = await VaultBookmarkManager.getOrCreateVaultPath();

  if (vaultPath == null) {
    debugPrint('User cancelled folder selection.');
    return;
  }

  setVaultPath(vaultPath);
  debugPrint('Vault path set to: $vaultPath');
}

@pragma('vm:entry-point')
void notificationTapBackground(
  NotificationResponse notificationResponse,
) async {
  await handleSnooze(notificationResponse);
}

void onDidReceiveNotificationResponse(
  NotificationResponse notificationResponse,
) async {
  await handleSnooze(notificationResponse);
}

Future<void> handleSnooze(NotificationResponse notificationResponse) async {
  debugPrint('notification id: ${notificationResponse.id}');
  debugPrint('notification action id: ${notificationResponse.actionId}');

  tz.initializeTimeZones();
  final String currentTimeZone = await FlutterTimezone.getLocalTimezone();
  tz.setLocalLocation(tz.getLocation(currentTimeZone));

  tz.TZDateTime reminderTime = tz.TZDateTime.now(tz.local);

  if (notificationResponse.payload != null) {
    debugPrint('notification payload: ${notificationResponse.data.length}');

    final List<dynamic> notificationDetailsDecoded =
        jsonDecode(notificationResponse.payload!) as List<dynamic>;
    int taskId = notificationDetailsDecoded[0];

    final DatabaseManager dbManager = DatabaseManager();
    Task? task = await dbManager.getTaskById(taskId);

    if (task != null) {
      switch (notificationResponse.actionId) {
        case snooze5SecondsId:
          reminderTime = reminderTime.add(Duration(seconds: 5));
          _setReminderForTask(task, reminderTime);
        case snooze1MinutesId:
          reminderTime = reminderTime.add(Duration(minutes: 1));
          _setReminderForTask(task, reminderTime);
        case snooze5MinutesId:
          reminderTime = reminderTime.add(Duration(minutes: 5));
          _setReminderForTask(task, reminderTime);
        case snooze1HourId:
          reminderTime = reminderTime.add(Duration(hours: 1));
          _setReminderForTask(task, reminderTime);
        case snooze1DayId:
          reminderTime = reminderTime.add(Duration(days: 1));
          _setReminderForTask(task, reminderTime);
        case snooze1WeekId:
          reminderTime = reminderTime.add(Duration(days: 7));
          _setReminderForTask(task, reminderTime);
        default:
          reminderTime = reminderTime.add(Duration(minutes: 1));
          _setReminderForTask(task, reminderTime);
      }
    }
  }
}

void _setReminderForTask(Task task, [TZDateTime? reminderTime]) async {
  tz.initializeTimeZones();
  final String currentTimeZone = await FlutterTimezone.getLocalTimezone();
  tz.setLocalLocation(tz.getLocation(currentTimeZone));

  reminderTime ??= tz.TZDateTime.from(task.reminderDate, tz.local);

  NotificationDetails notificationDetails = const NotificationDetails(
    android: AndroidNotificationDetails(
      'reminders',
      'Reminders',
      channelDescription: 'Sending user reminders of their tasks.',
      importance: Importance.max,
      priority: Priority.high,
      actions: <AndroidNotificationAction>[actionSnooze5Seconds],
    ),
    iOS: DarwinNotificationDetails(
      categoryIdentifier: 'reminder',
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      presentBanner: true,
      presentList: true,
    ),
  );

  await flutterLocalNotificationsPlugin.zonedSchedule(
    task.id,
    task.task,
    task.task,
    reminderTime,
    notificationDetails,
    payload: jsonEncode([task.id, task.task]),
    androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
  );
}

class ObsidianBuddy extends StatelessWidget {
  const ObsidianBuddy({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Obsidian Buddy',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurpleAccent),
      ),
      home: const MyHomePage(title: 'Obsidian Buddy'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});
  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  String? vaultDirectoryPath = "";
  late Future<List<Task>> tasksFuture;

  @override
  void initState() {
    super.initState();
    _loadTasks();
  }

  void _loadTasks() {
    final dbManager = DatabaseManager();
    setState(() {
      tasksFuture = dbManager.getAllTasks();
    });
  }

  Future<void> _readVaultFilesWithBookmarks() async {
    final dbManager = DatabaseManager();
    final vaultParser = VaultParser('');
    late String? vaultPath;
    bool needsNewBookmark = false;

    debugPrint("=== Starting _readVaultFilesWithBookmarks ===");

    vaultPath = await VaultBookmarkManager.getOrCreateVaultPath();

    if (vaultPath == null) return;

    final vaultDirectory = Directory(vaultPath);
    print("Directory exists: ${await vaultDirectory.exists()}");

    // Use our native method instead of the plugin
    bool granted =
        await VaultBookmarkManager.startAccessingSecurityScopedResource(
          vaultPath,
        );

    if (!granted) {
      print("Cannot access vault directory: $vaultPath");
      // If we couldn't access with the resolved path, try getting a fresh selection
      if (!needsNewBookmark) {
        print("Trying to get fresh directory selection...");
        String? newPath = await FilePicker.platform.getDirectoryPath();
        if (newPath != null) {
          vaultPath = newPath;
          granted =
              await VaultBookmarkManager.startAccessingSecurityScopedResource(
                vaultPath,
              );
          needsNewBookmark = true;
        }
      }

      if (!granted) {
        print("Still cannot access vault directory after retry");
        return;
      }
    }

    try {
      debugPrint("Granted access to $vaultPath");

      // Create/update bookmark for future use
      if (needsNewBookmark) {
        try {
          await VaultBookmarkManager.createAndSaveBookmark(vaultPath);
          debugPrint("Created new bookmark successfully");
        } catch (e) {
          debugPrint("Failed to create bookmark: $e");
        }
      }

      // Enumerate markdown files
      List<File> files = vaultParser.getFilesInFolder(vaultPath);
      debugPrint("Found ${files.length} markdown files.");

      for (File file in files) {
        DateTime? lastRead = await dbManager.getFileLastRead(file.path);
        if (lastRead == null || file.lastModifiedSync().isAfter(lastRead)) {
          debugPrint('${file.path} has changed, parsing tasks');

          final currTasksInFile = await vaultParser.parseTasksFromFile(file);
          final currTasksInDb = await dbManager.getTasksByPath(file.path);
          debugPrint("Found ${currTasksInFile.length} tasks in ${file.path}");

          for (Task dbTask in currTasksInDb) {
            debugPrint("Processing task: ${dbTask.task} (ID: ${dbTask.id})");

            Task? existingTaskInFile = await currTasksInFile[dbTask.id];
            if (existingTaskInFile != null) {
              debugPrint("Task already exists in database");
              if (existingTaskInFile.reminderDate != dbTask.reminderDate) {
                debugPrint(
                  "Reminder date changed, updating task and notification",
                );
                await flutterLocalNotificationsPlugin.cancel(dbTask.id);
                _setReminderForTask(existingTaskInFile);
                await dbManager.updateTask(existingTaskInFile);
              } else {
                debugPrint("Task unchanged, skipping");
              }
            } else {
              // task no longer exists in file remove it from db and cancel reminder

              debugPrint(
                "Task removed from file. Removing from db and cancelling.",
              );
              await flutterLocalNotificationsPlugin.cancel(dbTask.id);
              dbManager.deleteTaskById(dbTask.id);
            }

            // done processing existing task remove it from task list
            currTasksInFile.remove(dbTask.id);
          }

          // need to loop through new tasks in file
          currTasksInFile.forEach((taskId, taskInFile) async {
            debugPrint(
              "Found new task ${taskInFile.reminderDate} setting reminder for ${taskInFile.reminderDate}",
            );
            await dbManager.insertTask(taskInFile);
            _setReminderForTask(taskInFile);
          });
          await dbManager.updateFileLastRead(file.path, DateTime.now());
        } else {
          //print("File ${file.path} hasn't changed since last read");
        }
      }
      _loadTasks();
    } finally {
      // Always stop accessing resource when done
      await VaultBookmarkManager.stopAccessingSecurityScopedResource(vaultPath);
      print("Stopped accessing security-scoped resource");
    }

    print("Finished processing vault files.");
  }

  // Example placeholders for Obsidian opening functions
  Future<void> _openObsidianFile() async {}
  Future<void> _openObsidian() async {}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      body: FutureBuilder<List<Task>>(
        future: tasksFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('No tasks found'));
          }

          final tasks = snapshot.data!;
          return ListView.builder(
            itemCount: tasks.length,
            itemBuilder: (context, index) {
              final task = tasks[index];
              return Card(
                margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                child: ListTile(
                  title: Text(task.task),
                  subtitle: Text(
                    'Reminder: ${task.reminderDate.toLocal()}\nLast read: ${task.lastRead.toLocal()}',
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.notifications),
                    onPressed: () => _setReminderForTask(task),
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _readVaultFilesWithBookmarks,
        tooltip: 'Parse Vault & Reload Tasks',
        child: const Icon(Icons.open_in_new_rounded),
      ),
    );
  }
}
