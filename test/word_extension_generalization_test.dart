import 'package:flutter_test/flutter_test.dart';
import 'package:yunxu_learning_english/domain/models/builtin_word_entry.dart';
import 'package:yunxu_learning_english/domain/models/word_card.dart';
import 'package:yunxu_learning_english/domain/services/word_extension_service.dart';

void main() {
  test('長篇說明列舉蘋果不代表 protogyny 與 apple 同義', () async {
    final service = _service([
      _entry(
        'apple',
        '蘋果',
        [PartOfSpeech.noun],
        examples: ['I ate an apple. 我吃了一顆蘋果。'],
      ),
      _entry(
        'protogyny',
        '雌雄同體系統中的狀態，蘋果、梨、玄參和幾類動物中存在這種情況',
        [PartOfSpeech.noun],
        examples: ['Some plants show protogyny. 有些植物具有雌先熟的現象。'],
      ),
    ]);
    final result = await service.recommend(
      _card('apple', '蘋果', PartOfSpeech.noun),
    );
    expect(
      result.related.map((item) => item.entry.word),
      isNot(contains('protogyny')),
    );
  });

  test('律師說明中的城市是語境，不能讓 city 推薦 solicitor', () async {
    final service = _service([
      _entry(
        'city',
        '城市',
        [PartOfSpeech.noun],
        examples: ['The city is large. 這座城市很大。'],
      ),
      _entry(
        'solicitor',
        '在部分地區，城市、城鎮或其他司法管轄區的首席法律官。',
        [PartOfSpeech.noun],
        examples: ['She consulted a solicitor. 她諮詢了一位律師。'],
      ),
    ]);
    final result = await service.recommend(
      _card('city', '城市', PartOfSpeech.noun),
    );
    expect(
      result.related.map((item) => item.entry.word),
      isNot(contains('solicitor')),
    );
  });

  test('逗號列舉釋義需要例句佐證，迅速不能僅靠列舉推薦 elegantly', () async {
    final service = _service([
      _entry(
        'quickly',
        '迅速',
        [PartOfSpeech.adverb],
        examples: ['He left quickly. 他迅速離開了。'],
      ),
      _entry(
        'elegantly',
        '優雅、順利、迅速；具有風格。',
        [PartOfSpeech.adverb],
        examples: ['She danced elegantly. 她優雅地跳舞。'],
      ),
    ]);
    final result = await service.recommend(
      _card('quickly', '迅速', PartOfSpeech.adverb),
    );
    expect(
      result.related.map((item) => item.entry.word),
      isNot(contains('elegantly')),
    );
  });

  test('完整短釋義列舉若有對應例句佐證，仍可推薦該義項', () async {
    final service = _service([
      _entry(
        'peaceful',
        '平靜的',
        [PartOfSpeech.adjective],
        examples: ['The village is peaceful. 這個村莊很平靜。'],
      ),
      _entry(
        'calm',
        '平靜、安詳',
        [PartOfSpeech.adjective],
        examples: ['She looked calm. 她顯得很平靜。'],
      ),
    ]);
    final result = await service.recommend(
      _card('peaceful', '平靜的', PartOfSpeech.adjective),
    );
    expect(result.related.map((item) => item.entry.word), ['calm']);
    expect(result.related.single.explanation, contains('字庫釋義'));
  });

  test('相同查證警語不是詞義，不能讓 took 推薦 eaver', () async {
    const caution = '疑似非標準或極罕見拼寫；正式使用前應再查證';
    final service = _service([
      _entry('took', caution, [PartOfSpeech.noun]),
      _entry('eaver', caution, [PartOfSpeech.noun]),
    ]);
    final result = await service.recommend(
      _card('took', caution, PartOfSpeech.noun),
    );
    expect(
      result.related.map((item) => item.entry.word),
      isNot(contains('eaver')),
    );
  });

  // These fixtures intentionally disable curated relations. Success must come
  // from a general rule, rather than the original teaching-content whitelist.
  for (final item in [
    ('unfair', '不公平的', 'fair', '公平的'),
    ('non-verbal', '非語言的', 'verbal', '語言的'),
    ('impossible', '不可能的', 'possible', '可能的'),
    ('illegal', '不合法的', 'legal', '合法的'),
    ('irregular', '不規則的', 'regular', '規則的'),
    ('dishonest', '不誠實的', 'honest', '誠實的'),
    ('inaccurate', '不精確的', 'accurate', '精確的'),
  ]) {
    test('未預設的前綴字 ${item.$1} 有語義佐證，雙向找到 ${item.$3}', () async {
      final service = _service([
        _entry(item.$1, item.$2, [PartOfSpeech.adjective]),
        _entry(item.$3, item.$4, [PartOfSpeech.adjective]),
      ]);
      final forward = await service.recommend(
        _card(item.$1, item.$2, PartOfSpeech.adjective),
      );
      expect(forward.related.map((item) => item.entry.word), [item.$3]);
      expect(forward.related.single.explanation, contains('否定前綴'));
      expect(forward.confused, isEmpty);
      final reverse = await service.recommend(
        _card(item.$3, item.$4, PartOfSpeech.adjective),
      );
      expect(reverse.related.map((item) => item.entry.word), [item.$1]);
    });
  }

  for (final item in [
    ('snowman', '雪人', 'snow', '雪', 'man', '男人'),
    ('bookcase', '書櫃', 'book', '書', 'case', '箱子'),
    ('raincoat', '雨衣', 'rain', '雨', 'coat', '外套'),
  ]) {
    test('未預設的複合字 ${item.$1} 只推薦釋義有佐證的 ${item.$3}', () async {
      final service = _service([
        _entry(item.$1, item.$2, [PartOfSpeech.noun]),
        _entry(item.$3, item.$4, [PartOfSpeech.noun]),
        _entry(item.$5, item.$6, [PartOfSpeech.noun]),
      ]);
      final result = await service.recommend(
        _card(item.$1, item.$2, PartOfSpeech.noun),
      );
      expect(result.related.map((item) => item.entry.word), [item.$3]);
      expect(
        result.related.single.explanation,
        contains('${item.$3} + ${item.$5}'),
      );
      expect(result.confused, isEmpty);
    });
  }

  test('不透明複合字 pineapple 不能依拼字連到 pine 或 apple', () async {
    final service = _service([
      _entry('pineapple', '鳳梨', [PartOfSpeech.noun]),
      _entry('pine', '松樹', [PartOfSpeech.noun]),
      _entry('apple', '蘋果', [PartOfSpeech.noun]),
    ]);
    final result = await service.recommend(
      _card('pineapple', '鳳梨', PartOfSpeech.noun),
    );
    expect(result.related, isEmpty);
    expect(result.confused, isEmpty);
  });

  test('同拼字不同目前義項的複合字不能沿用字典原義推薦', () async {
    final service = _service([
      _entry('bookcase', '書櫃', [PartOfSpeech.noun]),
      _entry('book', '書', [PartOfSpeech.noun]),
      _entry('case', '箱子', [PartOfSpeech.noun]),
    ]);
    final result = await service.recommend(
      _card('bookcase', '自訂品牌名稱', PartOfSpeech.noun),
    );
    expect(result.related, isEmpty);
    expect(result.usages, isEmpty);
  });

  for (final item in [
    ('mice', 'mouse 的複數；老鼠', 'mouse', '老鼠', PartOfSpeech.noun),
    ('went', 'go 的過去式；前往', 'go', '前往', PartOfSpeech.verb),
    ('written', 'write 的過去分詞；書寫', 'write', '書寫', PartOfSpeech.verb),
  ]) {
    test('未預設的不規則形 ${item.$1} 依明載定義雙向找到 ${item.$3}', () async {
      final service = _service([
        _entry(item.$1, item.$2, [item.$5]),
        _entry(item.$3, item.$4, [item.$5]),
      ]);
      final result = await service.recommend(_card(item.$1, item.$2, item.$5));
      expect(result.related.map((item) => item.entry.word), [item.$3]);
      expect(result.related.single.explanation, contains('字典明確標示'));
      final reverse = await service.recommend(_card(item.$3, item.$4, item.$5));
      expect(reverse.related.map((item) => item.entry.word), [item.$1]);
    });
  }

  test('多義多詞性 saw 的鋸子義項不能推薦動詞 see', () async {
    final service = _service([
      _entry('saw', '看見（see 的過去式）；鋸子', [PartOfSpeech.verb, PartOfSpeech.noun]),
      _entry('see', '看見', [PartOfSpeech.verb]),
    ]);
    final noun = await service.recommend(_card('saw', '鋸子', PartOfSpeech.noun));
    expect(noun.related.map((item) => item.entry.word), isNot(contains('see')));
    final verb = await service.recommend(
      _card('saw', '看見（see 的過去式）', PartOfSpeech.verb),
    );
    expect(verb.related.map((item) => item.entry.word), contains('see'));
  });

  test('同詞性多義字的非關聯義項不應沿用另一義項的變化形關係', () async {
    final service = _service([
      _entry('saw', '看見（see 的過去式）；鋸切', [PartOfSpeech.verb]),
      _entry('see', '看見', [PartOfSpeech.verb]),
    ]);
    final result = await service.recommend(
      _card('saw', '鋸切', PartOfSpeech.verb),
    );
    expect(
      result.related.map((item) => item.entry.word),
      isNot(contains('see')),
    );
  });

  test('多義字 content 只在滿意義項使用否定關係，不牽連內容義項', () async {
    final service = _service([
      _entry('content', '滿意；內容', [PartOfSpeech.adjective, PartOfSpeech.noun]),
      _entry('discontent', '不滿意的', [PartOfSpeech.adjective]),
    ]);
    final noun = await service.recommend(
      _card('content', '內容', PartOfSpeech.noun),
    );
    expect(noun.related, isEmpty);
    final otherAdjectiveSense = await service.recommend(
      _card('content', '內容', PartOfSpeech.adjective),
    );
    expect(otherAdjectiveSense.related, isEmpty);
    final adjective = await service.recommend(
      _card('content', '滿意', PartOfSpeech.adjective),
    );
    expect(adjective.related.map((item) => item.entry.word), ['discontent']);
  });

  test('不在字庫的自訂字可利用釋義及詞性，但不混入另一詞性的字', () async {
    final service = _service([
      _entry('peaceful', '平靜的。', [PartOfSpeech.adjective]),
      _entry('tranquility', '平靜', [PartOfSpeech.noun]),
    ]);
    final result = await service.recommend(
      _card('my-special-term', '平靜', PartOfSpeech.adjective),
    );
    expect(result.related.map((item) => item.entry.word), ['peaceful']);
    expect(result.related.single.explanation, contains('字庫釋義'));
    expect(result.usages, isEmpty);
  });

  test('字典將 kept 錯標為名詞時，不能當成動詞變化形推薦 keep', () async {
    final service = _service([
      _entry('kept', 'keep 的過去式', [PartOfSpeech.noun]),
      _entry('keep', '保留', [PartOfSpeech.verb]),
    ]);
    final result = await service.recommend(
      _card('kept', 'keep 的過去式', PartOfSpeech.noun),
    );
    expect(result.related, isEmpty);
  });

  test('單義明確變化形也不能沿用目前卡片的錯誤詞性', () async {
    final service = _service([
      _entry('wrote', 'write 的過去式', [PartOfSpeech.verb]),
      _entry('write', '書寫', [PartOfSpeech.verb]),
    ]);
    final result = await service.recommend(
      _card('wrote', 'write 的過去式', PartOfSpeech.noun),
    );
    expect(result.related, isEmpty);
  });
}

WordExtensionService _service(List<BuiltinWordEntry> entries) =>
    WordExtensionService(loadEntries: () async => entries, relations: const []);

BuiltinWordEntry _entry(
  String word,
  String meaning,
  List<PartOfSpeech> parts, {
  List<String>? examples,
}) => BuiltinWordEntry(
  word: word,
  meaning: meaning,
  partsOfSpeech: parts,
  sentences: examples ?? ['The example uses $word correctly. 這個例句正確使用這個詞。'],
  sourcePage: 0,
  schoolLevels: const [],
  examTags: const [],
  audienceTags: const [],
  sourceTags: const [BuiltinSourceTag.twCeec],
  difficultyLevel: 2,
);

WordCard _card(String word, String meaning, PartOfSpeech part) {
  final now = DateTime(2026);
  return WordCard(
    id: word,
    word: word,
    meaning: meaning,
    partsOfSpeech: [part],
    sentences: const [],
    origin: WordOrigin.manual,
    createdAt: now,
    updatedAt: now,
    reviewSchedule: const [1, 2, 3],
    nextReviewIndex: 0,
    nextReviewDate: now,
    history: const [],
    isDeleted: false,
  );
}
