import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/drug.dart';
import '../models/drug_query.dart';
import '../state/drug_list_notifier.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/entity_card_list.dart';
import '../widgets/entity_table.dart';
import '../widgets/pagination_bar.dart';
import '../widgets/screen_state_view.dart';

class DrugListScreen extends StatefulWidget {
  final DrugQuery query;
  const DrugListScreen({super.key, required this.query});

  @override
  State<DrugListScreen> createState() => _DrugListScreenState();
}

class _DrugListScreenState extends State<DrugListScreen> {
  late final TextEditingController _searchController;
  late final TextEditingController _yearFromController;
  late final TextEditingController _yearToController;
  Timer? _searchDebounce;
  Timer? _yearDebounce;

  static const _categories = [
    'Анальгетики',
    'Противовоспалительные',
    'Антибиотики',
    'Антигистаминные',
    'ЖКТ',
    'Сердечно-сосудистые',
  ];

  static const _supplierNames = {
    1: 'Фармстандарт',
    2: 'Bayer',
    3: 'KRKA',
    4: 'Гедеон Рихтер',
    5: 'Озон Фармацевтика',
    6: 'Sanofi',
    7: 'Sandoz',
    8: 'ПОЛИСАН',
    9: 'Teva',
    10: 'Dr. Reddy’s',
  };

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: widget.query.search);
    _yearFromController = TextEditingController(
      text: widget.query.yearFrom?.toString() ?? '',
    );
    _yearToController = TextEditingController(
      text: widget.query.yearTo?.toString() ?? '',
    );
    _applyRouteQuery();
  }

  @override
  void didUpdateWidget(covariant DrugListScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.query != widget.query) {
      _syncController(_searchController, widget.query.search);
      _syncController(
        _yearFromController,
        widget.query.yearFrom?.toString() ?? '',
      );
      _syncController(_yearToController, widget.query.yearTo?.toString() ?? '');
      _applyRouteQuery();
    }
  }

  void _applyRouteQuery() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<DrugListNotifier>().applyQuery(widget.query);
    });
  }

  void _syncController(TextEditingController controller, String value) {
    if (controller.text == value) return;
    controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _yearDebounce?.cancel();
    _searchController.dispose();
    _yearFromController.dispose();
    _yearToController.dispose();
    super.dispose();
  }

  void _navigate(DrugQuery query) {
    final uri = Uri(path: '/drugs', queryParameters: query.toParameters());
    context.go(uri.toString());
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(
      const Duration(milliseconds: 400),
      () => _navigate(widget.query.copyWith(search: value)),
    );
  }

  void _onYearsChanged() {
    _yearDebounce?.cancel();
    _yearDebounce = Timer(const Duration(milliseconds: 400), () {
      _navigate(
        widget.query.copyWith(
          yearFrom: int.tryParse(_yearFromController.text),
          yearTo: int.tryParse(_yearToController.text),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final notifier = context.watch<DrugListNotifier>();
    return AppScaffold(
      title: 'Препараты',
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildFilters(context),
            if (notifier.hasSelection) _buildSelectionBar(context, notifier),
            const SizedBox(height: 8),
            Expanded(
              child: ScreenStateView(
                status: notifier.status,
                error: notifier.error,
                isEmpty: notifier.result.items.isEmpty,
                emptyMessage: 'Препараты по заданным условиям не найдены',
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

  Widget _buildFilters(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      color: colors.surfaceContainerHighest.withValues(alpha: 0.45),
      child: ExpansionTile(
        initiallyExpanded: true,
        tilePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
        title: const Text('Поиск и фильтры'),
        childrenPadding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 300,
                child: TextField(
                  controller: _searchController,
                  onChanged: _onSearchChanged,
                  decoration: const InputDecoration(
                    labelText: 'Название или рег. номер',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              SizedBox(
                width: 230,
                child: DropdownButtonFormField<String?>(
                  key: ValueKey(widget.query.category),
                  initialValue: widget.query.category,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Категория',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: Text('Все категории'),
                    ),
                    ..._categories.map(
                      (value) => DropdownMenuItem(
                        value: value,
                        child: Text(value, overflow: TextOverflow.ellipsis),
                      ),
                    ),
                  ],
                  onChanged: (value) =>
                      _navigate(widget.query.copyWith(category: value)),
                ),
              ),
              SizedBox(
                width: 230,
                child: DropdownButtonFormField<int?>(
                  key: ValueKey(widget.query.supplierId),
                  initialValue: widget.query.supplierId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Поставщик',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: Text('Все поставщики'),
                    ),
                    ..._supplierNames.entries.map(
                      (entry) => DropdownMenuItem(
                        value: entry.key,
                        child: Text(
                          entry.value,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                  onChanged: (value) =>
                      _navigate(widget.query.copyWith(supplierId: value)),
                ),
              ),
              SizedBox(
                width: 130,
                child: TextField(
                  controller: _yearFromController,
                  onChanged: (_) => _onYearsChanged(),
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Год от',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              SizedBox(
                width: 130,
                child: TextField(
                  controller: _yearToController,
                  onChanged: (_) => _onYearsChanged(),
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Год до',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Switch(
                    value: widget.query.includeDeleted,
                    onChanged: (value) =>
                        _navigate(widget.query.copyWith(includeDeleted: value)),
                  ),
                  const Text('Показывать удалённые'),
                ],
              ),
              OutlinedButton.icon(
                onPressed: () {
                  _searchDebounce?.cancel();
                  _yearDebounce?.cancel();
                  _navigate(const DrugQuery());
                },
                icon: const Icon(Icons.filter_alt_off),
                label: const Text('Сбросить'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSelectionBar(BuildContext context, DrugListNotifier notifier) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Expanded(child: Text('Выбрано: ${notifier.selected.length}')),
          FilledButton.tonalIcon(
            onPressed: () => _deleteSelected(context, notifier),
            icon: const Icon(Icons.delete_sweep_outlined),
            label: const Text('Удалить выбранные'),
          ),
        ],
      ),
    );
  }

  Widget _buildResults(BuildContext context, DrugListNotifier notifier) {
    final items = notifier.result.items;
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 600) {
          return EntityCardList<Drug>(
            items: items,
            idOf: (drug) => drug.id,
            titleOf: (drug) => drug.name,
            selected: notifier.selected,
            onToggleSelect: notifier.toggleSelection,
            isSelectable: (drug) => !drug.isDeleted,
            isDeleted: (drug) => drug.isDeleted,
            fields: [
              CardFieldSpec(
                label: 'Рег. номер',
                value: (drug) => drug.registrationNumber,
              ),
              CardFieldSpec(label: 'Категория', value: (drug) => drug.category),
              CardFieldSpec(
                label: 'Год',
                value: (drug) => '${drug.productionYear}',
              ),
              CardFieldSpec(
                label: 'Цена',
                value: (drug) => '${drug.price.toStringAsFixed(2)} ₽',
              ),
            ],
            actions: (drug) => _drugActions(context, notifier, drug),
          );
        }
        return EntityTable<Drug>(
          items: items,
          idOf: (drug) => drug.id,
          selected: notifier.selected,
          onToggleSelect: notifier.toggleSelection,
          onSelectAll: (selected) => notifier.togglePageSelection(
            items.where((drug) => !drug.isDeleted).map((drug) => drug.id),
            selected,
          ),
          isSelectable: (drug) => !drug.isDeleted,
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
              build: (drug) => Text(drug.name),
            ),
            TableColumnSpec(
              label: 'Рег. номер',
              build: (drug) => Text(drug.registrationNumber),
            ),
            TableColumnSpec(
              label: 'Категория',
              build: (drug) => Text(drug.category),
            ),
            TableColumnSpec(
              label: 'Год',
              sortField: 'productionYear',
              numeric: true,
              build: (drug) => Text('${drug.productionYear}'),
            ),
            TableColumnSpec(
              label: 'Цена',
              sortField: 'price',
              numeric: true,
              build: (drug) => Text('${drug.price.toStringAsFixed(2)} ₽'),
            ),
            TableColumnSpec(
              label: 'Остаток',
              sortField: 'stock',
              numeric: true,
              build: (drug) => Text('${drug.stock}'),
            ),
          ],
          actions: (drug) => _drugActions(context, notifier, drug),
        );
      },
    );
  }

  List<Widget> _drugActions(
    BuildContext context,
    DrugListNotifier notifier,
    Drug drug,
  ) => [
    IconButton(
      tooltip: 'Открыть карточку',
      onPressed: () => context.push('/drugs/${drug.id}'),
      icon: const Icon(Icons.visibility_outlined),
    ),
    if (drug.isDeleted)
      IconButton(
        tooltip: 'Восстановить',
        onPressed: () async {
          await notifier.restore(drug.id);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Препарат восстановлен')),
            );
          }
        },
        icon: const Icon(Icons.restore),
      )
    else
      IconButton(
        tooltip: 'Логическое удаление',
        onPressed: () => _deleteOne(context, notifier, drug, hard: false),
        icon: const Icon(Icons.delete_outline),
      ),
    IconButton(
      tooltip: 'Удалить навсегда',
      onPressed: () => _deleteOne(context, notifier, drug, hard: true),
      icon: const Icon(Icons.delete_forever_outlined),
    ),
  ];

  Future<void> _deleteOne(
    BuildContext context,
    DrugListNotifier notifier,
    Drug drug, {
    required bool hard,
  }) async {
    final confirmed = await confirmAction(
      context,
      title: hard ? 'Удалить препарат навсегда?' : 'Удалить препарат?',
      message: hard
          ? '«${drug.name}» будет физически удалён без возможности восстановления.'
          : '«${drug.name}» исчезнет из обычной выборки, но его можно будет восстановить.',
    );
    if (!confirmed) return;
    hard
        ? await notifier.hardDelete(drug.id)
        : await notifier.softDelete(drug.id);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(hard ? 'Препарат удалён навсегда' : 'Препарат удалён'),
        ),
      );
    }
  }

  Future<void> _deleteSelected(
    BuildContext context,
    DrugListNotifier notifier,
  ) async {
    final count = notifier.selected.length;
    final confirmed = await confirmAction(
      context,
      title: 'Удалить выбранные препараты?',
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
