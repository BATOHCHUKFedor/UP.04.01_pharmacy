import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../state/drug_details_notifier.dart';
import '../state/drug_list_notifier.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/detail_field.dart';
import '../widgets/screen_state_view.dart';

class DrugDetailScreen extends StatefulWidget {
  final int id;
  const DrugDetailScreen({super.key, required this.id});

  @override
  State<DrugDetailScreen> createState() => _DrugDetailScreenState();
}

class _DrugDetailScreenState extends State<DrugDetailScreen> {
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant DrugDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id) _load();
  }

  void _load() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<DrugDetailsNotifier>().load(widget.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final notifier = context.watch<DrugDetailsNotifier>();
    final drug = notifier.drug;
    return AppScaffold(
      title: drug?.name ?? 'Карточка препарата',
      actions: [
        IconButton(
          tooltip: 'Назад к списку',
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/drugs'),
          icon: const Icon(Icons.arrow_back),
        ),
      ],
      body: ScreenStateView(
        status: notifier.status,
        error: notifier.error,
        isEmpty: drug == null,
        emptyMessage: 'Препарат не найден',
        onRetry: () => notifier.load(widget.id),
        child: drug == null
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
                                    drug.name,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.headlineSmall,
                                  ),
                                ),
                                if (drug.isDeleted)
                                  const Chip(label: Text('Удалён')),
                              ],
                            ),
                            const Divider(),
                            DetailField(
                              label: 'Регистрационный номер',
                              value: drug.registrationNumber,
                            ),
                            DetailField(
                              label: 'Категория',
                              value: drug.category,
                            ),
                            DetailField(
                              label: 'Производитель',
                              value: drug.manufacturer,
                            ),
                            DetailField(
                              label: 'Год производства',
                              value: '${drug.productionYear}',
                            ),
                            DetailField(
                              label: 'Цена',
                              value: '${drug.price.toStringAsFixed(2)} ₽',
                            ),
                            DetailField(
                              label: 'Остаток',
                              value: '${drug.stock} шт.',
                            ),
                            DetailField(
                              label: 'Поставщик',
                              value: '№ ${drug.supplierId}',
                            ),
                            const SizedBox(height: 16),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              alignment: WrapAlignment.end,
                              children: [
                                if (drug.isDeleted)
                                  FilledButton.tonalIcon(
                                    onPressed: () async {
                                      await context
                                          .read<DrugListNotifier>()
                                          .restore(drug.id);
                                      if (context.mounted) {
                                        await notifier.load(drug.id);
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
    final drug = context.read<DrugDetailsNotifier>().drug;
    if (drug == null) return;
    final confirmed = await confirmAction(
      context,
      title: hard ? 'Удалить препарат навсегда?' : 'Удалить препарат?',
      message: hard
          ? 'Запись будет стёрта без возможности восстановления.'
          : 'Запись можно будет восстановить из списка удалённых.',
    );
    if (!confirmed || !context.mounted) return;
    final list = context.read<DrugListNotifier>();
    if (hard) {
      await list.hardDelete(drug.id);
      if (context.mounted) {
        context.canPop() ? context.pop() : context.go('/drugs');
      }
    } else {
      await list.softDelete(drug.id);
      if (context.mounted) {
        await context.read<DrugDetailsNotifier>().load(drug.id);
      }
    }
  }
}
