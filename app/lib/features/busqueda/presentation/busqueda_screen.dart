import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/matix_colors.dart';
import '../../apuntes/domain/apunte.dart';
import '../../apuntes/presentation/editor_apunte_screen.dart';
import '../../apuntes/providers/apuntes_providers.dart';
import '../../cursos/domain/curso.dart';
import '../../proyectos/domain/proyecto.dart';
import '../../proyectos/presentation/detalle_proyecto_screen.dart';
import '../../proyectos/providers/proyectos_providers.dart';
import '../../tareas/domain/tarea.dart';
import '../../tareas/presentation/nueva_tarea_screen.dart';
import '../../tareas/providers/tareas_providers.dart';
import '../../universidad/presentation/detalle_curso_screen.dart';
import '../../universidad/providers/universidad_providers.dart';

/// Búsqueda global por texto sobre todo lo cargado en cliente.
/// Filtra sobre los providers cacheados — no hace queries extra al
/// cerebro.
class BusquedaScreen extends ConsumerStatefulWidget {
  const BusquedaScreen({super.key});
  @override
  ConsumerState<BusquedaScreen> createState() => _BusquedaScreenState();
}

class _BusquedaScreenState extends ConsumerState<BusquedaScreen> {
  final _ctrl = TextEditingController();
  String _q = '';

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final proyectos =
        ref.watch(proyectosListProvider).valueOrNull ?? const <Proyecto>[];
    final tareas =
        ref.watch(tareasProvider).valueOrNull ?? const <Tarea>[];
    final apuntes =
        ref.watch(apuntesListProvider).valueOrNull ?? const <Apunte>[];
    final cursos =
        ref.watch(cursosListProvider).valueOrNull ?? const <Curso>[];

    final q = _q.trim().toLowerCase();
    final pMatch = q.isEmpty
        ? const <Proyecto>[]
        : proyectos
            .where((p) =>
                p.nombre.toLowerCase().contains(q) ||
                (p.descripcion ?? '').toLowerCase().contains(q) ||
                (p.lineaMeta ?? '').toLowerCase().contains(q))
            .toList();
    final tMatch = q.isEmpty
        ? const <Tarea>[]
        : tareas
            .where((t) =>
                t.titulo.toLowerCase().contains(q) ||
                (t.nota ?? '').toLowerCase().contains(q))
            .toList();
    final aMatch = q.isEmpty
        ? const <Apunte>[]
        : apuntes
            .where((a) =>
                a.titulo.toLowerCase().contains(q) ||
                a.contenido.toLowerCase().contains(q) ||
                a.etiquetas.any((e) => e.toLowerCase().contains(q)))
            .toList();
    final cMatch = q.isEmpty
        ? const <Curso>[]
        : cursos
            .where((c) =>
                c.nombre.toLowerCase().contains(q) ||
                (c.profesor ?? '').toLowerCase().contains(q))
            .toList();

    final hayAlgo = pMatch.isNotEmpty ||
        tMatch.isNotEmpty ||
        aMatch.isNotEmpty ||
        cMatch.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Buscar en todo Matix…',
            border: InputBorder.none,
          ),
          style: const TextStyle(fontSize: 16, color: MatixColors.text),
          onChanged: (v) => setState(() => _q = v),
        ),
        actions: [
          if (_q.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () {
                _ctrl.clear();
                setState(() => _q = '');
              },
            ),
        ],
      ),
      body: q.isEmpty
          ? const _Hint()
          : !hayAlgo
              ? const _SinResultados()
              : ListView(
                  padding: const EdgeInsets.fromLTRB(0, 8, 0, 24),
                  children: [
                    if (pMatch.isNotEmpty)
                      _Section('Proyectos · ${pMatch.length}'),
                    ...pMatch.map(
                      (p) => _Tile(
                        icon: Icons.flag,
                        titulo: p.nombre,
                        subtitulo: p.lineaMeta ?? p.estado.label,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                DetalleProyectoScreen(proyectoId: p.id),
                          ),
                        ),
                      ),
                    ),
                    if (tMatch.isNotEmpty)
                      _Section('Tareas · ${tMatch.length}'),
                    ...tMatch.map(
                      (t) => _Tile(
                        icon: Icons.checklist,
                        titulo: t.titulo,
                        subtitulo: t.completada ? 'Completada' : null,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                NuevaTareaScreen(tareaId: t.id),
                          ),
                        ),
                      ),
                    ),
                    if (aMatch.isNotEmpty)
                      _Section('Apuntes · ${aMatch.length}'),
                    ...aMatch.map(
                      (a) => _Tile(
                        icon: Icons.note_alt,
                        titulo: a.titulo,
                        subtitulo: a.contenido.isEmpty
                            ? null
                            : a.contenido.length > 80
                                ? '${a.contenido.substring(0, 80)}…'
                                : a.contenido,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                EditorApunteScreen(apunteId: a.id),
                          ),
                        ),
                      ),
                    ),
                    if (cMatch.isNotEmpty)
                      _Section('Cursos · ${cMatch.length}'),
                    ...cMatch.map(
                      (c) => _Tile(
                        icon: Icons.school,
                        titulo: c.nombre,
                        subtitulo: c.profesor,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                DetalleCursoScreen(cursoId: c.id),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.t);
  final String t;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 16, 22, 6),
      child: Text(
        t.toUpperCase(),
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

class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.titulo,
    required this.onTap,
    this.subtitulo,
  });
  final IconData icon;
  final String titulo;
  final String? subtitulo;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 3, 16, 3),
      child: Material(
        color: MatixColors.card,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(icon, color: MatixColors.accent, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(titulo,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: MatixColors.text,
                          )),
                      if (subtitulo != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitulo!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: MatixColors.muted,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint();
  @override
  Widget build(BuildContext context) => const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'Escribe para buscar en proyectos, tareas, apuntes y cursos.',
            textAlign: TextAlign.center,
            style: TextStyle(color: MatixColors.muted),
          ),
        ),
      );
}

class _SinResultados extends StatelessWidget {
  const _SinResultados();
  @override
  Widget build(BuildContext context) => const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'No hay coincidencias.',
            style: TextStyle(color: MatixColors.muted),
          ),
        ),
      );
}
