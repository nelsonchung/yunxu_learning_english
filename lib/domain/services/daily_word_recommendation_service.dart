import '../models/app_settings.dart';
import '../models/builtin_word_entry.dart';
import '../models/word_card.dart';

class DailyWordRecommendationService {
  List<BuiltinWordEntry> recommend({
    required List<BuiltinWordEntry> entries,
    required List<WordCard> existingWords,
    required AppSettings settings,
    required int dueTodayCount,
    required DateTime now,
  }) {
    if (!settings.dailyNewWordsEnabled) {
      return const [];
    }
    if (settings.dailyNewWordsCount <= 0) {
      return const [];
    }
    if (dueTodayCount > settings.dailyNewWordsReviewThreshold) {
      return const [];
    }

    final existingKeys = existingWords
        .map((card) => _normalizeKey(card.word))
        .where((key) => key.isNotEmpty)
        .toSet();
    final existingRoots = existingWords
        .map((card) => _stemWord(card.word))
        .where((root) => root.length >= 4)
        .toSet();
    final targetDifficulty = _resolveTargetDifficulty(
      entries: entries,
      existingWords: existingWords,
    );
    final dayKey = '${now.year}-${now.month}-${now.day}';

    final scored =
        entries
            .where((entry) => _isEligible(entry, existingKeys, existingRoots))
            .map(
              (entry) => _ScoredEntry(
                entry: entry,
                score: _buildScore(
                  entry: entry,
                  targetDifficulty: targetDifficulty,
                ),
                rotationKey: _stableHash('$dayKey:${entry.word.toLowerCase()}'),
              ),
            )
            .toList(growable: false)
          ..sort((a, b) {
            final byScore = b.score.compareTo(a.score);
            if (byScore != 0) {
              return byScore;
            }
            final byRotation = a.rotationKey.compareTo(b.rotationKey);
            if (byRotation != 0) {
              return byRotation;
            }
            return a.entry.word.compareTo(b.entry.word);
          });

    final selected = <BuiltinWordEntry>[];
    final selectedRoots = <String>{};
    final selectedParts = <PartOfSpeech, int>{};

    for (final item in scored) {
      if (selected.length >= settings.dailyNewWordsCount) {
        break;
      }

      final root = _stemWord(item.entry.word);
      if (root.length >= 4 && selectedRoots.contains(root)) {
        continue;
      }

      final partCount = selectedParts[item.entry.partOfSpeech] ?? 0;
      if (partCount >= 1) {
        continue;
      }

      selected.add(item.entry);
      if (root.length >= 4) {
        selectedRoots.add(root);
      }
      selectedParts[item.entry.partOfSpeech] = partCount + 1;
    }

    if (selected.length >= settings.dailyNewWordsCount) {
      return selected;
    }

    for (final item in scored) {
      if (selected.length >= settings.dailyNewWordsCount) {
        break;
      }
      if (selected.any((entry) => entry.word == item.entry.word)) {
        continue;
      }

      final root = _stemWord(item.entry.word);
      if (root.length >= 4 && selectedRoots.contains(root)) {
        continue;
      }

      selected.add(item.entry);
      if (root.length >= 4) {
        selectedRoots.add(root);
      }
    }

    return selected;
  }

  bool _isEligible(
    BuiltinWordEntry entry,
    Set<String> existingKeys,
    Set<String> existingRoots,
  ) {
    final normalizedWord = _normalizeKey(entry.word);
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

    final root = _stemWord(entry.word);
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

  int _resolveTargetDifficulty({
    required List<BuiltinWordEntry> entries,
    required List<WordCard> existingWords,
  }) {
    final difficultyByWord = <String, int>{};
    for (final entry in entries) {
      final difficultyLevel = entry.difficultyLevel;
      if (difficultyLevel == null) {
        continue;
      }
      difficultyByWord[_normalizeKey(entry.word)] = difficultyLevel;
    }

    final sortedExisting = List<WordCard>.from(existingWords)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final samples = <int>[];
    for (final card in sortedExisting) {
      final difficulty = difficultyByWord[_normalizeKey(card.word)];
      if (difficulty == null) {
        continue;
      }
      samples.add(difficulty);
      if (samples.length >= 12) {
        break;
      }
    }

    if (samples.isEmpty) {
      return 2;
    }

    final average =
        samples.reduce((sum, value) => sum + value) / samples.length;
    final target = (average + 0.6).round();
    if (target < 1) {
      return 1;
    }
    if (target > 6) {
      return 6;
    }
    return target;
  }

  int _buildScore({
    required BuiltinWordEntry entry,
    required int targetDifficulty,
  }) {
    final difficultyLevel = entry.difficultyLevel ?? targetDifficulty;
    final difficultyDistance = (difficultyLevel - targetDifficulty).abs();

    var score = 100 - (difficultyDistance * 12);
    if (difficultyDistance == 0) {
      score += 8;
    } else if (difficultyDistance == 1) {
      score += 4;
    }

    score += _metadataScore(entry);

    final wordLength = entry.word.trim().length;
    if (wordLength >= 4 && wordLength <= 10) {
      score += 4;
    } else if (wordLength >= 3 && wordLength <= 12) {
      score += 2;
    }

    return score;
  }

  int _metadataScore(BuiltinWordEntry entry) {
    var score = 0;
    if (entry.schoolLevels.isNotEmpty) {
      score += 14;
    }
    if (entry.examTags.isNotEmpty) {
      score += 10;
    }
    if (entry.audienceTags.isNotEmpty) {
      score += 6;
    }
    if (entry.sourceTags.contains(BuiltinSourceTag.twCeec)) {
      score += 12;
    }
    if (entry.sourceTags.contains(BuiltinSourceTag.pdfExamBook)) {
      score += 8;
    }
    if (entry.sourceTags.contains(BuiltinSourceTag.toeicSignals)) {
      score += 8;
    }
    if (entry.sourceTags.contains(BuiltinSourceTag.collegeSignals)) {
      score += 8;
    }
    return score;
  }

  bool _looksLikeSingleWord(String word) {
    return RegExp(r'^[A-Za-z]+$').hasMatch(word.trim());
  }

  bool _looksTooSimilar(String candidate, String existing) {
    if (candidate == existing) {
      return true;
    }
    if (candidate.length < 5 || existing.length < 5) {
      return false;
    }

    final lengthDelta = (candidate.length - existing.length).abs();
    if (lengthDelta > 3) {
      return false;
    }

    return candidate.startsWith(existing) || existing.startsWith(candidate);
  }

  String _normalizeKey(String word) {
    return word.trim().toLowerCase();
  }

  String _stemWord(String word) {
    var normalized = word.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
    if (normalized.length < 4) {
      return normalized;
    }

    const suffixes = <String>[
      'ingly',
      'edly',
      'ing',
      'ed',
      'ers',
      'er',
      'est',
      'ies',
      'es',
      's',
      'ly',
    ];

    for (final suffix in suffixes) {
      if (!normalized.endsWith(suffix)) {
        continue;
      }
      final candidateLength = normalized.length - suffix.length;
      if (candidateLength < 4) {
        continue;
      }
      if (suffix == 'ies') {
        return '${normalized.substring(0, candidateLength)}y';
      }
      return normalized.substring(0, candidateLength);
    }

    return normalized;
  }

  int _stableHash(String input) {
    var hash = 0x811C9DC5;
    for (final codeUnit in input.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 0x01000193) & 0x7FFFFFFF;
    }
    return hash;
  }
}

class _ScoredEntry {
  const _ScoredEntry({
    required this.entry,
    required this.score,
    required this.rotationKey,
  });

  final BuiltinWordEntry entry;
  final int score;
  final int rotationKey;
}
