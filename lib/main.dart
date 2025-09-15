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
    await _readVaultFilesTest();
    _loadTasks();
  }

  Future<void> _readVaultFilesTestAgainAgainAgain() async {
    final dbManager = DatabaseManager();
    final vaultParser = VaultParser('');

    // 1️⃣ Try to get saved bookmark
    String? bookmark = await VaultBookmarkManager.getSavedBookmark();
    String vaultPath;

    if (bookmark != null) {
      // 2️⃣ Resolve bookmark
      vaultPath = await VaultBookmarkManager.resolveBookmark(bookmark);
    } else {
      // 3️⃣ User picks vault folder
      String? selectedPath = await FilePicker.platform.getDirectoryPath();
      if (selectedPath == null) return; // user cancelled
      vaultPath = selectedPath;

      // 4️⃣ Save a bookmark for future access
      await VaultBookmarkManager.createAndSaveBookmark(vaultPath);
    }

    vaultParser.vaultPath = vaultPath;
    final Directory vaultDirectory = Directory(vaultPath);

    // 5️⃣ Start accessing security scoped resource (you already have this)
    bool granted = await SecurityScopedResource.instance
        .startAccessingSecurityScopedResource(vaultDirectory);
    if (!granted) {
      debugPrint("Cannot access vault directory: $vaultPath");
      return;
    }

    debugPrint("Granted access to $vaultPath");

    // 6️⃣ Enumerate files recursively
    final List<File> files = vaultParser.getFilesInFolder(vaultPath);
    debugPrint("Found ${files.length} markdown files.");

    for (File file in files) {
      DateTime? lastRead = await dbManager.getFileLastRead(file.path);
      if (lastRead == null || file.lastModifiedSync().isAfter(lastRead)) {
        debugPrint('${file.path} has changed, parsing tasks');
        final tasks = await vaultParser.parseTasksFromFile(file);

        for (final task in tasks) {
          Task? prev = await dbManager.getTaskById(task.id);
          if (prev != null) {
            if (prev.reminderDate != task.reminderDate) {
              await flutterLocalNotificationsPlugin.cancel(task.id);
              _setReminderForTask(task);
              dbManager.insertTask(task);
            }
          } else {
            _setReminderForTask(task);
            dbManager.insertTask(task);
          }
        }

        await dbManager.updateFileLastRead(file.path, DateTime.now());
      }
    }

    // 7️⃣ Stop accessing resource
    await SecurityScopedResource.instance.stopAccessingSecurityScopedResource(
      vaultDirectory,
    );
  }

  Future<void> _readVaultFilesTestAgainAgain() async {
    final databaseManager = DatabaseManager();

    Directory vaultDirectory;

    // Try to resolve the saved bookmark
    try {
      vaultDirectory = await VaultBookmarkManager.resolveSavedBookmark();
      debugPrint(
        'Resolved vault directory from bookmark: ${vaultDirectory.path}',
      );
    } catch (e) {
      // If no bookmark exists, ask the user to pick a folder
      String? pickedPath = await FilePicker.platform.getDirectoryPath();
      if (pickedPath == null) {
        debugPrint('No vault directory selected.');
        return;
      }
      vaultDirectory = Directory(pickedPath);

      // Create and save bookmark for future access
      await VaultBookmarkManager.createAndSaveBookmark(vaultDirectory);
      debugPrint(
        'Created bookmark for vault directory: ${vaultDirectory.path}',
      );
    }

    // Start accessing security-scoped resource
    final granted = await SecurityScopedResource.instance
        .startAccessingSecurityScopedResource(vaultDirectory);
    if (!granted) {
      debugPrint('Cannot access vault: permission denied');
      return;
    }
    debugPrint('Granted access to ${vaultDirectory.path}');

    // Parse files
    final vaultParser = VaultParser(vaultDirectory.path);
    final files = vaultParser.getFilesInFolder(vaultDirectory.path);
    debugPrint('Found ${files.length} markdown files.');

    for (File file in files) {
      DateTime? lastReadFileDateTime = await databaseManager.getFileLastRead(
        file.path,
      );

      if (lastReadFileDateTime == null ||
          file.lastModifiedSync().isAfter(lastReadFileDateTime)) {
        debugPrint('${file.path} has been updated, parsing tasks');

        final tasks = await vaultParser.parseTasksFromFile(file);
        for (final task in tasks) {
          final prevTaskVersion = await databaseManager.getTaskById(task.id);
          if (prevTaskVersion != null) {
            if (prevTaskVersion.reminderDate != task.reminderDate) {
              await flutterLocalNotificationsPlugin.cancel(task.id);
              _setReminderForTask(task);
              databaseManager.insertTask(task);
            }
          } else {
            _setReminderForTask(task);
            databaseManager.insertTask(task);
          }
        }

        await databaseManager.updateFileLastRead(file.path, DateTime.now());
      }
    }

    // Stop accessing security-scoped resource
    await SecurityScopedResource.instance.stopAccessingSecurityScopedResource(
      vaultDirectory,
    );
    debugPrint('Stopped access to ${vaultDirectory.path}');
  }

  Future<void> _readVaultFilesTestAgain() async {
    final prefs = await SharedPreferences.getInstance();
    String? bookmark = prefs.getString('vault_bookmark');

    late String vaultPath;
    if (bookmark != null) {
      // Resolve saved bookmark
      try {
        vaultPath = await Bookmarks.resolveBookmark(bookmark);
      } catch (e) {
        debugPrint('Failed to resolve bookmark, picking folder: $e');
        bookmark = null;
      }
    }

    if (bookmark == null) {
      // Pick folder and create bookmark
      String? selectedPath = await FilePicker.platform.getDirectoryPath();
      if (selectedPath == null) return;

      vaultPath = selectedPath;

      try {
        bookmark = await Bookmarks.createBookmark(vaultPath);
        await prefs.setString('vault_bookmark', bookmark);
      } catch (e) {
        debugPrint('Failed to create bookmark: $e');
        return;
      }
    }

    final vaultDir = Directory(vaultPath);
    final grantedAccessToVault = await SecurityScopedResource.instance
        .startAccessingSecurityScopedResource(vaultDir);

    debugPrint('Granted access to $vaultPath: $grantedAccessToVault');

    // Your existing parsing logic
    VaultParser vaultParser = VaultParser(vaultPath);
    DatabaseManager databaseManager = DatabaseManager();
    List<File> files = vaultParser.getFilesInFolder(vaultPath);

    for (File file in files) {
      DateTime? lastReadFileDateTime = await databaseManager.getFileLastRead(
        file.path,
      );

      if (lastReadFileDateTime == null ||
          file.lastModifiedSync().isAfter(lastReadFileDateTime)) {
        debugPrint('${file.path} has been updated, parsing tasks');

        List<Task> tasks = await vaultParser.parseTasksFromFile(file);

        for (Task task in tasks) {
          Task? prevTaskVersion = await databaseManager.getTaskById(task.id);
          if (prevTaskVersion != null) {
            if (prevTaskVersion.reminderDate != task.reminderDate) {
              await flutterLocalNotificationsPlugin.cancel(task.id);
              _setReminderForTask(task);
              databaseManager.insertTask(task);
            }
          } else {
            _setReminderForTask(task);
            databaseManager.insertTask(task);
          }
        }

        await databaseManager.updateFileLastRead(file.path, DateTime.now());
      }
    }

    await SecurityScopedResource.instance.stopAccessingSecurityScopedResource(
      vaultDir,
    );
  }

  Future<void> _readVaultFilesTest() async {
    String? vaultPath = await getVaultPath();
    if (vaultPath == null) return;

    VaultParser vaultParser = VaultParser(vaultPath);
    vaultParser.vaultPath = vaultPath;
    DatabaseManager databaseManager = DatabaseManager();
    String? selectedPath = await FilePicker.platform.getDirectoryPath();

    Directory vaultDirectory = Directory(selectedPath!);
    bool grantedAccessToVault = await SecurityScopedResource.instance
        .startAccessingSecurityScopedResource(vaultDirectory);
    debugPrint('granted access to ${vaultPath}: $grantedAccessToVault');
    List<File> files = vaultParser.getFilesInFolder(selectedPath);
    for (File file in files) {
      DateTime? lastReadFileDateTime = await databaseManager.getFileLastRead(
        file.path,
      );

      if (lastReadFileDateTime == null ||
          file.lastModifiedSync().isAfter(lastReadFileDateTime)) {
        debugPrint('${file.path} has been updated, parsing tasks');

        List<Task> tasks = await vaultParser.parseTasksFromFile(file);

        for (Task task in tasks) {
          Task? prevTaskVersion = await databaseManager.getTaskById(task.id);
          if (prevTaskVersion != null) {
            if (prevTaskVersion.reminderDate != task.reminderDate) {
              await flutterLocalNotificationsPlugin.cancel(task.id);
              _setReminderForTask(task);
              databaseManager.insertTask(task);
            }
          } else {
            _setReminderForTask(task);
            databaseManager.insertTask(task);
          }
        }

        await databaseManager.updateFileLastRead(file.path, DateTime.now());
      }
    }

    await SecurityScopedResource.instance.stopAccessingSecurityScopedResource(
      vaultDirectory,
    );
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
        onPressed: _readVaultFilesTestAgainAgainAgain,
        tooltip: 'Parse Vault & Reload Tasks',
        child: const Icon(Icons.open_in_new_rounded),
      ),
    );
  }
}
