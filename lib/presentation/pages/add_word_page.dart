import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../domain/models/word_card.dart';
import '../state/words_notifier.dart';
import '../state/settings_notifier.dart';
import '../widgets/app_background.dart';
import '../widgets/image_preview.dart';
import '../widgets/section_card.dart';
import '../widgets/sentence_field_list.dart';

class AddWordPage extends StatefulWidget {
  const AddWordPage({super.key});

  @override
  State<AddWordPage> createState() => _AddWordPageState();
}

class _AddWordPageState extends State<AddWordPage> {
  final _wordController = TextEditingController();
  final _meaningController = TextEditingController();
  final List<TextEditingController> _sentenceControllers = [
    TextEditingController(),
  ];
  final _picker = ImagePicker();

  File? _imageFile;
  bool _isSaving = false;
  PartOfSpeech _partOfSpeech = PartOfSpeech.noun;

  @override
  void dispose() {
    _wordController.dispose();
    _meaningController.dispose();
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
    if (!_picker.supportsImageSource(source)) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('此裝置不支援該圖片來源')));
      return;
    }
    try {
      final picked = await _picker.pickImage(
        source: source,
        imageQuality: 80,
        maxWidth: 1600,
        maxHeight: 1600,
      );
      if (picked == null) {
        return;
      }
      setState(() {
        _imageFile = File(picked.path);
      });
    } on PlatformException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('無法選擇圖片：${error.message ?? error.code}')),
      );
    } on StateError catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('無法使用此來源：${error.message}')));
    }
  }

  void _showImagePicker() {
    final supportsCamera = _picker.supportsImageSource(ImageSource.camera);
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
              if (supportsCamera)
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
    final meaning = _meaningController.text.trim();
    final sentences = _sentenceControllers
        .map((controller) => controller.text.trim())
        .where((text) => text.isNotEmpty)
        .toList();

    if (word.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('請輸入單字')));
      return;
    }

    if (meaning.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('請輸入中文意義')));
      return;
    }

    if (sentences.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('請至少輸入一個句子')));
      return;
    }

    setState(() {
      _isSaving = true;
    });

    final notifier = context.read<WordsNotifier>();
    await notifier.addWord(
      word: word,
      meaning: meaning,
      partOfSpeech: _partOfSpeech,
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
      appBar: AppBar(title: const Text('新增單字')),
      body: AppBackground(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
            children: [
              SectionCard(
                title: '英文單字',
                subtitle: '輸入你要記住的單字',
                child: TextField(
                  controller: _wordController,
                  decoration: const InputDecoration(hintText: '例如：inspiration'),
                ),
              ),
              const SizedBox(height: 16),
              SectionCard(
                title: '中文意義',
                subtitle: '輸入單字的中文解釋',
                child: TextField(
                  controller: _meaningController,
                  decoration: const InputDecoration(hintText: '例如：靈感'),
                  minLines: 2,
                  maxLines: 4,
                ),
              ),
              const SizedBox(height: 16),
              SectionCard(
                title: '詞性',
                subtitle: '選擇此單字的詞性',
                child: DropdownButtonFormField<PartOfSpeech>(
                  value: _partOfSpeech,
                  items: PartOfSpeech.values
                      .map(
                        (item) => DropdownMenuItem(
                          value: item,
                          child: Text(item.label),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }
                    setState(() {
                      _partOfSpeech = value;
                    });
                  },
                  decoration: const InputDecoration(),
                ),
              ),
              const SizedBox(height: 16),
              SectionCard(
                title: '例句',
                subtitle: '至少輸入一個例句',
                child: SentenceFieldList(
                  controllers: _sentenceControllers,
                  onAdd: _addSentence,
                  onRemove: _removeSentence,
                ),
              ),
              const SizedBox(height: 16),
              if (context.watch<SettingsNotifier>().showImages) ...[
                SectionCard(
                  title: '圖片',
                  subtitle: '可選擇相關圖片幫助記憶',
                  child: Column(
                    children: [
                      ImagePreview(imageFile: _imageFile),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: _showImagePicker,
                          icon: const Icon(Icons.image_outlined),
                          label: const Text('選擇圖片'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 20),
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
      ),
    );
  }
}
