import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../data/repositories/settings_repository.dart';
import '../../data/repositories/sync_state_repository.dart';
import '../../data/repositories/word_repository.dart';
import '../models/app_settings.dart';
import '../models/sync_state.dart';
import '../models/word_card.dart';

class CloudSyncService {
  CloudSyncService({
    required WordRepository wordRepository,
    required SettingsRepository settingsRepository,
    required SyncStateRepository syncStateRepository,
    required String containerId,
    bool allowAutoRestoreWhenLocalEmpty = true,
  }) : _wordRepository = wordRepository,
       _settingsRepository = settingsRepository,
       _syncStateRepository = syncStateRepository,
       _containerId = containerId,
       _allowAutoRestoreWhenLocalEmpty = allowAutoRestoreWhenLocalEmpty;

  static const MethodChannel _channel = MethodChannel('cloud_sync');

  final WordRepository _wordRepository;
  final SettingsRepository _settingsRepository;
  final SyncStateRepository _syncStateRepository;
  final String _containerId;
  final bool _allowAutoRestoreWhenLocalEmpty;

  static const int _maxRecordsPerPushBatch = 6;
  static const int _maxBytesPerPushBatch = 4 * 1024 * 1024;

  bool _isSyncing = false;

  Future<SyncState> fetchState() {
    return _syncStateRepository.fetch();
  }

  Future<bool> backupNow() async {
    if (_isSyncing) {
      return false;
    }
    _isSyncing = true;

    final startedAt = DateTime.now();
    final lastKnownState = await _syncStateRepository.fetch();

    try {
      final localAll = await _wordRepository.fetchAll(includeDeleted: true);
      if (localAll.isNotEmpty) {
        await _pushChangesInBatches(localAll);
      }

      final localSettings = await _settingsRepository.fetch();
      await _settingsRepository.save(localSettings);
      await _pushSettings(localSettings);

      await _syncStateRepository.save(
        lastKnownState.copyWith(
          lastSyncAt: startedAt,
          lastAttemptAt: startedAt,
          clearLastErrorCode: true,
          clearLastErrorMessage: true,
          hasEverSynced: true,
        ),
      );
      return true;
    } catch (error, stack) {
      final errorCode = _normalizeSyncErrorCode(error);
      final errorMessage = error is PlatformException
          ? error.message
          : error.toString();
      debugPrint('CloudSyncService backup failed: $error');
      debugPrint('CloudSyncService backup stack: $stack');
      await _syncStateRepository.save(
        lastKnownState.copyWith(
          lastAttemptAt: startedAt,
          lastErrorCode: errorCode,
          lastErrorMessage: errorMessage,
        ),
      );
      return false;
    } finally {
      _isSyncing = false;
    }
  }

  Future<bool> restoreNow() async {
    if (_isSyncing) {
      return false;
    }
    _isSyncing = true;

    final startedAt = DateTime.now();
    var lastKnownState = await _syncStateRepository.fetch();
    try {
      lastKnownState = lastKnownState.copyWith(
        lastAttemptAt: startedAt,
        lastRestoreAttemptAt: startedAt,
        clearLastErrorCode: true,
        clearLastErrorMessage: true,
        restoreStatus: RestoreStatus.restoring,
      );
      await _syncStateRepository.save(lastKnownState);

      final epoch = DateTime.fromMillisecondsSinceEpoch(0);
      final remoteRaw = await _channel.invokeMethod('fetchChanges', {
        'containerId': _containerId,
        'since': epoch.millisecondsSinceEpoch,
      });

      final remoteRecordsRaw = <Map<String, Object?>>[];
      if (remoteRaw is List) {
        for (final item in remoteRaw) {
          if (item is Map) {
            remoteRecordsRaw.add(item.cast<String, Object?>());
          }
        }
      }

      final remoteById = <String, WordCard>{};
      DateTime? newestRemote;
      for (final raw in remoteRecordsRaw) {
        final remoteCard = _fromCloudMap(raw);
        if (remoteCard.id.isEmpty) {
          continue;
        }
        final current = remoteById[remoteCard.id];
        if (current == null ||
            current.updatedAt.isBefore(remoteCard.updatedAt)) {
          remoteById[remoteCard.id] = remoteCard;
        }
        newestRemote = newestRemote == null
            ? remoteCard.updatedAt
            : remoteCard.updatedAt.isAfter(newestRemote)
            ? remoteCard.updatedAt
            : newestRemote;
      }

      final localAll = await _wordRepository.fetchAll(includeDeleted: true);
      final localById = {for (final card in localAll) card.id: card};
      for (final remoteCard in remoteById.values) {
        final local = localById[remoteCard.id];
        if (local == null ||
            local.updatedAt.isBefore(remoteCard.updatedAt) ||
            _shouldRecoverImageFromRemote(local, remoteCard)) {
          await _wordRepository.update(remoteCard);
        }
      }

      final remoteSettingsRaw = await _channel.invokeMethod('fetchSettings', {
        'containerId': _containerId,
      });
      var remoteHasSettings = false;
      if (remoteSettingsRaw is Map) {
        final remoteSettings = _settingsFromCloudMap(
          remoteSettingsRaw.cast<String, Object?>(),
        );
        await _settingsRepository.save(remoteSettings);
        remoteHasSettings = true;
      }

      final hasRemoteBackupData = remoteById.isNotEmpty || remoteHasSettings;
      var nextSyncAt = startedAt;
      if (newestRemote != null && newestRemote.isAfter(nextSyncAt)) {
        nextSyncAt = newestRemote;
      }

      await _syncStateRepository.save(
        lastKnownState.copyWith(
          lastSyncAt: nextSyncAt,
          lastAttemptAt: startedAt,
          lastRestoreAttemptAt: startedAt,
          clearLastErrorCode: true,
          clearLastErrorMessage: true,
          restoreStatus: hasRemoteBackupData
              ? RestoreStatus.restored
              : RestoreStatus.newInstall,
          hasEverSynced: true,
        ),
      );
      return true;
    } catch (error, stack) {
      final errorCode = _normalizeSyncErrorCode(error);
      final errorMessage = error is PlatformException
          ? error.message
          : error.toString();
      debugPrint('CloudSyncService restore failed: $error');
      debugPrint('CloudSyncService restore stack: $stack');
      await _syncStateRepository.save(
        lastKnownState.copyWith(
          lastAttemptAt: startedAt,
          lastRestoreAttemptAt: startedAt,
          lastErrorCode: errorCode,
          lastErrorMessage: errorMessage,
          restoreStatus: RestoreStatus.failed,
        ),
      );
      return false;
    } finally {
      _isSyncing = false;
    }
  }

  Future<bool> sync() async {
    if (_isSyncing) {
      return false;
    }
    _isSyncing = true;

    final syncStartedAt = DateTime.now();
    var lastKnownState = await _syncStateRepository.fetch();
    var shouldRunRestoreCheck = false;

    try {
      final epoch = DateTime.fromMillisecondsSinceEpoch(0);
      final lastSyncAt = lastKnownState.lastSyncAt ?? epoch;

      final localAllBeforeSync = await _wordRepository.fetchAll(
        includeDeleted: true,
      );
      final hasLocalSettings = await _settingsRepository.hasSavedSettings();
      shouldRunRestoreCheck =
          _allowAutoRestoreWhenLocalEmpty &&
          localAllBeforeSync.isEmpty &&
          !hasLocalSettings;

      if (shouldRunRestoreCheck) {
        lastKnownState = lastKnownState.copyWith(
          lastAttemptAt: syncStartedAt,
          lastRestoreAttemptAt: syncStartedAt,
          clearLastErrorCode: true,
          clearLastErrorMessage: true,
          restoreStatus: RestoreStatus.restoring,
        );
        await _syncStateRepository.save(lastKnownState);
      }

      final since =
          (shouldRunRestoreCheck ? epoch : lastSyncAt)
              .subtract(const Duration(minutes: 5))
              .isBefore(epoch)
          ? epoch
          : (shouldRunRestoreCheck ? epoch : lastSyncAt).subtract(
              const Duration(minutes: 5),
            );

      final remoteRaw = await _channel.invokeMethod('fetchChanges', {
        'containerId': _containerId,
        'since': since.millisecondsSinceEpoch,
      });

      final remoteRecordsRaw = <Map<String, Object?>>[];
      if (remoteRaw is List) {
        for (final item in remoteRaw) {
          if (item is Map) {
            remoteRecordsRaw.add(item.cast<String, Object?>());
          }
        }
      }

      final remoteById = <String, WordCard>{};
      final hasRemoteWordData = remoteRecordsRaw.isNotEmpty;
      DateTime? newestRemote;
      for (final raw in remoteRecordsRaw) {
        final remoteCard = _fromCloudMap(raw);
        if (remoteCard.id.isEmpty) {
          continue;
        }
        final current = remoteById[remoteCard.id];
        if (current == null ||
            current.updatedAt.isBefore(remoteCard.updatedAt)) {
          remoteById[remoteCard.id] = remoteCard;
        }
        newestRemote = newestRemote == null
            ? remoteCard.updatedAt
            : remoteCard.updatedAt.isAfter(newestRemote)
            ? remoteCard.updatedAt
            : newestRemote;
      }

      final localByIdBeforeSync = {
        for (final card in localAllBeforeSync) card.id: card,
      };

      for (final remoteCard in remoteById.values) {
        final local = localByIdBeforeSync[remoteCard.id];
        if (local == null) {
          await _wordRepository.update(remoteCard);
          continue;
        }
        if (local.updatedAt.isBefore(remoteCard.updatedAt) ||
            _shouldRecoverImageFromRemote(local, remoteCard)) {
          await _wordRepository.update(remoteCard);
        }
      }

      final localChanges = localAllBeforeSync
          .where((card) => card.updatedAt.isAfter(lastSyncAt))
          .where((card) {
            final remote = remoteById[card.id];
            if (remote == null) {
              return true;
            }
            return card.updatedAt.isAfter(remote.updatedAt);
          })
          .toList();

      if (localChanges.isNotEmpty) {
        await _pushChangesInBatches(localChanges);
      }

      final settingsSyncResult = await _syncSettings();

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
      if (settingsSyncResult.newestSyncedAt != null &&
          settingsSyncResult.newestSyncedAt!.isAfter(nextSyncAt)) {
        nextSyncAt = settingsSyncResult.newestSyncedAt!;
      }
      if (nextSyncAt.isBefore(syncStartedAt)) {
        nextSyncAt = syncStartedAt;
      }

      final hasRemoteBackupData =
          hasRemoteWordData || settingsSyncResult.remoteHasData;
      final restoreStatus = shouldRunRestoreCheck
          ? (hasRemoteBackupData
                ? RestoreStatus.restored
                : RestoreStatus.newInstall)
          : lastKnownState.restoreStatus;

      await _syncStateRepository.save(
        lastKnownState.copyWith(
          lastSyncAt: nextSyncAt,
          lastAttemptAt: syncStartedAt,
          lastRestoreAttemptAt: shouldRunRestoreCheck ? syncStartedAt : null,
          clearLastErrorCode: true,
          clearLastErrorMessage: true,
          restoreStatus: restoreStatus,
          hasEverSynced: true,
        ),
      );
      return true;
    } catch (error, stack) {
      final errorCode = _normalizeSyncErrorCode(error);
      String? errorMessage;
      if (error is PlatformException) {
        errorMessage = error.message;
        debugPrint(
          'CloudSyncService PlatformException: code=${error.code} message=${error.message} details=${error.details}',
        );
      } else {
        errorMessage = error.toString();
        debugPrint('CloudSyncService sync failed: $error');
      }
      debugPrint('CloudSyncService stack: $stack');

      await _syncStateRepository.save(
        lastKnownState.copyWith(
          lastAttemptAt: syncStartedAt,
          lastRestoreAttemptAt: shouldRunRestoreCheck ? syncStartedAt : null,
          lastErrorCode: errorCode,
          lastErrorMessage: errorMessage,
          restoreStatus: shouldRunRestoreCheck
              ? RestoreStatus.failed
              : lastKnownState.restoreStatus,
        ),
      );
      return false;
    } finally {
      _isSyncing = false;
    }
  }

  Future<_SettingsSyncResult> _syncSettings() async {
    final localSettings = await _settingsRepository.fetch();

    final remoteRaw = await _channel.invokeMethod('fetchSettings', {
      'containerId': _containerId,
    });

    AppSettings? remoteSettings;
    if (remoteRaw is Map) {
      remoteSettings = _settingsFromCloudMap(remoteRaw.cast<String, Object?>());
    }

    if (remoteSettings == null) {
      await _settingsRepository.save(localSettings);
      await _pushSettings(localSettings);
      return _SettingsSyncResult(
        newestSyncedAt: localSettings.updatedAt,
        remoteHasData: false,
      );
    }

    if (localSettings.updatedAt.isBefore(remoteSettings.updatedAt)) {
      await _settingsRepository.save(remoteSettings);
      return _SettingsSyncResult(
        newestSyncedAt: remoteSettings.updatedAt,
        remoteHasData: true,
      );
    }

    if (localSettings.updatedAt.isAfter(remoteSettings.updatedAt)) {
      await _pushSettings(localSettings);
      return _SettingsSyncResult(
        newestSyncedAt: localSettings.updatedAt,
        remoteHasData: true,
      );
    }

    return _SettingsSyncResult(
      newestSyncedAt: localSettings.updatedAt,
      remoteHasData: true,
    );
  }

  Future<void> _pushChangesInBatches(List<WordCard> cards) async {
    if (cards.isEmpty) {
      return;
    }

    final batch = <WordCard>[];
    var batchBytes = 0;

    Future<void> flush() async {
      if (batch.isEmpty) {
        return;
      }
      final records = <Map<String, Object?>>[];
      for (final card in batch) {
        records.add(await _toCloudMap(card));
      }
      await _channel.invokeMethod('pushChanges', {
        'containerId': _containerId,
        'records': records,
      });
      batch.clear();
      batchBytes = 0;
    }

    for (final card in cards) {
      final estimatedBytes = _estimatePushPayloadBytes(card);
      final hitRecordLimit = batch.length >= _maxRecordsPerPushBatch;
      final hitBytesLimit =
          batch.isNotEmpty &&
          (batchBytes + estimatedBytes) > _maxBytesPerPushBatch;

      if (hitRecordLimit || hitBytesLimit) {
        await flush();
      }

      batch.add(card);
      batchBytes += estimatedBytes;
    }

    await flush();
  }

  int _estimatePushPayloadBytes(WordCard card) {
    if (card.imageCleared) {
      return 2048;
    }

    final imageBytes = card.imageBytes;
    var imageSize = imageBytes == null ? 0 : imageBytes.length;
    if (imageSize == 0 && card.imagePath != null) {
      try {
        final file = File(card.imagePath!);
        if (file.existsSync()) {
          imageSize = file.lengthSync();
        }
      } catch (_) {
        imageSize = 0;
      }
    }
    return 2048 + imageSize;
  }

  Future<void> _pushSettings(AppSettings settings) {
    return _channel.invokeMethod('pushSettings', {
      'containerId': _containerId,
      'settings': _settingsToCloudMap(settings),
    });
  }

  Future<Map<String, Object?>> _toCloudMap(WordCard card) async {
    if (card.imageCleared) {
      return {
        'id': card.id,
        'word': card.word,
        'meaning': card.meaning,
        'partOfSpeech': card.partOfSpeech.name,
        'sentences': card.sentences,
        'origin': card.origin.name,
        'imageBytes': null,
        'createdAt': card.createdAt.millisecondsSinceEpoch,
        'updatedAt': card.updatedAt.millisecondsSinceEpoch,
        'reviewSchedule': card.reviewSchedule,
        'nextReviewIndex': card.nextReviewIndex,
        'nextReviewDate': card.nextReviewDate.millisecondsSinceEpoch,
        'history': card.history
            .map((item) => item.millisecondsSinceEpoch)
            .toList(),
        'isDeleted': card.isDeleted,
      };
    }

    var imageBytes = card.imageBytes;
    var hasImageSource = imageBytes != null && imageBytes.isNotEmpty;
    if ((imageBytes == null || imageBytes.isEmpty) && card.imagePath != null) {
      hasImageSource = true;
      final file = File(card.imagePath!);
      if (await file.exists()) {
        imageBytes = await file.readAsBytes();
      }
    }

    final typedImageBytes = imageBytes == null
        ? null
        : imageBytes is Uint8List
        ? imageBytes
        : Uint8List.fromList(imageBytes);

    final map = <String, Object?>{
      'id': card.id,
      'word': card.word,
      'meaning': card.meaning,
      'partOfSpeech': card.partOfSpeech.name,
      'sentences': card.sentences,
      'origin': card.origin.name,
      'createdAt': card.createdAt.millisecondsSinceEpoch,
      'updatedAt': card.updatedAt.millisecondsSinceEpoch,
      'reviewSchedule': card.reviewSchedule,
      'nextReviewIndex': card.nextReviewIndex,
      'nextReviewDate': card.nextReviewDate.millisecondsSinceEpoch,
      'history': card.history
          .map((item) => item.millisecondsSinceEpoch)
          .toList(),
      'isDeleted': card.isDeleted,
    };

    if (typedImageBytes != null) {
      map['imageBytes'] = typedImageBytes;
    } else if (!hasImageSource) {
      // Keep CloudKit asset untouched when local card has no image updates.
    } else {
      // Local card references an image but file is currently unavailable.
      // Do not send image=nil; preserve existing cloud asset.
    }

    return map;
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

    final originRaw = data['origin'];
    var origin = WordOrigin.unknown;
    if (originRaw is String) {
      origin = WordOrigin.values.firstWhere(
        (item) => item.name == originRaw,
        orElse: () => WordOrigin.unknown,
      );
    }

    List<int>? imageBytes;
    final bytesRaw = data['imageBytes'];
    if (bytesRaw is Uint8List) {
      imageBytes = bytesRaw;
    } else if (bytesRaw is List) {
      try {
        imageBytes = bytesRaw.cast<int>();
      } catch (_) {
        imageBytes = null;
      }
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
      origin: origin,
      imageCleared: false,
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

  Map<String, Object?> _settingsToCloudMap(AppSettings settings) {
    return {
      'reminderMinutes': settings.reminderMinutes,
      'showImages': settings.showImages,
      'reminderEnabled': settings.reminderEnabled,
      'dailyNewWordsEnabled': settings.dailyNewWordsEnabled,
      'dailyNewWordsReviewThreshold': settings.dailyNewWordsReviewThreshold,
      'dailyNewWordsCount': settings.dailyNewWordsCount,
      'syncEnabled': settings.syncEnabled,
      'syncIntervalSeconds': settings.syncIntervalSeconds,
      'pronunciationEnabled': settings.pronunciationEnabled,
      'pronunciationRate': settings.pronunciationRate,
      'pronunciationLocale': settings.pronunciationLocale,
      'updatedAt': settings.updatedAt.millisecondsSinceEpoch,
    };
  }

  AppSettings _settingsFromCloudMap(Map<String, Object?> data) {
    final reminderMinutesRaw = data['reminderMinutes'];
    final showImagesRaw = data['showImages'];
    final reminderEnabledRaw = data['reminderEnabled'];
    final dailyNewWordsEnabledRaw = data['dailyNewWordsEnabled'];
    final dailyNewWordsReviewThresholdRaw =
        data['dailyNewWordsReviewThreshold'];
    final dailyNewWordsCountRaw = data['dailyNewWordsCount'];
    final syncEnabledRaw = data['syncEnabled'];
    final syncIntervalSecondsRaw = data['syncIntervalSeconds'];
    final pronunciationEnabledRaw = data['pronunciationEnabled'];
    final pronunciationRateRaw = data['pronunciationRate'];
    final pronunciationLocaleRaw = data['pronunciationLocale'];
    final updatedAtRaw = data['updatedAt'];

    return AppSettings(
      reminderMinutes: reminderMinutesRaw is int ? reminderMinutesRaw : 20 * 60,
      showImages: showImagesRaw is bool ? showImagesRaw : true,
      reminderEnabled: reminderEnabledRaw is bool ? reminderEnabledRaw : true,
      dailyNewWordsEnabled: dailyNewWordsEnabledRaw is bool
          ? dailyNewWordsEnabledRaw
          : true,
      dailyNewWordsReviewThreshold:
          dailyNewWordsReviewThresholdRaw is int &&
              dailyNewWordsReviewThresholdRaw >= 0
          ? dailyNewWordsReviewThresholdRaw
          : 10,
      dailyNewWordsCount:
          dailyNewWordsCountRaw is int && dailyNewWordsCountRaw > 0
          ? dailyNewWordsCountRaw
          : 3,
      syncEnabled: syncEnabledRaw is bool ? syncEnabledRaw : true,
      syncIntervalSeconds: syncIntervalSecondsRaw is int
          ? syncIntervalSecondsRaw
          : 60,
      pronunciationEnabled: pronunciationEnabledRaw is bool
          ? pronunciationEnabledRaw
          : true,
      pronunciationRate: pronunciationRateRaw is num
          ? pronunciationRateRaw.toDouble()
          : 0.45,
      pronunciationLocale:
          pronunciationLocaleRaw is String &&
              pronunciationLocaleRaw.trim().isNotEmpty
          ? pronunciationLocaleRaw.trim()
          : 'en-US',
      updatedAt: updatedAtRaw is int
          ? DateTime.fromMillisecondsSinceEpoch(updatedAtRaw)
          : DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  String _normalizeSyncErrorCode(Object error) {
    if (error is! PlatformException) {
      return 'sync_failed';
    }

    switch (error.code) {
      case 'icloud_not_signed_in':
      case 'icloud_permission_denied':
      case 'quota_exceeded':
      case 'network_unavailable':
      case 'server_error':
      case 'schema_version_mismatch':
      case 'sync_failed':
        return error.code;
    }

    final message = (error.message ?? '').toLowerCase();
    if (message.contains('not authenticated') ||
        message.contains('not signed in') ||
        message.contains('icloud account')) {
      return 'icloud_not_signed_in';
    }
    if (message.contains('permission') || message.contains('entitlement')) {
      return 'icloud_permission_denied';
    }
    if (message.contains('quota')) {
      return 'quota_exceeded';
    }
    if (message.contains('network') || message.contains('internet')) {
      return 'network_unavailable';
    }
    if (message.contains('service unavailable') ||
        message.contains('rate') ||
        message.contains('busy')) {
      return 'server_error';
    }
    return 'sync_failed';
  }

  bool _shouldRecoverImageFromRemote(WordCard local, WordCard remote) {
    if (!local.updatedAt.isAtSameMomentAs(remote.updatedAt)) {
      return false;
    }
    if (local.imageCleared) {
      return false;
    }
    return !_hasImageData(local) && _hasImageData(remote);
  }

  bool _hasImageData(WordCard card) {
    final bytes = card.imageBytes;
    return (bytes != null && bytes.isNotEmpty) || card.imagePath != null;
  }
}

class _SettingsSyncResult {
  const _SettingsSyncResult({
    required this.newestSyncedAt,
    required this.remoteHasData,
  });

  final DateTime? newestSyncedAt;
  final bool remoteHasData;
}
