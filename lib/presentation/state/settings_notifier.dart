import 'package:flutter/material.dart';

import '../../data/repositories/settings_repository.dart';
import '../../domain/models/app_settings.dart';
import '../../domain/services/notification_service.dart';
import '../../domain/services/pronunciation_service.dart';

class SettingsNotifier extends ChangeNotifier {
  SettingsNotifier({
    required SettingsRepository repository,
    required NotificationService notificationService,
    required PronunciationService pronunciationService,
  }) : _repository = repository,
       _notificationService = notificationService,
       _pronunciationService = pronunciationService;

  final SettingsRepository _repository;
  final NotificationService _notificationService;
  final PronunciationService _pronunciationService;

  AppSettings _settings = AppSettings.defaults();
  bool _isLoading = false;
  bool _didPromptSettings = false;

  bool get isLoading => _isLoading;
  bool get showImages => _settings.showImages;
  bool get reminderEnabled => _settings.reminderEnabled;
  bool get syncEnabled => _settings.syncEnabled;
  int get syncIntervalSeconds => _settings.syncIntervalSeconds;
  bool get pronunciationEnabled => _settings.pronunciationEnabled;
  bool get pronunciationSupported => _pronunciationService.isSupported;
  double get pronunciationRate => _settings.pronunciationRate;
  String get pronunciationLocale => _settings.pronunciationLocale;

  TimeOfDay get reminderTime {
    final hours = _settings.reminderMinutes ~/ 60;
    final minutes = _settings.reminderMinutes % 60;
    return TimeOfDay(hour: hours, minute: minutes);
  }

  Future<void> load() async {
    _isLoading = true;
    notifyListeners();

    _settings = await _repository.fetch();
    await _pronunciationService.applySettings(_settings);
    if (_settings.reminderEnabled) {
      await _ensurePermissionAndSchedule();
    } else {
      await _notificationService.cancelDailyReminder();
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> setReminderTime(TimeOfDay time) async {
    final minutes = time.hour * 60 + time.minute;
    _settings = _settings.copyWith(
      reminderMinutes: minutes,
      updatedAt: DateTime.now(),
    );
    await _repository.save(_settings);
    if (_settings.reminderEnabled) {
      await _ensurePermissionAndSchedule();
    }
    notifyListeners();
  }

  Future<void> setShowImages(bool value) async {
    _settings = _settings.copyWith(
      showImages: value,
      updatedAt: DateTime.now(),
    );
    await _repository.save(_settings);
    notifyListeners();
  }

  Future<void> setReminderEnabled(bool value) async {
    _settings = _settings.copyWith(
      reminderEnabled: value,
      updatedAt: DateTime.now(),
    );
    await _repository.save(_settings);
    if (value) {
      await _ensurePermissionAndSchedule();
    } else {
      await _notificationService.cancelDailyReminder();
    }
    notifyListeners();
  }

  Future<void> setPronunciationEnabled(bool value) async {
    _settings = _settings.copyWith(
      pronunciationEnabled: value,
      updatedAt: DateTime.now(),
    );
    await _repository.save(_settings);
    await _pronunciationService.applySettings(_settings);
    notifyListeners();
  }

  Future<void> setPronunciationRate(double value) async {
    final clamped = value.clamp(0.2, 0.7).toDouble();
    _settings = _settings.copyWith(
      pronunciationRate: clamped,
      updatedAt: DateTime.now(),
    );
    await _repository.save(_settings);
    await _pronunciationService.applySettings(_settings);
    notifyListeners();
  }

  Future<void> setPronunciationLocale(String value) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return;
    }

    _settings = _settings.copyWith(
      pronunciationLocale: trimmed,
      updatedAt: DateTime.now(),
    );
    await _repository.save(_settings);
    await _pronunciationService.applySettings(_settings);
    notifyListeners();
  }

  Future<void> setSyncIntervalSeconds(int seconds) async {
    _settings = _settings.copyWith(
      syncIntervalSeconds: seconds,
      updatedAt: DateTime.now(),
    );
    await _repository.save(_settings);
    notifyListeners();
  }

  Future<void> setSyncEnabled(bool value) async {
    _settings = _settings.copyWith(
      syncEnabled: value,
      updatedAt: DateTime.now(),
    );
    await _repository.save(_settings);
    notifyListeners();
  }

  Future<void> _ensurePermissionAndSchedule() async {
    final granted = await _notificationService.ensurePermission();
    if (!granted && !_didPromptSettings) {
      _didPromptSettings = true;
      await _notificationService.openAppNotificationSettings();
      return;
    }
    if (granted) {
      await _notificationService.scheduleDailyReminder(reminderTime);
    }
  }
}
