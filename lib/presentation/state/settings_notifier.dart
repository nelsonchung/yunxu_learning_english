import 'package:flutter/material.dart';

import '../../data/repositories/settings_repository.dart';
import '../../domain/models/app_settings.dart';

class SettingsNotifier extends ChangeNotifier {
  SettingsNotifier({required SettingsRepository repository})
      : _repository = repository;

  final SettingsRepository _repository;

  AppSettings _settings = AppSettings.defaults();
  bool _isLoading = false;

  bool get isLoading => _isLoading;
  bool get showImages => _settings.showImages;

  TimeOfDay get reminderTime {
    final hours = _settings.reminderMinutes ~/ 60;
    final minutes = _settings.reminderMinutes % 60;
    return TimeOfDay(hour: hours, minute: minutes);
  }

  Future<void> load() async {
    _isLoading = true;
    notifyListeners();

    _settings = await _repository.fetch();

    _isLoading = false;
    notifyListeners();
  }

  Future<void> setReminderTime(TimeOfDay time) async {
    final minutes = time.hour * 60 + time.minute;
    _settings = _settings.copyWith(reminderMinutes: minutes);
    await _repository.save(_settings);
    notifyListeners();
  }

  Future<void> setShowImages(bool value) async {
    _settings = _settings.copyWith(showImages: value);
    await _repository.save(_settings);
    notifyListeners();
  }
}
