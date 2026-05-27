import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/matix_colors.dart';
import '../../../theme/matix_spacing.dart';
import '../../../theme/matix_typography.dart';
import '../../apuntes/domain/apunte.dart';
import '../../apuntes/providers/apuntes_providers.dart';
import '../../eventos/domain/evento.dart';
import '../../eventos/providers/eventos_providers.dart';
import '../../tareas/domain/tarea.dart';
import '../../tareas/providers/tareas_providers.dart';

/// Pantalla Papelera (Capa 2 Paso 5).
///
/// Una sola vista con 3 secciones (Tareas, Eventos, Apuntes), cada
/// una con sus items eliminados. Cada item se puede **Restaurar**
/// individualmente. Un botón "Vaciar todo" purga toda la papelera —
/// la única acción destructiva del hub, y por eso vive solo acá y
/// pide confirmación. Matix nunca puede llegar a este botón.
class PapeleraScreen extends ConsumerStatefulWidget {
  const PapeleraScreen({super.key});

  @override
  ConsumerState<PapeleraScreen> createState() => _PapeleraScreenState();
}

class _PapeleraScreenState extends ConsumerState<PapeleraScreen> {
  late Future<_DatosPapelera> _carga;

  @override
  void initState() {
    super.initState();
    _carga = _cargar();
  }

  Future<_DatosPapelera> _cargar() async {
    final tareasRepo = ref.read(tareasRepositoryProvider);
    final eventosRepo = ref.read(eventosRepositoryProvider);
    final apuntesRepo = ref.read(apuntesRepoProvider);
    final results = await Future.wait([
      tareasRepo.listarPapelera(),
      eventosRepo.listarPapelera(),
      apuntesRepo.listarPapelera(),
    ]);
    return _DatosPapelera(
      tareas: results[0] as List<Tarea>,
      eventos: results[1] as List<Evento>,
      apuntes: results[2] as List<Apunte>,
    );
  }

  Future<void> _refrescar() async {
    setState(() => _carga = _cargar());
    await _carga;
  }

  Future<void> _restaurarTarea(Tarea t) async {
    await ref.read(tareasRepositoryProvider).restaurar(t.id);
    ref.invalidate(tareasProvider);
    await _refrescar();
  }

  Future<void> _restaurarEvento(Evento e) async {
    await ref.read(eventosRepositoryProvider).restaurar(e.id);
    ref.invalidate(eventosProvider);
    await _refrescar();
  }

  Future<void> _restaurarApunte(Apunte a) async {
    await ref.read(apuntesRepoProvider).restaurar(a.id);
    ref.invalidate(apuntesListProvider);
    await _refrescar();
  }

  Future<void> _vaciarTodo(_DatosPapelera datos) async {
    final n = datos.total;
    if (n == 0) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: MatixColors.card,
        title: const Text('Vaciar papelera'),
        content: Text(
          'Se van a destruir $n elementos de forma permanente. '
          'Esto no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: MatixColors.red,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Vaciar'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final tareasRepo = ref.read(tareasRepositoryProvider);
    final eventosRepo = ref.read(eventosRepositoryProvider);
    final apuntesRepo = ref.read(apuntesRepoProvider);

    // Defensivo: cada borrado en su propio try/catch. Si uno falla
    // (p. ej. otro proceso ya lo purgó, o el cerebro devuelve 404),
    // no queremos abortar el resto — la papelera debe quedar lo más
    // limpia posible. Esto era la causa del bug: si un ítem fallaba,
    // `Future.wait` propagaba la excepción y el await en `_vaciarTodo`
    // bubbleaba, dejando la pantalla sin invalidar ni refrescar.
    var okCount = 0;
    var failCount = 0;
    Future<void> purgar(Future<void> Function() fn) async {
      try {
        await fn();
        okCount++;
      } catch (_) {
        failCount++;
      }
    }

    await Future.wait([
      for (final t in datos.tareas) purgar(() => tareasRepo.borrarPermanente(t.id)),
      for (final e in datos.eventos) purgar(() => eventosRepo.borrarPermanente(e.id)),
      for (final a in datos.apuntes) purgar(() => apuntesRepo.borrarPermanente(a.id)),
    ]);

    // Invalidamos las listas normales por si quedaron derivados con
    // referencias huérfanas.
    ref.invalidate(tareasProvider);
    ref.invalidate(eventosProvider);
    ref.invalidate(apuntesListProvider);
    await _refrescar();

    if (!mounted) return;
    final msg = failCount == 0
        ? 'Papelera vaciada ($okCount eliminados)'
        : 'Vaciados $okCount · $failCount fallaron';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: failCount == 0 ? null : MatixColors.amber,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Papelera'),
      ),
      body: FutureBuilder<_DatosPapelera>(
        future: _carga,
        builder: (ctx, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(
              child: CircularProgressIndicator(color: MatixColors.accent),
            );
          }
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(MatixSpacing.xl3),
                child: Text(
                  'Error al cargar la papelera:\n${snap.error}',
                  textAlign: TextAlign.center,
                  style: MatixText.small,
                ),
              ),
            );
          }
          final datos = snap.data ?? const _DatosPapelera.vacia();
          if (datos.total == 0) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(MatixSpacing.xl3),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.delete_outline,
                      size: 48,
                      color: MatixColors.muted,
                    ),
                    const SizedBox(height: MatixSpacing.l),
                    Text(
                      'La papelera está vacía.',
                      style: MatixText.body,
                    ),
                    const SizedBox(height: MatixSpacing.s),
                    Text(
                      'Lo que borres aparece acá durante el tiempo '
                      'que quieras, hasta que decidas vaciarla.',
                      style: MatixText.small,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }
          return RefreshIndicator(
            color: MatixColors.accent,
            onRefresh: _refrescar,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                MatixSpacing.xl,
                MatixSpacing.xl,
                MatixSpacing.xl,
                MatixSpacing.xl3,
              ),
              children: [
                if (datos.tareas.isNotEmpty) ...[
                  _Header('Tareas (${datos.tareas.length})'),
                  for (final t in datos.tareas)
                    _ItemCard(
                      titulo: t.titulo,
                      subtitulo: 'Tarea',
                      onRestaurar: () => _restaurarTarea(t),
                    ),
                  const SizedBox(height: MatixSpacing.xl),
                ],
                if (datos.eventos.isNotEmpty) ...[
                  _Header('Eventos (${datos.eventos.length})'),
                  for (final e in datos.eventos)
                    _ItemCard(
                      titulo: e.titulo,
                      subtitulo: 'Evento',
                      onRestaurar: () => _restaurarEvento(e),
                    ),
                  const SizedBox(height: MatixSpacing.xl),
                ],
                if (datos.apuntes.isNotEmpty) ...[
                  _Header('Apuntes (${datos.apuntes.length})'),
                  for (final a in datos.apuntes)
                    _ItemCard(
                      titulo: a.titulo,
                      subtitulo: 'Apunte',
                      onRestaurar: () => _restaurarApunte(a),
                    ),
                  const SizedBox(height: MatixSpacing.xl),
                ],
                const SizedBox(height: MatixSpacing.l),
                OutlinedButton.icon(
                  onPressed: () => _vaciarTodo(datos),
                  icon: const Icon(Icons.delete_forever),
                  label: Text('Vaciar papelera (${datos.total})'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: MatixColors.red,
                    side: const BorderSide(color: MatixColors.red),
                    padding: const EdgeInsets.symmetric(
                      vertical: MatixSpacing.xl,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _DatosPapelera {
  const _DatosPapelera({
    required this.tareas,
    required this.eventos,
    required this.apuntes,
  });

  const _DatosPapelera.vacia()
      : tareas = const <Tarea>[],
        eventos = const <Evento>[],
        apuntes = const <Apunte>[];

  final List<Tarea> tareas;
  final List<Evento> eventos;
  final List<Apunte> apuntes;

  int get total => tareas.length + eventos.length + apuntes.length;
}

class _Header extends StatelessWidget {
  const _Header(this.texto);
  final String texto;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: MatixSpacing.m),
      child: Text(
        texto,
        style: MatixText.micro.copyWith(
          color: MatixColors.muted,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _ItemCard extends StatelessWidget {
  const _ItemCard({
    required this.titulo,
    required this.subtitulo,
    required this.onRestaurar,
  });

  final String titulo;
  final String subtitulo;
  final Future<void> Function() onRestaurar;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: MatixSpacing.m),
      padding: const EdgeInsets.fromLTRB(
        MatixSpacing.xl,
        MatixSpacing.l,
        MatixSpacing.m,
        MatixSpacing.l,
      ),
      decoration: BoxDecoration(
        color: MatixColors.card,
        border: Border.all(color: MatixColors.hairline),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: MatixText.body,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: MatixSpacing.xs),
                Text(subtitulo, style: MatixText.caption),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: () async {
              await onRestaurar();
            },
            icon: const Icon(Icons.restore, size: 18),
            label: const Text('Restaurar'),
            style: TextButton.styleFrom(
              foregroundColor: MatixColors.accent,
            ),
          ),
        ],
      ),
    );
  }
}
