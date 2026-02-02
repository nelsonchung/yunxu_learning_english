import 'package:flutter/material.dart';

import '../../domain/services/sort_service.dart';

class SortSelector extends StatelessWidget {
  const SortSelector({
    super.key,
    required this.mode,
    required this.onChanged,
  });

  final SortMode mode;
  final ValueChanged<SortMode> onChanged;

  String _labelFor(SortMode mode) {
    switch (mode) {
      case SortMode.alphabetAsc:
        return 'A → Z';
      case SortMode.alphabetDesc:
        return 'Z → A';
      case SortMode.createdAtDesc:
        return '新 → 舊';
      case SortMode.createdAtAsc:
        return '舊 → 新';
    }
  }

  @override
  Widget build(BuildContext context) {
    return DropdownButton<SortMode>(
      value: mode,
      onChanged: (value) {
        if (value != null) {
          onChanged(value);
        }
      },
      items: SortMode.values
          .map(
            (item) => DropdownMenuItem(
              value: item,
              child: Text(_labelFor(item)),
            ),
          )
          .toList(),
    );
  }
}
