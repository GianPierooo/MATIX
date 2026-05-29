import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../api/matix_client.dart';
import '../../../theme/matix_colors.dart';
import '../domain/track.dart';
import '../providers/tracks_providers.dart';

/// Vista para manejar los tracks de aprendizaje (Fase 2): listar activos
/// y en pausa, crear, fijar posición, activar / pausar, borrar.
class TracksScreen extends ConsumerWidget {
  const TracksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(tracksListProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Aprendizaje'),
        actions: [
          IconButton(
            tooltip: 'Nuevo track',
            icon: const Icon(Icons.add),
            onPressed: () => _crear(context, ref),
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: MatixColors.accent),
        ),
        error: (e, _) => Center(child: Text('No pude cargar tus tracks.\n$e')),
        data: (tracks) {
          if (tracks.isEmpty) {
            return _Vacio(onNuevo: () => _crear(context, ref));
          }
          final activos = tracksActivos(tracks);
          final pausados = tracksPausados(tracks);
          return ListView(
            padding: const EdgeInsets.fromLTRB(0, 8, 0, 24),
            children: [
              _Etiqueta('Activos (${activos.length}/$kTopeTracksActivos)'),
              if (activos.isEmpty)
                const _Hint('Ninguno activo. Activa uno para enfocarte.'),
              for (final t in activos) _TrackCard(track: t),
              if (pausados.isNotEmpty) ...[
                const _Etiqueta('En pausa'),
                for (final t in pausados) _TrackCard(track: t),
              ],
            ],
          );
        },
      ),
    );
  }

  Future<void> _crear(BuildContext context, WidgetRef ref) async {
    final datos = await _dialogoCrear(context);
    if (datos == null) return;
    try {
      await ref.read(tracksRepoProvider).crear(
            nombre: datos.$1,
            descripcion: datos.$2,
            bloqueActual: datos.$3,
          );
      ref.invalidate(tracksListProvider);
    } on MatixApiException catch (e) {
      if (context.mounted) _snack(context, e.message);
    } catch (e) {
      if (context.mounted) _snack(context, 'No pude crear el track: $e');
    }
  }
}

void _snack(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));
}

/// Devuelve (nombre, descripcion, bloque) o null si se cancela.
Future<(String, String?, String?)?> _dialogoCrear(BuildContext context) {
  final nombre = TextEditingController();
  final desc = TextEditingController();
  final bloque = TextEditingController();
  return showDialog<(String, String?, String?)>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Nuevo track'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: nombre,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Skill (ej. Calistenia)',
            ),
          ),
          TextField(
            controller: desc,
            decoration: const InputDecoration(labelText: 'Descripción (opcional)'),
          ),
          TextField(
            controller: bloque,
            decoration: const InputDecoration(
              labelText: 'Bloque actual (opcional)',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            final n = nombre.text.trim();
            if (n.isEmpty) return;
            Navigator.pop(context, (
              n,
              desc.text.trim().isEmpty ? null : desc.text.trim(),
              bloque.text.trim().isEmpty ? null : bloque.text.trim(),
            ));
          },
          child: const Text('Crear'),
        ),
      ],
    ),
  );
}

class _TrackCard extends ConsumerWidget {
  const _TrackCard({required this.track});
  final Track track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(tracksRepoProvider);
    final color = track.activo ? MatixColors.accent : MatixColors.muted;

    Future<void> hacer(Future<void> Function() accion, String errPrefix) async {
      try {
        await accion();
        ref.invalidate(tracksListProvider);
      } on MatixApiException catch (e) {
        if (context.mounted) _snack(context, e.message);
      } catch (e) {
        if (context.mounted) _snack(context, '$errPrefix: $e');
      }
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 3, 16, 3),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
        decoration: BoxDecoration(
          color: MatixColors.card,
          borderRadius: BorderRadius.circular(12),
          border: Border(left: BorderSide(color: color, width: 3)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.nombre,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: MatixColors.text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    track.posicionLabel,
                    style: TextStyle(fontSize: 12.5, color: color),
                  ),
                  if (track.descripcion != null &&
                      track.descripcion!.trim().isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      track.descripcion!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12, color: MatixColors.muted),
                    ),
                  ],
                ],
              ),
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: MatixColors.muted),
              onSelected: (v) async {
                switch (v) {
                  case 'posicion':
                    final pos = await _dialogoPosicion(context, track);
                    if (pos == null) break;
                    await hacer(
                      () => repo.fijarPosicion(track.id,
                          bloqueActual: pos.$1, semana: pos.$2, dia: pos.$3),
                      'No pude fijar la posición',
                    );
                  case 'estado':
                    await hacer(
                      () => track.activo
                          ? repo.pausar(track.id)
                          : repo.activar(track.id),
                      'No pude cambiar el estado',
                    );
                  case 'borrar':
                    await hacer(
                        () => repo.borrar(track.id), 'No pude borrar');
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                    value: 'posicion', child: Text('Fijar posición')),
                PopupMenuItem(
                  value: 'estado',
                  child: Text(track.activo ? 'Pausar' : 'Activar'),
                ),
                const PopupMenuItem(value: 'borrar', child: Text('Borrar')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Devuelve (bloque, semana, dia) o null si se cancela.
Future<(String?, int?, int?)?> _dialogoPosicion(
    BuildContext context, Track track) {
  final bloque = TextEditingController(text: track.bloqueActual ?? '');
  final semana = TextEditingController(text: track.semana?.toString() ?? '');
  final dia = TextEditingController(text: track.dia?.toString() ?? '');
  return showDialog<(String?, int?, int?)>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Fijar posición'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: bloque,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Bloque (ej. Bloque 3)'),
          ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: semana,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Semana'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: dia,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Día'),
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, (
            bloque.text.trim().isEmpty ? null : bloque.text.trim(),
            int.tryParse(semana.text.trim()),
            int.tryParse(dia.text.trim()),
          )),
          child: const Text('Guardar'),
        ),
      ],
    ),
  );
}

class _Etiqueta extends StatelessWidget {
  const _Etiqueta(this.texto);
  final String texto;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 16, 14, 6),
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

class _Hint extends StatelessWidget {
  const _Hint(this.texto);
  final String texto;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 2),
      child: Text(texto,
          style: const TextStyle(fontSize: 13, color: MatixColors.muted)),
    );
  }
}

class _Vacio extends StatelessWidget {
  const _Vacio({required this.onNuevo});
  final VoidCallback onNuevo;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.school_outlined,
                color: MatixColors.muted, size: 48),
            const SizedBox(height: 16),
            const Text(
              'Aún no tienes tracks de aprendizaje.\nCada skill que practicas '
              'de forma continua es un track.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: MatixColors.muted),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onNuevo,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Empezar un track'),
              style: FilledButton.styleFrom(
                backgroundColor: MatixColors.accent,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
