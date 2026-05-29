import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../api/matix_client.dart';
import '../../../theme/matix_colors.dart';
import '../../cursos/domain/curso.dart';
import '../../universidad/providers/universidad_providers.dart';
import '../domain/evento.dart';
import '../domain/recordatorio_evento.dart';
import '../domain/recurrencia.dart';
import '../providers/eventos_providers.dart';

/// Preset de frecuencia que ve el usuario. "Cada día de semana" no es una
/// frecuencia propia: se guarda como semanal con días {lun..vie}.
enum _PresetFreq { ninguna, diaria, semanalDias, cadaDiaSemana, mensual }

const _diasLaborables = {1, 2, 3, 4, 5};

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
  int? _recordatorioOffsetMin;
  bool _todoElDia = false;
  String? _cursoId;
  bool _guardando = false;
  bool _borrando = false;
  String? _error;

  // Recurrencia (Cal-3).
  _PresetFreq _presetFreq = _PresetFreq.ninguna;
  Set<int> _diasSemana = {};
  FinRecurrencia _fin = FinRecurrencia.nunca;
  DateTime? _hasta;
  late final TextEditingController _conteo;

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
    _recordatorioOffsetMin = e?.recordatorioOffsetMin;
    _todoElDia = e?.todoElDia ?? false;
    _cursoId = e?.cursoId;
    _conteo = TextEditingController(
      text: e?.regla?.conteo?.toString() ?? '10',
    );
    _cargarRecurrencia(e?.regla);
  }

  /// Reconstruye el estado de la UI desde la regla guardada (o sin regla).
  void _cargarRecurrencia(ReglaRecurrencia? regla) {
    if (regla == null) {
      _presetFreq = _PresetFreq.ninguna;
      return;
    }
    switch (regla.frecuencia) {
      case FrecuenciaRecurrencia.diaria:
        _presetFreq = _PresetFreq.diaria;
        break;
      case FrecuenciaRecurrencia.mensual:
        _presetFreq = _PresetFreq.mensual;
        break;
      case FrecuenciaRecurrencia.semanal:
        if (setEquals(regla.diasSemana, _diasLaborables)) {
          _presetFreq = _PresetFreq.cadaDiaSemana;
        } else {
          _presetFreq = _PresetFreq.semanalDias;
          _diasSemana = {...regla.diasSemana};
        }
        break;
    }
    _fin = regla.fin;
    _hasta = regla.hasta;
  }

  @override
  void dispose() {
    _titulo.dispose();
    _ubicacion.dispose();
    _conteo.dispose();
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

  /// Arma la regla de recurrencia desde el estado de la UI, o `null` si el
  /// usuario eligió "Ninguna".
  ReglaRecurrencia? _construirRegla() {
    final FrecuenciaRecurrencia frecuencia;
    var dias = const <int>{};
    switch (_presetFreq) {
      case _PresetFreq.ninguna:
        return null;
      case _PresetFreq.diaria:
        frecuencia = FrecuenciaRecurrencia.diaria;
        break;
      case _PresetFreq.semanalDias:
        frecuencia = FrecuenciaRecurrencia.semanal;
        // Sin días marcados, usa el día de inicio de la serie.
        dias = _diasSemana.isNotEmpty ? _diasSemana : {_inicia.weekday};
        break;
      case _PresetFreq.cadaDiaSemana:
        frecuencia = FrecuenciaRecurrencia.semanal;
        dias = _diasLaborables;
        break;
      case _PresetFreq.mensual:
        frecuencia = FrecuenciaRecurrencia.mensual;
        break;
    }
    final conteo = _fin == FinRecurrencia.conteo
        ? (int.tryParse(_conteo.text.trim()) ?? 1).clamp(1, 999)
        : null;
    return ReglaRecurrencia(
      frecuencia: frecuencia,
      diasSemana: dias,
      fin: _fin,
      hasta: _fin == FinRecurrencia.hasta ? _hasta : null,
      conteo: conteo,
    );
  }

  Future<void> _guardar() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final regla = _construirRegla();
    // "Hasta una fecha" sin fecha elegida no puede guardarse.
    if (regla != null &&
        regla.fin == FinRecurrencia.hasta &&
        regla.hasta == null) {
      setState(() => _error = 'Elige la fecha en la que termina la repetición.');
      return;
    }
    setState(() {
      _guardando = true;
      _error = null;
    });
    final repo = ref.read(eventosRepositoryProvider);
    final ubic =
        _ubicacion.text.trim().isEmpty ? null : _ubicacion.text.trim();
    try {
      if (_editando) {
        // El offset manda; `recordar_en` se deriva (null lo limpia).
        final recordarEn =
            momentoRecordatorio(_inicia, _recordatorioOffsetMin);
        await repo.actualizar(widget.evento!.id, {
          'titulo': _titulo.text.trim(),
          'inicia_en': _inicia.toUtc().toIso8601String(),
          'termina_en': _termina?.toUtc().toIso8601String(),
          'todo_el_dia': _todoElDia,
          'ubicacion': ubic,
          'curso_id': _cursoId,
          'recordatorio_offset_min': _recordatorioOffsetMin,
          'recordar_en': recordarEn?.toUtc().toIso8601String(),
          // Editar la serie cambia todas: guardamos la regla en el ancla.
          // Sin recurrencia, limpiamos cualquier regla previa con nulls.
          ...(regla?.toJson() ?? ReglaRecurrencia.jsonNulo()),
        });
      } else {
        await repo.crear(
          titulo: _titulo.text.trim(),
          iniciaEn: _inicia,
          terminaEn: _termina,
          todoElDia: _todoElDia,
          ubicacion: ubic,
          cursoId: _cursoId,
          recordatorioOffsetMin: _recordatorioOffsetMin,
          regla: regla,
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

  static const _etiquetaPreset = {
    _PresetFreq.ninguna: 'No se repite',
    _PresetFreq.diaria: 'Cada día',
    _PresetFreq.semanalDias: 'Semanal (elijo días)',
    _PresetFreq.cadaDiaSemana: 'Cada día de semana (L–V)',
    _PresetFreq.mensual: 'Cada mes',
  };

  static const _etiquetaFin = {
    FinRecurrencia.nunca: 'Sin fecha de fin',
    FinRecurrencia.hasta: 'Hasta una fecha',
    FinRecurrencia.conteo: 'Tras N repeticiones',
  };

  // ISO 1=lunes … 7=domingo.
  static const _diasCorto = ['L', 'M', 'X', 'J', 'V', 'S', 'D'];

  Future<void> _pickFechaHasta() async {
    final base = _hasta ?? _inicia.add(const Duration(days: 30));
    final fecha = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: _inicia,
      lastDate: _inicia.add(const Duration(days: 365 * 5)),
    );
    if (fecha != null) setState(() => _hasta = fecha);
  }

  Widget _seccionRecurrencia() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<_PresetFreq>(
          initialValue: _presetFreq,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Repetición'),
          items: [
            for (final p in _PresetFreq.values)
              DropdownMenuItem(value: p, child: Text(_etiquetaPreset[p]!)),
          ],
          onChanged: (v) => setState(() {
            _presetFreq = v ?? _PresetFreq.ninguna;
            // Al elegir "semanal", arranca con el día de inicio marcado.
            if (_presetFreq == _PresetFreq.semanalDias &&
                _diasSemana.isEmpty) {
              _diasSemana = {_inicia.weekday};
            }
          }),
        ),
        if (_presetFreq == _PresetFreq.semanalDias) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            children: [
              for (var iso = 1; iso <= 7; iso++)
                FilterChip(
                  label: Text(_diasCorto[iso - 1]),
                  selected: _diasSemana.contains(iso),
                  onSelected: (sel) => setState(() {
                    if (sel) {
                      _diasSemana.add(iso);
                    } else {
                      _diasSemana.remove(iso);
                    }
                  }),
                ),
            ],
          ),
        ],
        if (_presetFreq != _PresetFreq.ninguna) ...[
          const SizedBox(height: 10),
          DropdownButtonFormField<FinRecurrencia>(
            initialValue: _fin,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Termina'),
            items: [
              for (final f in FinRecurrencia.values)
                DropdownMenuItem(value: f, child: Text(_etiquetaFin[f]!)),
            ],
            onChanged: (v) => setState(() {
              _fin = v ?? FinRecurrencia.nunca;
              if (_fin == FinRecurrencia.hasta && _hasta == null) {
                _hasta = _inicia.add(const Duration(days: 30));
              }
            }),
          ),
          if (_fin == FinRecurrencia.hasta)
            _Pick(
              label: 'Hasta',
              value: _hasta == null
                  ? 'Elige una fecha'
                  : DateFormat("EEE d MMM y", 'es').format(_hasta!),
              onTap: _pickFechaHasta,
            ),
          if (_fin == FinRecurrencia.conteo) ...[
            const SizedBox(height: 10),
            TextFormField(
              controller: _conteo,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Repeticiones',
                helperText: 'Cuántas veces se repite en total',
              ),
            ),
          ],
        ],
      ],
    );
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
              const SizedBox(height: 12),
              _SelectorRecordatorio(
                offsetMin: _recordatorioOffsetMin,
                onChanged: (v) =>
                    setState(() => _recordatorioOffsetMin = v),
              ),
              const SizedBox(height: 12),
              _seccionRecurrencia(),
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

/// Desplegable del recordatorio como offset antes del inicio. El valor
/// elegido es a la vez el control de edición y el "detalle" que se ve
/// del recordatorio del evento.
class _SelectorRecordatorio extends StatelessWidget {
  const _SelectorRecordatorio({
    required this.offsetMin,
    required this.onChanged,
  });
  final int? offsetMin;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    final esPreset = presetsRecordatorio.any((p) => p.offsetMin == offsetMin);
    return DropdownButtonFormField<int?>(
      initialValue: offsetMin,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Recordatorio'),
      items: [
        for (final p in presetsRecordatorio)
          DropdownMenuItem<int?>(
            value: p.offsetMin,
            child: Text(p.etiqueta),
          ),
        // Offset que no es uno de los presets (p.ej. de un valor legado):
        // se ofrece como opción extra para no perderlo al editar.
        if (!esPreset && offsetMin != null)
          DropdownMenuItem<int?>(
            value: offsetMin,
            child: Text(etiquetaRecordatorio(offsetMin)),
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
