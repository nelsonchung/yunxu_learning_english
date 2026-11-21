import 'dart:async';
import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:yunxu_learning_english/domain/models/word_card.dart';
import 'package:yunxu_learning_english/domain/services/online_picture_service.dart';
import 'package:yunxu_learning_english/presentation/state/words_notifier.dart';
import 'package:yunxu_learning_english/presentation/widgets/online_picture_button.dart';

final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a2ioAAAAASUVORK5CYII=',
);
final _url = Uri.parse('https://example.com/apple.png');
final _card = WordCard.fromMap({
  'id': 'apple-id',
  'word': 'apple',
  'meaning': '蘋果',
  'imagePath': '/images/existing.png',
});

class _Pictures extends OnlinePictureService {
  _Pictures(this.result, {super.saveSource});

  Future<OnlinePicture?> Function() result;
  final requestedWords = <String>[];

  @override
  Future<OnlinePicture?> download(String word) {
    requestedWords.add(word);
    return result();
  }
}

class _Words extends ChangeNotifier implements WordsNotifier {
  WordCard card = _card;
  final appliedIds = <String>[];
  WordCard? expected;
  List<int>? appliedBytes;

  @override
  Future<void> updateWordImage(
    String id,
    List<int> bytes, {
    WordCard? expectedCard,
    bool allowImageReplacement = false,
  }) async {
    appliedIds.add(id);
    expected = expectedCard;
    appliedBytes = bytes;
    card = card.copyWith(imagePath: '/images/downloaded.png');
  }

  @override
  WordCard? findById(String id) => id == card.id ? card : null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _mount(
  WidgetTester tester,
  _Pictures pictures,
  _Words words,
) async {
  addTearDown(pictures.dispose);
  addTearDown(words.dispose);
  await tester.pumpWidget(
    ChangeNotifierProvider<WordsNotifier>.value(
      value: words,
      child: MaterialApp(
        home: Scaffold(
          body: OnlinePictureButton(card: _card, service: pictures),
        ),
      ),
    ),
  );
}

OutlinedButton _button(WidgetTester tester) =>
    tester.widget<OutlinedButton>(find.byType(OutlinedButton));

void main() {
  testWidgets('mounting does not request a picture', (tester) async {
    final pictures = _Pictures(() async => null);
    await _mount(tester, pictures, _Words());
    await tester.pumpAndSettle();
    expect(pictures.requestedWords, isEmpty);
    expect(_button(tester).onPressed, isNotNull);
  });

  testWidgets('missing picture leaves current image and allows retry', (
    tester,
  ) async {
    final pictures = _Pictures(() async => null);
    final words = _Words();
    await _mount(tester, pictures, words);
    await tester.tap(find.text('下載線上圖片'));
    await tester.pumpAndSettle();
    expect(find.textContaining('尚未提供線上圖片'), findsOneWidget);
    expect(words.card.imagePath, _card.imagePath);
    expect(words.appliedIds, isEmpty);
    expect(_button(tester).onPressed, isNotNull);
    await tester.tap(find.text('下載線上圖片'));
    await tester.pumpAndSettle();
    expect(pictures.requestedWords, ['apple', 'apple']);
  });

  testWidgets('download error displays explanation and permits retry', (
    tester,
  ) async {
    final pictures = _Pictures(
      () async => throw const OnlinePictureException('下載逾時，請重試'),
    );
    final words = _Words();
    await _mount(tester, pictures, words);
    await tester.tap(find.text('下載線上圖片'));
    await tester.pumpAndSettle();
    expect(find.text('下載逾時，請重試'), findsOneWidget);
    expect(_button(tester).onPressed, isNotNull);
    expect(words.appliedIds, isEmpty);
    pictures.result = () async => null;
    await tester.tap(find.text('下載線上圖片'));
    await tester.pumpAndSettle();
    expect(find.textContaining('尚未提供線上圖片'), findsOneWidget);
  });

  testWidgets('canceling preview preserves the current picture and source', (
    tester,
  ) async {
    final sources = <String>[];
    final pictures = _Pictures(
      () async => OnlinePicture(_png, _url),
      saveSource: (name, url) async => sources.add(url),
    );
    final words = _Words();
    await _mount(tester, pictures, words);
    await tester.tap(find.text('下載線上圖片'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('apple 線上圖片'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(words.appliedIds, isEmpty);
    expect(words.card.imagePath, _card.imagePath);
    expect(sources, isEmpty);
    expect(_button(tester).onPressed, isNotNull);
  });

  testWidgets(
    'apply passes the original snapshot and saves downloaded source',
    (tester) async {
      final sources = <List<String>>[];
      final pictures = _Pictures(
        () async => OnlinePicture(_png, _url),
        saveSource: (name, url) async => sources.add([name, url]),
      );
      final words = _Words();
      await _mount(tester, pictures, words);
      await tester.tap(find.text('下載線上圖片'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(words.appliedIds, isEmpty);
      await tester.tap(find.text('套用圖片'));
      await tester.pumpAndSettle();
      expect(words.appliedIds, [_card.id]);
      expect(words.expected, same(_card));
      expect(words.appliedBytes, orderedEquals(_png));
      expect(sources, [
        ['downloaded.png', _url.toString()],
      ]);
      expect(find.text('圖片已套用，可離線查看'), findsOneWidget);
    },
  );

  testWidgets('pending download disables repeated requests', (tester) async {
    final pending = Completer<OnlinePicture?>();
    final pictures = _Pictures(() => pending.future);
    await _mount(tester, pictures, _Words());
    await tester.tap(find.text('下載線上圖片'));
    await tester.pump();
    expect(_button(tester).onPressed, isNull);
    expect(find.text('正在取得線上圖片…'), findsOneWidget);
    await tester.tap(find.byType(OutlinedButton));
    expect(pictures.requestedWords, ['apple']);
    pending.complete(null);
    await tester.pumpAndSettle();
    expect(_button(tester).onPressed, isNotNull);
  });
}
