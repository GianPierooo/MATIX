import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/matix_colors.dart';
import '../data/modelos_repository.dart';
import '../providers/modelos_providers.dart';

/// "Modelo" — elige qué LLM usa Matix para el chat. El catálogo y el ruteo
/// (qué proveedor) viven en el cerebro; acá solo eliges y se persiste.
class ModeloScreen extends ConsumerWidget {
  const ModeloScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final estado = ref.watch(modelosProvider);
    final ctrl = ref.read(modelosProvider.notifier);

    if (estado.cargando) {
      return const Scaffold(
        appBar: _AppBarModelo(),
        body: Center(
          child: CircularProgressIndicator(color: MatixColors.accent),
        ),
      );
    }

    final grupos = estado.porProveedor;
    // Orden de proveedores: OpenAI primero, Anthropic después.
    final orden = ['openai', 'anthropic']
        .where(grupos.containsKey)
        .toList();

    return Scaffold(
      appBar: const _AppBarModelo(),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(0, 8, 0, 24),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 8, 20, 8),
            child: Text(
              'El modelo que usa Matix para conversar. La voz y la búsqueda en '
              'tus apuntes usan siempre OpenAI, no cambian con esto.',
              style: TextStyle(fontSize: 12.5, color: MatixColors.muted, height: 1.4),
            ),
          ),

          // Reservado para el siguiente paso: "Automático".
          const _AutomaticoTile(),

          for (final prov in orden) ...[
            _Encabezado(grupos[prov]!.first.proveedorEtiqueta),
            for (final m in grupos[prov]!)
              _ModeloTile(
                modelo: m,
                seleccionado: m.id == estado.seleccionado,
                onTap: () => ctrl.seleccionar(m.id),
              ),
          ],
          if (orden.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(
                child: Text(
                  'No pude cargar los modelos. Revisa la conexión con el cerebro.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: MatixColors.muted),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AppBarModelo extends StatelessWidget implements PreferredSizeWidget {
  const _AppBarModelo();
  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
  @override
  Widget build(BuildContext context) => AppBar(title: const Text('Modelo'));
}

class _Encabezado extends StatelessWidget {
  const _Encabezado(this.texto);
  final String texto;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
      child: Text(
        texto.toUpperCase(),
        style: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.0,
          color: MatixColors.muted,
        ),
      ),
    );
  }
}

class _ModeloTile extends StatelessWidget {
  const _ModeloTile({
    required this.modelo,
    required this.seleccionado,
    required this.onTap,
  });
  final ModeloLlm modelo;
  final bool seleccionado;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 3, 16, 3),
      child: Material(
        color: seleccionado
            ? MatixColors.accent.withValues(alpha: 0.14)
            : MatixColors.card,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        modelo.etiqueta,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight:
                              seleccionado ? FontWeight.w700 : FontWeight.w500,
                          color: seleccionado
                              ? MatixColors.accent
                              : MatixColors.text,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        modelo.id,
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: MatixColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                if (seleccionado)
                  const Icon(Icons.check_circle,
                      color: MatixColors.accent, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Lugar reservado para "Automático" (Matix elige el modelo según la tarea).
/// Se construye en el siguiente paso; por ahora va deshabilitado.
class _AutomaticoTile extends StatelessWidget {
  const _AutomaticoTile();
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Opacity(
        opacity: 0.55,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: MatixColors.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: MatixColors.hairline),
          ),
          child: Row(
            children: [
              const Icon(Icons.auto_awesome,
                  color: MatixColors.muted, size: 20),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Automático',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: MatixColors.text,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Matix elige el mejor modelo según la tarea.',
                      style: TextStyle(fontSize: 12, color: MatixColors.muted),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: MatixColors.bg,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'Próximamente',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: MatixColors.muted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
