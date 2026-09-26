import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/supplier.dart';
import '../models/supplier_query.dart';
import '../state/supplier_list_notifier.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/entity_card_list.dart';
import '../widgets/entity_table.dart';
import '../widgets/pagination_bar.dart';
import '../widgets/screen_state_view.dart';

class SupplierListScreen extends StatefulWidget {
  final SupplierQuery query;
  const SupplierListScreen({super.key, required this.query});

  @override
  State<SupplierListScreen> createState() => _SupplierListScreenState();
}

class _SupplierListScreenState extends State<SupplierListScreen> {
  late final TextEditingController _searchController;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: widget.query.search);
    _applyRouteQuery();
  }

  @override
  void didUpdateWidget(covariant SupplierListScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.query != widget.query) {
      if (_searchController.text != widget.query.search) {
        _searchController.value = TextEditingValue(
          text: widget.query.search,
          selection: TextSelection.collapsed(
            offset: widget.query.search.length,
          ),
        );
      }
      _applyRouteQuery();
    }
  }

  void _applyRouteQuery() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<SupplierListNotifier>().applyQuery(widget.query);
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _navigate(SupplierQuery query) {
    context.go(
      Uri(path: '/suppliers', queryParameters: query.toParameters()).toString(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final notifier = context.watch<SupplierListNotifier>();
    return AppScaffold(
      title: 'Поставщики',
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SizedBox(
                      width: 340,
                      child: TextField(
                        controller: _searchController,
                        onChanged: (value) {
                          _debounce?.cancel();
                          _debounce = Timer(
                            const Duration(milliseconds: 400),
                            () =>
                                _navigate(widget.query.copyWith(search: value)),
                          );
                        },
                        decoration: const InputDecoration(
                          labelText: 'Название, контактное лицо или страна',
                          prefixIcon: Icon(Icons.search),
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Switch(
                          value: widget.query.includeDeleted,
                          onChanged: (value) => _navigate(
                            widget.query.copyWith(includeDeleted: value),
                          ),
                        ),
                        const Text('Показывать удалённых'),
                      ],
                    ),
                    OutlinedButton.icon(
                      onPressed: () {
                        _debounce?.cancel();
                        _navigate(const SupplierQuery());
                      },
                      icon: const Icon(Icons.filter_alt_off),
                      label: const Text('Сбросить'),
                    ),
                  ],
                ),
              ),
            ),
            if (notifier.hasSelection)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('Выбрано: ${notifier.selected.length}'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: () => _deleteSelected(context, notifier),
                      icon: const Icon(Icons.delete_sweep_outlined),
                      label: const Text('Удалить выбранных'),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            Expanded(
              child: ScreenStateView(
                status: notifier.status,
                error: notifier.error,
                isEmpty: notifier.result.items.isEmpty,
                emptyMessage: 'Поставщики по заданным условиям не найдены',
                onRetry: notifier.load,
                child: Column(
                  children: [
                    Expanded(child: _buildResults(context, notifier)),
                    PaginationBar(
                      page: notifier.result.page,
                      totalPages: notifier.result.totalPages,
                      totalItems: notifier.result.total,
                      pageSize: notifier.result.size,
                      onPageChanged: (page) =>
                          _navigate(widget.query.copyWith(page: page)),
                      onPageSizeChanged: (size) =>
                          _navigate(widget.query.copyWith(size: size)),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResults(BuildContext context, SupplierListNotifier notifier) {
    final items = notifier.result.items;
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 600) {
          return EntityCardList<Supplier>(
            items: items,
            idOf: (supplier) => supplier.id,
            titleOf: (supplier) => supplier.name,
            selected: notifier.selected,
            onToggleSelect: notifier.toggleSelection,
            isSelectable: (supplier) => !supplier.isDeleted,
            isDeleted: (supplier) => supplier.isDeleted,
            fields: [
              CardFieldSpec(
                label: 'Контакт',
                value: (supplier) => supplier.contactPerson,
              ),
              CardFieldSpec(
                label: 'Страна',
                value: (supplier) => supplier.country,
              ),
              CardFieldSpec(
                label: 'Сотрудничаем с',
                value: (supplier) => '${supplier.partnershipYear} года',
              ),
            ],
            actions: (supplier) =>
                _supplierActions(context, notifier, supplier),
          );
        }
        return EntityTable<Supplier>(
          items: items,
          idOf: (supplier) => supplier.id,
          selected: notifier.selected,
          onToggleSelect: notifier.toggleSelection,
          onSelectAll: (selected) => notifier.togglePageSelection(
            items
                .where((supplier) => !supplier.isDeleted)
                .map((supplier) => supplier.id),
            selected,
          ),
          isSelectable: (supplier) => !supplier.isDeleted,
          sortField: widget.query.sortField,
          sortAscending: widget.query.sortAscending,
          onSort: (field) => _navigate(
            widget.query.copyWith(
              sortField: field,
              sortAscending: field == widget.query.sortField
                  ? !widget.query.sortAscending
                  : true,
            ),
          ),
          columns: [
            TableColumnSpec(
              label: 'Название',
              sortField: 'name',
              build: (supplier) => Text(supplier.name),
            ),
            TableColumnSpec(
              label: 'Контактное лицо',
              build: (supplier) => Text(supplier.contactPerson),
            ),
            TableColumnSpec(
              label: 'Страна',
              sortField: 'country',
              build: (supplier) => Text(supplier.country),
            ),
            TableColumnSpec(
              label: 'Сотрудничество с',
              sortField: 'partnershipYear',
              numeric: true,
              build: (supplier) => Text('${supplier.partnershipYear}'),
            ),
            TableColumnSpec(
              label: 'Телефон',
              build: (supplier) => Text(supplier.phone),
            ),
          ],
          actions: (supplier) => _supplierActions(context, notifier, supplier),
        );
      },
    );
  }

  List<Widget> _supplierActions(
    BuildContext context,
    SupplierListNotifier notifier,
    Supplier supplier,
  ) => [
    IconButton(
      tooltip: 'Открыть карточку',
      onPressed: () => context.push('/suppliers/${supplier.id}'),
      icon: const Icon(Icons.visibility_outlined),
    ),
    if (supplier.isDeleted)
      IconButton(
        tooltip: 'Восстановить',
        onPressed: () async {
          await notifier.restore(supplier.id);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Поставщик восстановлен')),
            );
          }
        },
        icon: const Icon(Icons.restore),
      )
    else
      IconButton(
        tooltip: 'Логическое удаление',
        onPressed: () => _deleteOne(context, notifier, supplier, hard: false),
        icon: const Icon(Icons.delete_outline),
      ),
    IconButton(
      tooltip: 'Удалить навсегда',
      onPressed: () => _deleteOne(context, notifier, supplier, hard: true),
      icon: const Icon(Icons.delete_forever_outlined),
    ),
  ];

  Future<void> _deleteOne(
    BuildContext context,
    SupplierListNotifier notifier,
    Supplier supplier, {
    required bool hard,
  }) async {
    final confirmed = await confirmAction(
      context,
      title: hard ? 'Удалить поставщика навсегда?' : 'Удалить поставщика?',
      message: hard
          ? '«${supplier.name}» будет физически удалён без возможности восстановления.'
          : '«${supplier.name}» исчезнет из обычной выборки, но его можно будет восстановить.',
    );
    if (!confirmed) return;
    hard
        ? await notifier.hardDelete(supplier.id)
        : await notifier.softDelete(supplier.id);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            hard ? 'Поставщик удалён навсегда' : 'Поставщик удалён',
          ),
        ),
      );
    }
  }

  Future<void> _deleteSelected(
    BuildContext context,
    SupplierListNotifier notifier,
  ) async {
    final count = notifier.selected.length;
    final confirmed = await confirmAction(
      context,
      title: 'Удалить выбранных поставщиков?',
      message:
          'Будет логически удалено записей: $count. Их можно восстановить.',
    );
    if (!confirmed) return;
    final deleted = await notifier.deleteSelected();
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Удалено записей: $deleted')));
    }
  }
}
