import 'package:hive_flutter/hive_flutter.dart';

class WordLocalDb {
  static const String boxName = 'word_cards';

  Future<Box<Map>> _openBox() async {
    if (Hive.isBoxOpen(boxName)) {
      return Hive.box<Map>(boxName);
    }
    return Hive.openBox<Map>(boxName);
  }

  Future<void> put(String id, Map<String, Object?> data) async {
    final box = await _openBox();
    await box.put(id, data);
  }

  Future<void> delete(String id) async {
    final box = await _openBox();
    await box.delete(id);
  }

  Future<List<Map>> getAll() async {
    final box = await _openBox();
    return box.values.cast<Map>().toList();
  }
}
