import 'dart:io';
import 'dart:typed_data';

import '../../domain/models/word_card.dart';
import '../../domain/services/review_schedule_service.dart';
import '../sources/word_local_db.dart';
import 'word_repository.dart';

class LocalWordRepository implements WordRepository {
  LocalWordRepository({
    required WordLocalDb localDb,
    required ReviewScheduleService scheduleService,
  }) : _localDb = localDb,
       _scheduleService = scheduleService;

  final WordLocalDb _localDb;
  final ReviewScheduleService _scheduleService;

  @override
  Future<int> migrateImageBytesToPaths({
    required Future<String> Function(List<int> bytes) saveBytes,
  }) async {
    var migrated = 0;

    await _localDb.forEach((id, data) async {
      final imagePathRaw = data['imagePath'];
      final currentPath = imagePathRaw is String && imagePathRaw.isNotEmpty
          ? imagePathRaw
          : null;

      List<int>? bytes;
      final imageBytesRaw = data['imageBytes'];
      if (imageBytesRaw is Uint8List) {
        bytes = imageBytesRaw;
      } else if (imageBytesRaw is List) {
        try {
          bytes = imageBytesRaw.cast<int>();
        } catch (_) {
          bytes = null;
        }
      }

      var nextPath = currentPath;
      var changed = false;

      if (bytes != null && bytes.isNotEmpty) {
        nextPath ??= await saveBytes(bytes);
        changed = true;
      }

      if (nextPath != null) {
        final file = File(nextPath);
        if (!await file.exists()) {
          nextPath = null;
          changed = true;
        }
      }

      if (!changed) {
        return;
      }

      final updatedData = Map<String, Object?>.from(data);
      updatedData['imagePath'] = nextPath;
      updatedData['imageBytes'] = null;
      await _localDb.put(id, updatedData);
      migrated++;
    });

    return migrated;
  }

  @override
  Future<List<WordCard>> fetchAll({bool includeDeleted = false}) async {
    final cards = <WordCard>[];
    await _localDb.forEach((_, data) {
      if (!includeDeleted && data['isDeleted'] == true) {
        return;
      }
      cards.add(WordCard.fromMap(data));
    });
    return cards;
  }

  @override
  Future<List<WordCard>> fetchDue(DateTime day) async {
    final all = await fetchAll();
    return all
        .where((card) => _scheduleService.isDueOnOrBefore(card, day))
        .toList();
  }

  @override
  Future<void> add(WordCard card) async {
    await _localDb.put(card.id, card.toMap());
  }

  @override
  Future<void> update(WordCard card) async {
    await _localDb.put(card.id, card.toMap());
  }

  @override
  Future<void> delete(String id) async {
    await _localDb.delete(id);
  }
}
