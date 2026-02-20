import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

class ImagePreview extends StatelessWidget {
  const ImagePreview({
    super.key,
    required this.imageFile,
    this.imagePath,
    this.imageBytes,
    this.height = 180,
  });

  final File? imageFile;
  final String? imagePath;
  final List<int>? imageBytes;
  final double height;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final cacheWidth = (MediaQuery.sizeOf(context).width * dpr).round();
    final cacheHeight = (height * dpr).round();

    if (imageBytes != null && imageBytes!.isNotEmpty) {
      final bytes = imageBytes!;
      final typedBytes = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
      return Container(
        height: height,
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.04),
          borderRadius: BorderRadius.circular(16),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Image.memory(
            typedBytes,
            fit: BoxFit.contain,
            alignment: Alignment.center,
            cacheWidth: cacheWidth,
            cacheHeight: cacheHeight,
          ),
        ),
      );
    }

    final file = imageFile ?? (imagePath != null ? File(imagePath!) : null);

    if (file == null) {
      return Container(
        height: height,
        width: double.infinity,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFF0B6E99).withOpacity(0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF0B6E99).withOpacity(0.2)),
        ),
        child: const Text('尚未選擇圖片'),
      );
    }

    return Container(
      height: height,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.04),
        borderRadius: BorderRadius.circular(16),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Image.file(
          file,
          fit: BoxFit.contain,
          alignment: Alignment.center,
          cacheWidth: cacheWidth,
          cacheHeight: cacheHeight,
        ),
      ),
    );
  }
}
