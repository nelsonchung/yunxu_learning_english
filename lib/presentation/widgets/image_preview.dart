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
    this.enableZoom = false,
  });

  final File? imageFile;
  final String? imagePath;
  final List<int>? imageBytes;
  final double height;
  final bool enableZoom;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final cacheWidth = (MediaQuery.sizeOf(context).width * dpr).round();

    final preview = _buildPreview(cacheWidth);
    if (!enableZoom || !_hasImage) {
      return preview;
    }

    return Tooltip(
      message: '放大圖片',
      child: Semantics(
        button: true,
        label: '放大圖片',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _showZoomDialog(context),
          child: Stack(
            children: [
              preview,
              Positioned(
                right: 10,
                bottom: 10,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.58),
                    shape: BoxShape.circle,
                  ),
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Icon(
                      Icons.zoom_out_map,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool get _hasImage =>
      (imageBytes != null && imageBytes!.isNotEmpty) ||
      imageFile != null ||
      imagePath != null;

  Widget _buildPreview(int cacheWidth) {
    if (imageBytes != null && imageBytes!.isNotEmpty) {
      return _ImageFrame(
        height: height,
        child: Image.memory(
          _typedImageBytes!,
          fit: BoxFit.contain,
          alignment: Alignment.center,
          cacheWidth: cacheWidth,
        ),
      );
    }

    final file = _imageFile;

    if (file == null) {
      return Container(
        height: height,
        width: double.infinity,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFF0B6E99).withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const Color(0xFF0B6E99).withValues(alpha: 0.2),
          ),
        ),
        child: const Text('尚未選擇圖片'),
      );
    }

    return _ImageFrame(
      height: height,
      child: Image.file(
        file,
        fit: BoxFit.contain,
        alignment: Alignment.center,
        cacheWidth: cacheWidth,
      ),
    );
  }

  File? get _imageFile =>
      imageFile ?? (imagePath != null ? File(imagePath!) : null);

  Uint8List? get _typedImageBytes {
    final bytes = imageBytes;
    if (bytes == null || bytes.isEmpty) {
      return null;
    }
    return bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
  }

  Future<void> _showZoomDialog(BuildContext context) {
    return showDialog<void>(
      context: context,
      useSafeArea: false,
      barrierColor: Colors.black.withValues(alpha: 0.9),
      builder: (context) =>
          _ImageZoomDialog(imageFile: _imageFile, imageBytes: _typedImageBytes),
    );
  }
}

class _ImageFrame extends StatelessWidget {
  const _ImageFrame({required this.height, required this.child});

  final double height;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
      ),
      child: ClipRRect(borderRadius: BorderRadius.circular(16), child: child),
    );
  }
}

class _ImageZoomDialog extends StatefulWidget {
  const _ImageZoomDialog({required this.imageFile, required this.imageBytes});

  final File? imageFile;
  final Uint8List? imageBytes;

  @override
  State<_ImageZoomDialog> createState() => _ImageZoomDialogState();
}

class _ImageZoomDialogState extends State<_ImageZoomDialog> {
  static const double _minScale = 1;
  static const double _maxScale = 5;
  static const double _scaleStep = 0.5;

  final TransformationController _controller = TransformationController();
  double _scale = _minScale;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_syncScale);
  }

  @override
  void dispose() {
    _controller.removeListener(_syncScale);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                children: [
                  IconButton(
                    onPressed: _resetZoom,
                    icon: const Icon(Icons.restart_alt),
                    color: Colors.white,
                    tooltip: '重設縮放',
                  ),
                  IconButton(
                    onPressed: () => _setScale(_scale - _scaleStep),
                    icon: const Icon(Icons.zoom_out),
                    color: Colors.white,
                    tooltip: '縮小',
                  ),
                  IconButton(
                    onPressed: () => _setScale(_scale + _scaleStep),
                    icon: const Icon(Icons.zoom_in),
                    color: Colors.white,
                    tooltip: '放大',
                  ),
                  const Spacer(),
                  Text(
                    '${_scale.toStringAsFixed(1)}x',
                    style: const TextStyle(color: Colors.white),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                    color: Colors.white,
                    tooltip: '關閉',
                  ),
                ],
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return InteractiveViewer(
                    transformationController: _controller,
                    minScale: _minScale,
                    maxScale: _maxScale,
                    boundaryMargin: const EdgeInsets.all(120),
                    child: SizedBox(
                      width: constraints.maxWidth,
                      height: constraints.maxHeight,
                      child: Center(child: _buildImage()),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 18),
              child: Slider(
                value: _scale.clamp(_minScale, _maxScale),
                min: _minScale,
                max: _maxScale,
                divisions: 16,
                label: '${_scale.toStringAsFixed(1)}x',
                activeColor: Colors.white,
                inactiveColor: Colors.white.withValues(alpha: 0.28),
                onChanged: _setScale,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImage() {
    final imageBytes = widget.imageBytes;
    if (imageBytes != null && imageBytes.isNotEmpty) {
      return Image.memory(
        imageBytes,
        fit: BoxFit.contain,
        alignment: Alignment.center,
      );
    }

    final imageFile = widget.imageFile;
    if (imageFile != null) {
      return Image.file(
        imageFile,
        fit: BoxFit.contain,
        alignment: Alignment.center,
      );
    }

    return const SizedBox.shrink();
  }

  void _setScale(double scale) {
    final nextScale = scale.clamp(_minScale, _maxScale).toDouble();
    _controller.value = Matrix4.identity()
      ..scaleByDouble(nextScale, nextScale, nextScale, 1);
  }

  void _resetZoom() {
    _controller.value = Matrix4.identity();
  }

  void _syncScale() {
    final nextScale = _controller.value
        .getMaxScaleOnAxis()
        .clamp(_minScale, _maxScale)
        .toDouble();
    if ((nextScale - _scale).abs() < 0.01) {
      return;
    }
    setState(() {
      _scale = nextScale;
    });
  }
}
