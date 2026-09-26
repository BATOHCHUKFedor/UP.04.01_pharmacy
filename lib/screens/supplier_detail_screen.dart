import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../state/supplier_details_notifier.dart';
import '../state/supplier_list_notifier.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/detail_field.dart';
import '../widgets/screen_state_view.dart';

class SupplierDetailScreen extends StatefulWidget {
  final int id;
  const SupplierDetailScreen({super.key, required this.id});

  @override
  State<SupplierDetailScreen> createState() => _SupplierDetailScreenState();
}

class _SupplierDetailScreenState extends State<SupplierDetailScreen> {
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant SupplierDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id) _load();
  }

  void _load() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<SupplierDetailsNotifier>().load(widget.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final notifier = context.watch<SupplierDetailsNotifier>();
    final supplier = notifier.supplier;
    return AppScaffold(
      title: supplier?.name ?? 'Карточка поставщика',
      actions: [
        IconButton(
          tooltip: 'Назад к списку',
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/suppliers'),
          icon: const Icon(Icons.arrow_back),
        ),
      ],
      body: ScreenStateView(
        status: notifier.status,
        error: notifier.error,
        isEmpty: supplier == null,
        emptyMessage: 'Поставщик не найден',
        onRetry: () => notifier.load(widget.id),
        child: supplier == null
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
                                    supplier.name,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.headlineSmall,
                                  ),
                                ),
                                if (supplier.isDeleted)
                                  const Chip(label: Text('Удалён')),
                              ],
                            ),
                            const Divider(),
                            DetailField(
                              label: 'Контактное лицо',
                              value: supplier.contactPerson,
                            ),
                            DetailField(
                              label: 'Страна',
                              value: supplier.country,
                            ),
                            DetailField(
                              label: 'Телефон',
                              value: supplier.phone,
                            ),
                            DetailField(label: 'E-mail', value: supplier.email),
                            DetailField(
                              label: 'Год начала сотрудничества',
                              value: '${supplier.partnershipYear}',
                            ),
                            const SizedBox(height: 16),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              alignment: WrapAlignment.end,
                              children: [
                                if (supplier.isDeleted)
                                  FilledButton.tonalIcon(
                                    onPressed: () async {
                                      await context
                                          .read<SupplierListNotifier>()
                                          .restore(supplier.id);
                                      if (context.mounted) {
                                        await notifier.load(supplier.id);
                                      }
                                    },
                                    icon: const Icon(Icons.restore),
                                    label: const Text('Восстановить'),
                                  )
                                else
                                  FilledButton.tonalIcon(
                                    onPressed: () =>
                                        _remove(context, hard: false),
                                    icon: const Icon(Icons.delete_outline),
                                    label: const Text('Удалить'),
                                  ),
                                FilledButton.icon(
                                  onPressed: () => _remove(context, hard: true),
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

  Future<void> _remove(BuildContext context, {required bool hard}) async {
    final supplier = context.read<SupplierDetailsNotifier>().supplier;
    if (supplier == null) return;
    final confirmed = await confirmAction(
      context,
      title: hard ? 'Удалить поставщика навсегда?' : 'Удалить поставщика?',
      message: hard
          ? 'Запись будет стёрта без возможности восстановления.'
          : 'Запись можно будет восстановить из списка удалённых.',
    );
    if (!confirmed || !context.mounted) return;
    final list = context.read<SupplierListNotifier>();
    if (hard) {
      await list.hardDelete(supplier.id);
      if (context.mounted) {
        context.canPop() ? context.pop() : context.go('/suppliers');
      }
    } else {
      await list.softDelete(supplier.id);
      if (context.mounted) {
        await context.read<SupplierDetailsNotifier>().load(supplier.id);
      }
    }
  }
}
