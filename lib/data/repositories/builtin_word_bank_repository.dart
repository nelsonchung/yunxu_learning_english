import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../domain/models/builtin_word_entry.dart';
import '../../domain/models/word_card.dart';
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
  static const int _recommendationRecentSampleLimit = 12;
  static const int _recommendationMinimumShardCount = 6;
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
  final Set<String> _searchPrimedShardPaths = <String>{};
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

  Future<List<BuiltinWordEntry>> fetchRecommendationCandidates({
    required List<WordCard> existingWords,
    required DateTime now,
    required int desiredCount,
    int minimumShardCount = _recommendationMinimumShardCount,
    int? candidateLimit,
  }) async {
    final sortedExisting = List<WordCard>.from(existingWords)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final sampledExisting = sortedExisting.take(
      _recommendationRecentSampleLimit,
    );
    final sampleKeys = sampledExisting
        .map((card) => _normalizeRecommendationKey(card.word))
        .where((key) => key.isNotEmpty)
        .toSet();
    final supportEntries = <BuiltinWordEntry>[];

    for (final shardPath
        in sampledExisting
            .map((card) => _assetPathForWord(card.word))
            .whereType<String>()
            .toSet()) {
      final shardEntries = await _loadShard(shardPath, primeForSearch: false);
      for (final entry in shardEntries) {
        if (sampleKeys.contains(_normalizeRecommendationKey(entry.word))) {
          supportEntries.add(entry);
        }
      }
    }

    final existingKeys = existingWords
        .map((card) => _normalizeRecommendationKey(card.word))
        .where((key) => key.isNotEmpty)
        .toSet();
    final existingRoots = existingWords
        .map((card) => _stemRecommendationWord(card.word))
        .where((root) => root.length >= 4)
        .toSet();
    final effectiveCandidateLimit =
        candidateLimit ??
        ((desiredCount <= 0 ? 3 : desiredCount) * 300 < 900
            ? 900
            : (desiredCount <= 0 ? 3 : desiredCount) * 300);
    final rotatedShardPaths = _rotatedAssetPathsForDay(now);
    final candidates = <BuiltinWordEntry>[];
    var visitedShardCount = 0;

    for (final shardPath in rotatedShardPaths) {
      final shardEntries = await _loadShard(shardPath, primeForSearch: false);
      visitedShardCount += 1;

      for (final entry in shardEntries) {
        if (_isRecommendationCandidate(
          entry,
          existingKeys: existingKeys,
          existingRoots: existingRoots,
        )) {
          candidates.add(entry);
        }
      }

      if (visitedShardCount >= minimumShardCount &&
          candidates.length >= effectiveCandidateLimit) {
        break;
      }
    }

    final mergedEntries = <BuiltinWordEntry>[];
    final seenWords = <String>{};

    for (final entry in supportEntries.followedBy(candidates)) {
      final key = _normalizeRecommendationKey(entry.word);
      if (key.isEmpty || !seenWords.add(key)) {
        continue;
      }
      mergedEntries.add(entry);
    }

    return List<BuiltinWordEntry>.unmodifiable(mergedEntries);
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

  Future<List<BuiltinWordEntry>> _loadShard(
    String assetPath, {
    bool primeForSearch = true,
  }) async {
    final cachedEntries = _cachedShardEntries[assetPath];
    if (cachedEntries != null) {
      if (primeForSearch) {
        _primeShardForSearch(assetPath, cachedEntries);
      }
      return cachedEntries;
    }

    final inFlight = _loadingShardEntries[assetPath];
    if (inFlight != null) {
      final entries = await inFlight;
      if (primeForSearch) {
        _primeShardForSearch(assetPath, entries);
      }
      return entries;
    }

    final loadFuture = _loadShardFromBundle(assetPath);
    _loadingShardEntries[assetPath] = loadFuture;
    try {
      final entries = await loadFuture;
      _cachedShardEntries[assetPath] = entries;
      if (primeForSearch) {
        _primeShardForSearch(assetPath, entries);
      }
      return entries;
    } finally {
      _loadingShardEntries.remove(assetPath);
    }
  }

  void _primeShardForSearch(String assetPath, List<BuiltinWordEntry> entries) {
    if (!_searchPrimedShardPaths.add(assetPath)) {
      return;
    }
    _searchService.prime(entries);
  }

  Future<List<BuiltinWordEntry>> _loadShardFromBundle(String assetPath) async {
    final rawJson = await _assetBundle.loadString(assetPath);
    final entries = await compute(
      _parseBuiltinWordEntriesOnBackground,
      <String, String>{'assetPath': assetPath, 'rawJson': rawJson},
    );
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

  String? _assetPathForWord(String word) {
    final normalized = _normalizeRecommendationKey(word);
    if (normalized.isEmpty) {
      return null;
    }

    final codeUnit = normalized.codeUnitAt(0);
    if (codeUnit < _lowercaseACodeUnit ||
        codeUnit >= _lowercaseACodeUnit + _alphabetLength) {
      return null;
    }

    return 'assets/word_bank/word_bank_main-${normalized[0]}.json';
  }

  List<String> _rotatedAssetPathsForDay(DateTime now) {
    final dayKey = '${now.year}-${now.month}-${now.day}';
    final offset = _stableHash(dayKey) % _assetPaths.length;

    return List<String>.generate(
      _assetPaths.length,
      (index) => _assetPaths[(offset + index) % _assetPaths.length],
      growable: false,
    );
  }

  bool _isRecommendationCandidate(
    BuiltinWordEntry entry, {
    required Set<String> existingKeys,
    required Set<String> existingRoots,
  }) {
    final normalizedWord = _normalizeRecommendationKey(entry.word);
    if (normalizedWord.isEmpty || !_looksLikeSingleWord(entry.word)) {
      return false;
    }
    if (existingKeys.contains(normalizedWord)) {
      return false;
    }
    if (entry.difficultyLevel == null) {
      return false;
    }
    if (entry.sentences.length < 2) {
      return false;
    }
    if (entry.meaning.trim().isEmpty) {
      return false;
    }
    if (entry.sourceTags.isEmpty) {
      return false;
    }

    final root = _stemRecommendationWord(entry.word);
    if (root.length >= 4 && existingRoots.contains(root)) {
      return false;
    }

    for (final existingKey in existingKeys) {
      if (_looksTooSimilar(normalizedWord, existingKey)) {
        return false;
      }
    }

    return true;
  }

  String _normalizeRecommendationKey(String word) {
    return word.trim().toLowerCase();
  }

  bool _looksLikeSingleWord(String word) {
    final trimmed = word.trim();
    if (trimmed.isEmpty) {
      return false;
    }
    return !trimmed.contains(' ') &&
        !trimmed.contains('-') &&
        !trimmed.contains('/') &&
        !trimmed.contains(RegExp(r'\d'));
  }

  String _stemRecommendationWord(String word) {
    final normalized = _normalizeRecommendationKey(word);
    const suffixes = [
      'ingly',
      'edly',
      'ing',
      'edly',
      'ed',
      'ies',
      'es',
      's',
      'ly',
      'er',
      'est',
      'ment',
      'tion',
      'ions',
      'al',
      'ity',
      'ness',
    ];

    for (final suffix in suffixes) {
      if (normalized.length - suffix.length < 4) {
        continue;
      }
      if (normalized.endsWith(suffix)) {
        return normalized.substring(0, normalized.length - suffix.length);
      }
    }

    return normalized;
  }

  bool _looksTooSimilar(String candidate, String existing) {
    if (candidate == existing) {
      return true;
    }
    if (candidate.length >= 4 &&
        existing.length >= 4 &&
        (candidate.startsWith(existing) || existing.startsWith(candidate))) {
      return true;
    }
    return false;
  }

  int _stableHash(String value) {
    var hash = 0;
    for (final codeUnit in value.codeUnits) {
      hash = (hash * 31 + codeUnit) & 0x7fffffff;
    }
    return hash;
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

List<BuiltinWordEntry> _parseBuiltinWordEntriesOnBackground(
  Map<String, String> payload,
) {
  final assetPath = payload['assetPath'] ?? '';
  final rawJson = payload['rawJson'] ?? '[]';
  final parsed = jsonDecode(rawJson);
  if (parsed is! List) {
    throw FormatException('字庫資料格式錯誤：$assetPath');
  }

  return parsed
      .whereType<Map>()
      .map(
        (item) => BuiltinWordEntry.fromMap(
          item.map((key, value) => MapEntry(key.toString(), value)),
        ),
      )
      .where((entry) => entry.word.isNotEmpty && entry.meaning.isNotEmpty)
      .toList(growable: false);
}
