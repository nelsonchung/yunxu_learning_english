import 'dart:convert';

import 'package:flutter/services.dart';

import '../../domain/models/builtin_word_entry.dart';

class BuiltinWordBankRepository {
  BuiltinWordBankRepository({AssetBundle? assetBundle})
    : _assetBundle = assetBundle ?? rootBundle;

  static const int _alphabetLength = 26;
  static const int _lowercaseACodeUnit = 97;
  static final List<String> _assetPaths = List<String>.unmodifiable(
    List<String>.generate(_alphabetLength, (index) {
      final letter = String.fromCharCode(_lowercaseACodeUnit + index);
      return 'assets/word_bank/word_bank_main-$letter.json';
    }),
  );

  final AssetBundle _assetBundle;
  final Map<String, List<BuiltinWordEntry>> _cachedShardEntries =
      <String, List<BuiltinWordEntry>>{};
  List<BuiltinWordEntry>? _cachedEntries;
  Future<List<BuiltinWordEntry>>? _loadingEntriesFuture;

  Future<List<BuiltinWordEntry>> fetchAll() async {
    final cachedEntries = _cachedEntries;
    if (cachedEntries != null) {
      return cachedEntries;
    }

    final inFlight = _loadingEntriesFuture;
    if (inFlight != null) {
      return inFlight;
    }

    final loadFuture = _loadAllEntries();
    _loadingEntriesFuture = loadFuture;
    try {
      final entries = await loadFuture;
      _cachedEntries = entries;
      return entries;
    } finally {
      _loadingEntriesFuture = null;
    }
  }

  Future<List<BuiltinWordEntry>> _loadAllEntries() async {
    final mergedEntries = <BuiltinWordEntry>[];

    for (final assetPath in _assetPaths) {
      mergedEntries.addAll(await _loadShard(assetPath));
    }

    return List<BuiltinWordEntry>.unmodifiable(mergedEntries);
  }

  Future<List<BuiltinWordEntry>> _loadShard(String assetPath) async {
    final cachedEntries = _cachedShardEntries[assetPath];
    if (cachedEntries != null) {
      return cachedEntries;
    }

    final rawJson = await _assetBundle.loadString(assetPath);
    final parsed = jsonDecode(rawJson);
    if (parsed is! List) {
      throw FormatException('字庫資料格式錯誤：$assetPath');
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
    final shardEntries = List<BuiltinWordEntry>.unmodifiable(entries);
    _cachedShardEntries[assetPath] = shardEntries;
    return shardEntries;
  }
}
