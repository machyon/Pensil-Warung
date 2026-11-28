import 'package:material_ui/material_ui.dart';

import '../../../data/api_exception.dart';
import 'empty_state.dart';

/// Network error ([30] layout) or the server's Indonesian message, with "Coba lagi".
class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final e = error;
    if (e is ApiException) {
      return EmptyState(
        icon: Icons.error_outline,
        title: 'Terjadi masalah',
        text: e.message,
        actionLabel: 'Coba lagi',
        onAction: onRetry,
      );
    }
    return EmptyState(
      icon: Icons.wifi_off_rounded,
      title: 'Tidak ada koneksi',
      text: 'Periksa internet kamu, lalu coba lagi.',
      actionLabel: 'Coba lagi',
      onAction: onRetry,
    );
  }
}
