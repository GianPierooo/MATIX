import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../api/matix_client.dart';
import '../../../theme/matix_colors.dart';
import '../../cursos/domain/curso.dart';
import '../../universidad/providers/universidad_providers.dart';
import '../domain/evento.dart';
import '../providers/eventos_providers.dart';

/// Alta y edición de un evento del calendario nativo.
///
/// Si recibe `evento`, entra en modo edición: precarga los campos,
/// guarda con PATCH y ofrece borrar. Sin `evento`, crea uno nuevo.
class NuevoEventoScreen extends ConsumerStatefulWidget {
  const NuevoEventoScreen({super.key, this.evento});

  /// Evento a editar. `null` = alta.
  final Evento? evento;

  @override
  ConsumerState<NuevoEventoScreen> createState() =>
      _NuevoEventoScreenState();
}

class _NuevoEventoScreenState extends ConsumerState<NuevoEventoScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titulo;
  late final TextEditingController _ubicacion;
  late DateTime _inicia;
  DateTime? _termina;
  DateTime? _recordar;
  bool _todoElDia = false;
  String? _cursoId;
  bool _guardando = false;
  bool _borrando = false;
  String? _error;

  bool get _editando => widget.evento != null;

  @override
  void initState() {
    super.initState();
    final e = widget.evento;
    _titulo = TextEditingController(text: e?.titulo ?? '');
    _ubicacion = TextEditingController(text: e?.ubicacion ?? '');
    _inicia =
        e?.iniciaEn.toLocal() ?? DateTime.now().add(const Duration(hours: 1));
    _termina = e?.terminaEn?.toLocal();
    _recordar = e?.recordarEn?.toLocal();
    _todoElDia = e?.todoElDia ?? false;
    _cursoId = e?.cursoId;
  }

  @override
  void dispose() {
    _titulo.dispose();
    _ubicacion.dispose();
    super.dispose();
  }

  Future<DateTime?> _pickDateTime(DateTime base) async {
    final fecha = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: DateTime.now().subtract(const Duration(days: 365 * 2)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );
    if (fecha == null || !mounted) return null;
    final hora = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(base),
    );
    if (hora == null) return null;
    return DateTime(fecha.year, fecha.month, fecha.day, hora.hour, hora.minute);
  }

  Future<void> _guardar() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _guardando = true;
      _error = null;
    });
    final repo = ref.read(eventosRepositoryProvider);
    final ubic =
        _ubicacion.text.trim().isEmpty ? null : _ubicacion.text.trim();
    try {
      if (_editando) {
        await repo.actualizar(widget.evento!.id, {
          'titulo': _titulo.text.trim(),
          'inicia_en': _inicia.toUtc().toIso8601String(),
          'termina_en': _termina?.toUtc().toIso8601String(),
          'todo_el_dia': _todoElDia,
          'ubicacion': ubic,
          'curso_id': _cursoId,
          'recordar_en': _recordar?.toUtc().toIso8601String(),
        });
      } else {
        await repo.crear(
          titulo: _titulo.text.trim(),
          iniciaEn: _inicia,
          terminaEn: _termina,
          todoElDia: _todoElDia,
          ubicacion: ubic,
          cursoId: _cursoId,
          recordarEn: _recordar,
        );
      }
      ref.invalidate(eventosProvider);
      if (mounted) Navigator.of(context).pop();
    } on MatixApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Future<void> _borrar() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('¿Borrar este evento?'),
        content: Text(
          'Vas a mandar "${widget.evento!.titulo}" a la papelera. '
          'Puedes restaurarlo desde Ajustes.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: MatixColors.red),
            child: const Text('Borrar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() {
      _borrando = true;
      _error = null;
    });
    try {
      await ref.read(eventosRepositoryProvider).borrar(widget.evento!.id);
      ref.invalidate(eventosProvider);
      if (mounted) Navigator.of(context).pop();
    } on MatixApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _borrando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cursos = ref.watch(cursosListProvider).valueOrNull ?? const <Curso>[];
    return Scaffold(
      appBar: AppBar(
        title: Text(_editando ? 'Editar evento' : 'Nuevo evento'),
        actions: [
          if (_editando)
            IconButton(
              tooltip: 'Borrar',
              onPressed: _borrando || _guardando ? null : _borrar,
              icon: _borrando
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          color: MatixColors.red, strokeWidth: 2.2),
                    )
                  : const Icon(Icons.delete_outline, color: MatixColors.red),
            ),
        ],
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            children: [
              TextFormField(
                controller: _titulo,
                decoration: const InputDecoration(labelText: 'Título'),
                autofocus: !_editando,
                validator: (s) =>
                    (s == null || s.trim().isEmpty) ? 'Pon un título' : null,
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                title: const Text('Todo el día'),
                value: _todoElDia,
                onChanged: (v) => setState(() => _todoElDia = v),
                contentPadding: EdgeInsets.zero,
              ),
              _Pick(
                label: 'Inicia',
                value: DateFormat("EEE d MMM HH:mm", 'es').format(_inicia),
                onTap: () async {
                  final d = await _pickDateTime(_inicia);
                  if (d != null) setState(() => _inicia = d);
                },
              ),
              _Pick(
                label: 'Termina (opcional)',
                value: _termina == null
                    ? 'Sin fin definido'
                    : DateFormat("EEE d MMM HH:mm", 'es').format(_termina!),
                onTap: () async {
                  final d = await _pickDateTime(_termina ?? _inicia);
                  if (d != null) setState(() => _termina = d);
                },
                onClear: _termina == null
                    ? null
                    : () => setState(() => _termina = null),
              ),
              _Pick(
                label: 'Recordatorio',
                value: _recordar == null
                    ? 'Sin recordatorio'
                    : DateFormat("EEE d MMM HH:mm", 'es').format(_recordar!),
                onTap: () async {
                  final d = await _pickDateTime(
                      _recordar ?? _inicia.subtract(const Duration(minutes: 15)));
                  if (d != null) setState(() => _recordar = d);
                },
                onClear: _recordar == null
                    ? null
                    : () => setState(() => _recordar = null),
              ),
              const SizedBox(height: 12),
              _SelectorCurso(
                cursos: cursos,
                cursoId: _cursoId,
                onChanged: (v) => setState(() => _cursoId = v),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _ubicacion,
                decoration:
                    const InputDecoration(labelText: 'Ubicación (opcional)'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: MatixColors.red.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(_error!,
                      style: const TextStyle(color: MatixColors.red)),
                ),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _guardando ? null : _guardar,
                child: _guardando
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2.2),
                      )
                    : Text(_editando ? 'Guardar cambios' : 'Crear evento'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Desplegable de curso (opcional). El color del curso pinta el evento
/// en el calendario; sin curso, el evento usa el color de acento.
class _SelectorCurso extends StatelessWidget {
  const _SelectorCurso({
    required this.cursos,
    required this.cursoId,
    required this.onChanged,
  });
  final List<Curso> cursos;
  final String? cursoId;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    // El valor solo es válido si el curso sigue existiendo.
    final valor = cursos.any((c) => c.id == cursoId) ? cursoId : null;
    return DropdownButtonFormField<String?>(
      initialValue: valor,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Curso (opcional)'),
      items: [
        const DropdownMenuItem<String?>(
          value: null,
          child: Text('Sin curso'),
        ),
        for (final c in cursos)
          DropdownMenuItem<String?>(
            value: c.id,
            child: Text(c.nombre, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: onChanged,
    );
  }
}

class _Pick extends StatelessWidget {
  const _Pick({
    required this.label,
    required this.value,
    required this.onTap,
    this.onClear,
  });
  final String label;
  final String value;
  final VoidCallback onTap;
  final VoidCallback? onClear;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 14),
                decoration: BoxDecoration(
                  color: MatixColors.card,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Text(
                      '$label:',
                      style: const TextStyle(
                          color: MatixColors.muted, fontSize: 12),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        value,
                        style: const TextStyle(
                          color: MatixColors.text,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (onClear != null)
            IconButton(
                onPressed: onClear,
                icon: const Icon(Icons.close, color: MatixColors.muted)),
        ],
      ),
    );
  }
}
