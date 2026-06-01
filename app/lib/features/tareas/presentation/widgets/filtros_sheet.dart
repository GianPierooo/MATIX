import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../theme/matix_colors.dart';
import '../../../../widgets/pantalla_scroll.dart';
import '../../domain/tarea.dart';
import '../../providers/tareas_providers.dart';

class FiltrosSheet extends ConsumerWidget {
  const FiltrosSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final f = ref.watch(filtrosTareasProvider);
    final notifier = ref.read(filtrosTareasProvider.notifier);
    final cats = ref.watch(categoriasProvider);
    final cursos = ref.watch(cursosProvider);
    final proys = ref.watch(proyectosProvider);

    return HojaScroll(
      children: [
        Row(
          children: [
            const Text(
              'Filtros',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: MatixColors.text,
              ),
            ),
            const Spacer(),
            TextButton(
              onPressed: f.vacio
                  ? null
                  : () {
                      notifier.limpiar();
                      Navigator.of(context).pop();
                    },
              child: const Text('Limpiar todo'),
            ),
          ],
        ),
        const SizedBox(height: 8),

        _Seccion(
              titulo: 'Prioridad',
              child: _ChipsRow(
                opciones: const [
                  ('Alta', Prioridad.alta),
                  ('Media', Prioridad.media),
                  ('Baja', Prioridad.baja),
                ],
                seleccionado: f.prioridad,
                onTap: (p) => notifier
                    .set(f.copyWith(prioridad: f.prioridad == p ? null : p)),
              ),
            ),

            _Seccion(
              titulo: 'Vencimiento',
              child: _ChipsRow(
                opciones: const [
                  ('Hoy', 1),
                  ('3 días', 3),
                  ('Semana', 7),
                  ('Mes', 30),
                ],
                seleccionado: f.venceEnDias,
                onTap: (d) => notifier.set(
                  f.copyWith(venceEnDias: f.venceEnDias == d ? null : d),
                ),
              ),
            ),

            _SeccionAsync(
              titulo: 'Curso',
              datos: cursos,
              seleccionadoId: f.cursoId,
              builder: (c) => (c.nombre, c.id),
              onTap: (id) => notifier
                  .set(f.copyWith(cursoId: f.cursoId == id ? null : id)),
            ),

            _SeccionAsync(
              titulo: 'Categoría',
              datos: cats,
              seleccionadoId: f.categoriaId,
              builder: (c) => (c.nombre, c.id),
              onTap: (id) => notifier.set(
                f.copyWith(categoriaId: f.categoriaId == id ? null : id),
              ),
            ),

            _SeccionAsync(
              titulo: 'Proyecto',
              datos: proys,
              seleccionadoId: f.proyectoId,
              builder: (p) => (p.nombre, p.id),
              onTap: (id) => notifier
                  .set(f.copyWith(proyectoId: f.proyectoId == id ? null : id)),
            ),

        const SizedBox(height: 16),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Aplicar'),
        ),
      ],
    );
  }
}

class _Seccion extends StatelessWidget {
  const _Seccion({required this.titulo, required this.child});
  final String titulo;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titulo.toUpperCase(),
            style: const TextStyle(
              fontSize: 11.5,
              color: MatixColors.muted,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class _ChipsRow<T> extends StatelessWidget {
  const _ChipsRow({
    required this.opciones,
    required this.seleccionado,
    required this.onTap,
  });
  final List<(String, T)> opciones;
  final T? seleccionado;
  final ValueChanged<T> onTap;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: opciones.map((opt) {
        final activo = seleccionado == opt.$2;
        return InkWell(
          onTap: () => onTap(opt.$2),
          borderRadius: BorderRadius.circular(99),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: activo ? MatixColors.accent : MatixColors.card,
              borderRadius: BorderRadius.circular(99),
            ),
            child: Text(
              opt.$1,
              style: TextStyle(
                fontSize: 13,
                fontWeight: activo ? FontWeight.w600 : FontWeight.w500,
                color: activo ? Colors.white : MatixColors.muted,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _SeccionAsync<T> extends StatelessWidget {
  const _SeccionAsync({
    required this.titulo,
    required this.datos,
    required this.seleccionadoId,
    required this.builder,
    required this.onTap,
  });
  final String titulo;
  final AsyncValue<List<T>> datos;
  final String? seleccionadoId;
  final (String, String) Function(T item) builder;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    return datos.when(
      loading: () => const SizedBox(),
      error: (_, _) => _Seccion(
        titulo: titulo,
        child: const Text(
          'No se pudo cargar',
          style: TextStyle(color: MatixColors.red, fontSize: 12),
        ),
      ),
      data: (items) {
        if (items.isEmpty) return const SizedBox();
        final opciones = items
            .map((item) {
              final (nombre, id) = builder(item);
              return (nombre, id);
            })
            .toList();
        return _Seccion(
          titulo: titulo,
          child: _ChipsRow<String>(
            opciones: opciones,
            seleccionado: seleccionadoId,
            onTap: onTap,
          ),
        );
      },
    );
  }
}
