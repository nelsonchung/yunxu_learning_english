import 'package:flutter/material.dart';

import '../../domain/models/word_card.dart';

class CustomTagEditor extends StatefulWidget {
  const CustomTagEditor({
    super.key,
    required this.tags,
    required this.onChanged,
    this.suggestions = const [],
  });

  final List<String> tags;
  final ValueChanged<List<String>> onChanged;
  final List<String> suggestions;

  @override
  State<CustomTagEditor> createState() => _CustomTagEditorState();
}

class _CustomTagEditorState extends State<CustomTagEditor> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _addFromInput() {
    final rawInput = _controller.text;
    final candidates = rawInput
        .split(RegExp(r'[,，、;\n；]+'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);

    if (candidates.isEmpty) {
      _showMessage('請先輸入標籤');
      return;
    }

    final nextTags = WordCard.normalizeCustomTags([
      ...widget.tags,
      ...candidates,
    ]);
    if (nextTags.length == widget.tags.length) {
      _showMessage('標籤已存在');
      return;
    }

    widget.onChanged(nextTags);
    _controller.clear();
  }

  void _addSuggestion(String tag) {
    final nextTags = WordCard.normalizeCustomTags([...widget.tags, tag]);
    if (nextTags.length == widget.tags.length) {
      return;
    }
    widget.onChanged(nextTags);
  }

  void _removeTag(String tag) {
    widget.onChanged(
      widget.tags.where((item) => item != tag).toList(growable: false),
    );
  }

  @override
  Widget build(BuildContext context) {
    final suggestionTags = WordCard.normalizeCustomTags(widget.suggestions)
        .where((tag) => !widget.tags.contains(tag))
        .take(12)
        .toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _addFromInput(),
                decoration: const InputDecoration(hintText: '例如：課本A 第3課、期中考'),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonal(
              onPressed: _addFromInput,
              child: const Text('加入'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '可一次輸入多個標籤，支援逗號或換行分隔。',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: Colors.black54),
        ),
        if (widget.tags.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: widget.tags
                .map(
                  (tag) => InputChip(
                    label: Text(tag),
                    onDeleted: () => _removeTag(tag),
                  ),
                )
                .toList(growable: false),
          ),
        ],
        if (suggestionTags.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            '快速加入',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: Colors.black54),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: suggestionTags
                .map(
                  (tag) => ActionChip(
                    label: Text(tag),
                    onPressed: () => _addSuggestion(tag),
                  ),
                )
                .toList(growable: false),
          ),
        ],
      ],
    );
  }
}
