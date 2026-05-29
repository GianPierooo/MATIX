import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../api/matix_client.dart';
import '../../../core/undo_snackbar.dart';
import '../../../theme/matix_colors.dart';
import '../../../theme/matix_spacing.dart';
import '../../captura_camara/presentation/captura_camara_screen.dart';
import '../domain/selectores.dart';
import '../domain/tarea.dart';
import '../providers/tareas_providers.dart';
import 'nueva_tarea_screen.dart';
import 'widgets/filtros_sheet.dart';
import 'widgets/tarea_tile.dart';

class TareasListScreen extends ConsumerWidget {
  const TareasListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filtros = ref.watch(filtrosTareasProvider);
    final vista = ref.watch(vistaTareasProvider);
    final filtradas = ref.watch(tareasFiltradasProvider);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              DateFormat.yMMMMEEEEd('es').format(DateTime.now()),
              style: const TextStyle(
                fontSize: 12,
                color: MatixColors.muted,
                fontWeight: FontWeight.w500,
              ),
            ),
            const Text(
              'Tareas',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w700,
                color: MatixColors.text,
                letterSpacing: -0.5,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Capturar texto con la cámara',
            onPressed: () => _abrirCaptura(context),
            icon: const Icon(Icons.document_scanner_outlined),
          ),
          IconButton(
            tooltip: 'Filtros',
            onPressed: () => _abrirFiltros(context),
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(Icons.tune),
                if (filtros.activos > 0)
                  Positioned(
                    top: -2,
                    right: -4,
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: const BoxDecoration(
                        color: MatixColors.accent,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '${filtros.activos}',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          SizedBox(
            height: 50,
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              scrollDirection: Axis.horizontal,
              itemCount: VistaTareas.values.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final v = VistaTareas.values[i];
                final activo = v == vista;
                return InkWell(
                  borderRadius: BorderRadius.circular(99),
                  onTap: () => ref.read(vistaTareasProvider.notifier).set(v),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: activo ? MatixColors.accent : MatixColors.card,
                      borderRadius: BorderRadius.circular(99),
                      boxShadow: activo
                          ? [
                              BoxShadow(
                                color: MatixColors.accent.withValues(alpha: 0.35),
                                blurRadius: 14,
                                offset: const Offset(0, 4),
                              ),
                            ]
                          : null,
                    ),
                    child: Center(
                      child: Text(
                        v.label,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: activo ? FontWeight.w600 : FontWeight.w500,
                          color: activo ? Colors.white : MatixColors.muted,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Expanded(
            child: filtradas.when(
              loading: () => const Center(
                child: CircularProgressIndicator(color: MatixColors.accent),
              ),
              error: (e, _) => _Error(
                mensaje: e is MatixApiException ? e.message : e.toString(),
                onRetry: () => ref.invalidate(tareasProvider),
              ),
              data: (lista) => lista.isEmpty
                  ? _Vacio(vista: vista)
                  : RefreshIndicator(
                      color: MatixColors.accent,
                      onRefresh: () async => ref.invalidate(tareasProvider),
                      child: vista == VistaTareas.porCurso
                          ? _ListaPorCurso(tareas: lista)
                          : _ListaPlana(tareas: lista),
                    ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _abrirNueva(context),
        backgroundColor: MatixColors.accent,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Nueva tarea'),
      ),
    );
  }

  void _abrirFiltros(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: MatixColors.cardHi,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => const FiltrosSheet(),
    );
  }

  void _abrirNueva(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const NuevaTareaScreen()),
    );
  }

  // Capa 7-A: por ahora solo abre la pantalla de captura + OCR
  // on-device. Convertir ese texto en tareas es 7-B.
  void _abrirCaptura(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const CapturaCamaraScreen()),
    );
  }
}

class _ListaPlana extends ConsumerWidget {
  const _ListaPlana({required this.tareas});
  final List<Tarea> tareas;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cursos = ref.watch(cursosProvider).valueOrNull ?? const <CursoRef>[];
    final cats = ref.watch(categoriasProvider).valueOrNull ?? const <CategoriaRef>[];
    final repo = ref.watch(tareasRepositoryProvider);

    return ListView.builder(
      padding: EdgeInsets.fromLTRB(
        0,
        4,
        0,
        MatixLayout.bottomNavGuard(context),
      ),
      itemCount: tareas.length,
      itemBuilder: (_, i) {
        final t = tareas[i];
        final meta = _metaSecundaria(t, cursos, cats);
        return TareaTile(
          tarea: t,
          metaSecundaria: meta,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => NuevaTareaScreen(tareaId: t.id),
            ),
          ),
          onToggleCompletada: (v) async {
            await repo.marcarCompletada(t.id, completada: v);
            ref.invalidate(tareasProvider);
            // Solo ofrecemos deshacer al completar (la mayoría de
            // los toques son éste). Al "des-completar" manualmente,
            // el usuario ya está deshaciendo algo: no metemos un
            // segundo snackbar.
            if (v && context.mounted) {
              mostrarSnackbarDeshacer(
                context,
                mensaje: '«${t.titulo}» completada',
                onUndo: () async {
                  await repo.marcarCompletada(t.id, completada: false);
                  ref.invalidate(tareasProvider);
                },
              );
            }
          },
        );
      },
    );
  }
}

class _ListaPorCurso extends ConsumerWidget {
  const _ListaPorCurso({required this.tareas});
  final List<Tarea> tareas;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cursos = ref.watch(cursosProvider).valueOrNull ?? const <CursoRef>[];
    final cats = ref.watch(categoriasProvider).valueOrNull ?? const <CategoriaRef>[];
    final repo = ref.watch(tareasRepositoryProvider);

    final mapaCursos = {for (final c in cursos) c.id: c};
    final grupos = <String, List<Tarea>>{};
    for (final t in tareas) {
      grupos.putIfAbsent(t.cursoId ?? '__sin__', () => []).add(t);
    }
    final keysOrdenadas = grupos.keys.toList()
      ..sort((a, b) {
        final na = mapaCursos[a]?.nombre ?? 'zzz';
        final nb = mapaCursos[b]?.nombre ?? 'zzz';
        return na.compareTo(nb);
      });

    return ListView.builder(
      padding: EdgeInsets.fromLTRB(
        0,
        4,
        0,
        MatixLayout.bottomNavGuard(context),
      ),
      itemCount: keysOrdenadas.length,
      itemBuilder: (_, i) {
        final k = keysOrdenadas[i];
        final curso = mapaCursos[k];
        final lista = grupos[k]!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Text(
                (curso?.nombre ?? 'Sin curso').toUpperCase(),
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0,
                  color: curso?.colorOrAccent ?? MatixColors.muted,
                ),
              ),
            ),
            ...lista.map(
              (t) => TareaTile(
                tarea: t,
                metaSecundaria: _metaSecundaria(t, cursos, cats),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => NuevaTareaScreen(tareaId: t.id),
                  ),
                ),
                onToggleCompletada: (v) async {
                  await repo.marcarCompletada(t.id, completada: v);
                  ref.invalidate(tareasProvider);
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

String? _metaSecundaria(
  Tarea t,
  List<CursoRef> cursos,
  List<CategoriaRef> cats,
) {
  if (t.cursoId != null) {
    final c = cursos.firstWhere(
      (e) => e.id == t.cursoId,
      orElse: () => const CursoRef(id: '', nombre: 'Curso'),
    );
    return c.nombre;
  }
  if (t.categoriaId != null) {
    final c = cats.firstWhere(
      (e) => e.id == t.categoriaId,
      orElse: () => const CategoriaRef(id: '', nombre: 'Categoría'),
    );
    return c.nombre;
  }
  return null;
}

class _Vacio extends StatelessWidget {
  const _Vacio({required this.vista});
  final VistaTareas vista;
  @override
  Widget build(BuildContext context) {
    final msg = switch (vista) {
      VistaTareas.hoy => 'No tienes tareas para hoy.',
      VistaTareas.semana => 'Nada planificado esta semana.',
      VistaTareas.todas => 'Aún no has creado ninguna tarea.',
      VistaTareas.completadas => 'No hay tareas completadas todavía.',
      VistaTareas.porCurso => 'Ninguna tarea asociada a un curso.',
    };
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.check_circle_outline,
              color: MatixColors.muted,
              size: 56,
            ),
            const SizedBox(height: 16),
            Text(
              msg,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                color: MatixColors.muted,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Error extends StatelessWidget {
  const _Error({required this.mensaje, required this.onRetry});
  final String mensaje;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: MatixColors.red, size: 40),
            const SizedBox(height: 12),
            const Text(
              'No se pudieron cargar las tareas',
              style: TextStyle(fontSize: 16, color: MatixColors.text),
            ),
            const SizedBox(height: 6),
            Text(
              mensaje,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: MatixColors.muted),
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Reintentar')),
          ],
        ),
      ),
    );
  }
}
