import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/services.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  static const int dailyReminderId = 1001;
  static const MethodChannel _androidMaintenanceChannel = MethodChannel(
    'com.yunxu.yunxulearn/android_maintenance',
  );

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
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

    if (Platform.isAndroid) {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      final granted = await android?.requestNotificationsPermission();
      return granted ?? true;
    }

    if (Platform.isIOS) {
      final ios = _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
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

    await _runWithAndroidScheduleRecovery(() async {
      await _plugin.cancel(dailyReminderId);
      await _plugin.zonedSchedule(
        dailyReminderId,
        '複習提醒',
        '今天記得複習單字',
        scheduledDate,
        details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    });
  }

  Future<void> _runWithAndroidScheduleRecovery(
    Future<void> Function() operation,
  ) async {
    try {
      await operation();
    } on PlatformException catch (error) {
      if (!Platform.isAndroid || !_isRecoverableAndroidScheduleError(error)) {
        rethrow;
      }

      await _clearAndroidScheduledNotificationCache();
      await operation();
    }
  }

  bool _isRecoverableAndroidScheduleError(PlatformException error) {
    final message = '${error.code} ${error.message} ${error.details}';
    return message.contains('Missing type parameter');
  }

  Future<void> _clearAndroidScheduledNotificationCache() async {
    await _androidMaintenanceChannel.invokeMethod<void>(
      'clearScheduledNotificationCache',
      {'notificationId': dailyReminderId},
    );
  }

  Future<void> cancelDailyReminder() async {
    if (!_initialized) {
      await initialize();
    }
    await _runWithAndroidScheduleRecovery(() async {
      await _plugin.cancel(dailyReminderId);
    });
  }

  tz.TZDateTime _nextInstanceOfTime(TimeOfDay time) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      time.hour,
      time.minute,
    );
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }

  Future<void> _configureLocalTimeZone() async {
    tz.initializeTimeZones();
    final fallbackOffset = DateTime.now().timeZoneOffset;

    try {
      final timezone = await FlutterTimezone.getLocalTimezone();
      final location = resolveNotificationTimeZoneLocation(
        timezone.identifier,
        fallbackOffset: fallbackOffset,
      );
      tz.setLocalLocation(location);
    } catch (error, stackTrace) {
      debugPrint('NotificationService: failed to configure timezone: $error');
      debugPrintStack(stackTrace: stackTrace);
      tz.setLocalLocation(
        buildFixedOffsetTimeZoneLocation(
          'UTC${formatNotificationTimeZoneOffset(fallbackOffset)}',
          fallbackOffset,
        ),
      );
    }
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

tz.Location resolveNotificationTimeZoneLocation(
  String rawIdentifier, {
  Duration? fallbackOffset,
}) {
  final identifier = rawIdentifier.trim();
  final candidates = <String>{
    identifier,
    normalizeNotificationTimeZoneIdentifier(identifier),
  }..removeWhere((candidate) => candidate.isEmpty);

  for (final candidate in candidates) {
    final existingLocation = _tryGetNotificationTimeZoneLocation(candidate);
    if (existingLocation != null) {
      return existingLocation;
    }

    final fixedOffset = parseNotificationTimeZoneOffset(candidate);
    if (fixedOffset != null) {
      return buildFixedOffsetTimeZoneLocation(candidate, fixedOffset);
    }
  }

  final offset = fallbackOffset ?? DateTime.now().timeZoneOffset;
  final fallbackName = 'UTC${formatNotificationTimeZoneOffset(offset)}';
  debugPrint(
    'NotificationService: unsupported timezone "$rawIdentifier", '
    'falling back to $fallbackName',
  );
  return buildFixedOffsetTimeZoneLocation(fallbackName, offset);
}

String normalizeNotificationTimeZoneIdentifier(String identifier) {
  switch (identifier.trim()) {
    case 'GMT':
    case 'Etc/GMT':
    case 'Etc/UTC':
    case 'UCT':
    case 'Universal':
    case 'Zulu':
      return 'UTC';
    default:
      return identifier.trim();
  }
}

Duration? parseNotificationTimeZoneOffset(String identifier) {
  final value = identifier.trim();
  if (value.isEmpty) {
    return null;
  }

  if (value == 'UTC') {
    return Duration.zero;
  }

  final etcMatch = RegExp(
    r'^Etc/GMT([+-])(\d{1,2})(?::?(\d{2}))?$',
  ).firstMatch(value);
  if (etcMatch != null) {
    final sign = etcMatch.group(1) == '-' ? 1 : -1;
    return _notificationOffsetFromMatch(
      sign: sign,
      hoursText: etcMatch.group(2)!,
      minutesText: etcMatch.group(3),
    );
  }

  final utcMatch = RegExp(
    r'^(?:UTC|GMT)([+-])(\d{1,2})(?::?(\d{2}))?$',
  ).firstMatch(value);
  if (utcMatch != null) {
    final sign = utcMatch.group(1) == '+' ? 1 : -1;
    return _notificationOffsetFromMatch(
      sign: sign,
      hoursText: utcMatch.group(2)!,
      minutesText: utcMatch.group(3),
    );
  }

  return null;
}

tz.Location buildFixedOffsetTimeZoneLocation(
  String identifier,
  Duration offset,
) {
  return tz.Location(identifier, <int>[tz.minTime], <int>[0], <tz.TimeZone>[
    tz.TimeZone(offset.inMilliseconds, isDst: false, abbreviation: identifier),
  ]);
}

String formatNotificationTimeZoneOffset(Duration offset) {
  final totalMinutes = offset.inMinutes;
  final sign = totalMinutes >= 0 ? '+' : '-';
  final absoluteMinutes = totalMinutes.abs();
  final hours = absoluteMinutes ~/ 60;
  final minutes = absoluteMinutes % 60;
  final paddedHours = hours.toString().padLeft(2, '0');
  final paddedMinutes = minutes.toString().padLeft(2, '0');
  return '$sign$paddedHours:$paddedMinutes';
}

tz.Location? _tryGetNotificationTimeZoneLocation(String identifier) {
  try {
    return tz.getLocation(identifier);
  } on tz.LocationNotFoundException {
    return null;
  }
}

Duration? _notificationOffsetFromMatch({
  required int sign,
  required String hoursText,
  String? minutesText,
}) {
  final hours = int.tryParse(hoursText);
  final minutes = int.tryParse(minutesText ?? '0');
  if (hours == null || minutes == null) {
    return null;
  }
  if (hours > 23 || minutes > 59) {
    return null;
  }
  return Duration(minutes: sign * ((hours * 60) + minutes));
}
