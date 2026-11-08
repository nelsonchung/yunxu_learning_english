import 'package:flutter_test/flutter_test.dart';
import 'package:yunxu_learning_english/data/repositories/builtin_word_bank_repository.dart';
import 'package:yunxu_learning_english/domain/models/builtin_word_entry.dart';
import 'package:yunxu_learning_english/domain/models/word_card.dart';
import 'package:yunxu_learning_english/domain/services/word_extension_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('實際26個字庫分片可用於通用推薦，且整個服務只建立一次索引', () async {
    final repository = BuiltinWordBankRepository();
    var loads = 0;
    final entries = await repository.fetchAll();
    final byWord = {
      for (final entry in entries) entry.word.toLowerCase(): entry,
    };
    final service = WordExtensionService(
      loadEntries: () async {
        loads++;
        return entries;
      },
    );
    for (final pair in [
      ('fly', 'flown'),
      ('forget', 'forgot'),
      ('decision', 'decide'),
      ('windmill', 'wind'),
      ('nonsignificant', 'significant'),
    ]) {
      final result = await service.recommend(_card(byWord[pair.$1]!));
      expect(
        result.related.map((item) => item.entry.word.toLowerCase()),
        contains(pair.$2),
        reason: '${pair.$1} → ${pair.$2}',
      );
      for (final item in [...result.related, ...result.confused]) {
        expect(byWord.containsKey(item.entry.word.toLowerCase()), isTrue);
        expect(item.examples, isNotEmpty);
      }
    }
    final beautiful = await service.recommend(_card(byWord['beautiful']!));
    expect(beautiful.usages, isNotEmpty);
    final custom = await service.recommend(
      _card(
        byWord['beautiful']!,
      ).copyWith(word: 'my-custom-term', sentences: const []),
    );
    expect(custom.related, isNotEmpty);
    final missing = await service.recommend(
      _card(
        byWord['beautiful']!,
      ).copyWith(word: 'zz-no-evidence', meaning: '', sentences: const []),
    );
    expect(missing.isEmpty, isTrue);
    expect(loads, 1);
  }, timeout: const Timeout(Duration(minutes: 2)));
}

WordCard _card(BuiltinWordEntry entry) {
  final now = DateTime(2026);
  return WordCard(
    id: entry.word,
    word: entry.word,
    meaning: entry.meaning,
    partsOfSpeech: entry.partsOfSpeech,
    sentences: const [],
    origin: WordOrigin.builtinWordBank,
    createdAt: now,
    updatedAt: now,
    reviewSchedule: const [1, 2, 3],
    nextReviewIndex: 0,
    nextReviewDate: now,
    history: const [],
    isDeleted: false,
  );
}
