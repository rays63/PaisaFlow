import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// The daily "note today's spending" notification.
///
/// One inexact notification is scheduled for the next occurrence of the
/// chosen time and repeats daily; [sync] runs on every app start so the
/// wording follows the current language and a cleared schedule (new phone,
/// force stop) heals itself. Everything is best-effort: a phone that
/// refuses is never an error.
class Reminder {
  Reminder._();

  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  static Future<bool> _init() async {
    if (_ready) return true;
    try {
      tzdata.initializeTimeZones();
      // Without this the timezone package treats local as UTC, and an
      // 8 PM reminder fires at 8 PM UTC.
      try {
        tz.setLocalLocation(
          tz.getLocation((await FlutterTimezone.getLocalTimezone()).identifier),
        );
      } catch (error) {
        debugPrint('Reminder timezone unknown, using UTC: $error');
      }
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
      );
      return _ready = true;
    } catch (error) {
      // No plugin in tests, or a platform without notifications.
      debugPrint('Reminder unavailable: $error');
      return false;
    }
  }

  /// Asks the system for permission to notify. True when allowed.
  static Future<bool> requestPermission() async {
    if (!await _init()) return false;
    try {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      if (android != null) {
        return await android.requestNotificationsPermission() ?? true;
      }
      final ios = _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      if (ios != null) {
        return await ios.requestPermissions(alert: true, sound: true) ?? true;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Schedules (or clears, for null [minutes]) the daily reminder at
  /// [minutes] past midnight, worded with [title] and [body].
  static Future<void> sync(
    int? minutes, {
    required String title,
    required String body,
  }) async {
    if (!await _init()) return;
    try {
      await _plugin.cancel(id: 1);
      if (minutes == null) return;
      final now = tz.TZDateTime.from(DateTime.now(), tz.local);
      var at = tz.TZDateTime(
        tz.local,
        now.year,
        now.month,
        now.day,
        minutes ~/ 60,
        minutes % 60,
      );
      if (!at.isAfter(now)) at = at.add(const Duration(days: 1));
      await _plugin.zonedSchedule(
        id: 1,
        title: title,
        body: body,
        scheduledDate: at,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'daily_reminder',
            'Daily reminder',
            channelDescription: 'A daily nudge to note the day\'s spending.',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        // Inexact: a minute or two of drift beats asking for the exact-alarm
        // permission.
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    } catch (error) {
      debugPrint('Reminder not scheduled: $error');
    }
  }
}
