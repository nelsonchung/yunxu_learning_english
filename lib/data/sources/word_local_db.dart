import 'dart:async';

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

  Future<void> forEach(
    FutureOr<void> Function(String id, Map data) action,
  ) async {
    final box = await _openBox();
    final keys = box.keys.whereType<String>().toList(growable: false);
    for (final id in keys) {
      final data = box.get(id);
      if (data == null) {
        continue;
      }
      await action(id, data);
    }
  }
}
