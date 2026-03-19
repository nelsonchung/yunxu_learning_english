import 'dart:convert';

import 'package:flutter/services.dart';

import '../../domain/models/builtin_word_entry.dart';

class BuiltinWordBankRepository {
  static const String _assetPath = 'assets/word_bank/word_bank_main.json';

  List<BuiltinWordEntry>? _cachedEntries;

  Future<List<BuiltinWordEntry>> fetchAll() async {
    final cachedEntries = _cachedEntries;
    if (cachedEntries != null) {
      return cachedEntries;
    }

    final rawJson = await rootBundle.loadString(_assetPath);
    final parsed = jsonDecode(rawJson);
    if (parsed is! List) {
      throw const FormatException('字庫資料格式錯誤');
    }

    final entries = parsed
        .whereType<Map>()
        .map(
          (item) => BuiltinWordEntry.fromMap(
            item.map((key, value) => MapEntry(key.toString(), value)),
          ),
        )
        .where((entry) => entry.word.isNotEmpty && entry.meaning.isNotEmpty)
        .toList(growable: false);
    _cachedEntries = entries;
    return entries;
  }
}
