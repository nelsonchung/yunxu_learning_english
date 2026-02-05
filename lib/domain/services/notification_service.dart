import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_native_timezone/flutter_native_timezone.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  static const int dailyReminderId = 1001;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinSettings = DarwinInitializationSettings();

    await _plugin.initialize(
      const InitializationSettings(
        android: androidSettings,
        iOS: darwinSettings,
        macOS: darwinSettings,
      ),
    );

    await _configureLocalTimeZone();
    _initialized = true;
  }

  Future<bool> ensurePermission() async {
    if (!_initialized) {
      await initialize();
    }

    if (Platform.isIOS) {
      final ios = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      final status = await ios?.checkPermissions();
      if (status?.isEnabled == true) {
        return true;
      }
      final requested = await ios?.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
      return requested ?? false;
    }

    return true;
  }

  Future<void> scheduleDailyReminder(TimeOfDay time) async {
    final granted = await ensurePermission();
    if (!granted) {
      return;
    }

    await _plugin.cancel(dailyReminderId);

    final scheduledDate = _nextInstanceOfTime(time);

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'daily_reminder',
        '每日複習提醒',
        channelDescription: '每天提醒複習單字',
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
      macOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );

    await _plugin.zonedSchedule(
      dailyReminderId,
      '複習提醒',
      '今天記得複習單字',
      scheduledDate,
      details,
      androidAllowWhileIdle: true,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  Future<void> cancelDailyReminder() async {
    if (!_initialized) {
      await initialize();
    }
    await _plugin.cancel(dailyReminderId);
  }

  tz.TZDateTime _nextInstanceOfTime(TimeOfDay time) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled =
        tz.TZDateTime(tz.local, now.year, now.month, now.day, time.hour, time.minute);
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }

  Future<void> _configureLocalTimeZone() async {
    tz.initializeTimeZones();
    final name = await FlutterNativeTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(name));
  }

  Future<void> openAppNotificationSettings() async {
    if (!Platform.isIOS) {
      return;
    }
    final uri = Uri.parse('app-settings:');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }
}
