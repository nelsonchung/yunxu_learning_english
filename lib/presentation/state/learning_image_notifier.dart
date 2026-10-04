import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../data/storage/learning_image_store.dart';
import '../../domain/models/learning_image.dart';
import '../../domain/models/word_card.dart';
import '../../domain/services/learning_image_service.dart';

class LearningImageNotifier extends ChangeNotifier {
  LearningImageNotifier({
    required LearningImageService service,
    required LearningImageStore store,
    required LearningImageCredentials credentials,
  }) : _service = service,
       _store = store,
       _credentials = credentials;
  final LearningImageService _service;
  final LearningImageStore _store;
  final LearningImageCredentials _credentials;
  LearningImageMode mode = LearningImageMode.precise;
  LearningImageStage stage = LearningImageStage.idle;
  String? error;
  WordCard? sourceWord;
  LearningImageContent? content;
  Uint8List? imageBytes;
  bool hasKey = false;
  bool _active = false,
      _draining = false,
      _cancelled = false,
      _disposed = false;
  final List<LearningImageAttempt> _attempts = [];
  final Set<String> _currentIds = {};
  int _sequence = 0;
  String? _generatedModel;
  bool isApplying = false;
  bool get isBusy => _active || _draining || isApplying;
  bool beginApply() {
    if (isBusy ||
        stage != LearningImageStage.ready ||
        imageBytes == null ||
        sourceWord == null) {
      return false;
    }
    isApplying = true;
    _notify();
    return true;
  }

  void endApply() {
    isApplying = false;
    _notify();
  }

  List<LearningImageSource> get sources => content?.sources ?? const [];
  List<LearningImageAttempt> get attempts => List.unmodifiable(_attempts);
  double get knownCostUsd => _attempts.fold(0, (sum, a) => sum + a.cost.usd);
  bool get hasUnknownCost => _attempts.any((a) => a.cost.unknown);
  double get currentCostUsd => _attempts
      .where((a) => _currentIds.contains(a.id))
      .fold(0, (sum, a) => sum + a.cost.usd);
  bool get currentHasUnknownCost => _attempts
      .where((a) => _currentIds.contains(a.id))
      .any((a) => a.cost.unknown);
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void>? _initialization;
  Future<void> initialize() => _initialization ??= _initialize();
  Future<void> _initialize() async {
    try {
      hasKey = (await _credentials.load())?.trim().isNotEmpty ?? false;
      mode = await _store.loadMode();
      _attempts.clear();
      _attempts.addAll(await _store.attempts());
    } catch (_) {
      error = '無法讀取 AI 設定或費用紀錄，請檢查裝置安全儲存。';
    }
    _notify();
  }

  Future<void> saveApiKey(String key) async {
    await initialize();
    if (key.trim().isEmpty) throw const LearningImageException('請輸入 API Key。');
    await _credentials.save(key);
    hasKey = true;
    _notify();
  }

  Future<void> deleteApiKey() async {
    await initialize();
    await _credentials.delete();
    hasKey = false;
    _notify();
  }

  Future<void> setMode(LearningImageMode value) async {
    await initialize();
    if (isBusy) return;
    await _store.saveMode(value);
    mode = value;
    _notify();
  }

  Future<void> _run(Future<void> Function(String key) action) async {
    if (isBusy || _disposed) return;
    _active = true;
    _cancelled = false;
    error = null;
    _notify();
    try {
      await initialize();
      final key = await _credentials.load();
      if (key == null || key.trim().isEmpty) {
        throw const LearningImageException('請先設定 OpenAI API Key。');
      }
      if (_cancelled) return;
      await action(key);
    } on TimeoutException {
      if (!_cancelled) {
        error = '請求逾時，費用可能仍已產生。請手動重試。';
        stage = LearningImageStage.failed;
        _cancelled = true;
      }
    } on LearningImageException catch (e) {
      if (!_cancelled) {
        error = e.message;
        stage = LearningImageStage.failed;
      }
    } catch (_) {
      if (!_cancelled) {
        error = '無法完成生成，請檢查網路與本機儲存後手動重試。費用可能已產生。';
        stage = LearningImageStage.failed;
      }
    } finally {
      _active = false;
      _notify();
    }
  }

  Future<T> _phase<T>(Future<T> response) {
    _draining = true;
    return response
        .whenComplete(() {
          _draining = false;
          _notify();
        })
        .timeout(_service.timeout);
  }

  Future<LearningImageUsageCallback> _beginAttempt(String model) async {
    final attempt = LearningImageAttempt(
      id: '${DateTime.now().microsecondsSinceEpoch}-${_sequence++}',
      model: model,
      createdAt: DateTime.now(),
    );
    await _store.putAttempt(
      attempt,
    ); // Durably account for unknown charges before paid dispatch.
    _attempts.add(attempt);
    _currentIds.add(attempt.id);
    _notify();
    return (requestId, usage, searches) async {
      final completed = LearningImageAttempt(
        id: attempt.id,
        model: model,
        createdAt: attempt.createdAt,
        requestId: requestId,
        usage: usage,
        searches: searches,
        status: usage == null ? 'unknown' : 'completed',
      );
      await _store.putAttempt(completed);
      final index = _attempts.indexWhere((a) => a.id == attempt.id);
      if (index >= 0) _attempts[index] = completed;
      _notify();
    };
  }

  Future<void> _markNotSent() async {
    final pending = _attempts.last;
    final skipped = LearningImageAttempt(
      id: pending.id,
      model: pending.model,
      createdAt: pending.createdAt,
      status: 'not_sent',
      savedCost: const LearningImageCost(usd: 0, unknown: false),
    );
    await _store.putAttempt(skipped);
    _attempts[_attempts.length - 1] = skipped;
    _notify();
  }

  Future<void> start(WordCard word) async {
    if (isBusy) return;
    sourceWord = word;
    content = null;
    imageBytes = null;
    _currentIds.clear();
    await _run((key) async {
      stage = LearningImageStage.researching;
      _notify();
      final record = await _beginAttempt('gpt-5.4-mini');
      if (_cancelled) {
        await _markNotSent();
        return;
      }
      final researched = await _phase(_service.research(word, key, record));
      if (_cancelled) return;
      content = researched;
      if (researched.conflict.isNotEmpty) {
        stage = LearningImageStage.conflict;
        _notify();
        return;
      }
      await _generate(key);
    });
  }

  Future<void> resolveConflict({required bool useExisting}) async {
    if (isBusy || content == null || sourceWord == null) return;
    if (useExisting) {
      final word = sourceWord!;
      content = LearningImageContent(
        word: word.word,
        meaning: word.meaning,
        partsOfSpeech: word.partsOfSpeechLabel,
        sentences: word.sentences.take(3).toList(),
        memoryHint: word.memoryHint,
        diagram: '以情境插圖呈現使用者提供的詞義。',
        sources: content!.sources,
      );
    }
    await _run(_generate);
  }

  Future<void> regenerate() async {
    if (isBusy || content == null) return;
    imageBytes = null;
    await _run(_generate);
  }

  Future<void> _generate(String key) async {
    if (_cancelled || content == null) return;
    stage = LearningImageStage.generating;
    _notify();
    final selectedMode = mode;
    final record = await _beginAttempt(selectedMode.model);
    if (_cancelled) {
      await _markNotSent();
      return;
    }
    final bytes = await _phase(
      _service.generate(content!, selectedMode, key, record),
    );
    if (_cancelled) return;
    _generatedModel = selectedMode.model;
    imageBytes = bytes;
    stage = LearningImageStage.ready;
    _notify();
  }

  void cancel() {
    if (isApplying) return;
    _cancelled = true;
    imageBytes = null;
    stage = LearningImageStage.cancelled;
    error = '已取消；已送出的請求仍可能計費。等待請求結束後才能再次生成。';
    _notify();
  }

  void discard() {
    if (isApplying) return;
    if (_active) {
      cancel();
      return;
    }
    imageBytes = null;
    content = null;
    sourceWord = null;
    stage = LearningImageStage.idle;
    error = null;
    _notify();
  }

  Future<void> saveMetadata({
    required String wordId,
    required String imageIdentity,
  }) async {
    if (content == null || imageBytes == null) return;
    await _store.putMetadata(
      LearningImageMetadata(
        wordId: wordId,
        imageIdentity: imageIdentity,
        content: content!,
        model: _generatedModel ?? mode.model,
        createdAt: DateTime.now(),
      ),
    );
  }

  Future<LearningImageMetadata?> metadataFor(String wordId) =>
      _store.metadataFor(wordId);
  @override
  void dispose() {
    _disposed = true;
    _cancelled = true;
    _service.dispose();
    super.dispose();
  }
}
