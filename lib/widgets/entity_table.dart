import 'package:flutter/material.dart';

class TableColumnSpec<T> {
  final String label;
  final String? sortField;
  final String? fieldKey;
  final bool numeric;
  final Widget Function(T item) build;

  const TableColumnSpec({
    required this.label,
    required this.build,
    this.sortField,
    this.fieldKey,
    this.numeric = false,
  });
}

class EntityTable<T> extends StatefulWidget {
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
  State<EntityTable<T>> createState() => _EntityTableState<T>();
}

class _EntityTableState<T> extends State<EntityTable<T>> {
  final _horizontal = ScrollController();
  final _vertical = ScrollController();

  @override
  void dispose() {
    _horizontal.dispose();
    _vertical.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final columns = widget.columns;
    final items = widget.items;
    final idOf = widget.idOf;
    final selected = widget.selected;
    final onToggleSelect = widget.onToggleSelect;
    final onSelectAll = widget.onSelectAll;
    final isSelectable = widget.isSelectable;
    final sortField = widget.sortField;
    final sortAscending = widget.sortAscending;
    final onSort = widget.onSort;
    final actions = widget.actions;
    final dataColumns = <DataColumn>[
      for (final column in columns)
        DataColumn(
          label: Tooltip(
            message: column.sortField == null
                ? column.label
                : 'Сортировать: ${column.label}',
            child: Text(column.label),
          ),
          numeric: column.numeric,
          onSort: column.sortField == null || onSort == null
              ? null
              : (_, _) => onSort(column.sortField!),
        ),
      if (actions != null) const DataColumn(label: Text('Действия')),
    ];
    final activeSortIndex = columns.indexWhere((c) => c.sortField == sortField);

    return LayoutBuilder(
      builder: (context, constraints) => Scrollbar(
        controller: _horizontal,
        thumbVisibility: true,
        notificationPredicate: (notification) => notification.depth == 0,
        child: SingleChildScrollView(
          controller: _horizontal,
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            height: constraints.maxHeight,
            child: Scrollbar(
              controller: _vertical,
              thumbVisibility: true,
              child: SingleChildScrollView(
                controller: _vertical,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: constraints.maxWidth),
                  child: DataTable(
                    showCheckboxColumn: onToggleSelect != null,
                    sortColumnIndex: activeSortIndex < 0
                        ? null
                        : activeSortIndex,
                    sortAscending: sortAscending,
                    onSelectAll: onSelectAll == null
                        ? null
                        : (value) => onSelectAll(value ?? false),
                    columns: dataColumns,
                    rows: items.map((item) {
                      final id = idOf(item);
                      final selectable = isSelectable?.call(item) ?? true;
                      return DataRow(
                        selected: selected.contains(id),
                        onSelectChanged: onToggleSelect == null || !selectable
                            ? null
                            : (_) => onToggleSelect(id),
                        cells: [
                          for (final column in columns)
                            DataCell(column.build(item)),
                          if (actions != null)
                            DataCell(
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: actions(item),
                              ),
                            ),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
