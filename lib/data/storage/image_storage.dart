import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

class ImageStorage {
  Future<Directory> _ensureImagesDir() async {
    final directory = await getApplicationDocumentsDirectory();
    final imagesDir = Directory(path.join(directory.path, 'images'));
    if (!await imagesDir.exists()) {
      await imagesDir.create(recursive: true);
    }
    return imagesDir;
  }

  Future<String> saveImage(File source) async {
    final imagesDir = await _ensureImagesDir();
    final extension = path.extension(source.path);
    final filename =
        '${DateTime.now().microsecondsSinceEpoch}${extension.isEmpty ? '.jpg' : extension}';
    final targetPath = path.join(imagesDir.path, filename);
    final saved = await source.copy(targetPath);
    return saved.path;
  }

  Future<String> saveBytes(List<int> bytes, {String extension = '.jpg'}) async {
    final imagesDir = await _ensureImagesDir();
    final normalizedExtension = extension.startsWith('.')
        ? extension
        : '.$extension';
    final filename =
        '${DateTime.now().microsecondsSinceEpoch}$normalizedExtension';
    final targetPath = path.join(imagesDir.path, filename);
    final file = File(targetPath);
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  Future<void> deleteImage(String pathValue) async {
    final file = File(pathValue);
    if (await file.exists()) {
      await file.delete();
    }
  }
}
