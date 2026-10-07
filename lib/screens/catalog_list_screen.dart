import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/catalog_item.dart';
import '../models/auth_user.dart';
import '../models/catalog_query.dart';
import '../models/category.dart';
import '../models/drug.dart';
import '../models/manufacturer.dart';
import '../models/supplier.dart';
import '../models/supplier_license.dart';
import '../state/catalog_store.dart';
import '../state/load_status.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/entity_card_list.dart';
import '../widgets/entity_table.dart';
import '../widgets/pagination_bar.dart';
import '../widgets/screen_state_view.dart';

class CatalogListScreen extends StatefulWidget {
  final EntityKind kind;
  final CatalogQuery query;
  const CatalogListScreen({super.key, required this.kind, required this.query});
  @override
  State<CatalogListScreen> createState() => _CatalogListScreenState();
}

class _CatalogListScreenState extends State<CatalogListScreen> {
  late final TextEditingController _search;
  late final TextEditingController _yearFrom;
  late final TextEditingController _yearTo;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _search = TextEditingController(text: widget.query.search);
    _yearFrom = TextEditingController(
      text: widget.query.yearFrom?.toString() ?? '',
    );
    _yearTo = TextEditingController(
      text: widget.query.yearTo?.toString() ?? '',
    );
    _applyRoute();
  }

  @override
  void didUpdateWidget(covariant CatalogListScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.kind != widget.kind || oldWidget.query != widget.query) {
      _debounce?.cancel();
      _sync(_search, widget.query.search);
      _sync(_yearFrom, widget.query.yearFrom?.toString() ?? '');
      _sync(_yearTo, widget.query.yearTo?.toString() ?? '');
      _applyRoute();
    }
  }

  void _sync(TextEditingController controller, String value) {
    if (controller.text == value) return;
    controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  void _applyRoute() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted) {
      context.read<CatalogStore>().applyQuery(widget.kind, widget.query);
    }
  });

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _yearFrom.dispose();
    _yearTo.dispose();
    super.dispose();
  }

  void _navigate(CatalogQuery query) {
    _debounce?.cancel();
    if (CatalogQuery.fromParameters(query.toParameters()) == widget.query) {
      final store = context.read<CatalogStore>();
      if (store.list(widget.kind).status == LoadStatus.idle) {
        store.applyQuery(widget.kind, widget.query, force: true);
      }
      return;
    }
    context.go(
      Uri(
        path: '/${widget.kind.path}',
        queryParameters: query.toParameters(),
      ).toString(),
    );
  }

  void _debounced(CatalogQuery Function() query) {
    _debounce?.cancel();
    context.read<CatalogStore>().cancelList(widget.kind);
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (mounted) _navigate(query());
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<CatalogStore>();
    final state = store.list(widget.kind);
    return AppScaffold(
      title: widget.kind.title,
      actions: [
        if (canAct(context, Permission.write))
          IconButton(
            tooltip: 'Создать',
            icon: const Icon(Icons.add),
            onPressed: () => context.push('/${widget.kind.path}/new'),
          ),
      ],
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (store.showStorageNotice)
              MaterialBanner(
                content: Text(store.storageNotice!),
                actions: [
                  TextButton(
                    onPressed: store.dismissStorageNotice,
                    child: const Text('Понятно'),
                  ),
                ],
              ),
            _filters(store),
            if (canAct(context, Permission.delete) && state.selected.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Expanded(child: Text('Выбрано: ${state.selected.length}')),
                    FilledButton.tonalIcon(
                      onPressed: () => _deleteSelected(store),
                      icon: const Icon(Icons.delete_sweep_outlined),
                      label: const Text('Удалить выбранные'),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            Expanded(
              child: ScreenStateView(
                status: state.status,
                error: state.error,
                isEmpty: state.result.items.isEmpty,
                emptyMessage: 'По заданным условиям записей нет',
                onRetry: () => store.load(widget.kind),
                child: Column(
                  children: [
                    Expanded(child: _results(store)),
                    PaginationBar(
                      page: state.result.page,
                      totalPages: state.result.totalPages,
                      totalItems: state.result.total,
                      pageSize: state.result.size,
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

  Widget _filters(CatalogStore store) {
    final query = widget.query;
    final manufacturers = store.options(EntityKind.manufacturers);
    final suppliers = store.options(EntityKind.suppliers);
    final categories = store.options(EntityKind.categories);
    final countries =
        store
            .options(widget.kind)
            .map(
              (item) => switch (item) {
                Supplier s => s.country,
                Manufacturer m => m.country,
                _ => '',
              },
            )
            .where((value) => value.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    return Card(
      child: ExpansionTile(
        title: const Text('Поиск и фильтры'),
        initiallyExpanded: true,
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        childrenPadding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 300,
                child: TextField(
                  controller: _search,
                  onChanged: (value) =>
                      _debounced(() => query.copyWith(search: value)),
                  decoration: const InputDecoration(
                    labelText: 'Поиск',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              if (widget.kind == EntityKind.drugs) ...[
                _idFilter(
                  'Категория',
                  query.categoryId,
                  categories,
                  (id) => _navigate(query.copyWith(categoryId: id)),
                ),
                _idFilter(
                  'Производитель',
                  query.manufacturerId,
                  manufacturers,
                  (id) => _navigate(query.copyWith(manufacturerId: id)),
                ),
                _idFilter(
                  'Поставщик',
                  query.supplierId,
                  suppliers,
                  (id) => _navigate(query.copyWith(supplierId: id)),
                ),
              ],
              if (widget.kind == EntityKind.suppliers)
                _idFilter(
                  'Производитель',
                  query.manufacturerId,
                  manufacturers,
                  (id) => _navigate(query.copyWith(manufacturerId: id)),
                ),
              if (widget.kind == EntityKind.licenses)
                _idFilter(
                  'Поставщик',
                  query.supplierId,
                  suppliers,
                  (id) => _navigate(query.copyWith(supplierId: id)),
                ),
              if (widget.kind == EntityKind.suppliers ||
                  widget.kind == EntityKind.manufacturers)
                SizedBox(
                  width: 200,
                  child: DropdownButtonFormField<String?>(
                    key: ValueKey(
                      'country-${query.country}-${countries.join(',')}',
                    ),
                    initialValue: countries.contains(query.country)
                        ? query.country
                        : null,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Страна',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('Все страны'),
                      ),
                      ...countries.map(
                        (country) => DropdownMenuItem(
                          value: country,
                          child: Text(country),
                        ),
                      ),
                    ],
                    onChanged: (value) =>
                        _navigate(query.copyWith(country: value)),
                  ),
                ),
              if (widget.kind == EntityKind.categories)
                FilterChip(
                  label: const Text('Используемые'),
                  selected: query.usedOnly == true,
                  onSelected: (value) =>
                      _navigate(query.copyWith(usedOnly: value ? true : null)),
                ),
              if (widget.kind == EntityKind.drugs ||
                  widget.kind == EntityKind.licenses) ...[
                SizedBox(
                  width: 115,
                  child: TextField(
                    controller: _yearFrom,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => _debounced(
                      () => query.copyWith(
                        yearFrom: int.tryParse(_yearFrom.text),
                        yearTo: int.tryParse(_yearTo.text),
                      ),
                    ),
                    decoration: InputDecoration(
                      labelText: widget.kind == EntityKind.drugs
                          ? 'Год от'
                          : 'Истекает от',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                SizedBox(
                  width: 115,
                  child: TextField(
                    controller: _yearTo,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => _debounced(
                      () => query.copyWith(
                        yearFrom: int.tryParse(_yearFrom.text),
                        yearTo: int.tryParse(_yearTo.text),
                      ),
                    ),
                    decoration: InputDecoration(
                      labelText: widget.kind == EntityKind.drugs
                          ? 'Год до'
                          : 'Истекает до',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
              if (canAct(context, Permission.write))
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Switch(
                      value: query.includeDeleted,
                      onChanged: (value) =>
                          _navigate(query.copyWith(includeDeleted: value)),
                    ),
                    const Text('Показывать удалённые'),
                  ],
                ),
              OutlinedButton.icon(
                onPressed: () {
                  _debounce?.cancel();
                  _navigate(const CatalogQuery());
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

  Widget _idFilter(
    String label,
    int? selected,
    List<CatalogItem> options,
    ValueChanged<int?> onChanged,
  ) => SizedBox(
    width: 220,
    child: DropdownButtonFormField<int?>(
      key: ValueKey(
        '$label-$selected-${options.map((item) => item.id).join(',')}',
      ),
      initialValue: options.any((item) => item.id == selected)
          ? selected
          : null,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      items: [
        const DropdownMenuItem(value: null, child: Text('Все')),
        ...options.map(
          (item) => DropdownMenuItem(
            value: item.id,
            child: Text(item.title, overflow: TextOverflow.ellipsis),
          ),
        ),
      ],
      onChanged: onChanged,
    ),
  );

  Widget _results(CatalogStore store) {
    final canSelect = canAct(context, Permission.delete);
    final state = store.list(widget.kind);
    final items = state.result.items;
    final fields = _columns(store);
    return LayoutBuilder(
      builder: (context, constraints) {
        if (MediaQuery.sizeOf(context).width < 600) {
          return EntityCardList<CatalogItem>(
            items: items,
            idOf: (item) => item.id,
            titleOf: (item) => item.title,
            selected: state.selection,
            onToggleSelect: canSelect
                ? (id) => store.toggleSelection(widget.kind, id)
                : null,
            isSelectable: (item) => !item.isDeleted,
            isDeleted: (item) => item.isDeleted,
            fields: fields
                .skip(1)
                .map(
                  (column) => CardFieldSpec<CatalogItem>(
                    label: column.label,
                    value: (item) =>
                        _fieldValue(store, item, column.fieldKey ?? 'name'),
                  ),
                )
                .toList(),
            actions: (item) => _actions(store, item),
          );
        }
        return EntityTable<CatalogItem>(
          items: items,
          idOf: (item) => item.id,
          selected: state.selection,
          onToggleSelect: canSelect
              ? (id) => store.toggleSelection(widget.kind, id)
              : null,
          onSelectAll: canSelect
              ? (selected) => store.togglePageSelection(
                  widget.kind,
                  items.where((item) => !item.isDeleted).map((item) => item.id),
                  selected,
                )
              : null,
          isSelectable: (item) => !item.isDeleted,
          sortField: widget.query.sortField,
          sortAscending: widget.query.ascending,
          onSort: (field) => _navigate(
            widget.query.copyWith(
              sortField: field,
              ascending: field == widget.query.sortField
                  ? !widget.query.ascending
                  : true,
            ),
          ),
          columns: fields,
          actions: (item) => _actions(store, item),
        );
      },
    );
  }

  List<TableColumnSpec<CatalogItem>> _columns(CatalogStore store) =>
      switch (widget.kind) {
        EntityKind.drugs => [
          _column(store, 'Название', 'name'),
          _column(store, 'Рег. номер', 'registrationNumber'),
          _column(store, 'Категории', 'categories'),
          _column(store, 'Производитель', 'manufacturer'),
          _column(store, 'Год', 'year', numeric: true),
          _column(store, 'Цена', 'price', numeric: true),
          _column(store, 'Остаток', 'stock', numeric: true),
        ],
        EntityKind.suppliers => [
          _column(store, 'Название', 'name'),
          _column(store, 'Контактное лицо', 'contact'),
          _column(store, 'Страна', 'country'),
          _column(store, 'Почта', 'email'),
          _column(store, 'Сотрудничество с', 'year', numeric: true),
        ],
        EntityKind.manufacturers => [
          _column(store, 'Название', 'name'),
          _column(store, 'Страна', 'country'),
          _column(store, 'Почта', 'email'),
          _column(store, '№', 'id', numeric: true),
        ],
        EntityKind.categories => [
          _column(store, 'Название', 'name'),
          _column(store, 'Описание', 'description'),
          _column(store, '№', 'id', numeric: true),
        ],
        EntityKind.licenses => [
          _column(store, 'Номер', 'name'),
          _column(store, 'Поставщик', 'supplier'),
          _column(store, 'Выдана', 'issuedYear', numeric: true),
          _column(store, 'Истекает', 'expiresYear', numeric: true),
        ],
      };

  TableColumnSpec<CatalogItem> _column(
    CatalogStore store,
    String label,
    String key, {
    bool numeric = false,
  }) => TableColumnSpec<CatalogItem>(
    label: label,
    fieldKey: key,
    sortField:
        const {
          'name',
          'year',
          'price',
          'stock',
          'country',
          'expiresYear',
          'issuedYear',
          'description',
          'email',
          'id',
        }.contains(key)
        ? key
        : null,
    numeric: numeric,
    build: (item) => Text(_fieldValue(store, item, key)),
  );

  String _fieldValue(CatalogStore store, CatalogItem item, String key) =>
      switch ((item, key)) {
        (Drug d, 'registrationNumber') => d.registrationNumber,
        (Drug d, 'categories') =>
          d.categoryIds
              .map(
                (id) => store.byId(EntityKind.categories, id)?.title ?? '№$id',
              )
              .join(', '),
        (Drug d, 'manufacturer') =>
          store.byId(EntityKind.manufacturers, d.manufacturerId)?.title ??
              '№${d.manufacturerId}',
        (Drug d, 'year') => '${d.productionYear}',
        (Drug d, 'price') => '${d.price.toStringAsFixed(2)} ₽',
        (Drug d, 'stock') => '${d.stock}',
        (Supplier s, 'contact') => s.contactPerson,
        (Supplier s, 'country') => s.country,
        (Supplier s, 'email') => s.email,
        (Supplier s, 'year') => '${s.partnershipYear}',
        (Manufacturer m, 'country') => m.country,
        (Manufacturer m, 'email') => m.contactEmail,
        (Category c, 'description') => c.description,
        (SupplierLicense l, 'supplier') =>
          store.byId(EntityKind.suppliers, l.supplierId)?.title ??
              '№${l.supplierId}',
        (SupplierLicense l, 'issuedYear') => '${l.issuedYear}',
        (SupplierLicense l, 'expiresYear') => '${l.expiresYear}',
        (_, 'id') => '${item.id}',
        _ => item.title,
      };

  List<Widget> _actions(CatalogStore store, CatalogItem item) => [
    IconButton(
      tooltip: 'Карточка',
      icon: const Icon(Icons.visibility_outlined),
      onPressed: () => context.push('/${widget.kind.path}/${item.id}'),
    ),
    if (canAct(context, Permission.write))
      IconButton(
        tooltip: 'Изменить',
        icon: const Icon(Icons.edit_outlined),
        onPressed: item.isDeleted
            ? null
            : () => context.push('/${widget.kind.path}/${item.id}/edit'),
      ),
    if (item.isDeleted && canAct(context, Permission.restore))
      IconButton(
        tooltip: 'Восстановить',
        icon: const Icon(Icons.restore),
        onPressed: () => _run(() => store.restore(widget.kind, item.id)),
      ),
    if (!item.isDeleted && canAct(context, Permission.delete))
      IconButton(
        tooltip: 'Логически удалить',
        icon: const Icon(Icons.delete_outline),
        onPressed: () => _remove(store, item, hard: false),
      ),
    if (canAct(context, Permission.hardDelete))
      IconButton(
        tooltip: 'Удалить навсегда',
        icon: const Icon(Icons.delete_forever_outlined),
        onPressed: () => _remove(store, item, hard: true),
      ),
  ];

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  Future<void> _remove(
    CatalogStore store,
    CatalogItem item, {
    required bool hard,
  }) async {
    final confirmed = await confirmAction(
      context,
      title: hard ? 'Удалить навсегда?' : 'Логически удалить?',
      message: hard
          ? '«${item.title}» нельзя будет восстановить.'
          : '«${item.title}» можно будет восстановить.',
    );
    if (!confirmed) return;
    await _run(
      () => hard
          ? store.hardDelete(widget.kind, item.id)
          : store.softDelete(widget.kind, item.id),
    );
  }

  Future<void> _deleteSelected(CatalogStore store) async {
    final count = store.list(widget.kind).selected.length;
    final confirmed = await confirmAction(
      context,
      title: 'Удалить выбранные записи?',
      message: 'Логически удалить записей: $count?',
    );
    if (!confirmed) return;
    await _run(() async {
      await store.deleteSelected(widget.kind);
    });
  }
}
