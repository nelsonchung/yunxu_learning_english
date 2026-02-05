import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../data/repositories/sync_state_repository.dart';
import '../../data/repositories/word_repository.dart';
import '../models/sync_state.dart';
import '../models/word_card.dart';

class CloudSyncService {
  CloudSyncService({
    required WordRepository wordRepository,
    required SyncStateRepository syncStateRepository,
    required String containerId,
  })  : _wordRepository = wordRepository,
        _syncStateRepository = syncStateRepository,
        _containerId = containerId;

  static const MethodChannel _channel = MethodChannel('cloud_sync');

  final WordRepository _wordRepository;
  final SyncStateRepository _syncStateRepository;
  final String _containerId;

  bool _isSyncing = false;

  Future<void> sync() async {
    if (_isSyncing) {
      return;
    }
    _isSyncing = true;

    try {
      final state = await _syncStateRepository.fetch();
      final lastSyncAt =
          state.lastSyncAt ?? DateTime.fromMillisecondsSinceEpoch(0);

      final remoteRaw = await _channel.invokeMethod(
        'fetchChanges',
        {
          'containerId': _containerId,
          'since': lastSyncAt.millisecondsSinceEpoch,
        },
      );

      final remoteRecords = <Map<String, Object?>>[];
      if (remoteRaw is List) {
        for (final item in remoteRaw) {
          if (item is Map) {
            remoteRecords.add(item.cast<String, Object?>());
          }
        }
      }

      final localAll = await _wordRepository.fetchAll(includeDeleted: true);
      final localById = {for (final card in localAll) card.id: card};

      DateTime? newestRemote;
      for (final raw in remoteRecords) {
        final remoteCard = _fromCloudMap(raw);
        if (remoteCard.id.isEmpty) {
          continue;
        }
        newestRemote = newestRemote == null
            ? remoteCard.updatedAt
            : remoteCard.updatedAt.isAfter(newestRemote)
                ? remoteCard.updatedAt
                : newestRemote;

        final local = localById[remoteCard.id];
        if (local == null) {
          await _wordRepository.update(remoteCard);
          continue;
        }
        if (local.updatedAt.isBefore(remoteCard.updatedAt)) {
          await _wordRepository.update(remoteCard);
        }
      }

      final refreshedLocal = await _wordRepository.fetchAll(includeDeleted: true);
      final localChanges = refreshedLocal
          .where((card) => card.updatedAt.isAfter(lastSyncAt))
          .toList();

      if (localChanges.isNotEmpty) {
        final payload = {
          'containerId': _containerId,
          'records': localChanges.map(_toCloudMap).toList(),
        };
        await _channel.invokeMethod('pushChanges', payload);
      }

      final newestLocal = localChanges.isEmpty
          ? null
          : localChanges
              .map((card) => card.updatedAt)
              .reduce((a, b) => a.isAfter(b) ? a : b);

      var nextSyncAt = lastSyncAt;
      if (newestRemote != null && newestRemote.isAfter(nextSyncAt)) {
        nextSyncAt = newestRemote;
      }
      if (newestLocal != null && newestLocal.isAfter(nextSyncAt)) {
        nextSyncAt = newestLocal;
      }
      if (nextSyncAt.isBefore(DateTime.now())) {
        nextSyncAt = DateTime.now();
      }

      await _syncStateRepository.save(SyncState(lastSyncAt: nextSyncAt));
    } catch (error, stack) {
      if (error is PlatformException) {
        debugPrint(
          'CloudSyncService PlatformException: code=${error.code} message=${error.message} details=${error.details}',
        );
      } else {
        debugPrint('CloudSyncService sync failed: $error');
      }
      debugPrint('CloudSyncService stack: $stack');
    } finally {
      _isSyncing = false;
    }
  }

  Map<String, Object?> _toCloudMap(WordCard card) {
    final imageBytes = card.imageBytes;
    return {
      'id': card.id,
      'word': card.word,
      'meaning': card.meaning,
      'partOfSpeech': card.partOfSpeech.name,
      'sentences': card.sentences,
      'imageBytes': imageBytes == null ? null : Uint8List.fromList(imageBytes),
      'createdAt': card.createdAt.millisecondsSinceEpoch,
      'updatedAt': card.updatedAt.millisecondsSinceEpoch,
      'reviewSchedule': card.reviewSchedule,
      'nextReviewIndex': card.nextReviewIndex,
      'nextReviewDate': card.nextReviewDate.millisecondsSinceEpoch,
      'history': card.history.map((item) => item.millisecondsSinceEpoch).toList(),
      'isDeleted': card.isDeleted,
    };
  }

  WordCard _fromCloudMap(Map<String, Object?> data) {
    final partRaw = data['partOfSpeech'];
    var part = PartOfSpeech.noun;
    if (partRaw is String) {
      part = PartOfSpeech.values.firstWhere(
        (item) => item.name == partRaw,
        orElse: () => PartOfSpeech.noun,
      );
    }

    List<int>? imageBytes;
    final bytesRaw = data['imageBytes'];
    if (bytesRaw is Uint8List) {
      imageBytes = bytesRaw.toList();
    } else if (bytesRaw is List) {
      imageBytes = List<int>.from(bytesRaw);
    }

    final createdRaw = data['createdAt'];
    final updatedRaw = data['updatedAt'];

    final createdAt = createdRaw is int
        ? DateTime.fromMillisecondsSinceEpoch(createdRaw)
        : DateTime.now();
    final updatedAt = updatedRaw is int
        ? DateTime.fromMillisecondsSinceEpoch(updatedRaw)
        : createdAt;

    final nextReviewRaw = data['nextReviewDate'];
    final nextReviewDate = nextReviewRaw is int
        ? DateTime.fromMillisecondsSinceEpoch(nextReviewRaw)
        : createdAt;

    final historyRaw = data['history'];
    final history = historyRaw is List
        ? historyRaw
            .whereType<int>()
            .map(DateTime.fromMillisecondsSinceEpoch)
            .toList()
        : <DateTime>[];

    final reviewRaw = data['reviewSchedule'];
    final reviewSchedule = reviewRaw is List
        ? reviewRaw.whereType<int>().toList()
        : const <int>[1, 2, 3, 5, 8, 13, 21, 39];

    final isDeletedRaw = data['isDeleted'];
    final isDeleted = isDeletedRaw is bool ? isDeletedRaw : false;

    return WordCard(
      id: (data['id'] as String?) ?? '',
      word: (data['word'] as String?) ?? '',
      meaning: (data['meaning'] as String?) ?? '',
      partOfSpeech: part,
      sentences: (data['sentences'] as List?)?.cast<String>() ?? <String>[],
      imagePath: null,
      imageBytes: imageBytes,
      createdAt: createdAt,
      updatedAt: updatedAt,
      reviewSchedule: reviewSchedule,
      nextReviewIndex: (data['nextReviewIndex'] as int?) ?? 0,
      nextReviewDate: nextReviewDate,
      history: history,
      isDeleted: isDeleted,
    );
  }
}
