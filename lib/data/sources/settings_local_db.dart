import 'package:hive_flutter/hive_flutter.dart';

class SettingsLocalDb {
  static const String boxName = 'app_settings';
  static const String settingsKey = 'settings';

  Future<Box<Map>> _openBox() async {
    if (Hive.isBoxOpen(boxName)) {
      return Hive.box<Map>(boxName);
    }
    return Hive.openBox<Map>(boxName);
  }

  Future<Map?> getSettings() async {
    final box = await _openBox();
    return box.get(settingsKey) as Map?;
  }

  Future<void> putSettings(Map<String, Object?> data) async {
    final box = await _openBox();
    await box.put(settingsKey, data);
  }
}
