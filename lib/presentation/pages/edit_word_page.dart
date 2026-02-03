import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../domain/models/word_card.dart';
import '../state/words_notifier.dart';
import '../widgets/app_background.dart';
import '../widgets/image_preview.dart';
import '../widgets/section_card.dart';
import '../widgets/sentence_field_list.dart';

class EditWordPage extends StatefulWidget {
  const EditWordPage({super.key});

  @override
  State<EditWordPage> createState() => _EditWordPageState();
}

class _EditWordPageState extends State<EditWordPage> {
  final _wordController = TextEditingController();
  final _meaningController = TextEditingController();
  final List<TextEditingController> _sentenceControllers = [];
  final _picker = ImagePicker();

  File? _imageFile;
  String? _existingImagePath;
  List<int>? _existingImageBytes;
  bool _removeImage = false;
  bool _isSaving = false;
  PartOfSpeech _partOfSpeech = PartOfSpeech.noun;
  WordCard? _card;
  bool _initialized = false;

  @override
  void dispose() {
    _wordController.dispose();
    _meaningController.dispose();
    for (final controller in _sentenceControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) {
      return;
    }

    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is String) {
      _card = context.read<WordsNotifier>().findById(args);
    } else if (args is WordCard) {
      _card = args;
    }

    final card = _card;
    if (card != null) {
      _wordController.text = card.word;
      _meaningController.text = card.meaning;
      _partOfSpeech = card.partOfSpeech;
      _existingImagePath = card.imagePath;
      _existingImageBytes = card.imageBytes;
      final sentences = card.sentences.isEmpty ? [''] : card.sentences;
      _sentenceControllers
        ..clear()
        ..addAll(
          sentences.map((sentence) => TextEditingController(text: sentence)),
        );
    }

    _initialized = true;
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
      _existingImageBytes = null;
      _existingImagePath = null;
      _removeImage = false;
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
              if (_existingImagePath != null || _imageFile != null)
                ListTile(
                  leading: const Icon(Icons.delete_outline),
                  title: const Text('移除圖片'),
                  onTap: () {
                    Navigator.pop(context);
                    setState(() {
                      _imageFile = null;
                      _existingImagePath = null;
                      _existingImageBytes = null;
                      _removeImage = true;
                    });
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _save() async {
    final card = _card;
    if (card == null) {
      return;
    }

    final word = _wordController.text.trim();
    final meaning = _meaningController.text.trim();
    final sentences = _sentenceControllers
        .map((controller) => controller.text.trim())
        .where((text) => text.isNotEmpty)
        .toList();

    if (word.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('請輸入單字')));
      return;
    }

    if (meaning.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('請輸入中文意義')));
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
    await notifier.updateWord(
      card: card,
      word: word,
      meaning: meaning,
      partOfSpeech: _partOfSpeech,
      sentences: sentences,
      imageFile: _imageFile,
      removeImage: _removeImage,
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
    if (_card == null) {
      return const Scaffold(
        body: Center(child: Text('找不到單字資料')),
      );
    }

    final imagePath = _imageFile?.path ?? _existingImagePath;
    final imageBytes = _imageFile == null ? _existingImageBytes : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('編輯單字'),
      ),
      body: AppBackground(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
            children: [
              SectionCard(
                title: '英文單字',
                subtitle: '修改單字拼寫',
                child: TextField(
                  controller: _wordController,
                  decoration: const InputDecoration(
                    hintText: '例如：inspiration',
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SectionCard(
                title: '中文意義',
                subtitle: '修改中文解釋',
                child: TextField(
                  controller: _meaningController,
                  decoration: const InputDecoration(
                    hintText: '例如：靈感',
                  ),
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
              SectionCard(
                title: '圖片',
                subtitle: '可選擇相關圖片幫助記憶',
                child: Column(
                  children: [
                    ImagePreview(
                      imageFile: _imageFile,
                      imagePath: imagePath,
                      imageBytes: imageBytes,
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: _showImagePicker,
                        icon: const Icon(Icons.image_outlined),
                        label: const Text('變更圖片'),
                      ),
                    ),
                  ],
                ),
              ),
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
                      : const Text('儲存修改'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
