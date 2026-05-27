import 'package:flutter/material.dart';

import '../theme/matix_colors.dart';
import '../theme/matix_spacing.dart';
import '../theme/matix_typography.dart';

/// Patrón estándar de Matix para mostrar el resultado de un Future:
/// cargando / error / vacío / con datos.
///
/// Uso:
/// ```dart
/// AsyncView<List<Tarea>>(
///   future: client.getList('/api/v1/tareas').then(...),
///   isEmpty: (l) => l.isEmpty,
///   builder: (ctx, data) => TareasList(data),
/// )
/// ```
class AsyncView<T> extends StatelessWidget {
  const AsyncView({
    super.key,
    required this.future,
    required this.builder,
    this.isEmpty,
    this.emptyTitle,
    this.emptyMessage,
    this.onRetry,
  });

  final Future<T> future;
  final Widget Function(BuildContext, T data) builder;
  final bool Function(T data)? isEmpty;
  final String? emptyTitle;
  final String? emptyMessage;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _LoadingView();
        }
        if (snapshot.hasError) {
          return _ErrorView(
            message: snapshot.error?.toString() ?? 'Error desconocido',
            onRetry: onRetry,
          );
        }
        final data = snapshot.data as T;
        if (isEmpty != null && isEmpty!(data)) {
          return _EmptyView(
            title: emptyTitle ?? 'Sin nada por aquí',
            message: emptyMessage ?? 'Cuando agregues algo, aparecerá acá.',
          );
        }
        return builder(context, data);
      },
    );
  }
}

class _LoadingView extends StatelessWidget {
  const _LoadingView();
  @override
  Widget build(BuildContext context) {
    return const Center(
      child: SizedBox(
        width: 28,
        height: 28,
        child: CircularProgressIndicator(
          strokeWidth: 2.4,
          color: MatixColors.accent,
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, this.onRetry});
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(MatixSpacing.xl3),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: MatixColors.red, size: 40),
            const SizedBox(height: MatixSpacing.l),
            Text('Algo falló', style: MatixText.subtitle),
            const SizedBox(height: MatixSpacing.m),
            Text(
              message,
              style: MatixText.small,
              textAlign: TextAlign.center,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: MatixSpacing.xl2),
              FilledButton(onPressed: onRetry, child: const Text('Reintentar')),
            ],
          ],
        ),
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView({required this.title, required this.message});
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(MatixSpacing.xl3),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: MatixText.subtitle),
            const SizedBox(height: MatixSpacing.m),
            Text(
              message,
              style: MatixText.small,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
