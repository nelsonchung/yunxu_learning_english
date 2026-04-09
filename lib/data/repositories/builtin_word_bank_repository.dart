import 'dart:convert';

import 'package:flutter/services.dart';

import '../../domain/models/builtin_word_entry.dart';
import '../../domain/services/word_bank_search_service.dart';

enum BuiltinWordBankAudienceFilter {
  all,
  general,
  elementary,
  juniorHigh,
  seniorHigh,
  college,
  toeic,
}

class BuiltinWordBankSearchResult {
  const BuiltinWordBankSearchResult({required this.entries});

  final List<BuiltinWordEntry> entries;
}

class BuiltinWordBankRepository {
  BuiltinWordBankRepository({
    AssetBundle? assetBundle,
    WordBankSearchService? searchService,
  }) : _assetBundle = assetBundle ?? rootBundle,
       _searchService = searchService ?? const WordBankSearchService();

  static const int _alphabetLength = 26;
  static const int _lowercaseACodeUnit = 97;
  static final List<String> _assetPaths = List<String>.unmodifiable(
    List<String>.generate(_alphabetLength, (index) {
      final letter = String.fromCharCode(_lowercaseACodeUnit + index);
      return 'assets/word_bank/word_bank_main-$letter.json';
    }),
  );

  final AssetBundle _assetBundle;
  final WordBankSearchService _searchService;
  final Map<String, List<BuiltinWordEntry>> _cachedShardEntries =
      <String, List<BuiltinWordEntry>>{};
  final Map<String, Future<List<BuiltinWordEntry>>> _loadingShardEntries =
      <String, Future<List<BuiltinWordEntry>>>{};
  List<BuiltinWordEntry>? _cachedEntries;
  Future<List<BuiltinWordEntry>>? _loadingEntriesFuture;
  Map<BuiltinWordBankAudienceFilter, int>? _cachedFilterCounts;
  Future<Map<BuiltinWordBankAudienceFilter, int>>? _loadingFilterCountsFuture;

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

  Future<BuiltinWordBankSearchResult> search({
    required String query,
    required BuiltinWordBankAudienceFilter filter,
    int emptyQueryLimit = 100,
    int queryLimit = 200,
  }) async {
    final candidateEntries = await _loadEntriesForSearch(
      query: query,
      filter: filter,
      emptyQueryLimit: emptyQueryLimit,
    );

    final entries = _searchService.search(
      entries: candidateEntries,
      query: query,
      emptyQueryLimit: emptyQueryLimit,
      queryLimit: queryLimit,
    );

    return BuiltinWordBankSearchResult(entries: entries);
  }

  Future<Map<BuiltinWordBankAudienceFilter, int>> fetchFilterCounts() async {
    final cachedCounts = _cachedFilterCounts;
    if (cachedCounts != null) {
      return cachedCounts;
    }

    final inFlight = _loadingFilterCountsFuture;
    if (inFlight != null) {
      return inFlight;
    }

    final loadFuture = _buildFilterCounts();
    _loadingFilterCountsFuture = loadFuture;
    try {
      final counts = await loadFuture;
      _cachedFilterCounts = counts;
      return counts;
    } finally {
      _loadingFilterCountsFuture = null;
    }
  }

  Future<List<BuiltinWordEntry>> _loadAllEntries() async {
    await _ensureAllShardsLoaded();
    final mergedEntries = <BuiltinWordEntry>[];

    for (final assetPath in _assetPaths) {
      final shardEntries = _cachedShardEntries[assetPath];
      if (shardEntries != null) {
        mergedEntries.addAll(shardEntries);
      }
    }

    return List<BuiltinWordEntry>.unmodifiable(mergedEntries);
  }

  Future<Iterable<BuiltinWordEntry>> _loadEntriesForSearch({
    required String query,
    required BuiltinWordBankAudienceFilter filter,
    required int emptyQueryLimit,
  }) async {
    final normalizedQuery = _searchService.normalizeQuery(query);

    if (normalizedQuery.isEmpty) {
      return _loadEntriesForEmptyQuery(filter: filter, limit: emptyQueryLimit);
    }

    if (_shouldUseSingleShardPrefixSearch(normalizedQuery)) {
      final shardEntries = await _loadShard(
        _assetPathForLeadingLetter(normalizedQuery),
      );
      return shardEntries.where((entry) => _matchesFilter(entry, filter));
    }

    await _ensureAllShardsLoaded();
    return _entriesForLoadedShards(filter);
  }

  Future<List<BuiltinWordEntry>> _loadEntriesForEmptyQuery({
    required BuiltinWordBankAudienceFilter filter,
    required int limit,
  }) async {
    final entries = <BuiltinWordEntry>[];

    for (final assetPath in _assetPaths) {
      final shardEntries = await _loadShard(assetPath);
      for (final entry in shardEntries) {
        if (!_matchesFilter(entry, filter)) {
          continue;
        }
        entries.add(entry);
        if (entries.length >= limit) {
          return List<BuiltinWordEntry>.unmodifiable(entries);
        }
      }
    }

    return List<BuiltinWordEntry>.unmodifiable(entries);
  }

  Iterable<BuiltinWordEntry> _entriesForLoadedShards(
    BuiltinWordBankAudienceFilter filter,
  ) sync* {
    for (final assetPath in _assetPaths) {
      final shardEntries = _cachedShardEntries[assetPath];
      if (shardEntries == null) {
        continue;
      }
      for (final entry in shardEntries) {
        if (_matchesFilter(entry, filter)) {
          yield entry;
        }
      }
    }
  }

  Future<void> _ensureAllShardsLoaded() async {
    for (final assetPath in _assetPaths) {
      await _loadShard(assetPath);
    }
  }

  Future<Map<BuiltinWordBankAudienceFilter, int>> _buildFilterCounts() async {
    final counts = _createEmptyFilterCounts();

    for (final assetPath in _assetPaths) {
      final shardEntries = await _loadShard(assetPath);
      for (final entry in shardEntries) {
        counts[BuiltinWordBankAudienceFilter.all] =
            (counts[BuiltinWordBankAudienceFilter.all] ?? 0) + 1;

        for (final filter in BuiltinWordBankAudienceFilter.values) {
          if (filter == BuiltinWordBankAudienceFilter.all) {
            continue;
          }
          if (_matchesFilter(entry, filter)) {
            counts[filter] = (counts[filter] ?? 0) + 1;
          }
        }
      }
    }

    return Map<BuiltinWordBankAudienceFilter, int>.unmodifiable(counts);
  }

  Future<List<BuiltinWordEntry>> _loadShard(String assetPath) async {
    final cachedEntries = _cachedShardEntries[assetPath];
    if (cachedEntries != null) {
      return cachedEntries;
    }

    final inFlight = _loadingShardEntries[assetPath];
    if (inFlight != null) {
      return inFlight;
    }

    final loadFuture = _loadShardFromBundle(assetPath);
    _loadingShardEntries[assetPath] = loadFuture;
    try {
      final entries = await loadFuture;
      _cachedShardEntries[assetPath] = entries;
      return entries;
    } finally {
      _loadingShardEntries.remove(assetPath);
    }
  }

  Future<List<BuiltinWordEntry>> _loadShardFromBundle(String assetPath) async {
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
    _searchService.prime(entries);
    return List<BuiltinWordEntry>.unmodifiable(entries);
  }

  bool _shouldUseSingleShardPrefixSearch(String normalizedQuery) {
    if (normalizedQuery.runes.length != 1) {
      return false;
    }

    final codeUnit = normalizedQuery.codeUnitAt(0);
    return codeUnit >= _lowercaseACodeUnit &&
        codeUnit < _lowercaseACodeUnit + _alphabetLength;
  }

  String _assetPathForLeadingLetter(String normalizedQuery) {
    return 'assets/word_bank/word_bank_main-${normalizedQuery[0]}.json';
  }

  bool _matchesFilter(
    BuiltinWordEntry entry,
    BuiltinWordBankAudienceFilter filter,
  ) {
    switch (filter) {
      case BuiltinWordBankAudienceFilter.all:
        return true;
      case BuiltinWordBankAudienceFilter.general:
        return entry.audienceTags.contains(BuiltinAudienceTag.general);
      case BuiltinWordBankAudienceFilter.elementary:
        return entry.schoolLevels.contains(BuiltinSchoolLevel.elementary);
      case BuiltinWordBankAudienceFilter.juniorHigh:
        return entry.schoolLevels.contains(BuiltinSchoolLevel.juniorHigh);
      case BuiltinWordBankAudienceFilter.seniorHigh:
        return entry.schoolLevels.contains(BuiltinSchoolLevel.seniorHigh);
      case BuiltinWordBankAudienceFilter.college:
        return entry.schoolLevels.contains(BuiltinSchoolLevel.college);
      case BuiltinWordBankAudienceFilter.toeic:
        return entry.examTags.contains(BuiltinExamTag.toeic);
    }
  }

  static Map<BuiltinWordBankAudienceFilter, int> _createEmptyFilterCounts() {
    return Map<BuiltinWordBankAudienceFilter, int>.fromEntries(
      BuiltinWordBankAudienceFilter.values.map(
        (filter) => MapEntry<BuiltinWordBankAudienceFilter, int>(filter, 0),
      ),
    );
  }
}
