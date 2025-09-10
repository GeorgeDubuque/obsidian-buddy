import 'package:flutter_local_notifications/flutter_local_notifications.dart';

const String snooze5SecondsId = 'snooze-5-seconds';

const AndroidNotificationAction actionSnooze5Seconds =
    AndroidNotificationAction(snooze5SecondsId, 'Snooze 5 Seconds');

const AndroidNotificationAction actionSnooze5Minutes =
    AndroidNotificationAction('snooze-5-minutes', 'Snooze 5 Minutes');
