import 'package:flutter/material.dart';

class PaginationBar extends StatelessWidget {
  final int page;
  final int totalPages;
  final int totalItems;
  final int pageSize;
  final ValueChanged<int> onPageChanged;
  final ValueChanged<int> onPageSizeChanged;

  const PaginationBar({
    super.key,
    required this.page,
    required this.totalPages,
    required this.totalItems,
    required this.pageSize,
    required this.onPageChanged,
    required this.onPageSizeChanged,
  });

  @override
  Widget build(BuildContext context) {
    Widget pageButton(
      String tooltip,
      IconData icon,
      int target,
      bool enabled,
    ) => IconButton(
      tooltip: tooltip,
      onPressed: enabled ? () => onPageChanged(target) : null,
      icon: Icon(icon),
      padding: const EdgeInsets.all(4),
      constraints: const BoxConstraints(minWidth: 32, minHeight: 40),
      visualDensity: VisualDensity.compact,
    );
    final pageButtons = [
      pageButton('Первая страница', Icons.first_page, 1, page > 1),
      pageButton('Предыдущая страница', Icons.chevron_left, page - 1, page > 1),
      pageButton(
        'Следующая страница',
        Icons.chevron_right,
        page + 1,
        page < totalPages,
      ),
      pageButton(
        'Последняя страница',
        Icons.last_page,
        totalPages,
        page < totalPages,
      ),
    ];
    final navigation = Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 2,
      children: [
        IconButton(
          tooltip: 'Первая страница',
          onPressed: page > 1 ? () => onPageChanged(1) : null,
          icon: const Icon(Icons.first_page),
          visualDensity: VisualDensity.compact,
        ),
        IconButton(
          tooltip: 'Предыдущая страница',
          onPressed: page > 1 ? () => onPageChanged(page - 1) : null,
          icon: const Icon(Icons.chevron_left),
          visualDensity: VisualDensity.compact,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            'Страница $page из $totalPages · Всего: $totalItems',
            textAlign: TextAlign.center,
          ),
        ),
        IconButton(
          tooltip: 'Следующая страница',
          onPressed: page < totalPages ? () => onPageChanged(page + 1) : null,
          icon: const Icon(Icons.chevron_right),
          visualDensity: VisualDensity.compact,
        ),
        IconButton(
          tooltip: 'Последняя страница',
          onPressed: page < totalPages ? () => onPageChanged(totalPages) : null,
          icon: const Icon(Icons.last_page),
          visualDensity: VisualDensity.compact,
        ),
      ],
    );

    final pageSizeSelector = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('На странице:'),
        const SizedBox(width: 8),
        Semantics(
          label: 'Количество записей на странице',
          child: DropdownButton<int>(
            value: pageSize,
            underline: const SizedBox.shrink(),
            items: const [10, 25, 50]
                .map(
                  (size) => DropdownMenuItem(value: size, child: Text('$size')),
                )
                .toList(),
            onChanged: (value) {
              if (value != null) {
                onPageSizeChanged(value);
              }
            },
          ),
        ),
      ],
    );

    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(top: BorderSide(color: colors.outlineVariant)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 700) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Страница $page из $totalPages · Всего: $totalItems',
                  textAlign: TextAlign.center,
                ),
                Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  children: [
                    Row(mainAxisSize: MainAxisSize.min, children: pageButtons),
                    pageSizeSelector,
                  ],
                ),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: Center(child: navigation)),
              const SizedBox(width: 16),
              pageSizeSelector,
            ],
          );
        },
      ),
    );
  }
}
