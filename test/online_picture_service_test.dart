import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yunxu_learning_english/domain/services/online_picture_service.dart';

late Uint8List png;

String manifest(Map<String, dynamic> images) =>
    jsonEncode({'version': 1, 'images': images});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawColor(const ui.Color(0xFFFF0000), ui.BlendMode.src);
    final picture = recorder.endRecording();
    final image = await picture.toImage(1, 1);
    png = (await image.toByteData(
      format: ui.ImageByteFormat.png,
    ))!.buffer.asUint8List();
    image.dispose();
    picture.dispose();
  });

  test(
    'manifest preserves path case; caches persist and avoid another lookup',
    () async {
      String? cache;
      var manifests = 0;
      final paths = <String>[];
      final service = OnlinePictureService(
        client: MockClient((request) async {
          paths.add(request.url.path);
          if (request.url.path.endsWith('manifest.json')) {
            manifests++;
            return http.Response(
              manifest({
                'apple': {'path': 'fruit/Apple.png'},
              }),
              200,
            );
          }
          return http.Response.bytes(png, 200);
        }),
        writeCache: (value) async => cache = value,
      );
      addTearDown(service.dispose);
      final first = await service.download(' APPLE ');
      expect(first!.url.path, endsWith('/main/fruit/Apple.png'));
      expect(first.bytes, png);
      await service.download('apple');
      expect(manifests, 1);
      expect(cache, isNotNull);
      final restored = OnlinePictureService(
        readCache: () async => cache,
        client: MockClient((request) async {
          expect(request.url.path, endsWith('fruit/Apple.png'));
          return http.Response.bytes(png, 200);
        }),
      );
      addTearDown(restored.dispose);
      expect(await restored.download('apple'), isNotNull);
    },
  );

  test(
    'cached missing word refreshes and discovers a newly published picture',
    () async {
      var requests = 0;
      final service = OnlinePictureService(
        readCache: () async => jsonEncode({
          'fetchedAt': DateTime.now().toIso8601String(),
          'content': manifest({}),
        }),
        client: MockClient((request) async {
          requests++;
          if (request.url.path.endsWith('manifest.json')) {
            return http.Response(
              manifest({
                'new': {'path': 'new.png'},
              }),
              200,
            );
          }
          return http.Response.bytes(png, 200);
        }),
        validateImage: (_) async {},
      );
      addTearDown(service.dispose);
      expect(await service.download('new'), isNotNull);
      expect(requests, 2);
    },
  );

  test(
    'no manifest falls back exact then lowercase and never caches a miss',
    () async {
      final paths = <String>[];
      var available = false;
      final service = OnlinePictureService(
        client: MockClient((request) async {
          paths.add(request.url.pathSegments.last);
          return available && request.url.path.endsWith('/apple.png')
              ? http.Response.bytes(png, 200)
              : http.Response('', 404);
        }),
        validateImage: (_) async {},
      );
      addTearDown(service.dispose);
      expect(await service.download('Apple'), isNull);
      expect(paths, ['manifest.json', 'Apple.png', 'apple.png']);
      available = true;
      expect(await service.download('Apple'), isNotNull);
    },
  );

  test(
    'fresh authoritative missing entry returns missing without guessing URLs',
    () async {
      final service = OnlinePictureService(
        client: MockClient((request) async {
          expect(request.url.path, endsWith('manifest.json'));
          return http.Response(manifest({}), 200);
        }),
      );
      addTearDown(service.dispose);
      expect(await service.download('absent'), isNull);
    },
  );

  for (final status in [403, 429, 500]) {
    test('$status is a retryable error, not a missing word', () async {
      final service = OnlinePictureService(
        client: MockClient((_) async => http.Response('', status)),
      );
      addTearDown(service.dispose);
      await expectLater(
        service.download('apple'),
        throwsA(isA<OnlinePictureException>()),
      );
    });
  }

  test('invalid manifest is not treated as absent', () async {
    final service = OnlinePictureService(
      client: MockClient((_) async => http.Response('bad json', 200)),
    );
    addTearDown(service.dispose);
    await expectLater(
      service.download('apple'),
      throwsA(isA<OnlinePictureException>()),
    );
  });

  for (final path in [
    '../secret.png',
    'https://evil.test/a.png',
    'a.jpg',
    '/a.png',
  ]) {
    test('rejects unsafe or unsupported manifest path $path', () async {
      var calls = 0;
      final service = OnlinePictureService(
        client: MockClient((_) async {
          calls++;
          return http.Response(
            manifest({
              'apple': {'path': path},
            }),
            200,
          );
        }),
      );
      addTearDown(service.dispose);
      await expectLater(
        service.download('apple'),
        throwsA(isA<OnlinePictureException>()),
      );
      expect(calls, 1);
    });
  }

  test('rejects HTML returned with successful status', () async {
    final service = OnlinePictureService(
      client: MockClient(
        (request) async => request.url.path.endsWith('manifest.json')
            ? http.Response('', 404)
            : http.Response('<html>not image</html>', 200),
      ),
    );
    addTearDown(service.dispose);
    await expectLater(
      service.download('apple'),
      throwsA(isA<OnlinePictureException>()),
    );
  });

  test('corrupt PNG is rejected by actual decoder', () async {
    final service = OnlinePictureService(
      client: MockClient(
        (request) async => request.url.path.endsWith('manifest.json')
            ? http.Response('', 404)
            : http.Response.bytes([137, 80, 78, 71, 13, 10, 26, 10], 200),
      ),
    );
    addTearDown(service.dispose);
    await expectLater(
      service.download('apple'),
      throwsA(isA<OnlinePictureException>()),
    );
  });

  test(
    'rejects oversized streamed images even without content length',
    () async {
      final service = OnlinePictureService(
        client: MockClient.streaming((request, _) async {
          if (request.url.path.endsWith('manifest.json')) {
            return http.StreamedResponse(const Stream.empty(), 404);
          }
          return http.StreamedResponse(
            Stream.fromIterable([
              List<int>.filled(8 * 1024 * 1024, 0),
              List<int>.filled(8 * 1024 * 1024, 0),
            ]),
            200,
          );
        }),
      );
      addTearDown(service.dispose);
      await expectLater(
        service.download('apple'),
        throwsA(isA<OnlinePictureException>()),
      );
    },
  );

  test('times out and cancels stalled response stream', () async {
    var cancelled = false;
    final stream = StreamController<List<int>>(
      onCancel: () => cancelled = true,
    );
    final service = OnlinePictureService(
      timeout: const Duration(milliseconds: 20),
      client: MockClient.streaming(
        (_, _) async => http.StreamedResponse(stream.stream, 200),
      ),
    );
    addTearDown(service.dispose);
    await expectLater(
      service.download('apple'),
      throwsA(
        isA<OnlinePictureException>().having(
          (e) => e.message,
          'message',
          contains('逾時'),
        ),
      ),
    );
    expect(cancelled, isTrue);
    await stream.close();
  });

  test('header timeout aborts the underlying HTTP request', () async {
    var aborted = false;
    final service = OnlinePictureService(
      timeout: const Duration(milliseconds: 20),
      client: _HeaderClient((request) async {
        await (request as http.AbortableRequest).abortTrigger;
        aborted = true;
        throw http.RequestAbortedException(request.url);
      }),
    );
    addTearDown(service.dispose);
    await expectLater(
      service.download('apple'),
      throwsA(isA<OnlinePictureException>()),
    );
    await Future<void>.delayed(Duration.zero);
    expect(aborted, isTrue);
  });

  test(
    'expired cache refreshes; disk cache failure does not block download',
    () async {
      var refreshed = false;
      final service = OnlinePictureService(
        readCache: () async =>
            jsonEncode({'fetchedAt': '2020-01-01', 'content': manifest({})}),
        writeCache: (_) async => throw StateError('disk'),
        client: MockClient((request) async {
          if (request.url.path.endsWith('manifest.json')) {
            refreshed = true;
            return http.Response(
              manifest({
                'apple': {'path': 'apple.png'},
              }),
              200,
            );
          }
          return http.Response.bytes(png, 200);
        }),
        validateImage: (_) async {},
      );
      addTearDown(service.dispose);
      expect(await service.download('apple'), isNotNull);
      expect(refreshed, isTrue);
    },
  );
}

class _HeaderClient extends http.BaseClient {
  _HeaderClient(this.handler);
  final Future<http.StreamedResponse> Function(http.BaseRequest) handler;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      handler(request);
}
