import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:provider/provider.dart';

import '../../domain/models/word_card.dart';
import '../../domain/services/online_picture_service.dart';
import '../state/words_notifier.dart';
import 'image_preview.dart';

class OnlinePictureButton extends StatefulWidget {
  const OnlinePictureButton({
    super.key,
    required this.card,
    required this.service,
  });
  final WordCard card;
  final OnlinePictureService service;

  @override
  State<OnlinePictureButton> createState() => _OnlinePictureButtonState();
}

class _OnlinePictureButtonState extends State<OnlinePictureButton> {
  bool _busy = false;
  String? _message;

  Future<void> _download() async {
    if (_busy) return;
    final snapshot = widget.card;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final picture = await widget.service.download(snapshot.word);
      if (!mounted) return;
      if (picture == null) {
        setState(() => _message = '這個單字尚未提供線上圖片，可日後再試');
        return;
      }
      final apply = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('${snapshot.word} 線上圖片'),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ImagePreview(
                    imageFile: null,
                    imageBytes: picture.bytes,
                    height: 300,
                    enableZoom: true,
                  ),
                  const SizedBox(height: 12),
                  const Text('請確認圖片符合這個單字的意思。套用會替換目前圖片，之後可離線查看。'),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('套用圖片'),
            ),
          ],
        ),
      );
      if (apply != true || !mounted) return;
      final words = context.read<WordsNotifier>();
      await words.updateWordImage(
        snapshot.id,
        picture.bytes,
        expectedCard: snapshot,
      );
      final saved = words.findById(snapshot.id);
      var sourceSaved = true;
      if (saved?.imagePath != null) {
        try {
          await widget.service.saveSource?.call(
            path.basename(saved!.imagePath!),
            picture.url.toString(),
          );
        } catch (_) {
          sourceSaved = false;
        }
      }
      if (mounted) {
        setState(
          () => _message = sourceSaved ? '圖片已套用，可離線查看' : '圖片已套用，但來源資訊保存失敗',
        );
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _message = error is OnlinePictureException
              ? error.message
              : '圖片未套用，單字可能已變更或暫時無法儲存，請重試',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      OutlinedButton.icon(
        onPressed: _busy ? null : _download,
        icon: _busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.cloud_download_outlined),
        label: Text(_busy ? '正在取得線上圖片…' : '下載線上圖片'),
      ),
      if (_message != null)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(_message!, semanticsLabel: _message),
        ),
      const SizedBox(height: 8),
    ],
  );
}
