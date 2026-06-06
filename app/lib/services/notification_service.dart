import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

/// Manages local push notifications. Currently used for the workout reminder:
/// every time a set is logged the 3-day "haven't trained" notification is
/// rescheduled, so it only fires if the user actually goes quiet for 3 days.
class NotificationService {
  static const _channelId = 'repiq_reminders';
  static const _reminderId = 42;

  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;

    tz.initializeTimeZones();
    final localTz = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(localTz.identifier));

    const androidInit =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(
      const InitializationSettings(android: androidInit),
    );

    // Request runtime permission on Android 13+.
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    _initialized = true;
  }

  /// Cancels any existing reminder and schedules a new one 3 days from now.
  /// Call this every time a set is logged so the notification self-heals.
  static Future<void> scheduleWorkoutReminder() async {
    await init();
    await _plugin.cancel(_reminderId);

    final fireAt = tz.TZDateTime.now(tz.local).add(const Duration(days: 3));

    await _plugin.zonedSchedule(
      _reminderId,
      'Time to train 💪',
      "You haven't logged a workout in 3 days. Keep your momentum going.",
      fireAt,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          'Workout Reminders',
          channelDescription: 'Reminds you to keep logging workouts',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          icon: '@mipmap/ic_launcher',
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  static Future<void> cancelWorkoutReminder() async {
    await init();
    await _plugin.cancel(_reminderId);
  }
}
