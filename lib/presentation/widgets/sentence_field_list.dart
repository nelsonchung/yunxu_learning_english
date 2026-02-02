import 'package:flutter/material.dart';

class SentenceFieldList extends StatelessWidget {
  const SentenceFieldList({
    super.key,
    required this.controllers,
    required this.onAdd,
    required this.onRemove,
  });

  final List<TextEditingController> controllers;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('例句'),
        const SizedBox(height: 8),
        for (var i = 0; i < controllers.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controllers[i],
                    decoration: InputDecoration(
                      labelText: '句子 ${i + 1}',
                      border: const OutlineInputBorder(),
                    ),
                    maxLines: 2,
                  ),
                ),
                const SizedBox(width: 8),
                if (controllers.length > 1)
                  IconButton(
                    onPressed: () => onRemove(i),
                    icon: const Icon(Icons.close),
                    tooltip: '刪除句子',
                  ),
              ],
            ),
          ),
        TextButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.add),
          label: const Text('新增句子'),
        ),
      ],
    );
  }
}
