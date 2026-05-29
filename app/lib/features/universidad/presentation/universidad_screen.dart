import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/matix_colors.dart';
import '../../../theme/matix_spacing.dart';
import '../../cursos/domain/curso.dart';
import '../../matix/presentation/manos_libres_screen.dart';
import '../providers/universidad_providers.dart';
import 'detalle_curso_screen.dart';
import 'nuevo_curso_screen.dart';

class UniversidadScreen extends ConsumerWidget {
  const UniversidadScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cursos = ref.watch(cursosListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Universidad'),
        actions: [
          // Sesión de estudio por voz (Capa 3 Paso 3). Abre manos
          // libres con un seed que pone a Matix en modo "tutor de
          // sesión": empieza preguntando qué repasar.
          IconButton(
            tooltip: 'Repasar (sesión de estudio)',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const ManosLibresScreen(
                  seedMensaje:
                      'Quiero una sesión de estudio. Pregúntame de qué '
                      'apunte quieres tomarme examen.',
                ),
              ),
            ),
            icon: const Icon(Icons.psychology_alt_outlined),
          ),
          IconButton(
            tooltip: 'Nuevo curso',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const NuevoCursoScreen()),
            ),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: cursos.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: MatixColors.accent),
        ),
        error: (e, _) => Center(child: Text(e.toString())),
        data: (lista) => lista.isEmpty
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Text(
                    'No tienes cursos registrados.\nUsa el + para añadir el primero.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: MatixColors.muted),
                  ),
                ),
              )
            : RefreshIndicator(
                color: MatixColors.accent,
                onRefresh: () async => ref.invalidate(cursosListProvider),
                child: ListView.builder(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    8,
                    16,
                    MatixLayout.bottomNavGuard(context),
                  ),
                  itemCount: lista.length,
                  itemBuilder: (_, i) => _CursoCard(curso: lista[i]),
                ),
              ),
      ),
    );
  }
}

class _CursoCard extends StatelessWidget {
  const _CursoCard({required this.curso});
  final Curso curso;
  @override
  Widget build(BuildContext context) {
    final color = _colorCurso(curso.color);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Material(
        color: MatixColors.card,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => DetalleCursoScreen(cursoId: curso.id),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.16),
                    border: Border.all(color: color.withValues(alpha: 0.4)),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    curso.nombre.isEmpty ? '?' : curso.nombre[0].toUpperCase(),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: color,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        curso.nombre,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: MatixColors.text,
                        ),
                      ),
                      if (curso.profesor != null)
                        Text(
                          curso.profesor!,
                          style: const TextStyle(
                            fontSize: 12,
                            color: MatixColors.muted,
                          ),
                        ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: MatixColors.muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Color _colorCurso(String? hex) {
  if (hex == null || hex.length != 7) return MatixColors.accent;
  final v = int.tryParse(hex.substring(1), radix: 16);
  return v == null ? MatixColors.accent : Color(0xFF000000 | v);
}
