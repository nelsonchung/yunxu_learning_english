import 'package:hive_flutter/hive_flutter.dart';

class PictureCatalogStore {
  static const boxName = 'picture_catalog';
  Future<Box<String>> _box() async => Hive.isBoxOpen(boxName)
      ? Hive.box<String>(boxName)
      : Hive.openBox<String>(boxName);

  Future<String?> read() async => (await _box()).get('manifest');
  Future<void> write(String value) async =>
      (await _box()).put('manifest', value);
  Future<void> saveSource(String imageIdentity, String source) async =>
      (await _box()).put('source:$imageIdentity', source);
}
