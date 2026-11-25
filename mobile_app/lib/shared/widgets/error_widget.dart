import 'package:flutter/material.dart';

import 'tr_text.dart';
import 'ui_kit.dart';

class AppErrorWidget extends StatelessWidget {
  final String message;
  final String title;
  final VoidCallback? onRetry;

  const AppErrorWidget({
    super.key,
    required this.message,
    this.title = 'Произошла ошибка',
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.error_outline_rounded,
      title: title,
      message: message,
      action: onRetry == null
          ? null
          : FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 18),
              label: const TrText('Повторить'),
            ),
    );
  }
}
