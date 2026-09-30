import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/catalog_item.dart';
import '../models/category.dart';
import '../models/drug.dart';
import '../models/manufacturer.dart';
import '../models/supplier.dart';
import '../models/supplier_license.dart';
import '../state/catalog_store.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/detail_field.dart';
import '../widgets/screen_state_view.dart';

class CatalogDetailScreen extends StatefulWidget {
  final EntityKind kind;
  final int id;
  const CatalogDetailScreen({super.key, required this.kind, required this.id});

  @override
  State<CatalogDetailScreen> createState() => _CatalogDetailScreenState();
}

class _CatalogDetailScreenState extends State<CatalogDetailScreen> {
  EntityKind get kind => widget.kind;
  int get id => widget.id;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant CatalogDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.kind != kind || oldWidget.id != id) _load();
  }

  void _load() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted) context.read<CatalogStore>().loadDetail(kind, id);
  });

  @override
  Widget build(BuildContext context) {
    final store = context.watch<CatalogStore>();
    final item = store.byId(kind, id);
    final detail = store.detail(kind, id);
    return AppScaffold(
      title: item?.title ?? kind.singular,
      actions: [
        IconButton(
          tooltip: 'К списку',
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/${kind.path}'),
          icon: const Icon(Icons.arrow_back),
        ),
      ],
      body: ScreenStateView(
        status: detail.status,
        error: detail.error,
        isEmpty: item == null,
        emptyMessage: 'Запись не найдена',
        onRetry: () => store.loadDetail(kind, id),
        child: item == null
            ? const SizedBox.shrink()
            : SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    item.title,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.headlineSmall,
                                  ),
                                ),
                                if (item.isDeleted)
                                  const Chip(label: Text('Удалён')),
                              ],
                            ),
                            const Divider(),
                            ..._fields(store, item),
                            const SizedBox(height: 20),
                            Wrap(
                              alignment: WrapAlignment.end,
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                if (!item.isDeleted)
                                  OutlinedButton.icon(
                                    onPressed: () =>
                                        context.push('/${kind.path}/$id/edit'),
                                    icon: const Icon(Icons.edit_outlined),
                                    label: const Text('Изменить'),
                                  ),
                                if (item.isDeleted)
                                  FilledButton.tonalIcon(
                                    onPressed: () => _run(
                                      context,
                                      () => store.restore(kind, id),
                                    ),
                                    icon: const Icon(Icons.restore),
                                    label: const Text('Восстановить'),
                                  )
                                else
                                  FilledButton.tonalIcon(
                                    onPressed: () =>
                                        _remove(context, store, hard: false),
                                    icon: const Icon(Icons.delete_outline),
                                    label: const Text('Удалить'),
                                  ),
                                FilledButton.icon(
                                  onPressed: () =>
                                      _remove(context, store, hard: true),
                                  icon: const Icon(
                                    Icons.delete_forever_outlined,
                                  ),
                                  label: const Text('Удалить навсегда'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  List<Widget> _fields(CatalogStore store, CatalogItem item) => switch (item) {
    Drug d => [
      DetailField(label: 'Регистрационный номер', value: d.registrationNumber),
      DetailField(
        label: 'Категории',
        value: d.categoryIds
            .map((id) => store.byId(EntityKind.categories, id)?.title ?? '№$id')
            .join(', '),
      ),
      DetailField(
        label: 'Производитель',
        value:
            store.byId(EntityKind.manufacturers, d.manufacturerId)?.title ??
            '№${d.manufacturerId}',
      ),
      DetailField(
        label: 'Поставщик',
        value:
            store.byId(EntityKind.suppliers, d.supplierId)?.title ??
            '№${d.supplierId}',
      ),
      DetailField(label: 'Год производства', value: '${d.productionYear}'),
      DetailField(label: 'Цена', value: '${d.price.toStringAsFixed(2)} ₽'),
      DetailField(label: 'Остаток', value: '${d.stock} шт.'),
    ],
    Supplier s => [
      DetailField(label: 'Контактное лицо', value: s.contactPerson),
      DetailField(label: 'Страна', value: s.country),
      DetailField(label: 'Телефон', value: s.phone),
      DetailField(label: 'Почта', value: s.email),
      DetailField(label: 'Сотрудничество с', value: '${s.partnershipYear}'),
      DetailField(
        label: 'Производители',
        value: s.manufacturerIds
            .map(
              (id) => store.byId(EntityKind.manufacturers, id)?.title ?? '№$id',
            )
            .join(', '),
      ),
      ..._licenseFields(store, s.id),
    ],
    Manufacturer m => [
      DetailField(label: 'Страна', value: m.country),
      DetailField(label: 'Контактная почта', value: m.contactEmail),
    ],
    Category c => [DetailField(label: 'Описание', value: c.description)],
    SupplierLicense l => [
      DetailField(
        label: 'Поставщик',
        value:
            store.byId(EntityKind.suppliers, l.supplierId)?.title ??
            '№${l.supplierId}',
      ),
      DetailField(label: 'Год выдачи', value: '${l.issuedYear}'),
      DetailField(label: 'Год окончания', value: '${l.expiresYear}'),
    ],
    _ => [],
  };

  List<Widget> _licenseFields(CatalogStore store, int supplierId) {
    final license = store
        .options(EntityKind.licenses, includeDeleted: true)
        .cast<SupplierLicense>()
        .where((item) => item.supplierId == supplierId)
        .firstOrNull;
    if (license == null) {
      return [const DetailField(label: 'Лицензия', value: 'Не указана')];
    }
    return [
      DetailField(label: 'Лицензия', value: license.number),
      DetailField(label: 'Выдана', value: '${license.issuedYear}'),
      DetailField(label: 'Истекает', value: '${license.expiresYear}'),
    ];
  }

  Future<void> _run(
    BuildContext context,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  Future<void> _remove(
    BuildContext context,
    CatalogStore store, {
    required bool hard,
  }) async {
    final confirmed = await confirmAction(
      context,
      title: hard ? 'Удалить запись навсегда?' : 'Логически удалить запись?',
      message: hard
          ? 'Восстановить запись будет нельзя.'
          : 'Запись можно будет восстановить из списка удалённых.',
    );
    if (!confirmed || !context.mounted) return;
    try {
      if (hard) {
        await store.hardDelete(kind, id);
        if (context.mounted) {
          context.go('/${kind.path}');
        }
      } else {
        await store.softDelete(kind, id);
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }
}
