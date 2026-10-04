import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../domain/models/learning_image.dart';

abstract class LearningImageCredentials {
  Future<String?> load();
  Future<void> save(String key);
  Future<void> delete();
}

class SecureLearningImageCredentials implements LearningImageCredentials {
  SecureLearningImageCredentials({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.first_unlock_this_device,
              synchronizable: false,
            ),
            mOptions: MacOsOptions(
              usesDataProtectionKeychain: false,
              synchronizable: false,
            ),
          );
  final FlutterSecureStorage _storage;
  static const keyName = 'learning_image_openai_key';
  @override
  Future<String?> load() => _storage.read(key: keyName);
  @override
  Future<void> save(String key) =>
      _storage.write(key: keyName, value: key.trim());
  @override
  Future<void> delete() => _storage.delete(key: keyName);
}

abstract class LearningImageStore {
  Future<List<LearningImageAttempt>> attempts();
  Future<void> putAttempt(LearningImageAttempt attempt);
  Future<LearningImageMode> loadMode();
  Future<void> saveMode(LearningImageMode mode);
  Future<void> putMetadata(LearningImageMetadata metadata);
  Future<LearningImageMetadata?> metadataFor(String wordId);
}

class HiveLearningImageStore implements LearningImageStore {
  static const boxName = 'learning_image_local';
  Future<Box<Map>> _box() async => Hive.isBoxOpen(boxName)
      ? Hive.box<Map>(boxName)
      : Hive.openBox<Map>(boxName);
  @override
  Future<List<LearningImageAttempt>> attempts() async => (await _box()).keys
      .where((k) => k.toString().startsWith('attempt:'))
      .map((k) => LearningImageAttempt.fromMap(Hive.box<Map>(boxName).get(k)!))
      .toList();
  @override
  Future<void> putAttempt(LearningImageAttempt attempt) async =>
      (await _box()).put('attempt:${attempt.id}', attempt.toMap());
  @override
  Future<LearningImageMode> loadMode() async =>
      (await _box()).get('settings')?['mode'] == 'fast'
      ? LearningImageMode.fast
      : LearningImageMode.precise;
  @override
  Future<void> saveMode(LearningImageMode mode) async =>
      (await _box()).put('settings', {'mode': mode.name});
  @override
  Future<void> putMetadata(LearningImageMetadata metadata) async =>
      (await _box()).put('metadata:${metadata.wordId}', metadata.toMap());
  @override
  Future<LearningImageMetadata?> metadataFor(String wordId) async {
    final value = (await _box()).get('metadata:$wordId');
    return value == null ? null : LearningImageMetadata.fromMap(value);
  }
}
