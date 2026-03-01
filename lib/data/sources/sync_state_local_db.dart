import 'package:hive_flutter/hive_flutter.dart';

class SyncStateLocalDb {
  static const String boxName = 'sync_state';
  static const String stateKey = 'state';

  Future<Box<Map>> _openBox() async {
    if (Hive.isBoxOpen(boxName)) {
      return Hive.box<Map>(boxName);
    }
    return Hive.openBox<Map>(boxName);
  }

  Future<Map?> getState() async {
    final box = await _openBox();
    return box.get(stateKey);
  }

  Future<void> putState(Map<String, Object?> data) async {
    final box = await _openBox();
    await box.put(stateKey, data);
  }
}
