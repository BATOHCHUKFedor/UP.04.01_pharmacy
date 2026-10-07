import 'package:flutter/material.dart';

import '../state/load_status.dart';

class ScreenStateView extends StatelessWidget {
  final LoadStatus status;
  final String? error;
  final bool isEmpty;
  final String emptyMessage;
  final VoidCallback onRetry;
  final Widget child;

  const ScreenStateView({
    super.key,
    required this.status,
    required this.isEmpty,
    required this.emptyMessage,
    required this.onRetry,
    required this.child,
    this.error,
  });

  @override
  Widget build(BuildContext context) {
    return switch (status) {
      LoadStatus.idle || LoadStatus.loading => Center(
        child: Semantics(
          label: 'Загрузка данных',
          liveRegion: true,
          child: const CircularProgressIndicator(),
        ),
      ),
      LoadStatus.error => CenteredMessage(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 48,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 12),
            Text(error ?? 'Произошла ошибка', textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Повторить'),
            ),
          ],
        ),
      ),
      LoadStatus.success when isEmpty => CenteredMessage(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.search_off, size: 48),
            const SizedBox(height: 12),
            Text(emptyMessage, textAlign: TextAlign.center),
          ],
        ),
      ),
      LoadStatus.success => child,
    };
  }
}

/// Scrollable even on a short window or at a large text scale.
class CenteredMessage extends StatelessWidget {
  final Widget child;
  const CenteredMessage({super.key, required this.child});
  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: child,
      ),
    ),
  );
}
