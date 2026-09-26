import 'package:flutter/material.dart';

class TableColumnSpec<T> {
  final String label;
  final String? sortField;
  final bool numeric;
  final Widget Function(T item) build;

  const TableColumnSpec({
    required this.label,
    required this.build,
    this.sortField,
    this.numeric = false,
  });
}

class EntityTable<T> extends StatelessWidget {
  final List<TableColumnSpec<T>> columns;
  final List<T> items;
  final int Function(T item) idOf;
  final Set<int> selected;
  final ValueChanged<int>? onToggleSelect;
  final ValueChanged<bool>? onSelectAll;
  final bool Function(T item)? isSelectable;
  final String? sortField;
  final bool sortAscending;
  final ValueChanged<String>? onSort;
  final List<Widget> Function(T item)? actions;

  const EntityTable({
    super.key,
    required this.columns,
    required this.items,
    required this.idOf,
    this.selected = const {},
    this.onToggleSelect,
    this.onSelectAll,
    this.isSelectable,
    this.sortField,
    this.sortAscending = true,
    this.onSort,
    this.actions,
  });

  @override
  Widget build(BuildContext context) {
    final dataColumns = <DataColumn>[
      for (final column in columns)
        DataColumn(
          label: Text(column.label),
          numeric: column.numeric,
          onSort: column.sortField == null || onSort == null
              ? null
              : (_, _) => onSort!(column.sortField!),
        ),
      if (actions != null) const DataColumn(label: Text('Действия')),
    ];
    final activeSortIndex = columns.indexWhere((c) => c.sortField == sortField);

    return SingleChildScrollView(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          showCheckboxColumn: onToggleSelect != null,
          sortColumnIndex: activeSortIndex < 0 ? null : activeSortIndex,
          sortAscending: sortAscending,
          onSelectAll: onSelectAll == null
              ? null
              : (value) => onSelectAll!(value ?? false),
          columns: dataColumns,
          rows: items.map((item) {
            final id = idOf(item);
            final selectable = isSelectable?.call(item) ?? true;
            return DataRow(
              selected: selected.contains(id),
              onSelectChanged: onToggleSelect == null || !selectable
                  ? null
                  : (_) => onToggleSelect!(id),
              cells: [
                for (final column in columns) DataCell(column.build(item)),
                if (actions != null)
                  DataCell(
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: actions!(item),
                    ),
                  ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }
}
