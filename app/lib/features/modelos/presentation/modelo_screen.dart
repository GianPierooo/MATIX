import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/matix_colors.dart';
import '../data/modelos_repository.dart';
import '../providers/modelos_providers.dart';

/// "Modelo" — elige qué LLM usa Matix para el chat. El catálogo y el ruteo
/// (qué proveedor; y en Automático, qué modelo por mensaje) viven en el
/// cerebro; acá solo eliges y se persiste.
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
    final orden = ['openai', 'anthropic'].where(grupos.containsKey).toList();

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
              style: TextStyle(
                  fontSize: 12.5, color: MatixColors.muted, height: 1.4),
            ),
          ),

          // Automático: Matix elige el modelo por cada mensaje.
          _AutomaticoTile(
            seleccionado: estado.esAuto,
            onTap: () => ctrl.seleccionar(kModeloAuto),
          ),
          // Config del par barato/fuerte: solo cuando Automático está activo.
          if (estado.esAuto) _ConfigAuto(estado: estado),

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

/// "Automático": Matix elige el mejor modelo según el mensaje. Seleccionable
/// como cualquier modelo; cuando está activo se resalta.
class _AutomaticoTile extends StatelessWidget {
  const _AutomaticoTile({required this.seleccionado, required this.onTap});
  final bool seleccionado;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
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
                Icon(Icons.auto_awesome,
                    color:
                        seleccionado ? MatixColors.accent : MatixColors.muted,
                    size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Automático',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: seleccionado
                              ? FontWeight.w700
                              : FontWeight.w600,
                          color: seleccionado
                              ? MatixColors.accent
                              : MatixColors.text,
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Matix elige el modelo según la tarea: rápido para lo '
                        'cotidiano, a fondo para lo pesado.',
                        style:
                            TextStyle(fontSize: 12, color: MatixColors.muted),
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

/// Config del par barato/fuerte que usa Automático. Dos filas que abren un
/// selector para elegir cuál modelo es el "rápido" y cuál el "a fondo".
class _ConfigAuto extends ConsumerWidget {
  const _ConfigAuto({required this.estado});
  final ModelosState estado;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctrl = ref.read(modelosProvider.notifier);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: MatixColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MatixColors.hairline),
      ),
      child: Column(
        children: [
          _FilaPar(
            icono: Icons.bolt,
            titulo: 'Rápido',
            subtitulo: 'Comandos, CRUD y preguntas cortas.',
            modeloEtiqueta: estado.etiquetaDe(estado.barato),
            onTap: () => _elegir(
              context,
              estado,
              titulo: 'Modelo rápido',
              actual: estado.barato,
              onElegido: (id) => ctrl.fijarPar(barato: id),
            ),
          ),
          const Divider(height: 1, color: MatixColors.hairline),
          _FilaPar(
            icono: Icons.auto_awesome,
            titulo: 'A fondo',
            subtitulo: 'Escritura, análisis, código y modos pesados.',
            modeloEtiqueta: estado.etiquetaDe(estado.fuerte),
            onTap: () => _elegir(
              context,
              estado,
              titulo: 'Modelo a fondo',
              actual: estado.fuerte,
              onElegido: (id) => ctrl.fijarPar(fuerte: id),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _elegir(
    BuildContext context,
    ModelosState estado, {
    required String titulo,
    required String actual,
    required ValueChanged<String> onElegido,
  }) async {
    final id = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: MatixColors.bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(
                titulo,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: MatixColors.text,
                ),
              ),
            ),
            for (final m in estado.modelos)
              ListTile(
                title: Text(m.etiqueta,
                    style: const TextStyle(
                        fontSize: 14, color: MatixColors.text)),
                subtitle: Text('${m.proveedorEtiqueta} · ${m.id}',
                    style: const TextStyle(
                        fontSize: 11.5, color: MatixColors.muted)),
                trailing: m.id == actual
                    ? const Icon(Icons.check_circle,
                        color: MatixColors.accent, size: 20)
                    : null,
                onTap: () => Navigator.of(ctx).pop(m.id),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (id != null && id != actual) onElegido(id);
  }
}

class _FilaPar extends StatelessWidget {
  const _FilaPar({
    required this.icono,
    required this.titulo,
    required this.subtitulo,
    required this.modeloEtiqueta,
    required this.onTap,
  });
  final IconData icono;
  final String titulo;
  final String subtitulo;
  final String modeloEtiqueta;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Icon(icono, size: 18, color: MatixColors.muted),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(titulo,
                      style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: MatixColors.text)),
                  const SizedBox(height: 1),
                  Text(subtitulo,
                      style: const TextStyle(
                          fontSize: 11.5, color: MatixColors.muted)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                modeloEtiqueta,
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: MatixColors.accent,
                ),
              ),
            ),
            const Icon(Icons.chevron_right, size: 18, color: MatixColors.muted),
          ],
        ),
      ),
    );
  }
}
