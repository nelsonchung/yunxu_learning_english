import 'package:flutter/material.dart';

import '../../data/repositories/settings_repository.dart';
import '../../domain/models/app_settings.dart';
import '../../domain/services/notification_service.dart';

class SettingsNotifier extends ChangeNotifier {
  SettingsNotifier({
    required SettingsRepository repository,
    required NotificationService notificationService,
  })  : _repository = repository,
        _notificationService = notificationService;

  final SettingsRepository _repository;
  final NotificationService _notificationService;

  AppSettings _settings = AppSettings.defaults();
  bool _isLoading = false;
  bool _didPromptSettings = false;

  bool get isLoading => _isLoading;
  bool get showImages => _settings.showImages;
  bool get reminderEnabled => _settings.reminderEnabled;

  TimeOfDay get reminderTime {
    final hours = _settings.reminderMinutes ~/ 60;
    final minutes = _settings.reminderMinutes % 60;
    return TimeOfDay(hour: hours, minute: minutes);
  }

  Future<void> load() async {
    _isLoading = true;
    notifyListeners();

    _settings = await _repository.fetch();
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
    _settings = _settings.copyWith(reminderMinutes: minutes);
    await _repository.save(_settings);
    if (_settings.reminderEnabled) {
      await _ensurePermissionAndSchedule();
    }
    notifyListeners();
  }

  Future<void> setShowImages(bool value) async {
    _settings = _settings.copyWith(showImages: value);
    await _repository.save(_settings);
    notifyListeners();
  }

  Future<void> setReminderEnabled(bool value) async {
    _settings = _settings.copyWith(reminderEnabled: value);
    await _repository.save(_settings);
    if (value) {
      await _ensurePermissionAndSchedule();
    } else {
      await _notificationService.cancelDailyReminder();
    }
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
