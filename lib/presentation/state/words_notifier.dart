import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../data/repositories/word_repository.dart';
import '../../data/storage/image_storage.dart';
import '../../domain/models/word_card.dart';
import '../../domain/services/review_schedule_service.dart';
import '../../domain/services/sort_service.dart';

class WordsNotifier extends ChangeNotifier {
  WordsNotifier({
    required WordRepository repository,
    required ReviewScheduleService scheduleService,
    required SortService sortService,
    required ImageStorage imageStorage,
  })  : _repository = repository,
        _scheduleService = scheduleService,
        _sortService = sortService,
        _imageStorage = imageStorage;

  final WordRepository _repository;
  final ReviewScheduleService _scheduleService;
  final SortService _sortService;
  final ImageStorage _imageStorage;
  final _uuid = const Uuid();

  final List<WordCard> _words = [];
  SortMode _sortMode = SortMode.alphabetAsc;
  bool _isLoading = false;

  List<WordCard> get words => _sortService.sort(_words, _sortMode);
  SortMode get sortMode => _sortMode;
  bool get isLoading => _isLoading;

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
    _words
      ..clear()
      ..addAll(all);

    _isLoading = false;
    notifyListeners();
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
    final imagePath =
        imageFile != null ? await _imageStorage.saveImage(imageFile) : null;

    final card = WordCard(
      id: _uuid.v4(),
      word: word.trim(),
      meaning: trimmedMeaning,
      partOfSpeech: partOfSpeech,
      sentences: cleanedSentences,
      imagePath: imagePath,
      createdAt: now,
      reviewSchedule: schedule,
      nextReviewIndex: 0,
      nextReviewDate: _scheduleService.initialNextDate(now),
      history: [],
    );

    await _repository.add(card);
    _words.add(card);
    notifyListeners();
  }

  Future<void> markReviewed(WordCard card) async {
    final updated = _scheduleService.advanceReview(card, DateTime.now());
    await _repository.update(updated);

    final index = _words.indexWhere((item) => item.id == card.id);
    if (index != -1) {
      _words[index] = updated;
    }

    notifyListeners();
  }

  Future<void> deleteWord(WordCard card) async {
    await _repository.delete(card.id);
    _words.removeWhere((item) => item.id == card.id);
    notifyListeners();
  }
}
