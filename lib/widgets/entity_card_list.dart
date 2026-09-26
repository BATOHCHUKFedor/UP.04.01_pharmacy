import 'package:flutter/material.dart';

class CardFieldSpec<T> {
  final String label;
  final String Function(T item) value;
  const CardFieldSpec({required this.label, required this.value});
}

class EntityCardList<T> extends StatelessWidget {
  final List<T> items;
  final int Function(T item) idOf;
  final String Function(T item) titleOf;
  final List<CardFieldSpec<T>> fields;
  final Set<int> selected;
  final ValueChanged<int>? onToggleSelect;
  final bool Function(T item)? isSelectable;
  final List<Widget> Function(T item) actions;
  final bool Function(T item)? isDeleted;

  const EntityCardList({
    super.key,
    required this.items,
    required this.idOf,
    required this.titleOf,
    required this.fields,
    required this.actions,
    this.selected = const {},
    this.onToggleSelect,
    this.isSelectable,
    this.isDeleted,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 12),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final item = items[index];
        final id = idOf(item);
        final deleted = isDeleted?.call(item) ?? false;
        final selectable = isSelectable?.call(item) ?? true;
        return Card(
          color: deleted
              ? Theme.of(
                  context,
                ).colorScheme.errorContainer.withValues(alpha: 0.35)
              : null,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (onToggleSelect != null)
                      Checkbox(
                        value: selected.contains(id),
                        onChanged: selectable
                            ? (_) => onToggleSelect!(id)
                            : null,
                      ),
                    Expanded(
                      child: Text(
                        titleOf(item),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    if (deleted) const Chip(label: Text('Удалён')),
                  ],
                ),
                for (final field in fields)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('${field.label}: ${field.value(item)}'),
                  ),
                Align(
                  alignment: Alignment.centerRight,
                  child: Wrap(spacing: 4, children: actions(item)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
