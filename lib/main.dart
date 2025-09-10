import 'dart:convert';
import 'dart:io';

import 'package:external_app_launcher/external_app_launcher.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:obsidian_buddy/constants.dart';
import 'package:obsidian_buddy/vault_parser.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:url_launcher/url_launcher.dart';

FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  tz.initializeTimeZones();
  final String currentTimeZone = await FlutterTimezone.getLocalTimezone();
  tz.setLocalLocation(tz.getLocation(currentTimeZone));

  // initialise the plugin. app_icon needs to be a added as a drawable resource to the Android head project
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
        // ...
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
  final bool? result = await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin
      >()
      ?.requestPermissions(alert: true, badge: true, sound: true);
  final InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
    iOS: initializationSettingsDarwin,
  );

  await flutterLocalNotificationsPlugin.initialize(
    initializationSettings,
    onDidReceiveNotificationResponse: onDidReceiveNotificationResponse,
    onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
  );

  final status = await Permission.manageExternalStorage.request();
  debugPrint(
    'ManageExternalStorage permission ${status.isGranted ? "is" : "isn't"} granted.',
  );
  if (status.isGranted == false) {
    //TODO: show a little message when they dont grant because app wont work if they dont
    debugPrint('we need that permission bruv sowwy :(');
  }

  String? vaultFolderPath = await getVaultPath();
  vaultFolderPath ??= await pickVaultFolder();

  setVaultPath(vaultFolderPath!);

  runApp(const ObsidianBuddy());
}

const String vaultKey = 'vault_path';

/// Get stored vault path (returns null if none)
Future<String?> getVaultPath() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString(vaultKey);
}

/// Store vault path
Future<void> setVaultPath(String path) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(vaultKey, path);
}

/// Pick a folder using FilePicker
Future<String?> pickVaultFolder() async {
  final result = await FilePicker.platform.getDirectoryPath();
  return result; // null if user cancels
}

@pragma('vm:entry-point')
void notificationTapBackground(
  NotificationResponse notificationResponse,
) async {
  debugPrint('action id: ${notificationResponse.actionId}');
  if (notificationResponse.actionId == actionSnooze5Seconds.id) {
    if (notificationResponse == null || notificationResponse.payload == null) {
      debugPrint('Notification payload missing! Something is wrong!!!');
      return;
    }

    final List<dynamic> notificationDetailsDecoded =
        jsonDecode(notificationResponse.payload!) as List<dynamic>;

    _setReminder5SecondsFromNow(
      notificationDetailsDecoded[0],
      notificationDetailsDecoded[1],
    );
  }

  // handle action
}

void onDidReceiveNotificationResponse(
  NotificationResponse notificationResponse,
) async {
  final String? payload = notificationResponse.payload;
  debugPrint('notification id: ${notificationResponse.id}');
  debugPrint('notification action id: ${notificationResponse.actionId}');
  if (notificationResponse.actionId == snooze5SecondsId) {
    if (notificationResponse == null || notificationResponse.payload == null) {
      debugPrint('Notification payload missing! Something is wrong!!!');
      return;
    }
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

void _setReminder(
  tz.TZDateTime dateTime,
  String title,
  String description,
) async {
  NotificationDetails notificationDetails = const NotificationDetails(
    android: AndroidNotificationDetails(
      'reminders', //channel id
      'Reminders', // channel name
      channelDescription:
          'Sending user reminders of their tasks.', // channel desc
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
    //TODO:: add ios
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

  // This widget is the root of your application.

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Obsidian Buddy',
      theme: ThemeData(
        // This is the theme of your application.
        //
        // TRY THIS: Try running your application with "flutter run". You'll see
        // the application has a purple toolbar. Then, without quitting the app,
        // try changing the seedColor in the colorScheme below to Colors.green
        // and then invoke "hot reload" (save your changes or press the "hot
        // reload" button in a Flutter-supported IDE, or press "r" if you used
        // the command line to start the app).
        //
        // Notice that the counter didn't reset back to zero; the application
        // state is not lost during the reload. To reset the state, use hot
        // restart instead.
        //
        // This works for code too, not just values: Most code changes can be
        // tested with just a hot reload.
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurpleAccent),
      ),
      home: const MyHomePage(title: 'Obsidian Buddy'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int _counter = 0;
  String? vaultDirectoryPath = "";
  // Method 1: Open specific file in specific vault
  Future<void> _openObsidianFile() async {
    try {
      // Properly encode the file path
      final String vaultName = 'Gtd';
      final String filePath =
          'Completed Projects/Add End of Stream Music Button on Stream Deck';
      final int lineNumber = 200;

      final String obsidianUrl =
          'obsidian://open?vault=${Uri.encodeComponent(vaultName)}&file=${Uri.encodeComponent(filePath)}&line=$lineNumber&mode=edit';

      print('Opening URL: $obsidianUrl'); // Debug line

      if (await canLaunchUrl(Uri.parse(obsidianUrl))) {
        await launchUrl(
          Uri.parse(obsidianUrl),
          mode: LaunchMode.externalApplication,
        );
      } else {
        // Fallback: try to open Obsidian app first
        //await _openObsidianApp();
      }
    } catch (e) {
      print('Error opening specific file: $e');
      //await _openObsidianApp();
    }
  }

  Future<void> _openObsidian() async {
    try {
      await LaunchApp.openApp(
        androidPackageName: 'md.obsidian',
        iosUrlScheme: 'obsidian://',
        appStoreLink:
            'https://apps.apple.com/app/obsidian-connected-notes/id1557175442',
        openStore: true, // Opens store if app is not installed
      );
    } catch (e) {
      print('Error launching Obsidian: $e');
    }
    setState(() {
      // This call to setState tells the Flutter framework that something has
      // changed in this State, which causes it to rerun the build method below
      // so that the display can reflect the updated values. If we changed
      // _counter without calling setState(), then the build method would not be
      // called again, and so nothing would appear to happen.

      _counter++;
    });
  }

  void _scheduleReminderTest() async {
    tz.initializeTimeZones();
    final String currentTimeZone = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(currentTimeZone));

    _setReminder(
      tz.TZDateTime.now(tz.local).add(Duration(seconds: 1)),
      'initial',
      'initial',
    );
  }

  void _readVaultFilesTest() async {
    String? vaultPath = await getVaultPath();
    if (vaultPath == null) {
      debugPrint(
        'Cant read vault cause vault path is returning null or empty. Something is wrong!!!',
      );
      return;
    }
    VaultParser vaultParser = VaultParser(vaultPath);
    vaultParser.vaultPath = vaultPath;

    List<File> files = vaultParser.getFilesInFolder(vaultPath);
    for (File file in files) {
      vaultParser.parseTasksFromFile(file);
    }
  }

  @override
  Widget build(BuildContext context) {
    // This method is rerun every time setState is called, for instance as done
    // by the _incrementCounter method above.
    //
    // The Flutter framework has been optimized to make rerunning build methods
    // fast, so that you can just rebuild anything that needs updating rather
    // than having to individually change instances of widgets.
    return Scaffold(
      appBar: AppBar(
        // TRY THIS: Try changing the color here to a specific color (to
        // Colors.amber, perhaps?) and trigger a hot reload to see the AppBar
        // change color while the other colors stay the same.
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        // Here we take the value from the MyHomePage object that was created by
        // the App.build method, and use it to set our appbar title.
        title: Text(widget.title),
      ),
      body: Center(
        // Center is a layout widget. It takes a single child and positions it
        // in the middle of the parent.
        child: Column(
          // Column is also a layout widget. It takes a list of children and
          // arranges them vertically. By default, it sizes itself to fit its
          // children horizontally, and tries to be as tall as its parent.
          //
          // Column has various properties to control how it sizes itself and
          // how it positions its children. Here we use mainAxisAlignment to
          // center the children vertically; the main axis here is the vertical
          // axis because Columns are vertical (the cross axis would be
          // horizontal).
          //
          // TRY THIS: Invoke "debug painting" (choose the "Toggle Debug Paint"
          // action in the IDE, or press "p" in the console), to see the
          // wireframe for each widget.
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Text('You eee pushed the button this many times:'),
            Text(
              '$_counter',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
          ],
        ),
      ),
      //floatingActionButton: FloatingActionButton(
      //  onPressed: _setReminder,
      //  tooltip: 'SetReminder',
      //  child: const Icon(Icons.notification_add),
      //), // This trailing comma makes auto-formatting nicer for build methods.
      floatingActionButton: FloatingActionButton(
        onPressed: _scheduleReminderTest,
        tooltip: 'Open Obsidian',
        child: const Icon(Icons.open_in_new_rounded),
      ), // This trailing comma makes auto-formatting nicer for build methods.
    );
  }
}
