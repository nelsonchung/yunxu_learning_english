import 'package:flutter/material.dart';

class SentenceFieldList extends StatelessWidget {
  const SentenceFieldList({
    super.key,
    required this.controllers,
    required this.onAdd,
    required this.onRemove,
    required this.onReorder,
  });

  final List<TextEditingController> controllers;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;
  final ReorderCallback onReorder;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          itemCount: controllers.length,
          onReorder: onReorder,
          itemBuilder: (context, i) {
            return Padding(
              key: ValueKey(controllers[i]),
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
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
                  if (controllers.length > 1) ...[
                    ReorderableDragStartListener(
                      index: i,
                      child: const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Icon(Icons.drag_indicator, size: 20),
                      ),
                    ),
                    IconButton(
                      onPressed: () => onRemove(i),
                      icon: const Icon(Icons.close),
                      tooltip: '刪除句子',
                    ),
                  ],
                ],
              ),
            );
          },
        ),
        OutlinedButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.add),
          label: const Text('新增句子'),
        ),
      ],
    );
  }
}
