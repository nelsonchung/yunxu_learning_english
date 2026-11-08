import 'package:flutter_test/flutter_test.dart';
import 'package:yunxu_learning_english/domain/models/builtin_word_entry.dart';
import 'package:yunxu_learning_english/domain/models/word_card.dart';
import 'package:yunxu_learning_english/domain/models/word_extension.dart';
import 'package:yunxu_learning_english/domain/services/word_extension_service.dart';

void main() {
  test('同釋義但無常用程度證據的候選不可用流暢例句湊結果', () async {
    final result = await _service([
      _entry('beautiful', '美麗的', common: true),
      _entry('fairlike', '美麗的'),
      _entry(
        'beauteous',
        '美麗的',
        difficulty: 6,
        sources: [BuiltinSourceTag.collegeSignals],
      ),
    ]).recommend(_card('beautiful', '美麗的'));
    expect(result.related, isEmpty);
    expect(result.usages, isNotEmpty);
  });

  test('常用候選留下，collegeSignals 的高難度同釋義候選排除', () async {
    final result = await _service([
      _entry('clever', '聰明的', common: true),
      _entry('smart', '聰明的', common: true),
      _entry(
        'witful',
        '聰明的',
        difficulty: 6,
        sources: [BuiltinSourceTag.collegeSignals],
      ),
    ]).recommend(_card('clever', '聰明的'));
    expect(result.related.map((item) => item.entry.word), ['smart']);
  });

  test('只有 general、職場或大學 signals 與低難度不足以當常用證據', () async {
    final result = await _service([
      _entry('quiet', '安靜的', common: true),
      _entry(
        'lown',
        '安靜的',
        difficulty: 2,
        sources: [BuiltinSourceTag.collegeSignals],
      ),
      _entry(
        'indisturbable',
        '安靜的',
        difficulty: 2,
        sources: [BuiltinSourceTag.toeicSignals],
      ),
      _entry('hushing', '安靜的', difficulty: 2),
    ]).recommend(_card('quiet', '安靜的'));
    expect(result.related, isEmpty);
  });

  test('正式詞彙來源加國小國中級標籤可支持沒有 difficulty 的常用候選', () async {
    final result = await _service([
      _entry('huge', '巨大的', common: true),
      _entry(
        'big',
        '巨大的',
        levels: [BuiltinSchoolLevel.elementary],
        sources: [BuiltinSourceTag.twCeec],
      ),
    ]).recommend(_card('huge', '巨大的'));
    expect(result.related.map((item) => item.entry.word), ['big']);
  });

  test('只有低難度與國小國中標籤不足，無正式來源的 victuals 不可混入推薦', () async {
    final result = await _service([
      _entry('food', '食物', part: PartOfSpeech.noun, common: true),
      _entry(
        'victuals',
        '食物',
        part: PartOfSpeech.noun,
        difficulty: 2,
        levels: [BuiltinSchoolLevel.elementary, BuiltinSchoolLevel.juniorHigh],
      ),
      _entry(
        'meal',
        '食物',
        part: PartOfSpeech.noun,
        difficulty: 2,
        levels: [BuiltinSchoolLevel.elementary],
        sources: [BuiltinSourceTag.pdfExamBook],
      ),
    ]).recommend(_card('food', '食物', part: PartOfSpeech.noun));
    expect(result.related.map((item) => item.entry.word), ['meal']);
  });

  test('低難度與正式參考詞彙來源共同構成常用證據', () async {
    final result = await _service([
      _entry('clever', '聰明的', common: true),
      _entry('smart', '聰明的', difficulty: 3, sources: [BuiltinSourceTag.twCeec]),
      _entry(
        'intelligent',
        '聰明的',
        difficulty: 4,
        sources: [BuiltinSourceTag.pdfExamBook],
      ),
    ]).recommend(_card('clever', '聰明的'));
    expect(
      result.related.map((item) => item.entry.word),
      containsAll(['smart', 'intelligent']),
    );
  });

  test('沒有程度的人工審核關係仍可推薦 kitten，並不要求硬加難度標籤', () async {
    final result = await _service(
      [
        _entry('cat', '貓', part: PartOfSpeech.noun, common: true),
        _entry('kitten', '小貓', part: PartOfSpeech.noun),
      ],
      relations: [_catKitten],
    ).recommend(_card('cat', '貓', part: PartOfSpeech.noun));
    expect(result.related.map((item) => item.entry.word), ['kitten']);
  });

  test('人工關係也不可放行標明古語、罕見、方言或外語的目標', () async {
    for (final meaning in [
      '小貓；古語',
      '小貓；罕見用法',
      '小貓；方言',
      '小貓；西班牙語中使用的稱呼',
      '小貓；正式使用前應再查證',
    ]) {
      final result = await _service(
        [
          _entry('cat', '貓', part: PartOfSpeech.noun, common: true),
          _entry('kitten', meaning, part: PartOfSpeech.noun, common: true),
        ],
        relations: [_catKitten],
      ).recommend(_card('cat', '貓', part: PartOfSpeech.noun));
      expect(result.related, isEmpty, reason: meaning);
    }
  });

  test('不合法字目格式不可因同釋義與常用標籤混進候選', () async {
    final result = await _service([
      _entry('quiet', '安靜的', common: true),
      _entry('calm/quiet', '安靜的', common: true),
      _entry('quiet2', '安靜的', common: true),
    ]).recommend(_card('quiet', '安靜的'));
    expect(result.related, isEmpty);
  });

  test('人工關係必須符合目前卡片詞性，不能由同拼字的另一詞性放行', () async {
    final result = await _service(
      [
        _entry('cat', '貓', part: PartOfSpeech.noun, common: true),
        _entry('kitten', '小貓', part: PartOfSpeech.noun),
      ],
      relations: [_catKitten],
    ).recommend(_card('cat', '貓', part: PartOfSpeech.verb));
    expect(result.related, isEmpty);
  });

  test('人工關係的目標字庫詞性不符時也要略過', () async {
    final result = await _service(
      [
        _entry('cat', '貓', part: PartOfSpeech.noun, common: true),
        _entry('kitten', '小貓', part: PartOfSpeech.verb),
      ],
      relations: [_catKitten],
    ).recommend(_card('cat', '貓', part: PartOfSpeech.noun));
    expect(result.related, isEmpty);
  });

  test('反向查詢人工關係時對調兩端詞性限制，仍需符合來源與目標', () async {
    final service = _service(
      [
        _entry('cat', '貓', part: PartOfSpeech.noun, common: true),
        _entry('kitten', '小貓', part: PartOfSpeech.noun),
      ],
      relations: [_catKitten],
    );
    final valid = await service.recommend(
      _card('kitten', '小貓', part: PartOfSpeech.noun),
    );
    expect(valid.related.map((item) => item.entry.word), ['cat']);
    final wrongSource = await service.recommend(
      _card('kitten', '小貓', part: PartOfSpeech.verb),
    );
    expect(wrongSource.related, isEmpty);
    final wrongTarget = await _service(
      [
        _entry('cat', '貓', part: PartOfSpeech.verb, common: true),
        _entry('kitten', '小貓', part: PartOfSpeech.noun),
      ],
      relations: [_catKitten],
    ).recommend(_card('kitten', '小貓', part: PartOfSpeech.noun));
    expect(wrongTarget.related, isEmpty);
  });

  test('字庫與義項不符的人工關係仍不得推薦', () async {
    final result = await _service(
      [
        _entry('cat', '貓', part: PartOfSpeech.noun, common: true),
        _entry('kitten', '機器零件', part: PartOfSpeech.noun),
      ],
      relations: [_catKitten],
    ).recommend(_card('cat', '貓', part: PartOfSpeech.noun));
    expect(result.related, isEmpty);
  });

  test('人工關係沒有可用雙語例句也不得推薦', () async {
    final result = await _service(
      [
        _entry('cat', '貓', part: PartOfSpeech.noun, common: true),
        _entry(
          'kitten',
          '小貓',
          part: PartOfSpeech.noun,
          examples: ['A kitten is sleeping.'],
        ),
      ],
      relations: [_catKitten],
    ).recommend(_card('cat', '貓', part: PartOfSpeech.noun));
    expect(result.related, isEmpty);
  });

  test('常用原形可支持沒有程度欄位的明載變化形', () async {
    final service = _service([
      _entry('fly', '飛', part: PartOfSpeech.verb, common: true),
      _entry('flown', '飛；fly 的過去分詞', part: PartOfSpeech.verb),
    ]);
    final forward = await service.recommend(
      _card('fly', '飛', part: PartOfSpeech.verb),
    );
    final reverse = await service.recommend(
      _card('flown', '飛；fly 的過去分詞', part: PartOfSpeech.verb),
    );
    expect(forward.related.map((item) => item.entry.word), ['flown']);
    expect(reverse.related.map((item) => item.entry.word), ['fly']);
  });

  test('不明程度原形與變化形不因拼字註記自動成為常用候選', () async {
    final result = await _service([
      _entry('quoth', '說；quote 的過去式', part: PartOfSpeech.verb),
      _entry('quote', '說', part: PartOfSpeech.verb),
    ]).recommend(_card('quote', '說', part: PartOfSpeech.verb));
    expect(result.related, isEmpty);
  });
  test('明確關係正向只帶入已核對的目標義項例句，不混入其他義項', () async {
    const selected = 'The bright light hurt my eyes. 明亮的光線刺痛了我的眼睛。';
    const other = 'The bright student solved the problem. 聰明的學生解出了問題。';
    const relation = WordRelation(
      sourceWord: 'light',
      targetWord: 'bright',
      sourceSense: '光',
      targetSense: '明亮的',
      sourcePartsOfSpeech: [PartOfSpeech.noun],
      targetPartsOfSpeech: [PartOfSpeech.adjective],
      kind: WordRelationKind.related,
      explanation: 'bright 可以描述 light 的明亮程度。',
      targetExample: selected,
    );
    final result = await _service(
      [
        _entry('light', '光', part: PartOfSpeech.noun, common: true),
        _entry('bright', '明亮的；聰明的', examples: [other, selected]),
      ],
      relations: [relation],
    ).recommend(_card('light', '光', part: PartOfSpeech.noun));
    expect(result.related.map((item) => item.entry.word), ['bright']);
    expect(result.related.single.examples, [selected]);
    expect(result.related.single.examples, isNot(contains(other)));
  });

  test('明確關係反向使用來源端核對例句，不把 book 預訂的例句混入書籍義項', () async {
    const selected = 'I read a book before bed. 我睡前讀一本書。';
    const other = 'Please book a flight today. 請今天預訂機票。';
    const readExample = 'I read every morning. 我每天早上閱讀。';
    const relation = WordRelation(
      sourceWord: 'book',
      targetWord: 'read',
      sourceSense: '書',
      targetSense: '閱讀',
      sourcePartsOfSpeech: [PartOfSpeech.noun],
      targetPartsOfSpeech: [PartOfSpeech.verb],
      kind: WordRelationKind.related,
      explanation: 'book 是可以 read 的書籍。',
      sourceExample: selected,
      targetExample: readExample,
    );
    final result = await _service(
      [
        _entry(
          'book',
          '書；預訂',
          part: PartOfSpeech.noun,
          examples: [other, selected],
        ),
        _entry(
          'read',
          '閱讀',
          part: PartOfSpeech.verb,
          common: true,
          examples: [readExample],
        ),
      ],
      relations: [relation],
    ).recommend(_card('read', '閱讀', part: PartOfSpeech.verb));
    expect(result.related.map((item) => item.entry.word), ['book']);
    expect(result.related.single.examples, [selected]);
    expect(result.related.single.examples, isNot(contains(other)));
  });

  test('指定例句不是有效雙語或已不在字庫時跳過關係，不退回其他義項', () async {
    const englishOnly = 'The kitten is asleep.';
    const actual = 'A kitten slept in the basket. 小貓睡在籃子裡。';
    for (final preferred in [englishOnly, 'The kitten is asleep. 小貓睡著了。']) {
      final relation = WordRelation(
        sourceWord: 'cat',
        targetWord: 'kitten',
        sourceSense: '貓',
        targetSense: '小貓',
        sourcePartsOfSpeech: const [PartOfSpeech.noun],
        targetPartsOfSpeech: const [PartOfSpeech.noun],
        kind: WordRelationKind.related,
        explanation: 'kitten 指幼年的 cat。',
        targetExample: preferred,
      );
      final result = await _service(
        [
          _entry('cat', '貓', part: PartOfSpeech.noun, common: true),
          _entry(
            'kitten',
            '小貓',
            part: PartOfSpeech.noun,
            examples: [englishOnly, actual],
          ),
        ],
        relations: [relation],
      ).recommend(_card('cat', '貓', part: PartOfSpeech.noun));
      expect(result.related, isEmpty, reason: preferred);
    }
  });

  test('未指定核對例句的既有關係仍保留有效字庫例句', () async {
    const first = 'A kitten slept in the basket. 小貓睡在籃子裡。';
    const second = 'The kitten is playful. 這隻小貓很愛玩。';
    final result = await _service(
      [
        _entry('cat', '貓', part: PartOfSpeech.noun, common: true),
        _entry(
          'kitten',
          '小貓',
          part: PartOfSpeech.noun,
          examples: [first, second],
        ),
      ],
      relations: [_catKitten],
    ).recommend(_card('cat', '貓', part: PartOfSpeech.noun));
    expect(result.related.single.examples, [first, second]);
  });
}

const _catKitten = WordRelation(
  sourceWord: 'cat',
  targetWord: 'kitten',
  sourceSense: '貓',
  targetSense: '小貓',
  kind: WordRelationKind.related,
  explanation: 'kitten 指小貓，是 cat 的幼年階段。',
  sourcePartsOfSpeech: [PartOfSpeech.noun],
  targetPartsOfSpeech: [PartOfSpeech.noun],
);

WordExtensionService _service(
  List<BuiltinWordEntry> entries, {
  List<WordRelation> relations = const [],
}) => WordExtensionService(
  loadEntries: () async => entries,
  relations: relations,
);

BuiltinWordEntry _entry(
  String word,
  String meaning, {
  PartOfSpeech part = PartOfSpeech.adjective,
  bool common = false,
  int? difficulty,
  List<BuiltinSchoolLevel> levels = const [],
  List<BuiltinSourceTag> sources = const [],
  List<String>? examples,
}) => BuiltinWordEntry(
  word: word,
  meaning: meaning,
  partsOfSpeech: [part],
  sentences: examples ?? ['$word appears here. 這句話談到$meaning。'],
  sourcePage: 0,
  schoolLevels: common ? [BuiltinSchoolLevel.juniorHigh] : levels,
  difficultyLevel: common ? 2 : difficulty,
  examTags: const [],
  audienceTags: const [BuiltinAudienceTag.general],
  sourceTags: common ? [BuiltinSourceTag.twCeec] : sources,
);

WordCard _card(
  String word,
  String meaning, {
  PartOfSpeech part = PartOfSpeech.adjective,
}) {
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
