import 'package:flutter/material.dart';

/// Rows with natural card heights: unlike a fixed-aspect grid, long text and
/// validation messages cannot overflow a tile vertically.
class ResponsiveCards extends StatelessWidget {
  final List<Widget> children;
  final EdgeInsetsGeometry padding;
  const ResponsiveCards({
    super.key,
    required this.children,
    this.padding = const EdgeInsets.all(12),
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns =
          MediaQuery.sizeOf(context).width >= 768 && constraints.maxWidth >= 640
          ? 2
          : 1;
      return ListView.separated(
        padding: padding,
        itemCount: (children.length / columns).ceil(),
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (_, row) => Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var column = 0; column < columns; column++) ...[
              if (column > 0) const SizedBox(width: 8),
              Expanded(
                child: row * columns + column < children.length
                    ? children[row * columns + column]
                    : const SizedBox.shrink(),
              ),
            ],
          ],
        ),
      );
    },
  );
}
