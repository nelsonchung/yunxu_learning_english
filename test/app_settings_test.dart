import 'package:flutter_test/flutter_test.dart';
import 'package:yunxu_learning_english/domain/models/app_settings.dart';

void main() {
  test('AppSettings defaults include daily new word recommendations', () {
    final settings = AppSettings.defaults();

    expect(settings.dailyNewWordsEnabled, isTrue);
    expect(settings.dailyNewWordsReviewThreshold, 10);
    expect(settings.dailyNewWordsCount, 3);
  });

  test('AppSettings serializes and restores daily new word settings', () {
    final now = DateTime.fromMillisecondsSinceEpoch(1_700_000_000_000);
    final settings = AppSettings(
      reminderMinutes: 540,
      showImages: false,
      reminderEnabled: false,
      dailyNewWordsEnabled: true,
      dailyNewWordsReviewThreshold: 8,
      dailyNewWordsCount: 5,
      syncEnabled: true,
      syncIntervalSeconds: 30,
      pronunciationEnabled: true,
      pronunciationRate: 0.55,
      pronunciationLocale: 'en-GB',
      updatedAt: now,
    );

    final restored = AppSettings.fromMap(settings.toMap());

    expect(restored.dailyNewWordsEnabled, isTrue);
    expect(restored.dailyNewWordsReviewThreshold, 8);
    expect(restored.dailyNewWordsCount, 5);
    expect(restored.updatedAt, now);
  });
}
