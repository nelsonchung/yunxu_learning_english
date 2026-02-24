import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../../domain/models/word_card.dart';
import '../../domain/services/review_schedule_service.dart';
import '../sources/word_local_db.dart';
import 'word_repository.dart';

class LocalWordRepository implements WordRepository {
  static const String _imagesDirectory = 'images';

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
      final currentPath =
          imagePathRaw is String && imagePathRaw.trim().isNotEmpty
          ? imagePathRaw
          : null;
      var nextPath = await _normalizeStoredImagePath(currentPath);

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

      var changed = nextPath != currentPath;

      if (bytes != null && bytes.isNotEmpty) {
        if (nextPath != null) {
          final resolvedExisting = await _resolveAbsoluteImagePath(nextPath);
          if (resolvedExisting == null) {
            final savedPath = await saveBytes(bytes);
            nextPath = await _normalizeStoredImagePath(savedPath);
          } else {
            nextPath = await _normalizeStoredImagePath(resolvedExisting);
          }
        } else {
          final savedPath = await saveBytes(bytes);
          nextPath = await _normalizeStoredImagePath(savedPath);
        }
        changed = true;
      }

      if (nextPath == null &&
          currentPath != null &&
          path.isAbsolute(currentPath)) {
        // Keep a relative candidate instead of dropping image metadata.
        nextPath = path.join(_imagesDirectory, path.basename(currentPath));
        changed = true;
      }

      if (nextPath != null) {
        final resolved = await _resolveAbsoluteImagePath(nextPath);
        if (resolved != null) {
          final rebased = await _normalizeStoredImagePath(resolved);
          if (rebased != null && rebased != nextPath) {
            nextPath = rebased;
            changed = true;
          }
        }
      }

      if (!changed) {
        return;
      }

      final updatedData = Map<String, Object?>.from(data);
      updatedData['imagePath'] = nextPath;
      if (bytes != null && bytes.isNotEmpty) {
        updatedData['imageBytes'] = null;
      }
      await _localDb.put(id, updatedData);
      migrated++;
    });

    return migrated;
  }

  @override
  Future<List<WordCard>> fetchAll({bool includeDeleted = false}) async {
    final cards = <WordCard>[];
    await _localDb.forEach((id, data) async {
      if (!includeDeleted && data['isDeleted'] == true) {
        return;
      }

      final imagePathRaw = data['imagePath'];
      final storedPath =
          imagePathRaw is String && imagePathRaw.trim().isNotEmpty
          ? imagePathRaw
          : null;
      final normalizedStoredPath = await _normalizeStoredImagePath(storedPath);
      final resolvedAbsolutePath = await _resolveAbsoluteImagePath(
        normalizedStoredPath,
      );

      final cardMap = Map<String, Object?>.from(data);
      cardMap['imagePath'] = resolvedAbsolutePath;
      cards.add(WordCard.fromMap(cardMap));

      if (normalizedStoredPath != storedPath) {
        final updatedData = Map<String, Object?>.from(data);
        updatedData['imagePath'] = normalizedStoredPath;
        await _localDb.put(id, updatedData);
      }
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
    await _localDb.put(card.id, await _toStoredMap(card));
  }

  @override
  Future<void> update(WordCard card) async {
    await _localDb.put(card.id, await _toStoredMap(card));
  }

  @override
  Future<void> delete(String id) async {
    await _localDb.delete(id);
  }

  Future<Map<String, Object?>> _toStoredMap(WordCard card) async {
    final data = Map<String, Object?>.from(card.toMap());
    data['imagePath'] = await _normalizeStoredImagePath(card.imagePath);
    return data;
  }

  Future<String?> _normalizeStoredImagePath(String? rawPath) async {
    if (rawPath == null) {
      return null;
    }

    final value = rawPath.trim();
    if (value.isEmpty) {
      return null;
    }

    if (!path.isAbsolute(value)) {
      final normalized = path.normalize(value);
      if (normalized.isEmpty || normalized == '.') {
        return null;
      }
      if (normalized == _imagesDirectory ||
          normalized.startsWith('../') ||
          normalized == '..') {
        return path.join(_imagesDirectory, path.basename(normalized));
      }
      if (path.dirname(normalized) == '.') {
        return path.join(_imagesDirectory, path.basename(normalized));
      }
      return normalized;
    }

    final docsDir = await getApplicationDocumentsDirectory();
    final docsPath = path.normalize(docsDir.path);
    final normalizedAbsolute = path.normalize(value);
    if (path.isWithin(docsPath, normalizedAbsolute)) {
      final relative = path.normalize(
        path.relative(normalizedAbsolute, from: docsPath),
      );
      if (relative.isEmpty || relative == '.') {
        return null;
      }
      if (path.dirname(relative) == '.') {
        return path.join(_imagesDirectory, path.basename(relative));
      }
      return relative;
    }

    return path.join(_imagesDirectory, path.basename(normalizedAbsolute));
  }

  Future<String?> _resolveAbsoluteImagePath(String? storedPath) async {
    if (storedPath == null || storedPath.trim().isEmpty) {
      return null;
    }

    final docsDir = await getApplicationDocumentsDirectory();
    if (path.isAbsolute(storedPath)) {
      final directFile = File(storedPath);
      if (await directFile.exists()) {
        return directFile.path;
      }
      final fallback = File(
        path.join(docsDir.path, _imagesDirectory, path.basename(storedPath)),
      );
      if (await fallback.exists()) {
        return fallback.path;
      }
      return null;
    }

    final normalizedRelative = path.normalize(storedPath);
    final directFile = File(path.join(docsDir.path, normalizedRelative));
    if (await directFile.exists()) {
      return directFile.path;
    }

    final fallback = File(
      path.join(
        docsDir.path,
        _imagesDirectory,
        path.basename(normalizedRelative),
      ),
    );
    if (await fallback.exists()) {
      return fallback.path;
    }

    return null;
  }
}
