import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:yunxu_learning_english/domain/services/notification_service.dart';

void main() {
  setUpAll(tz.initializeTimeZones);

  test('resolves supported IANA timezone names directly', () {
    final location = resolveNotificationTimeZoneLocation('Asia/Taipei');

    expect(location.name, 'Asia/Taipei');
  });

  test('parses Etc/GMT fixed offsets returned by some Android devices', () {
    final location = resolveNotificationTimeZoneLocation('Etc/GMT-8');

    expect(location.name, 'Etc/GMT-8');
    expect(
      location.currentTimeZone.offset,
      const Duration(hours: 8).inMilliseconds,
    );
  });

  test('parses GMT offsets with minutes', () {
    expect(
      parseNotificationTimeZoneOffset('GMT-05:30'),
      const Duration(minutes: -330),
    );
  });

  test('falls back to the provided offset for unsupported timezone names', () {
    final location = resolveNotificationTimeZoneLocation(
      'Mars/Olympus',
      fallbackOffset: const Duration(hours: 8),
    );

    expect(location.name, 'UTC+08:00');
    expect(
      location.currentTimeZone.offset,
      const Duration(hours: 8).inMilliseconds,
    );
  });
}
