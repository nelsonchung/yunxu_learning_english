import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yunxu_learning_english/data/storage/learning_image_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final calls = <MethodCall>[];
  String? stored;

  setUp(() {
    calls.clear();
    stored = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'write') {
            stored = call.arguments['value'] as String;
          }
          if (call.method == 'delete') {
            stored = null;
          }
          return call.method == 'read' ? stored : null;
        });
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  for (final platform in [
    TargetPlatform.iOS,
    TargetPlatform.macOS,
    TargetPlatform.android,
  ]) {
    test('secure credential adapter lifecycle on $platform', () async {
      debugDefaultTargetPlatformOverride = platform;
      final credentials = SecureLearningImageCredentials();
      await credentials.save('  test-local-only  ');
      expect(await credentials.load(), 'test-local-only');
      await credentials.delete();
      expect(await credentials.load(), isNull);
      expect(calls.map((c) => c.method), ['write', 'read', 'delete', 'read']);
      for (final call in calls) {
        expect(call.arguments['key'], SecureLearningImageCredentials.keyName);
        final options = call.arguments['options'] as Map;
        if (platform != TargetPlatform.android) {
          expect(options['synchronizable'], 'false');
        }
        if (platform == TargetPlatform.macOS) {
          expect(options['usesDataProtectionKeychain'], 'false');
        }
        if (platform == TargetPlatform.iOS) {
          expect(options['accessibility'], 'first_unlock_this_device');
        }
      }
    });
  }
}
