import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

class ImageStorage {
  Future<String> saveImage(File source) async {
    final directory = await getApplicationDocumentsDirectory();
    final imagesDir = Directory(path.join(directory.path, 'images'));
    if (!await imagesDir.exists()) {
      await imagesDir.create(recursive: true);
    }

    final extension = path.extension(source.path);
    final filename =
        '${DateTime.now().millisecondsSinceEpoch}${extension.isEmpty ? '.jpg' : extension}';
    final targetPath = path.join(imagesDir.path, filename);
    final saved = await source.copy(targetPath);
    return saved.path;
  }
}
