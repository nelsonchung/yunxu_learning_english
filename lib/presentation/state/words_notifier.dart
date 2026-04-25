import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../data/repositories/sync_state_repository.dart';
import '../../data/repositories/word_repository.dart';
import '../../data/storage/image_storage.dart';
import '../../domain/models/sync_state.dart';
import '../../domain/models/word_card.dart';
import '../../domain/services/cloud_sync_service.dart';
import '../../domain/services/review_schedule_service.dart';
import '../../domain/services/sort_service.dart';
import '../../domain/services/word_contribution_import_service.dart';

class WordsNotifier extends ChangeNotifier {
  WordsNotifier({
    required WordRepository repository,
    required ReviewScheduleService scheduleService,
    required SortService sortService,
    required ImageStorage imageStorage,
    required WordContributionImportService wordContributionImportService,
    SyncStateRepository? syncStateRepository,
    CloudSyncService? syncService,
    bool initialSyncEnabled = true,
    int initialSyncIntervalSeconds = 60,
  }) : _repository = repository,
       _scheduleService = scheduleService,
       _sortService = sortService,
       _imageStorage = imageStorage,
       _wordContributionImportService = wordContributionImportService,
       _syncStateRepository = syncStateRepository,
       _syncService = syncService,
       _syncEnabled = initialSyncEnabled,
       _syncIntervalSeconds = initialSyncIntervalSeconds > 0
           ? initialSyncIntervalSeconds
           : 60;

  final WordRepository _repository;
  final ReviewScheduleService _scheduleService;
  final SortService _sortService;
  final ImageStorage _imageStorage;
  final WordContributionImportService _wordContributionImportService;
  final SyncStateRepository? _syncStateRepository;
  final CloudSyncService? _syncService;
  final _uuid = const Uuid();

  final List<WordCard> _words = [];
  static const int _autoSyncImageByteLimit = 20 * 1024 * 1024;
  SortMode _sortMode = SortMode.alphabetAsc;
  bool _isLoading = false;
  bool _isSyncing = false;
  bool _syncQueued = false;
  bool _isBackingUp = false;
  bool _isRestoring = false;
  Timer? _pollingTimer;
  int _syncIntervalSeconds;
  bool _syncEnabled;
  int _loadedImageBytes = 0;
  DateTime? _lastSyncAt;
  DateTime? _lastSyncAttemptAt;
  String? _lastSyncErrorCode;
  String? _lastSyncErrorMessage;
  RestoreStatus _restoreStatus = RestoreStatus.idle;

  List<WordCard> get words => _sortService.sort(_words, _sortMode);
  SortMode get sortMode => _sortMode;
  bool get isLoading => _isLoading;
  bool get isSyncing => _isSyncing;
  bool get isBackingUp => _isBackingUp;
  bool get isRestoring => _isRestoring;
  bool get syncSupported => _syncService != null;
  bool get syncEnabled => _syncEnabled;
  bool get canSync => syncSupported && syncEnabled;
  int get totalWords => _words.length;
  int get pendingWordsCount =>
      _words.where((card) => card.needsCompletion).length;
  int get dueWordsCount => dueToday().length;
  int get manualWordsCount =>
      _words.where((card) => card.origin == WordOrigin.manual).length;
  int get unknownWordsCount =>
      _words.where((card) => card.origin == WordOrigin.unknown).length;
  Map<String, int> get customTagCounts {
    final counts = <String, int>{};
    for (final card in _words) {
      for (final tag in card.customTags) {
        counts[tag] = (counts[tag] ?? 0) + 1;
      }
    }

    final entries = counts.entries.toList(growable: false)
      ..sort((a, b) {
        final countCompare = b.value.compareTo(a.value);
        if (countCompare != 0) {
          return countCompare;
        }
        return a.key.toLowerCase().compareTo(b.key.toLowerCase());
      });

    return Map<String, int>.unmodifiable(Map<String, int>.fromEntries(entries));
  }

  List<String> get availableCustomTags =>
      customTagCounts.keys.toList(growable: false);
  DateTime? get lastSyncAt => _lastSyncAt;
  DateTime? get lastSyncAttemptAt => _lastSyncAttemptAt;
  String? get lastSyncErrorCode => _lastSyncErrorCode;
  String? get lastSyncErrorMessage => _lastSyncErrorMessage;
  RestoreStatus get restoreStatus => _restoreStatus;
  bool get hasSyncError => _lastSyncErrorCode != null;

  WordCard? findById(String id) {
    for (final card in _words) {
      if (card.id == id) {
        return card;
      }
    }
    return null;
  }

  List<WordCard> dueToday() {
    final now = DateTime.now();
    final due = _words
        .where((card) => _scheduleService.isDueOnOrBefore(card, now))
        .toList();
    due.sort((a, b) => a.nextReviewDate.compareTo(b.nextReviewDate));
    return due;
  }

  List<WordCard> developerContributionWords({bool includeUnknown = false}) {
    final selectedOrigins = <WordOrigin>{
      WordOrigin.manual,
      if (includeUnknown) WordOrigin.unknown,
    };
    return _words
        .where((card) => selectedOrigins.contains(card.origin))
        .toList(growable: false);
  }

  Future<void> load() async {
    if (_isLoading) {
      return;
    }

    _isLoading = true;
    notifyListeners();

    try {
      final migratedCount = await _repository.migrateImageBytesToPaths(
        saveBytes: _imageStorage.saveBytes,
      );
      if (kDebugMode && migratedCount > 0) {
        debugPrint(
          'WordsNotifier migrated $migratedCount image records to path',
        );
      }
      final all = await _repository.fetchAll();
      _words
        ..clear()
        ..addAll(all);
      _logImageStats(_words);

      if (_syncService != null) {
        await _refreshSyncState(notify: false);
        if (_shouldAutoSyncInBackground) {
          _startPolling();
        } else {
          _stopPolling();
        }
      }
    } catch (error, stackTrace) {
      debugPrint('WordsNotifier load failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> syncNow() async {
    final syncService = _syncService;
    if (syncService == null || !_syncEnabled) {
      return false;
    }
    if (_isSyncing) {
      _syncQueued = true;
      return false;
    }
    _isSyncing = true;
    notifyListeners();
    var success = false;
    var shouldRunQueuedSync = false;
    try {
      success = await syncService.sync();
      final refreshed = await _repository.fetchAll();
      _words
        ..clear()
        ..addAll(refreshed);
      await _refreshSyncState(notify: false);
    } finally {
      shouldRunQueuedSync = _syncQueued && canSync;
      _syncQueued = false;
      _isSyncing = false;
      notifyListeners();
      if (shouldRunQueuedSync) {
        unawaited(syncNow());
      }
    }
    return success;
  }

  Future<bool> backupNow() async {
    final syncService = _syncService;
    if (syncService == null || _isBackingUp || _isRestoring || _isSyncing) {
      return false;
    }
    _isBackingUp = true;
    notifyListeners();
    var success = false;
    try {
      success = await syncService.backupNow();
      await _refreshSyncState(notify: false);
    } finally {
      _isBackingUp = false;
      notifyListeners();
    }
    return success;
  }

  Future<bool> restoreNow() async {
    final syncService = _syncService;
    if (syncService == null || _isRestoring || _isBackingUp || _isSyncing) {
      return false;
    }
    _isRestoring = true;
    notifyListeners();
    var success = false;
    try {
      success = await syncService.restoreNow();
      final refreshed = await _repository.fetchAll();
      _words
        ..clear()
        ..addAll(refreshed);
      await _refreshSyncState(notify: false);
    } finally {
      _isRestoring = false;
      notifyListeners();
    }
    return success;
  }

  void setSyncIntervalSeconds(int seconds) {
    if (seconds <= 0 || _syncIntervalSeconds == seconds) {
      return;
    }
    _syncIntervalSeconds = seconds;
    if (canSync) {
      _stopPolling();
      _startPolling();
    }
  }

  void setSyncEnabled(bool value) {
    if (_syncEnabled == value) {
      return;
    }
    _syncEnabled = value;
    if (!_syncEnabled) {
      _syncQueued = false;
      _stopPolling();
      notifyListeners();
      return;
    }

    if (_syncService != null) {
      if (_shouldAutoSyncInBackground) {
        _startPolling();
      } else {
        _stopPolling();
      }
    }
    notifyListeners();
  }

  void _startPolling() {
    if (!canSync || !_shouldAutoSyncInBackground) {
      return;
    }
    if (_pollingTimer?.isActive == true) {
      return;
    }
    _pollingTimer = Timer.periodic(
      Duration(seconds: _syncIntervalSeconds),
      (_) => unawaited(syncNow()),
    );
  }

  void _stopPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
  }

  Future<void> _refreshSyncState({bool notify = true}) async {
    final repository = _syncStateRepository;
    final syncService = _syncService;
    if (repository == null || syncService == null) {
      return;
    }

    final state = await repository.fetch();
    _lastSyncAt = state.lastSyncAt;
    _lastSyncAttemptAt = state.lastAttemptAt;
    _lastSyncErrorCode = state.lastErrorCode;
    _lastSyncErrorMessage = state.lastErrorMessage;
    _restoreStatus = state.restoreStatus;

    if (notify) {
      notifyListeners();
    }
  }

  void _logImageStats(List<WordCard> cards) {
    if (!kDebugMode) {
      return;
    }
    var images = 0;
    var totalBytes = 0;
    var maxBytes = 0;
    for (final card in cards) {
      var size = 0;
      final bytes = card.imageBytes;
      if (bytes != null && bytes.isNotEmpty) {
        size = bytes is Uint8List ? bytes.lengthInBytes : bytes.length;
      } else if (card.imagePath != null) {
        final file = File(card.imagePath!);
        if (file.existsSync()) {
          try {
            size = file.lengthSync();
          } catch (_) {
            size = 0;
          }
        }
      }

      if (size <= 0) {
        continue;
      }
      images++;
      totalBytes += size;
      if (size > maxBytes) {
        maxBytes = size;
      }
    }
    _loadedImageBytes = totalBytes;
    debugPrint(
      'WordsNotifier image stats: cards=${cards.length}, images=$images, '
      'total=${(totalBytes / (1024 * 1024)).toStringAsFixed(2)}MB, '
      'max=${(maxBytes / (1024 * 1024)).toStringAsFixed(2)}MB',
    );
    if (!_shouldAutoSyncInBackground) {
      debugPrint(
        'WordsNotifier: auto sync disabled because image data is '
        '${(totalBytes / (1024 * 1024)).toStringAsFixed(2)}MB '
        '(limit ${(_autoSyncImageByteLimit / (1024 * 1024)).toStringAsFixed(0)}MB).',
      );
    }
  }

  bool get _shouldAutoSyncInBackground =>
      _syncEnabled && _loadedImageBytes <= _autoSyncImageByteLimit;

  @override
  void dispose() {
    _stopPolling();
    super.dispose();
  }

  void setSortMode(SortMode mode) {
    _sortMode = mode;
    notifyListeners();
  }

  Future<void> addWord({
    required String word,
    required String meaning,
    required PartOfSpeech partOfSpeech,
    required List<String> sentences,
    String memoryHint = '',
    List<String> customTags = const [],
    WordOrigin origin = WordOrigin.manual,
    File? imageFile,
  }) async {
    final trimmedWord = word.trim();
    if (trimmedWord.isEmpty) {
      throw ArgumentError('word cannot be empty');
    }

    final cleanedSentences = sentences
        .map((sentence) => sentence.trim())
        .where((sentence) => sentence.isNotEmpty)
        .toList();

    final trimmedMeaning = meaning.trim();
    final trimmedMemoryHint = memoryHint.trim();
    final cleanedCustomTags = WordCard.normalizeCustomTags(customTags);

    final now = DateTime.now();
    final schedule = ReviewScheduleService.defaultSchedule;
    final imagePath = imageFile == null
        ? null
        : await _imageStorage.saveImage(imageFile);

    final card = WordCard(
      id: _uuid.v4(),
      word: trimmedWord,
      meaning: trimmedMeaning,
      memoryHint: trimmedMemoryHint,
      partOfSpeech: partOfSpeech,
      sentences: cleanedSentences,
      origin: origin,
      imageCleared: false,
      imagePath: imagePath,
      imageBytes: null,
      createdAt: now,
      updatedAt: now,
      reviewSchedule: schedule,
      nextReviewIndex: 0,
      nextReviewDate: _scheduleService.initialNextDate(now),
      history: [],
      isDeleted: false,
      customTags: cleanedCustomTags,
    );

    await _repository.add(card);
    _words.add(card);
    notifyListeners();
    if (canSync) {
      unawaited(syncNow());
    }
  }

  Future<WordContributionImportResult> importSharedWordsFromJson(
    String jsonText,
  ) async {
    final existingWords = _words
        .map(
          (card) => WordContributionImportService.normalizeWordKey(card.word),
        )
        .where((word) => word.isNotEmpty)
        .toSet();
    final result = _wordContributionImportService.parseJson(
      jsonText: jsonText,
      existingWords: existingWords,
    );

    if (result.importedWords.isEmpty) {
      return result;
    }

    for (final card in result.importedWords) {
      await _repository.add(card);
    }

    _words.addAll(result.importedWords);
    notifyListeners();
    if (canSync) {
      unawaited(syncNow());
    }
    return result;
  }

  Future<void> updateWord({
    required WordCard card,
    required String word,
    required String meaning,
    required PartOfSpeech partOfSpeech,
    required List<String> sentences,
    String memoryHint = '',
    List<String> customTags = const [],
    File? imageFile,
    bool removeImage = false,
  }) async {
    final trimmedWord = word.trim();
    if (trimmedWord.isEmpty) {
      throw ArgumentError('word cannot be empty');
    }

    final cleanedSentences = sentences
        .map((sentence) => sentence.trim())
        .where((sentence) => sentence.isNotEmpty)
        .toList();

    final trimmedMeaning = meaning.trim();
    final trimmedMemoryHint = memoryHint.trim();
    final cleanedCustomTags = WordCard.normalizeCustomTags(customTags);

    var legacyPath = card.imagePath;
    var imageCleared = card.imageCleared;

    if (removeImage) {
      if (legacyPath != null) {
        await _imageStorage.deleteImage(legacyPath);
      }
      legacyPath = null;
      imageCleared = true;
    }

    if (imageFile != null) {
      final newPath = await _imageStorage.saveImage(imageFile);
      if (legacyPath != null) {
        await _imageStorage.deleteImage(legacyPath);
      }
      legacyPath = newPath;
      imageCleared = false;
    } else if (!removeImage &&
        legacyPath == null &&
        card.imageBytes != null &&
        card.imageBytes!.isNotEmpty) {
      legacyPath = await _imageStorage.saveBytes(card.imageBytes!);
      imageCleared = false;
    }

    final updated = card.copyWith(
      word: trimmedWord,
      meaning: trimmedMeaning,
      memoryHint: trimmedMemoryHint,
      partOfSpeech: partOfSpeech,
      sentences: cleanedSentences,
      customTags: cleanedCustomTags,
      imageCleared: imageCleared,
      imagePath: legacyPath,
      imageBytes: null,
      updatedAt: DateTime.now(),
    );

    await _repository.update(updated);

    final index = _words.indexWhere((item) => item.id == card.id);
    if (index != -1) {
      _words[index] = updated;
    }

    notifyListeners();
    if (canSync) {
      unawaited(syncNow());
    }
  }

  Future<void> markReviewed(WordCard card) async {
    final updated = _scheduleService
        .advanceReview(card, DateTime.now())
        .copyWith(updatedAt: DateTime.now());
    await _repository.update(updated);

    final index = _words.indexWhere((item) => item.id == card.id);
    if (index != -1) {
      _words[index] = updated;
    }

    notifyListeners();
    if (canSync) {
      unawaited(syncNow());
    }
  }

  Future<void> markMastered(WordCard card) async {
    final updated = _scheduleService
        .markMastered(card, DateTime.now())
        .copyWith(updatedAt: DateTime.now());
    await _repository.update(updated);

    final index = _words.indexWhere((item) => item.id == card.id);
    if (index != -1) {
      _words[index] = updated;
    }

    notifyListeners();
    if (canSync) {
      unawaited(syncNow());
    }
  }

  Future<void> resumeReview(WordCard card) async {
    final updated = _scheduleService
        .resumeReview(card)
        .copyWith(updatedAt: DateTime.now());
    await _repository.update(updated);

    final index = _words.indexWhere((item) => item.id == card.id);
    if (index != -1) {
      _words[index] = updated;
    }

    notifyListeners();
    if (canSync) {
      unawaited(syncNow());
    }
  }

  Future<void> deleteWord(WordCard card) async {
    final updated = card.copyWith(isDeleted: true, updatedAt: DateTime.now());
    await _repository.update(updated);
    _words.removeWhere((item) => item.id == card.id);
    notifyListeners();
    if (canSync) {
      unawaited(syncNow());
    }
  }
}
