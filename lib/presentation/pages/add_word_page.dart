import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../state/words_notifier.dart';
import '../widgets/sentence_field_list.dart';

class AddWordPage extends StatefulWidget {
  const AddWordPage({super.key});

  @override
  State<AddWordPage> createState() => _AddWordPageState();
}

class _AddWordPageState extends State<AddWordPage> {
  final _wordController = TextEditingController();
  final List<TextEditingController> _sentenceControllers = [
    TextEditingController(),
  ];
  final _picker = ImagePicker();

  File? _imageFile;
  bool _isSaving = false;

  @override
  void dispose() {
    _wordController.dispose();
    for (final controller in _sentenceControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _addSentence() {
    setState(() {
      _sentenceControllers.add(TextEditingController());
    });
  }

  void _removeSentence(int index) {
    if (_sentenceControllers.length <= 1) {
      return;
    }
    setState(() {
      final controller = _sentenceControllers.removeAt(index);
      controller.dispose();
    });
  }

  Future<void> _pickImage(ImageSource source) async {
    final picked = await _picker.pickImage(source: source, imageQuality: 85);
    if (picked == null) {
      return;
    }
    setState(() {
      _imageFile = File(picked.path);
    });
  }

  void _showImagePicker() {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('從相簿選擇'),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.gallery);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_camera),
                title: const Text('使用相機拍照'),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.camera);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _save() async {
    final word = _wordController.text.trim();
    final sentences = _sentenceControllers
        .map((controller) => controller.text.trim())
        .where((text) => text.isNotEmpty)
        .toList();

    if (word.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('請輸入單字')));
      return;
    }

    if (sentences.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('請至少輸入一個句子')));
      return;
    }

    setState(() {
      _isSaving = true;
    });

    final notifier = context.read<WordsNotifier>();
    await notifier.addWord(
      word: word,
      sentences: sentences,
      imageFile: _imageFile,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _isSaving = false;
    });

    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('新增單字'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('單字'),
            const SizedBox(height: 8),
            TextField(
              controller: _wordController,
              decoration: const InputDecoration(
                hintText: '請輸入英文單字',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            SentenceFieldList(
              controllers: _sentenceControllers,
              onAdd: _addSentence,
              onRemove: _removeSentence,
            ),
            const SizedBox(height: 16),
            const Text('圖片'),
            const SizedBox(height: 8),
            if (_imageFile != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(
                  _imageFile!,
                  width: double.infinity,
                  height: 180,
                  fit: BoxFit.cover,
                ),
              )
            else
              Container(
                height: 120,
                width: double.infinity,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('尚未選擇圖片'),
              ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _showImagePicker,
              icon: const Icon(Icons.image),
              label: const Text('選擇圖片'),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _save,
                child: _isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('儲存'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
