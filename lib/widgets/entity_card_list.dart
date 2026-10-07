import 'package:flutter/material.dart';
import 'responsive_cards.dart';

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
    return ResponsiveCards(
      padding: const EdgeInsets.only(bottom: 12),
      children: items.map((item) {
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
                        semanticLabel: 'Выбрать ${titleOf(item)}',
                        value: selected.contains(id),
                        onChanged: selectable
                            ? (_) => onToggleSelect!(id)
                            : null,
                      ),
                    Expanded(
                      child: Text(
                        titleOf(item),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    if (deleted) const Chip(label: Text('Удалён')),
                  ],
                ),
                for (final field in fields)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Tooltip(
                      message: '${field.label}: ${field.value(item)}',
                      child: Text(
                        '${field.label}: ${field.value(item)}',
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                Align(
                  alignment: Alignment.centerRight,
                  child: Wrap(spacing: 4, children: actions(item)),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}
