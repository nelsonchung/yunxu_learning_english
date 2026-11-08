import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:yunxu_learning_english/domain/models/builtin_word_entry.dart';
import 'package:yunxu_learning_english/domain/models/word_card.dart';
import 'package:yunxu_learning_english/domain/services/word_extension_service.dart';
import 'package:yunxu_learning_english/domain/services/word_relation_data.dart';

void main() {
  test('句末標點與形容詞的字尾「的」不應阻斷相同詞性釋義比對', () async {
    final service = _service([
      _entry('tiny', '微小的。', PartOfSpeech.adjective),
      _entry('little', '微小', PartOfSpeech.adjective),
      _entry('smallness', '微小', PartOfSpeech.noun),
    ]);
    final result = await service.recommend(
      _card('tiny', '微小的。', PartOfSpeech.adjective),
    );
    expect(result.related.map((item) => item.entry.word), ['little']);
    expect(result.confused, isEmpty);
  });

  test('nonsignificant 利用明確否定字義及字庫找到 significant 與同釋義字', () async {
    final service = _service([
      _entry('nonsignificant', '不重要。', PartOfSpeech.adjective),
      _entry('significant', '重要的；顯著的', PartOfSpeech.adjective),
      _entry('unimportant', '不重要的', PartOfSpeech.adjective),
      _entry('significance', '重要', PartOfSpeech.noun),
    ]);
    final result = await service.recommend(
      _card('nonsignificant', '不重要。', PartOfSpeech.adjective),
    );
    expect(
      result.related.map((item) => item.entry.word),
      containsAll(['significant', 'unimportant']),
    );
    expect(
      result.related.map((item) => item.entry.word),
      isNot(contains('significance')),
    );
    expect(result.confused, isEmpty);
    final reverse = await service.recommend(
      _card('significant', '重要的；顯著的', PartOfSpeech.adjective),
    );
    expect(
      reverse.related.map((item) => item.entry.word),
      contains('nonsignificant'),
    );
  });

  test('可拆字首仍需否定釋義、詞性與存在字目，不能只靠拼字推薦', () async {
    final service = _service([
      _entry('nonplus', '迷惑', PartOfSpeech.verb),
      _entry('plus', '加', PartOfSpeech.verb),
      _entry('unhappy', '不快樂的', PartOfSpeech.adjective),
      _entry('happy', '快樂', PartOfSpeech.noun),
      _entry('unready', '未準備好的', PartOfSpeech.adjective),
      _entry('invaluable', '無價的', PartOfSpeech.adjective),
      _entry('valuable', '有價值的', PartOfSpeech.adjective),
    ]);
    for (final item in [
      ('nonplus', '迷惑', PartOfSpeech.verb),
      ('unhappy', '不快樂的', PartOfSpeech.adjective),
      ('unready', '未準備好的', PartOfSpeech.adjective),
      ('invaluable', '無價的', PartOfSpeech.adjective),
    ]) {
      final result = await service.recommend(_card(item.$1, item.$2, item.$3));
      expect(result.related, isEmpty, reason: item.$1);
    }
  });

  test('inflammable 與 flammable 同義，不能只靠 in 字首說成否定關係', () async {
    final service = _service([
      _entry('inflammable', '易燃的', PartOfSpeech.adjective),
      _entry('flammable', '易燃的', PartOfSpeech.adjective),
    ]);
    final result = await service.recommend(
      _card('inflammable', '易燃的', PartOfSpeech.adjective),
    );
    expect(result.related.map((item) => item.entry.word), ['flammable']);
    expect(result.related.single.explanation, contains('字庫釋義'));
  });

  test('windmill 合成字有字庫雙組件及中文構詞證據時才推薦 wind', () async {
    final service = _service([
      _entry('windmill', '風車', PartOfSpeech.noun),
      _entry('wind', '風；氣流', PartOfSpeech.noun),
      _entry('mill', '磨', PartOfSpeech.noun),
    ]);
    final result = await service.recommend(
      _card('windmill', '風車', PartOfSpeech.noun),
    );
    expect(result.related.map((item) => item.entry.word), ['wind']);
    expect(result.confused, isEmpty);
  });

  test('合成字缺少另一組件字目或目前義項不同時不推薦', () async {
    final incomplete = _service([
      _entry('windmill', '風車', PartOfSpeech.noun),
      _entry('wind', '風', PartOfSpeech.noun),
    ]);
    final missing = await incomplete.recommend(
      _card('windmill', '風車', PartOfSpeech.noun),
    );
    expect(missing.related, isEmpty);
    final service = _service([
      _entry('windmill', '風車', PartOfSpeech.noun),
      _entry('wind', '風', PartOfSpeech.noun),
      _entry('mill', '磨', PartOfSpeech.noun),
    ]);
    final otherSense = await service.recommend(
      _card('windmill', '揮舞雙臂', PartOfSpeech.verb),
    );
    expect(otherSense.related, isEmpty);
    final wrongNounSense = await service.recommend(
      _card('windmill', '揮舞雙臂', PartOfSpeech.noun),
    );
    expect(wrongNounSense.related, isEmpty);
    final wrongPart = await service.recommend(
      _card('windmill', '風車', PartOfSpeech.verb),
    );
    expect(wrongPart.related, isEmpty);
    final innerCharacter = await service.recommend(
      _card('windmill', '順風車輛', PartOfSpeech.noun),
    );
    expect(innerCharacter.related, isEmpty);
  });

  test('butterfly 與 carpet 的可拆拼字不足以證明合成字關係', () async {
    final service = _service([
      _entry('butterfly', '蝴蝶', PartOfSpeech.noun),
      _entry('butter', '奶油', PartOfSpeech.noun),
      _entry('fly', '飛', PartOfSpeech.verb),
      _entry('carpet', '地毯', PartOfSpeech.noun),
      _entry('car', '汽車', PartOfSpeech.noun),
      _entry('pet', '寵物', PartOfSpeech.noun),
    ]);
    for (final item in [('butterfly', '蝴蝶'), ('carpet', '地毯')]) {
      final result = await service.recommend(
        _card(item.$1, item.$2, PartOfSpeech.noun),
      );
      expect(result.related, isEmpty, reason: item.$1);
      expect(result.confused, isEmpty, reason: item.$1);
    }
  });

  test('變化形原形需有正確詞性，避免把同拼字的人名或名詞當成動詞', () async {
    final service = _service([
      _entry('Gad', '迦得（聖經人物名）', PartOfSpeech.noun),
      _entry('gadded', '閒晃，遊蕩（gad 的過去式）', PartOfSpeech.verb),
      _entry('mag', '雜誌', PartOfSpeech.noun),
      _entry('magged', 'mag 的過去式', PartOfSpeech.verb),
    ]);
    for (final word in ['Gad', 'gadded', 'mag', 'magged']) {
      final result = await service.recommend(
        _card(
          word,
          {
            'Gad': '迦得（聖經人物名）',
            'gadded': '閒晃，遊蕩（gad 的過去式）',
            'mag': '雜誌',
            'magged': 'mag 的過去式',
          }[word]!,
          word == 'Gad' || word == 'mag'
              ? PartOfSpeech.noun
              : PartOfSpeech.verb,
        ),
      );
      expect(result.related, isEmpty, reason: word);
    }
  });

  test('非固定字目以相同釋義及詞性找到候選，不把不同詞性或拼字接近當成關係', () async {
    final service = _service([
      _entry('beautiful', '美麗的', PartOfSpeech.adjective),
      _entry('pretty', '美麗的', PartOfSpeech.adjective),
      _entry('beautify', '美麗的', PartOfSpeech.verb),
      _entry('beautifully', '美麗地', PartOfSpeech.adverb),
    ]);

    final result = await service.recommend(
      _card(' BEAUTIFUL ', '美麗的', PartOfSpeech.adjective),
    );

    expect(result.related.map((item) => item.entry.word), ['pretty']);
    expect(result.related.single.explanation, contains('字庫釋義'));
    expect(result.confused, isEmpty);
  });

  test('使用者自訂字不在內建字庫仍可利用自身釋義與詞性尋找候選', () async {
    final service = _service([_entry('pretty', '美麗的', PartOfSpeech.adjective)]);
    final result = await service.recommend(
      _card('user-term', '美麗的', PartOfSpeech.adjective),
    );
    expect(result.related.map((item) => item.entry.word), ['pretty']);
    expect(result.usages, isEmpty);
  });

  test('泛稱釋義及帶污染標記的例句不能用來湊候選', () async {
    final service = _service([
      _entry('john', '人名', PartOfSpeech.noun),
      _entry('mary', '人名', PartOfSpeech.noun),
      _entry('beautiful', '美麗的', PartOfSpeech.adjective),
      _entry(
        'pretty',
        '美麗的',
        PartOfSpeech.adjective,
        sentences: ['<b>It is pretty.</b> 它很美麗。'],
      ),
    ]);
    final generic = await service.recommend(
      _card('john', '人名', PartOfSpeech.noun),
    );
    final polluted = await service.recommend(
      _card('beautiful', '美麗的', PartOfSpeech.adjective),
    );
    expect(generic.related, isEmpty);
    expect(polluted.related, isEmpty);
  });

  test('定義明載的跨字首不規則變化可雙向查詢', () async {
    final service = _service([
      _entry('fly', '飛；飛行', PartOfSpeech.verb),
      _entry('flew', '飛；fly 的過去式', PartOfSpeech.verb),
      _entry('flower', '花', PartOfSpeech.noun),
    ]);

    final base = await service.recommend(
      _card('fly', '飛；飛行', PartOfSpeech.verb),
    );
    final inflected = await service.recommend(
      _card('flew', '飛；fly 的過去式', PartOfSpeech.verb),
    );

    expect(base.related.map((item) => item.entry.word), ['flew']);
    expect(inflected.related.map((item) => item.entry.word), ['fly']);
    expect(base.confused, isEmpty);
  });

  test('片語必須有完整單字及對應義項，不能以字串包含推測關係', () async {
    final service = _service([
      _entry('bank', '銀行', PartOfSpeech.noun),
      _entry('bank account', '銀行帳戶', PartOfSpeech.phrase),
      _entry('bank on', '依賴', PartOfSpeech.phrase),
      _entry('river bank', '河岸', PartOfSpeech.phrase),
      _entry('banker', '銀行家', PartOfSpeech.noun),
    ]);

    final result = await service.recommend(
      _card('bank', '銀行', PartOfSpeech.noun),
    );

    expect(result.related.map((item) => item.entry.word), ['bank account']);
    expect(result.confused, isEmpty);
  });

  test('拼字或標籤相似不足以推薦，空結果不生成模板', () async {
    final service = _service([
      _entry('cat', '貓', PartOfSpeech.noun),
      _entry('catalogue', '目錄', PartOfSpeech.noun),
      _entry('catch', '捕捉', PartOfSpeech.verb),
      _entry('dog', '狗', PartOfSpeech.noun),
    ]);

    final result = await service.recommend(
      _card('cat', '貓', PartOfSpeech.noun),
    );

    expect(result.related, isEmpty);
    expect(result.confused, isEmpty);
    // The source's real example may be shown, but no unrelated word is filled in.
    expect(
      result.usages.every((usage) => usage.example.contains('cat')),
      isTrue,
    );
    final unknown = await service.recommend(
      _card('xyzzy', '不存在的字', PartOfSpeech.other),
    );
    expect(unknown.isEmpty, isTrue);
    expect(unknown.usages, isEmpty);
  });

  test('字庫義項不同時不回退到另一義項的例句', () async {
    final service = _service([
      _entry(
        'bank',
        '銀行',
        PartOfSpeech.noun,
        sentences: ['I visited the bank. 我去了銀行。'],
      ),
      _entry('bank account', '銀行帳戶', PartOfSpeech.phrase),
    ]);

    final result = await service.recommend(
      _card('bank', '河岸', PartOfSpeech.noun),
    );

    expect(result.isEmpty, isTrue);
    expect(result.usages, isEmpty);
    expect(result.related, isEmpty);
  });

  test('以使用者自己的雙語例句提供用法，保留原文與來源', () async {
    const example = 'We sat on the bank.\n我們坐在河岸上。';
    final service = _service([_entry('bank', '銀行', PartOfSpeech.noun)]);

    final result = await service.recommend(
      _card('bank', '河岸', PartOfSpeech.noun, sentences: [example]),
    );

    expect(result.usages.map((usage) => usage.example), contains(example));
    expect(result.usages.every((usage) => usage.source.isNotEmpty), isTrue);
    expect(result.related, isEmpty);
  });

  test('字庫雙語例句支援空格分隔，英文單語或空例句不作為用法', () async {
    const example = 'The owl is awake. 貓頭鷹醒著。';
    final service = _service([
      _entry(
        'owl',
        '貓頭鷹',
        PartOfSpeech.noun,
        sentences: ['', 'The owl is awake.', example],
      ),
    ]);

    final result = await service.recommend(
      _card('owl', '貓頭鷹', PartOfSpeech.noun),
    );

    expect(result.usages.map((usage) => usage.example), [example]);
  });

  test('明確字族資料可從原本不在固定字目內的 decision 反向找到 decide', () async {
    final service = _service([
      _entry('decision', '決定', PartOfSpeech.noun),
      _entry('decide', '決定', PartOfSpeech.verb),
    ]);

    final result = await service.recommend(
      _card('decision', '決定', PartOfSpeech.noun),
    );

    expect(result.related.map((item) => item.entry.word), contains('decide'));
    expect(result.related.single.explanation, isNotEmpty);
  });

  test('易混淆推薦僅使用明確關係，支援雙向而不以近似字母推測', () async {
    final service = _service([
      _entry('borrow', '借入', PartOfSpeech.verb),
      _entry('lend', '借出', PartOfSpeech.verb),
      _entry('brow', '額頭', PartOfSpeech.noun),
    ]);
    final forward = await service.recommend(
      _card('borrow', '借入', PartOfSpeech.verb),
    );
    final reverse = await service.recommend(
      _card('lend', '借出', PartOfSpeech.verb),
    );
    expect(forward.confused.map((item) => item.entry.word), ['lend']);
    expect(reverse.confused.map((item) => item.entry.word), ['borrow']);
    expect(forward.confused.single.explanation, isNotEmpty);
  });

  test('缺少字庫目標時不沿用舊固定內容虛構可新增的字卡', () async {
    final service = _service([_entry('decide', '決定', PartOfSpeech.verb)]);

    final result = await service.recommend(
      _card('decide', '決定', PartOfSpeech.verb),
    );

    expect(result.related, isEmpty);
    expect(result.confused, isEmpty);
  });

  test('關係資料兩端都必須符合目前義項', () async {
    final service = _service([
      _entry('decide', '決定', PartOfSpeech.verb),
      _entry('decision', '法院判決', PartOfSpeech.noun),
    ]);

    final sourceMismatch = await service.recommend(
      _card('decide', '裁定', PartOfSpeech.verb),
    );
    final targetMismatch = await service.recommend(
      _card('decide', '決定', PartOfSpeech.verb),
    );

    expect(sourceMismatch.related, isEmpty);
    expect(targetMismatch.related, isEmpty);
  });

  test('候選缺少解釋或雙語例句時排除，不補預設句', () async {
    final service = _service([
      _entry('beautiful', '美麗的', PartOfSpeech.adjective),
      _entry('pretty', '美麗的', PartOfSpeech.adjective, sentences: []),
      _entry(
        'lovely',
        '美麗的',
        PartOfSpeech.adjective,
        sentences: ['It is lovely.'],
      ),
      _entry('attractive', '', PartOfSpeech.adjective),
    ]);

    final result = await service.recommend(
      _card('beautiful', '美麗的', PartOfSpeech.adjective),
    );

    expect(result.related, isEmpty);
    expect(result.confused, isEmpty);
  });

  test('候選去重、排除自己，依程度接近排序並限制數量', () async {
    final service = _service([
      _entry('bright', '明亮的', PartOfSpeech.adjective, difficulty: 2),
      _entry(' BRIGHT ', '明亮的', PartOfSpeech.adjective, difficulty: 2),
      _entry('radiant', '明亮的', PartOfSpeech.adjective, difficulty: 4),
      _entry('shiny', '明亮的', PartOfSpeech.adjective, difficulty: 2),
      _entry(' SHINY ', '明亮的', PartOfSpeech.adjective, difficulty: 2),
      _entry('sunny', '明亮的', PartOfSpeech.adjective, difficulty: 3),
      _entry('glaring', '明亮的', PartOfSpeech.adjective, difficulty: 6),
    ]);

    final result = await service.recommend(
      _card('bright', '明亮的', PartOfSpeech.adjective),
    );
    final keys = result.related.map(
      (item) => item.entry.word.trim().toLowerCase(),
    );

    expect(keys, ['shiny', 'sunny', 'radiant']);
    expect(keys.toSet().length, keys.length);
    expect(result.confused.length, lessThanOrEqualTo(2));
    final repeat = await service.recommend(
      _card('bright', '明亮的', PartOfSpeech.adjective),
    );
    expect(
      repeat.related.map((item) => item.entry.word),
      result.related.map((item) => item.entry.word),
    );
  });

  test('明確關係優先於定義詞形、片語及同釋義候選', () async {
    final service = _service([
      _entry('decide', '決定', PartOfSpeech.verb, difficulty: 1),
      _entry('decision', '決定', PartOfSpeech.noun, difficulty: 5),
      _entry('decided', 'decide 的過去式', PartOfSpeech.verb, difficulty: 1),
      _entry('decide on', '決定；選定', PartOfSpeech.phrase, difficulty: 1),
      _entry('determine', '決定', PartOfSpeech.verb, difficulty: 1),
    ]);

    final result = await service.recommend(
      _card('decide', '決定', PartOfSpeech.verb),
    );

    expect(result.related.map((item) => item.entry.word), [
      'decision',
      'decided',
      'decide on',
    ]);
  });

  test('明確關係資料有雙端義項，教學用法有來源與雙語例句', () {
    expect(WordRelationData.relations, isNotEmpty);
    for (final relation in WordRelationData.relations) {
      expect(relation.sourceWord.trim(), isNotEmpty);
      expect(relation.targetWord.trim(), isNotEmpty);
      expect(
        relation.sourceWord.toLowerCase(),
        isNot(relation.targetWord.toLowerCase()),
      );
      expect(relation.sourceSense.trim(), isNotEmpty);
      expect(relation.targetSense.trim(), isNotEmpty);
      expect(relation.explanation.trim(), isNotEmpty);
    }
    for (final usage in WordRelationData.usages.values) {
      expect(usage.sense.trim(), isNotEmpty);
      expect(usage.description.trim(), isNotEmpty);
      expect(usage.source.trim(), isNotEmpty);
      expect(usage.example, matches(RegExp(r'[a-zA-Z]')));
      expect(usage.example, matches(RegExp(r'[\u3400-\u9fff]')));
    }
  });

  test('字庫索引延遲載入，共用同時請求且成功後重用', () async {
    var loads = 0;
    final pending = Completer<List<BuiltinWordEntry>>();
    final service = WordExtensionService(
      loadEntries: () {
        loads++;
        return pending.future;
      },
    );
    expect(loads, 0);
    final first = service.recommend(_card('owl', '貓頭鷹', PartOfSpeech.noun));
    final second = service.recommend(_card('cat', '貓', PartOfSpeech.noun));
    pending.complete([
      _entry('owl', '貓頭鷹', PartOfSpeech.noun),
      _entry('cat', '貓', PartOfSpeech.noun),
    ]);
    await Future.wait([first, second]);
    await service.recommend(_card('owl', '貓頭鷹', PartOfSpeech.noun));
    expect(loads, 1);
  });

  test('字庫載入失敗後允許重試，不永久保留失敗的 future', () async {
    var loads = 0;
    final service = WordExtensionService(
      loadEntries: () async {
        loads++;
        if (loads == 1) throw StateError('temporary failure');
        return [_entry('owl', '貓頭鷹', PartOfSpeech.noun)];
      },
    );
    final card = _card('owl', '貓頭鷹', PartOfSpeech.noun);

    await expectLater(service.recommend(card), throwsStateError);
    final result = await service.recommend(card);

    expect(loads, 2);
    expect(result.usages, isNotEmpty);
  });
}

WordExtensionService _service(List<BuiltinWordEntry> entries) =>
    WordExtensionService(loadEntries: () async => entries);

BuiltinWordEntry _entry(
  String word,
  String meaning,
  PartOfSpeech part, {
  List<String>? sentences,
  int? difficulty,
}) => BuiltinWordEntry(
  word: word,
  meaning: meaning,
  partsOfSpeech: [part],
  sentences: sentences ?? ['We discussed $word today. 我們今天討論了$word。'],
  sourcePage: 0,
  schoolLevels: const [BuiltinSchoolLevel.seniorHigh],
  examTags: const [],
  audienceTags: const [],
  sourceTags: const [BuiltinSourceTag.twCeec],
  difficultyLevel: difficulty ?? 2,
);

WordCard _card(
  String word,
  String meaning,
  PartOfSpeech part, {
  List<String> sentences = const [],
}) {
  final now = DateTime(2026, 11, 7);
  return WordCard(
    id: 'test-$word',
    word: word,
    meaning: meaning,
    partsOfSpeech: [part],
    sentences: sentences,
    origin: WordOrigin.manual,
    createdAt: now,
    updatedAt: now,
    reviewSchedule: const [1, 2, 3],
    nextReviewIndex: 0,
    nextReviewDate: now.add(const Duration(days: 1)),
    history: const [],
    isDeleted: false,
  );
}
