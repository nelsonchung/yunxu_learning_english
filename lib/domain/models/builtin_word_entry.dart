import 'word_card.dart';

enum BuiltinSchoolLevel { elementary, juniorHigh, seniorHigh, college }

extension BuiltinSchoolLevelLabel on BuiltinSchoolLevel {
  String get label {
    switch (this) {
      case BuiltinSchoolLevel.elementary:
        return '國小';
      case BuiltinSchoolLevel.juniorHigh:
        return '國中';
      case BuiltinSchoolLevel.seniorHigh:
        return '高中';
      case BuiltinSchoolLevel.college:
        return '大學';
    }
  }
}

enum BuiltinExamTag { toeic }

extension BuiltinExamTagLabel on BuiltinExamTag {
  String get label {
    switch (this) {
      case BuiltinExamTag.toeic:
        return 'TOEIC';
    }
  }
}

enum BuiltinAudienceTag { general }

extension BuiltinAudienceTagLabel on BuiltinAudienceTag {
  String get label {
    switch (this) {
      case BuiltinAudienceTag.general:
        return '一般';
    }
  }
}

enum BuiltinSourceTag { twCeec, toeicSignals, collegeSignals, pdfExamBook }

extension BuiltinSourceTagLabel on BuiltinSourceTag {
  String get label {
    switch (this) {
      case BuiltinSourceTag.twCeec:
        return '高中參考詞彙';
      case BuiltinSourceTag.toeicSignals:
        return '職場情境';
      case BuiltinSourceTag.collegeSignals:
        return '學術情境';
      case BuiltinSourceTag.pdfExamBook:
        return '考試字書';
    }
  }
}

class BuiltinWordEntry {
  const BuiltinWordEntry({
    required this.word,
    required this.meaning,
    required this.partOfSpeech,
    required this.sentences,
    required this.sourcePage,
    required this.schoolLevels,
    required this.examTags,
    required this.audienceTags,
    required this.sourceTags,
    this.difficultyLevel,
    this.memoryHint = '',
  });

  final String word;
  final String meaning;
  final String memoryHint;
  final PartOfSpeech partOfSpeech;
  final List<String> sentences;
  final int sourcePage;
  final List<BuiltinSchoolLevel> schoolLevels;
  final List<BuiltinExamTag> examTags;
  final List<BuiltinAudienceTag> audienceTags;
  final List<BuiltinSourceTag> sourceTags;
  final int? difficultyLevel;

  List<String> get audienceLabels => [
    ...schoolLevels.map((item) => item.label),
    ...examTags.map((item) => item.label),
    ...audienceTags.map((item) => item.label),
  ];

  factory BuiltinWordEntry.fromMap(Map<String, dynamic> map) {
    final parsedSentences = (map['sentences'] as List<dynamic>? ?? const [])
        .whereType<String>()
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);

    final rawSourcePage = map['sourcePage'];
    final parsedSourcePage = rawSourcePage is int ? rawSourcePage : 0;
    final parsedSchoolLevels = _parseEnumList(
      raw: map['schoolLevels'],
      values: BuiltinSchoolLevel.values,
    );
    final parsedExamTags = _parseEnumList(
      raw: map['examTags'],
      values: BuiltinExamTag.values,
    );
    final parsedAudienceTags = _parseEnumList(
      raw: map['audienceTags'],
      values: BuiltinAudienceTag.values,
    );
    final parsedSourceTags = _parseEnumList(
      raw: map['sourceTags'],
      values: BuiltinSourceTag.values,
    );
    final rawDifficultyLevel = map['difficultyLevel'];
    final parsedDifficultyLevel = rawDifficultyLevel is int
        ? rawDifficultyLevel
        : null;

    return BuiltinWordEntry(
      word: _readTrimmedString(map['word']),
      meaning: _readTrimmedString(
        map['meaning'],
        allowList: true,
        separator: '；',
      ),
      memoryHint: _readTrimmedString(map['memoryHint']),
      partOfSpeech: _parsePartOfSpeech(_readTrimmedString(map['partOfSpeech'])),
      sentences: parsedSentences,
      sourcePage: parsedSourcePage,
      schoolLevels: parsedSchoolLevels,
      examTags: parsedExamTags,
      audienceTags: parsedAudienceTags,
      sourceTags: parsedSourceTags,
      difficultyLevel: parsedDifficultyLevel,
    );
  }

  static PartOfSpeech _parsePartOfSpeech(String raw) {
    final normalized = raw.trim();
    for (final value in PartOfSpeech.values) {
      if (value.name == normalized) {
        return value;
      }
    }
    return PartOfSpeech.other;
  }

  static String _readTrimmedString(
    Object? raw, {
    bool allowList = false,
    String separator = ' ',
  }) {
    if (raw is String) {
      return raw.trim();
    }
    if (allowList && raw is List) {
      return raw
          .whereType<String>()
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .join(separator);
    }
    return '';
  }

  static List<T> _parseEnumList<T extends Enum>({
    required Object? raw,
    required List<T> values,
  }) {
    if (raw is! List) {
      return const [];
    }

    final parsed = <T>[];
    for (final item in raw) {
      if (item is! String) {
        continue;
      }
      final normalized = item.trim();
      for (final value in values) {
        if (value.name == normalized) {
          parsed.add(value);
          break;
        }
      }
    }

    return parsed.toSet().toList(growable: false);
  }
}
