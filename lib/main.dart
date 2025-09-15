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

  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');

  final DarwinInitializationSettings initializationSettingsDarwin =
      DarwinInitializationSettings(
        requestAlertPermission: true,
        requestSoundPermission: true,
        requestBadgePermission: true,
        requestProvisionalPermission: true,
        requestCriticalPermission: true,
        notificationCategories: [
          DarwinNotificationCategory(
            'reminder',
            actions: <DarwinNotificationAction>[
              DarwinNotificationAction.plain(
                'snooze-5-seconds',
                'Snooze 5 Seconds',
                options: <DarwinNotificationActionOption>{
                  DarwinNotificationActionOption.foreground,
                },
              ),
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
  String? vaultFolderPath = await getVaultPath();
  await selectVault();

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
  String? vaultFolderPath;

  if (Platform.isAndroid) {
    // Only Android needs storage permission
    final status = await Permission.storage.request();
    if (!status.isGranted) {
      debugPrint('We need storage permission to read the vault!');
      return;
    }
  }

  // Pick vault folder (works on Android & iOS)
  vaultFolderPath = await FilePicker.platform.getDirectoryPath();

  if (vaultFolderPath == null) {
    debugPrint('User cancelled folder selection.');
    return;
  }

  setVaultPath(vaultFolderPath);
  debugPrint('Vault path set to: $vaultFolderPath');
}

@pragma('vm:entry-point')
void notificationTapBackground(
  NotificationResponse notificationResponse,
) async {
  debugPrint('action id: ${notificationResponse.actionId}');
  if (notificationResponse.actionId == actionSnooze5Seconds.id) {
    if (notificationResponse.payload != null) {
      final List<dynamic> notificationDetailsDecoded =
          jsonDecode(notificationResponse.payload!) as List<dynamic>;
      _setReminder5SecondsFromNow(
        notificationDetailsDecoded[0],
        notificationDetailsDecoded[1],
      );
    }
  }
}

void onDidReceiveNotificationResponse(
  NotificationResponse notificationResponse,
) async {
  final String? payload = notificationResponse.payload;
  debugPrint('notification id: ${notificationResponse.id}');
  debugPrint('notification action id: ${notificationResponse.actionId}');

  if (notificationResponse.actionId == snooze5SecondsId &&
      notificationResponse.payload != null) {
    final List<dynamic> notificationDetailsDecoded =
        jsonDecode(notificationResponse.payload!) as List<dynamic>;
    _setReminder5SecondsFromNow(
      notificationDetailsDecoded[0],
      notificationDetailsDecoded[1],
    );
  }

  if (notificationResponse.payload != null) {
    debugPrint('notification payload: ${notificationResponse.data.length}');
  }
}

void _setReminder5SecondsFromNow(String title, String description) async {
  tz.initializeTimeZones();
  final String currentTimeZone = await FlutterTimezone.getLocalTimezone();
  tz.setLocalLocation(tz.getLocation(currentTimeZone));

  tz.TZDateTime reminderTime = tz.TZDateTime.now(
    tz.local,
  ).add(const Duration(seconds: 5));

  _setReminder(reminderTime, title, description);
}

void _setReminderForTask(Task task) async {
  tz.initializeTimeZones();
  final String currentTimeZone = await FlutterTimezone.getLocalTimezone();
  tz.setLocalLocation(tz.getLocation(currentTimeZone));

  tz.TZDateTime reminderTime = tz.TZDateTime.from(task.reminderDate, tz.local);

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
    payload: jsonEncode([task.task, task.task, actionSnooze5Seconds.id]),
    androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
  );
}

void _setReminder(
  tz.TZDateTime dateTime,
  String title,
  String description,
) async {
  tz.initializeTimeZones();
  final String currentTimeZone = await FlutterTimezone.getLocalTimezone();
  tz.setLocalLocation(tz.getLocation(currentTimeZone));

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
    0,
    title,
    description,
    dateTime,
    notificationDetails,
    payload: jsonEncode([title, description, actionSnooze5Seconds.id]),
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

  Future<void> _readVaultFilesAndReload() async {
    await _readVaultFilesWithBookmarks();
    _loadTasks();
  }

  Future<void> _readVaultFilesWithBookmarks() async {
    final dbManager = DatabaseManager();
    final vaultParser = VaultParser('');
    late String vaultPath;
    bool needsNewBookmark = false;

    print("=== Starting _readVaultFilesWithBookmarks ===");

    String? bookmark = await VaultBookmarkManager.getSavedBookmark();
    print("Bookmark exists: ${bookmark != null}");

    if (bookmark != null) {
      try {
        // Try to resolve saved bookmark
        vaultPath = await VaultBookmarkManager.resolveBookmark(bookmark);
        print("Successfully resolved bookmark to: $vaultPath");
      } catch (e) {
        print("Failed to resolve saved bookmark: $e");
        needsNewBookmark = true;
      }
    } else {
      needsNewBookmark = true;
    }

    if (needsNewBookmark) {
      // User must pick the vault folder
      String? selectedPath = await FilePicker.platform.getDirectoryPath();
      if (selectedPath == null) return; // user cancelled
      vaultPath = selectedPath;
      print("User selected new path: $vaultPath");
    }

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
      print("Granted access to $vaultPath");

      // Create/update bookmark for future use
      if (needsNewBookmark) {
        try {
          await VaultBookmarkManager.createAndSaveBookmark(vaultPath);
          print("Created new bookmark successfully");
        } catch (e) {
          print("Failed to create bookmark: $e");
        }
      }

      // Enumerate markdown files
      List<File> files = vaultParser.getFilesInFolder(vaultPath);
      print("Found ${files.length} markdown files.");

      for (File file in files) {
        DateTime? lastRead = await dbManager.getFileLastRead(file.path);
        if (lastRead == null || file.lastModifiedSync().isAfter(lastRead)) {
          print('${file.path} has changed, parsing tasks');

          final tasks = await vaultParser.parseTasksFromFile(file);
          print("Found ${tasks.length} tasks in ${file.path}");

          for (final task in tasks) {
            print("Processing task: ${task.task} (ID: ${task.id})");

            Task? existingTask = await dbManager.getTaskById(task.id);
            if (existingTask != null) {
              print("Task already exists in database");
              if (existingTask.reminderDate != task.reminderDate) {
                print("Reminder date changed, updating task and notification");
                await flutterLocalNotificationsPlugin.cancel(task.id);
                _setReminderForTask(task);
                await dbManager.updateTask(task);
              } else {
                print("Task unchanged, skipping");
              }
            } else {
              print("New task, inserting into database");
              _setReminderForTask(task);
              await dbManager.insertTask(task);
            }
          }
          await dbManager.updateFileLastRead(file.path, DateTime.now());
        } else {
          print("File ${file.path} hasn't changed since last read");
        }
      }
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
