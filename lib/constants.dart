import 'package:flutter_local_notifications/flutter_local_notifications.dart';

const String snooze5SecondsId = 'snooze-5-seconds';
const String snooze5MinutesId = 'snooze-5-minutes';
const String snooze1HourId = 'snooze-1-hour';
const String snooze1DayId = 'snooze-1-day';
const String snooze1WeekId = 'snooze-1-week';

const AndroidNotificationAction actionSnooze5Seconds =
    AndroidNotificationAction(snooze5SecondsId, 'Snooze 5 Seconds');

const AndroidNotificationAction actionSnooze5Minutes =
    AndroidNotificationAction('snooze-5-minutes', 'Snooze 5 Minutes');
