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

class WordsNotifier extends ChangeNotifier {
  WordsNotifier({
    required WordRepository repository,
    required ReviewScheduleService scheduleService,
    required SortService sortService,
    required ImageStorage imageStorage,
    SyncStateRepository? syncStateRepository,
    CloudSyncService? syncService,
    bool initialSyncEnabled = true,
    int initialSyncIntervalSeconds = 60,
  }) : _repository = repository,
       _scheduleService = scheduleService,
       _sortService = sortService,
       _imageStorage = imageStorage,
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
  final SyncStateRepository? _syncStateRepository;
  final CloudSyncService? _syncService;
  final _uuid = const Uuid();

  final List<WordCard> _words = [];
  SortMode _sortMode = SortMode.alphabetAsc;
  bool _isLoading = false;
  bool _isSyncing = false;
  Timer? _pollingTimer;
  int _syncIntervalSeconds;
  bool _syncEnabled;
  DateTime? _lastSyncAt;
  DateTime? _lastSyncAttemptAt;
  String? _lastSyncErrorCode;
  String? _lastSyncErrorMessage;
  RestoreStatus _restoreStatus = RestoreStatus.idle;

  List<WordCard> get words => _sortService.sort(_words, _sortMode);
  SortMode get sortMode => _sortMode;
  bool get isLoading => _isLoading;
  bool get isSyncing => _isSyncing;
  bool get syncSupported => _syncService != null;
  bool get syncEnabled => _syncEnabled;
  bool get canSync => syncSupported && syncEnabled;
  int get totalWords => _words.length;
  int get dueWordsCount => dueToday().length;
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

  Future<void> load() async {
    _isLoading = true;
    notifyListeners();

    final all = await _repository.fetchAll();
    final migrated = await _migrateLegacyImages(all);
    _words
      ..clear()
      ..addAll(migrated);

    _isLoading = false;
    notifyListeners();

    if (_syncService != null) {
      await _refreshSyncState(notify: false);
      if (_syncEnabled) {
        unawaited(syncNow());
        _startPolling();
      } else {
        _stopPolling();
      }
    }
  }

  Future<bool> syncNow() async {
    final syncService = _syncService;
    if (syncService == null || _isSyncing || !_syncEnabled) {
      return false;
    }
    _isSyncing = true;
    notifyListeners();
    var success = false;
    try {
      success = await syncService.sync();
      final refreshed = await _repository.fetchAll();
      _words
        ..clear()
        ..addAll(refreshed);
      await _refreshSyncState(notify: false);
    } finally {
      _isSyncing = false;
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
      _stopPolling();
      notifyListeners();
      return;
    }

    if (_syncService != null) {
      _startPolling();
      unawaited(syncNow());
    }
    notifyListeners();
  }

  void _startPolling() {
    if (!canSync) {
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

  @override
  void dispose() {
    _stopPolling();
    super.dispose();
  }

  Future<List<WordCard>> _migrateLegacyImages(List<WordCard> cards) async {
    var updated = false;
    final migrated = <WordCard>[];

    for (final card in cards) {
      if (card.imageBytes == null && card.imagePath != null) {
        final file = File(card.imagePath!);
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          final newCard = card.copyWith(
            imageBytes: bytes,
            imagePath: null,
            updatedAt: DateTime.now(),
          );
          await _repository.update(newCard);
          migrated.add(newCard);
          updated = true;
          continue;
        }

        final cleanedCard = card.copyWith(
          imagePath: null,
          updatedAt: DateTime.now(),
        );
        await _repository.update(cleanedCard);
        migrated.add(cleanedCard);
        updated = true;
        continue;
      }

      migrated.add(card);
    }

    if (updated) {
      notifyListeners();
    }

    return migrated;
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
    File? imageFile,
  }) async {
    final cleanedSentences = sentences
        .map((sentence) => sentence.trim())
        .where((sentence) => sentence.isNotEmpty)
        .toList();

    if (cleanedSentences.isEmpty) {
      throw ArgumentError('sentences cannot be empty');
    }

    final trimmedMeaning = meaning.trim();
    if (trimmedMeaning.isEmpty) {
      throw ArgumentError('meaning cannot be empty');
    }

    final now = DateTime.now();
    final schedule = ReviewScheduleService.defaultSchedule;
    final imageBytes = imageFile != null ? await imageFile.readAsBytes() : null;

    final card = WordCard(
      id: _uuid.v4(),
      word: word.trim(),
      meaning: trimmedMeaning,
      partOfSpeech: partOfSpeech,
      sentences: cleanedSentences,
      imagePath: null,
      imageBytes: imageBytes,
      createdAt: now,
      updatedAt: now,
      reviewSchedule: schedule,
      nextReviewIndex: 0,
      nextReviewDate: _scheduleService.initialNextDate(now),
      history: [],
      isDeleted: false,
    );

    await _repository.add(card);
    _words.add(card);
    notifyListeners();
    if (canSync) {
      unawaited(syncNow());
    }
  }

  Future<void> updateWord({
    required WordCard card,
    required String word,
    required String meaning,
    required PartOfSpeech partOfSpeech,
    required List<String> sentences,
    File? imageFile,
    bool removeImage = false,
  }) async {
    final cleanedSentences = sentences
        .map((sentence) => sentence.trim())
        .where((sentence) => sentence.isNotEmpty)
        .toList();

    if (cleanedSentences.isEmpty) {
      throw ArgumentError('sentences cannot be empty');
    }

    final trimmedMeaning = meaning.trim();
    if (trimmedMeaning.isEmpty) {
      throw ArgumentError('meaning cannot be empty');
    }

    var imageBytes = card.imageBytes;
    var legacyPath = card.imagePath;

    if (removeImage) {
      imageBytes = null;
      if (legacyPath != null) {
        await _imageStorage.deleteImage(legacyPath);
        legacyPath = null;
      }
    }

    if (imageFile != null) {
      imageBytes = await imageFile.readAsBytes();
      if (legacyPath != null) {
        await _imageStorage.deleteImage(legacyPath);
        legacyPath = null;
      }
    }

    final updated = card.copyWith(
      word: word.trim(),
      meaning: trimmedMeaning,
      partOfSpeech: partOfSpeech,
      sentences: cleanedSentences,
      imagePath: legacyPath,
      imageBytes: imageBytes,
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
