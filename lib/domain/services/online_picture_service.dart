import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:http/http.dart' as http;

class OnlinePictureException implements Exception {
  const OnlinePictureException(this.message);
  final String message;
  @override
  String toString() => message;
}

class OnlinePicture {
  const OnlinePicture(this.bytes, this.url);
  final Uint8List bytes;
  final Uri url;
}

class OnlinePictureService {
  OnlinePictureService({
    http.Client? client,
    this.readCache,
    this.writeCache,
    this.saveSource,
    Future<void> Function(Uint8List)? validateImage,
    this.timeout = const Duration(seconds: 30),
    DateTime Function()? now,
  }) : _client = client ?? http.Client(),
       _validateImage = validateImage ?? _decode,
       _now = now ?? DateTime.now;

  final http.Client _client;
  final Future<String?> Function()? readCache;
  final Future<void> Function(String)? writeCache;
  final Future<void> Function(String, String)? saveSource;
  final Future<void> Function(Uint8List) _validateImage;
  final DateTime Function() _now;
  final Duration timeout;
  Map<String, dynamic>? _images;
  DateTime? _fetchedAt;
  bool _loaded = false;
  static final _base = Uri.https(
    'raw.githubusercontent.com',
    '/nelsonchung/yunxu_learning_english_pictures/main/',
  );
  static const maxImageBytes = 15 * 1024 * 1024;

  void dispose() => _client.close();

  static Future<void> _decode(Uint8List bytes) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    try {
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      try {
        if (descriptor.width * descriptor.height > 24000000) {
          throw const OnlinePictureException('圖片尺寸過大，無法使用');
        }
        final codec = await descriptor.instantiateCodec();
        try {
          final frame = await codec.getNextFrame();
          frame.image.dispose();
        } finally {
          codec.dispose();
        }
      } finally {
        descriptor.dispose();
      }
    } finally {
      buffer.dispose();
    }
  }

  Future<Uint8List?> _get(Uri url, int limit) async {
    final elapsed = Stopwatch()..start();
    final abort = Completer<void>();
    StreamIterator<List<int>>? chunks;
    try {
      final response = await _client
          .send(http.AbortableRequest('GET', url, abortTrigger: abort.future))
          .timeout(timeout);
      chunks = StreamIterator(response.stream);
      if (response.statusCode == 404) return null;
      if (response.statusCode != 200) {
        throw const OnlinePictureException('目前無法連線圖庫，請稍後重試');
      }
      if ((response.contentLength ?? 0) > limit) {
        throw const OnlinePictureException('下載檔案過大，無法使用');
      }
      final bytes = BytesBuilder(copy: false);
      while (true) {
        final remaining = timeout - elapsed.elapsed;
        if (remaining <= Duration.zero) throw TimeoutException('download');
        if (!await chunks.moveNext().timeout(remaining)) break;
        if (bytes.length + chunks.current.length > limit) {
          throw const OnlinePictureException('下載檔案過大，無法使用');
        }
        bytes.add(chunks.current);
      }
      return bytes.takeBytes();
    } finally {
      abort.complete();
      await chunks?.cancel();
    }
  }

  Map<String, dynamic> _parse(String raw) {
    final data = jsonDecode(raw);
    if (data is! Map || data['version'] != 1 || data['images'] is! Map) {
      throw const FormatException('Invalid picture manifest');
    }
    return Map<String, dynamic>.from(data['images'] as Map);
  }

  Future<bool> _refresh() async {
    final raw = await _get(_base.resolve('manifest.json'), 5 * 1024 * 1024);
    if (raw == null) {
      _images = null;
      _fetchedAt = null;
      return false;
    }
    final content = utf8.decode(raw);
    _images = _parse(content);
    _fetchedAt = _now();
    try {
      await writeCache?.call(
        jsonEncode({
          'fetchedAt': _fetchedAt!.toIso8601String(),
          'content': content,
        }),
      );
    } catch (_) {
      // A cache failure must not prevent downloading an available picture.
    }
    return true;
  }

  Future<OnlinePicture?> download(String word) async {
    final exact = word.trim();
    if (exact.isEmpty) return null;
    try {
      if (!_loaded) {
        _loaded = true;
        try {
          final cached = await readCache?.call();
          if (cached != null) {
            final data = jsonDecode(cached) as Map;
            _images = _parse(data['content'] as String);
            _fetchedAt = DateTime.parse(data['fetchedAt'] as String);
          }
        } catch (_) {
          _images = null;
          _fetchedAt = null;
        }
      }
      var refreshed = false;
      if (_fetchedAt == null ||
          _now().difference(_fetchedAt!) >= const Duration(days: 1)) {
        await _refresh();
        refreshed = true;
      }
      final key = exact.toLowerCase();
      if (_images != null && !_images!.containsKey(key) && !refreshed) {
        await _refresh();
      }
      final paths = <String>[];
      if (_images != null) {
        final entry = _images![key];
        if (entry == null) return null;
        if (entry is! Map || entry['path'] is! String) {
          throw const FormatException('Invalid image entry');
        }
        paths.add(entry['path'] as String);
      } else {
        // Support the existing repository before its first manifest is published.
        paths.addAll({'$exact.png', '$key.png'});
      }
      for (final path in paths) {
        final segments = path.split('/');
        if (!path.toLowerCase().endsWith('.png') ||
            segments.any((s) => s.isEmpty || s == '.' || s == '..') ||
            path.contains('\\') ||
            path.contains(':')) {
          throw const FormatException('Invalid image path');
        }
        final url = _base.replace(
          pathSegments: [
            ..._base.pathSegments.take(_base.pathSegments.length - 1),
            ...segments,
          ],
        );
        final bytes = await _get(url, maxImageBytes);
        if (bytes == null) continue;
        const signature = [137, 80, 78, 71, 13, 10, 26, 10];
        if (bytes.length < 8 ||
            !List.generate(
              8,
              (i) => bytes[i] == signature[i],
            ).every((v) => v)) {
          throw const OnlinePictureException('下載內容不是有效的 PNG 圖片');
        }
        await _validateImage(bytes);
        return OnlinePicture(bytes, url);
      }
      return null;
    } on OnlinePictureException {
      rethrow;
    } on TimeoutException {
      throw const OnlinePictureException('下載逾時，請重試');
    } catch (_) {
      throw const OnlinePictureException('目前無法讀取圖庫或圖片，請稍後重試');
    }
  }
}
