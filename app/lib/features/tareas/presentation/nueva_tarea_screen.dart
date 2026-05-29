import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../api/matix_client.dart';
import '../../../core/undo_snackbar.dart';
import '../../../core/urgencia.dart';
import '../../../theme/matix_colors.dart';
import '../../nudges/providers/nudges_providers.dart';
import '../domain/selectores.dart';
import '../domain/tarea.dart';
import '../providers/tareas_providers.dart';

class NuevaTareaScreen extends ConsumerStatefulWidget {
  const NuevaTareaScreen({super.key, this.tareaId});

  /// Si viene, la pantalla edita una tarea existente. Si es null, crea
  /// una nueva.
  final String? tareaId;

  @override
  ConsumerState<NuevaTareaScreen> createState() => _NuevaTareaScreenState();
}

class _NuevaTareaScreenState extends ConsumerState<NuevaTareaScreen> {
  final _formKey = GlobalKey<FormState>();
  final _tituloCtrl = TextEditingController();
  final _notaCtrl = TextEditingController();
  final _nuevaSubCtrl = TextEditingController();

  DateTime? _venceEn;
  DateTime? _recordarEn;
  Prioridad _prioridad = Prioridad.media;
  Repeticion? _repeticion;
  String? _categoriaId;
  String? _cursoId;
  String? _proyectoId;

  /// Urgencia-2: si está en true, esta tarea NO manda nudges escalados
  /// (interruptor por tarea). Se persiste en prefs, no en el hub.
  bool _nudgesSilenciados = false;

  bool _cargandoInicial = false;
  bool _guardando = false;
  String? _error;

  bool get _esEdicion => widget.tareaId != null;

  @override
  void initState() {
    super.initState();
    if (_esEdicion) _cargarTarea();
  }

  @override
  void dispose() {
    _tituloCtrl.dispose();
    _notaCtrl.dispose();
    _nuevaSubCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargarTarea() async {
    setState(() => _cargandoInicial = true);
    try {
      final t = await ref.read(tareasRepositoryProvider).obtener(widget.tareaId!);
      final silenciada =
          await ref.read(nudgesPrefsProvider).estaSilenciada(widget.tareaId!);
      setState(() {
        _tituloCtrl.text = t.titulo;
        _notaCtrl.text = t.nota ?? '';
        _venceEn = t.venceEn?.toLocal();
        _recordarEn = t.recordarEn?.toLocal();
        _prioridad = t.prioridad;
        _repeticion = t.repeticion;
        _categoriaId = t.categoriaId;
        _cursoId = t.cursoId;
        _proyectoId = t.proyectoId;
        _nudgesSilenciados = silenciada;
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _cargandoInicial = false);
    }
  }

  Future<void> _guardar() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_recordarEn != null &&
        _venceEn != null &&
        _recordarEn!.isAfter(_venceEn!)) {
      setState(() => _error =
          'El recordatorio es posterior al vencimiento. Ajústalo.');
      return;
    }
    setState(() {
      _guardando = true;
      _error = null;
    });
    final repo = ref.read(tareasRepositoryProvider);
    try {
      if (_esEdicion) {
        // Persistimos el interruptor de nudges ANTES de actualizar: la
        // reprogramación que dispara `actualizar` lee este valor.
        await ref
            .read(nudgesPrefsProvider)
            .setSilenciada(widget.tareaId!, _nudgesSilenciados);
        await repo.actualizar(widget.tareaId!, {
          'titulo': _tituloCtrl.text.trim(),
          'nota': _notaCtrl.text.trim().isEmpty ? null : _notaCtrl.text.trim(),
          'vence_en': _venceEn?.toUtc().toIso8601String(),
          'prioridad': _prioridad.toJson(),
          'categoria_id': _categoriaId,
          'curso_id': _cursoId,
          'proyecto_id': _proyectoId,
          'repeticion': _repeticion?.toJson(),
          'recordar_en': _recordarEn?.toUtc().toIso8601String(),
        });
      } else {
        await repo.crear(
          titulo: _tituloCtrl.text.trim(),
          nota: _notaCtrl.text.trim().isEmpty ? null : _notaCtrl.text.trim(),
          venceEn: _venceEn,
          prioridad: _prioridad,
          categoriaId: _categoriaId,
          cursoId: _cursoId,
          proyectoId: _proyectoId,
          repeticion: _repeticion,
          recordarEn: _recordarEn,
        );
      }
      ref.invalidate(tareasProvider);
      if (mounted) Navigator.of(context).pop();
    } on MatixApiException catch (e) {
      setState(() => _error = 'Error ${e.statusCode}: ${e.message}');
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Future<void> _confirmarBorrar() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Borrar tarea'),
        content: const Text(
          'La tarea se mueve a la papelera. Podés restaurarla desde '
          'Ajustes → Papelera.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: MatixColors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Borrar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final repo = ref.read(tareasRepositoryProvider);
    final tareaId = widget.tareaId!;
    // Guardamos el título para el snackbar antes de borrar.
    final titulo = _tituloCtrl.text.trim();
    try {
      await repo.borrar(tareaId);
      ref.invalidate(tareasProvider);
      if (!mounted) return;
      Navigator.of(context).pop();
      // El usuario ya volvió a la lista — el snackbar aparece allí
      // sobre el Scaffold padre. El ScaffoldMessenger es de toda
      // la app, así que funciona.
      mostrarSnackbarDeshacer(
        context,
        mensaje: titulo.isEmpty
            ? 'Tarea en la papelera'
            : '«$titulo» en la papelera',
        onUndo: () async {
          await repo.restaurar(tareaId);
          ref.invalidate(tareasProvider);
        },
      );
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final cats = ref.watch(categoriasProvider);
    final cursos = ref.watch(cursosProvider);
    final proys = ref.watch(proyectosProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(_esEdicion ? 'Editar tarea' : 'Nueva tarea'),
        actions: [
          if (_esEdicion)
            IconButton(
              tooltip: 'Borrar',
              onPressed: _guardando ? null : _confirmarBorrar,
              icon: const Icon(Icons.delete_outline, color: MatixColors.red),
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: _cargandoInicial
          ? const Center(child: CircularProgressIndicator(color: MatixColors.accent))
          : SafeArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                children: [
                  Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextFormField(
                          controller: _tituloCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Título',
                          ),
                          autofocus: !_esEdicion,
                          validator: (s) => (s == null || s.trim().isEmpty)
                              ? 'Pon un título'
                              : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _notaCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Nota (opcional)',
                          ),
                          minLines: 1,
                          maxLines: 4,
                        ),

                        const _SeccionTitulo('Prioridad'),
                        _PrioridadSelector(
                          actual: _prioridad,
                          onChanged: (p) => setState(() => _prioridad = p),
                        ),

                        const _SeccionTitulo('Vencimiento'),
                        _DateTimeRow(
                          valor: _venceEn,
                          onPick: (v) => setState(() => _venceEn = v),
                          onClear: () => setState(() => _venceEn = null),
                          placeholder: 'Sin fecha',
                        ),
                        // Cuenta regresiva viva: la presión se ve en el
                        // detalle, no se grita.
                        if (_venceEn != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8, left: 2),
                            child: ContadorUrgencia(
                              objetivo: _venceEn!,
                              fondo: true,
                            ),
                          ),
                        // Urgencia-2: interruptor de nudges por tarea. Solo
                        // tiene sentido al editar una tarea con plazo.
                        if (_esEdicion && _venceEn != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              dense: true,
                              value: !_nudgesSilenciados,
                              onChanged: (v) =>
                                  setState(() => _nudgesSilenciados = !v),
                              title: const Text(
                                'Avisos de urgencia',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: MatixColors.text,
                                ),
                              ),
                              subtitle: Text(
                                _nudgesSilenciados
                                    ? 'Apagados para esta tarea'
                                    : 'Te avisaré más seguido al acercarse',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: MatixColors.muted,
                                ),
                              ),
                            ),
                          ),

                        const _SeccionTitulo('Recordatorio'),
                        _DateTimeRow(
                          valor: _recordarEn,
                          onPick: (v) => setState(() => _recordarEn = v),
                          onClear: () => setState(() => _recordarEn = null),
                          placeholder: 'Sin recordatorio',
                        ),

                        const _SeccionTitulo('Repetición'),
                        _RepeticionSelector(
                          actual: _repeticion,
                          onChanged: (r) => setState(() => _repeticion = r),
                        ),

                        const _SeccionTitulo('Curso'),
                        _DropdownRef(
                          datos: cursos,
                          seleccionado: _cursoId,
                          onChanged: (id) => setState(() => _cursoId = id),
                          itemNombre: (c) => (c as CursoRef).nombre,
                          itemId: (c) => (c as CursoRef).id,
                          placeholder: 'Sin curso',
                        ),

                        const _SeccionTitulo('Categoría'),
                        _DropdownRef(
                          datos: cats,
                          seleccionado: _categoriaId,
                          onChanged: (id) => setState(() => _categoriaId = id),
                          itemNombre: (c) => (c as CategoriaRef).nombre,
                          itemId: (c) => (c as CategoriaRef).id,
                          placeholder: 'Sin categoría',
                        ),

                        const _SeccionTitulo('Proyecto'),
                        _DropdownRef(
                          datos: proys,
                          seleccionado: _proyectoId,
                          onChanged: (id) => setState(() => _proyectoId = id),
                          itemNombre: (p) {
                            final ref = p as ProyectoRef;
                            return ref.esActivo
                                ? ref.nombre
                                : '${ref.nombre}  ·  ${ref.estado}';
                          },
                          itemId: (p) => (p as ProyectoRef).id,
                          placeholder: 'Sin proyecto',
                        ),
                      ],
                    ),
                  ),

                  if (_esEdicion) ...[
                    const _SeccionTitulo('Subtareas'),
                    _SubtareasInline(tareaId: widget.tareaId!),
                  ],

                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: MatixColors.red.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        _error!,
                        style: const TextStyle(
                          color: MatixColors.red,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _guardando ? null : _guardar,
                    style: FilledButton.styleFrom(
                      backgroundColor: MatixColors.accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: _guardando
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2.2,
                            ),
                          )
                        : Text(_esEdicion ? 'Guardar cambios' : 'Crear tarea'),
                  ),
                ],
              ),
            ),
    );
  }
}

class _SeccionTitulo extends StatelessWidget {
  const _SeccionTitulo(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 24, 0, 10),
      child: Text(
        text.toUpperCase(),
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

class _PrioridadSelector extends StatelessWidget {
  const _PrioridadSelector({required this.actual, required this.onChanged});
  final Prioridad actual;
  final ValueChanged<Prioridad> onChanged;

  @override
  Widget build(BuildContext context) {
    final colores = {
      Prioridad.alta: MatixColors.red,
      Prioridad.media: MatixColors.amber,
      Prioridad.baja: MatixColors.accent,
    };
    return Wrap(
      spacing: 8,
      children: Prioridad.values.map((p) {
        final activo = p == actual;
        final color = colores[p]!;
        return InkWell(
          onTap: () => onChanged(p),
          borderRadius: BorderRadius.circular(99),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            decoration: BoxDecoration(
              color: activo ? color : MatixColors.card,
              borderRadius: BorderRadius.circular(99),
            ),
            child: Text(
              p.label,
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

class _RepeticionSelector extends StatelessWidget {
  const _RepeticionSelector({required this.actual, required this.onChanged});
  final Repeticion? actual;
  final ValueChanged<Repeticion?> onChanged;

  @override
  Widget build(BuildContext context) {
    final opciones = <(String, Repeticion?)>[
      ('Una vez', null),
      ('Diaria', Repeticion.diaria),
      ('Semanal', Repeticion.semanal),
      ('Mensual', Repeticion.mensual),
      ('Anual', Repeticion.anual),
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: opciones.map((opt) {
        final activo = opt.$2 == actual;
        return InkWell(
          onTap: () => onChanged(opt.$2),
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

class _DateTimeRow extends StatelessWidget {
  const _DateTimeRow({
    required this.valor,
    required this.onPick,
    required this.onClear,
    required this.placeholder,
  });
  final DateTime? valor;
  final ValueChanged<DateTime?> onPick;
  final VoidCallback onClear;
  final String placeholder;

  Future<void> _pick(BuildContext context) async {
    final ahora = DateTime.now();
    final fecha = await showDatePicker(
      context: context,
      initialDate: valor ?? ahora,
      firstDate: DateTime(ahora.year - 1),
      lastDate: DateTime(ahora.year + 5),
    );
    if (fecha == null) return;
    if (!context.mounted) return;
    final hora = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(valor ?? ahora),
    );
    if (hora == null) return;
    onPick(DateTime(fecha.year, fecha.month, fecha.day, hora.hour, hora.minute));
  }

  @override
  Widget build(BuildContext context) {
    final hasVal = valor != null;
    return Row(
      children: [
        Expanded(
          child: InkWell(
            onTap: () => _pick(context),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                color: MatixColors.card,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.event, size: 18, color: MatixColors.muted),
                  const SizedBox(width: 10),
                  Text(
                    hasVal
                        ? DateFormat("EEE d MMM 'a las' HH:mm", 'es')
                            .format(valor!)
                        : placeholder,
                    style: TextStyle(
                      fontSize: 14,
                      color: hasVal ? MatixColors.text : MatixColors.muted,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (hasVal)
          IconButton(
            tooltip: 'Quitar',
            onPressed: onClear,
            icon: const Icon(Icons.close, color: MatixColors.muted),
          ),
      ],
    );
  }
}

class _DropdownRef extends StatelessWidget {
  const _DropdownRef({
    required this.datos,
    required this.seleccionado,
    required this.onChanged,
    required this.itemNombre,
    required this.itemId,
    required this.placeholder,
  });
  final AsyncValue<List<Object>> datos;
  final String? seleccionado;
  final ValueChanged<String?> onChanged;
  final String Function(Object item) itemNombre;
  final String Function(Object item) itemId;
  final String placeholder;

  @override
  Widget build(BuildContext context) {
    return datos.when(
      loading: () => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: MatixColors.card,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Text(
          'Cargando…',
          style: TextStyle(color: MatixColors.muted, fontSize: 13),
        ),
      ),
      error: (e, _) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: MatixColors.red.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          'Error: $e',
          style: const TextStyle(color: MatixColors.red, fontSize: 12),
        ),
      ),
      data: (items) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: MatixColors.card,
          borderRadius: BorderRadius.circular(12),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String?>(
            value: seleccionado,
            isExpanded: true,
            dropdownColor: MatixColors.cardHi,
            iconEnabledColor: MatixColors.muted,
            hint: Text(
              placeholder,
              style: const TextStyle(color: MatixColors.muted, fontSize: 14),
            ),
            items: [
              DropdownMenuItem<String?>(
                value: null,
                child: Text(
                  placeholder,
                  style: const TextStyle(
                    color: MatixColors.muted,
                    fontSize: 14,
                  ),
                ),
              ),
              ...items.map(
                (it) {
                  // cast genérico
                  final raw = it as dynamic;
                  return DropdownMenuItem<String?>(
                    value: itemId(raw as Object),
                    child: Text(
                      itemNombre(raw),
                      style: const TextStyle(
                        color: MatixColors.text,
                        fontSize: 14,
                      ),
                    ),
                  );
                },
              ),
            ],
            onChanged: onChanged,
          ),
        ),
      ),
    );
  }
}

// ─── Subtareas inline ────────────────────────────────────────────────────

class _SubtareasInline extends ConsumerStatefulWidget {
  const _SubtareasInline({required this.tareaId});
  final String tareaId;
  @override
  ConsumerState<_SubtareasInline> createState() => _SubtareasInlineState();
}

class _SubtareasInlineState extends ConsumerState<_SubtareasInline> {
  final _nuevaCtrl = TextEditingController();
  bool _agregando = false;

  @override
  void dispose() {
    _nuevaCtrl.dispose();
    super.dispose();
  }

  Future<void> _agregar() async {
    final t = _nuevaCtrl.text.trim();
    if (t.isEmpty) return;
    setState(() => _agregando = true);
    final repo = ref.read(tareasRepositoryProvider);
    try {
      final actuales =
          await ref.read(subtareasDeProvider(widget.tareaId).future);
      await repo.crearSubtarea(
        tareaId: widget.tareaId,
        titulo: t,
        orden: actuales.length,
      );
      _nuevaCtrl.clear();
      ref.invalidate(subtareasDeProvider(widget.tareaId));
    } finally {
      if (mounted) setState(() => _agregando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(tareasRepositoryProvider);
    final subs = ref.watch(subtareasDeProvider(widget.tareaId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        subs.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: MatixColors.accent,
                ),
              ),
            ),
          ),
          error: (e, _) => Text(
            'Error cargando subtareas: $e',
            style: const TextStyle(color: MatixColors.red, fontSize: 12),
          ),
          data: (lista) => Column(
            children: lista
                .map(
                  (s) => Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: MatixColors.card,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: () async {
                            await repo.actualizarSubtarea(
                              s.id,
                              {'completada': !s.completada},
                            );
                            ref.invalidate(
                              subtareasDeProvider(widget.tareaId),
                            );
                          },
                          child: Container(
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: s.completada
                                  ? MatixColors.green
                                  : Colors.transparent,
                              border: s.completada
                                  ? null
                                  : Border.all(
                                      color: Colors.white
                                          .withValues(alpha: 0.18),
                                      width: 1.6,
                                    ),
                            ),
                            child: s.completada
                                ? const Icon(
                                    Icons.check,
                                    size: 13,
                                    color: MatixColors.bg,
                                  )
                                : null,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            s.titulo,
                            style: TextStyle(
                              fontSize: 13.5,
                              color: s.completada
                                  ? MatixColors.muted
                                  : MatixColors.text,
                              decoration: s.completada
                                  ? TextDecoration.lineThrough
                                  : TextDecoration.none,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Borrar',
                          iconSize: 18,
                          onPressed: () async {
                            await repo.borrarSubtarea(s.id);
                            ref.invalidate(
                              subtareasDeProvider(widget.tareaId),
                            );
                          },
                          icon: const Icon(
                            Icons.delete_outline,
                            color: MatixColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _nuevaCtrl,
                decoration: const InputDecoration(
                  hintText: 'Añadir subtarea',
                  isDense: true,
                ),
                onSubmitted: (_) => _agregar(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: _agregando ? null : _agregar,
              icon: const Icon(Icons.add_circle, color: MatixColors.accent),
            ),
          ],
        ),
      ],
    );
  }
}
