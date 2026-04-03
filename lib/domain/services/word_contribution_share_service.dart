import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/word_card.dart';

class WordContributionShareResult {
  const WordContributionShareResult({
    required this.filePath,
    required this.sharedCount,
    required this.shareResult,
  });

  final String filePath;
  final int sharedCount;
  final ShareResult shareResult;

  String get fileName => path.basename(filePath);
}

class WordContributionShareService {
  static const JsonEncoder _encoder = JsonEncoder.withIndent('  ');

  bool get isSupported => !Platform.isLinux;

  Future<WordContributionShareResult> shareWords({
    required List<WordCard> words,
    Rect? sharePositionOrigin,
  }) async {
    if (words.isEmpty) {
      throw ArgumentError('words cannot be empty');
    }
    if (!isSupported) {
      throw UnsupportedError('目前平台不支援 JSON 檔案分享');
    }

    final packageInfo = await PackageInfo.fromPlatform();
    final file = await _writeExportFile(words, packageInfo);
    final shareResult = await SharePlus.instance.share(
      ShareParams(
        title: '分享新增單字 JSON',
        subject: 'Yunxu Learning English 使用者新增單字',
        text: '這是我從 App 匯出的新增單字 JSON 檔案。',
        files: [XFile(file.path, mimeType: 'application/json')],
        sharePositionOrigin: sharePositionOrigin,
      ),
    );

    return WordContributionShareResult(
      filePath: file.path,
      sharedCount: words.length,
      shareResult: shareResult,
    );
  }

  Future<File> _writeExportFile(
    List<WordCard> words,
    PackageInfo packageInfo,
  ) async {
    final tempDir = await getTemporaryDirectory();
    final fileName = _buildFileName();
    final file = File(path.join(tempDir.path, fileName));
    final payload = _buildPayload(words, packageInfo);
    await file.writeAsString(_encoder.convert(payload));
    return file;
  }

  Map<String, Object?> _buildPayload(
    List<WordCard> words,
    PackageInfo packageInfo,
  ) {
    final sortedWords = List<WordCard>.from(words)
      ..sort((a, b) {
        final createdCompare = a.createdAt.compareTo(b.createdAt);
        if (createdCompare != 0) {
          return createdCompare;
        }
        return a.word.toLowerCase().compareTo(b.word.toLowerCase());
      });

    return {
      'schemaVersion': 1,
      'app': {
        'name': packageInfo.appName,
        'packageName': packageInfo.packageName,
        'version': packageInfo.version,
        'buildNumber': packageInfo.buildNumber,
      },
      'platform': Platform.operatingSystem,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'wordCount': sortedWords.length,
      'words': sortedWords.map(_wordToMap).toList(growable: false),
    };
  }

  Map<String, Object?> _wordToMap(WordCard card) {
    final cleanedSentences = card.sentences
        .map((sentence) => sentence.trim())
        .where((sentence) => sentence.isNotEmpty)
        .toList(growable: false);

    return {
      'id': card.id,
      'origin': card.origin.name,
      'word': card.word.trim(),
      'meaning': card.meaning.trim(),
      'partOfSpeech': card.partOfSpeech.name,
      'sentences': cleanedSentences,
      'customTags': WordCard.normalizeCustomTags(card.customTags),
      'createdAt': card.createdAt.toUtc().toIso8601String(),
      'updatedAt': card.updatedAt.toUtc().toIso8601String(),
      'hasImage':
          card.imagePath != null ||
          (card.imageBytes != null && card.imageBytes!.isNotEmpty),
    };
  }

  String _buildFileName() {
    final exportedAt = DateTime.now().toUtc();
    final safeTimestamp = exportedAt
        .toIso8601String()
        .replaceAll(':', '')
        .replaceAll('.', '_');
    return 'yunxu_user_words_$safeTimestamp.json';
  }
}
