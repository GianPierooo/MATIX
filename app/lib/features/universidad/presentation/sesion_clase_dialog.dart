import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../api/matix_client.dart';
import '../../../theme/matix_colors.dart';
import '../providers/universidad_providers.dart';

/// Diálogo para añadir una sesión de clase recurrente a un curso.
/// Día de la semana + hora inicio + hora fin + ubicación opcional.
class SesionClaseDialog extends ConsumerStatefulWidget {
  const SesionClaseDialog({super.key, required this.cursoId});
  final String cursoId;
  @override
  ConsumerState<SesionClaseDialog> createState() =>
      _SesionClaseDialogState();
}

class _SesionClaseDialogState extends ConsumerState<SesionClaseDialog> {
  int _dia = 0; // L=0..D=6
  TimeOfDay _ini = const TimeOfDay(hour: 18, minute: 30);
  TimeOfDay _fin = const TimeOfDay(hour: 20, minute: 0);
  final _ubicacion = TextEditingController();
  bool _guardando = false;
  String? _error;

  static const _dias = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];

  @override
  void dispose() {
    _ubicacion.dispose();
    super.dispose();
  }

  String _fmt(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:00';

  Future<void> _guardar() async {
    if (_fin.hour * 60 + _fin.minute <= _ini.hour * 60 + _ini.minute) {
      setState(() => _error = 'La hora de fin debe ser posterior al inicio.');
      return;
    }
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      await ref.read(cursosRepoProvider).crearSesion(
            cursoId: widget.cursoId,
            diaSemana: _dia,
            horaInicio: _fmt(_ini),
            horaFin: _fmt(_fin),
            ubicacion: _ubicacion.text.trim().isEmpty
                ? null
                : _ubicacion.text.trim(),
          );
      ref.invalidate(sesionesClaseProvider);
      if (mounted) Navigator.of(context).pop();
    } on MatixApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nueva sesión'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('DÍA',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0,
                  color: MatixColors.muted,
                )),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              children: List.generate(
                7,
                (i) => ChoiceChip(
                  label: Text(_dias[i]),
                  selected: _dia == i,
                  onSelected: (_) => setState(() => _dia = i),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.schedule),
                    label: Text('Inicio  ${_ini.format(context)}'),
                    onPressed: () async {
                      final t = await showTimePicker(
                          context: context, initialTime: _ini);
                      if (t != null) setState(() => _ini = t);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.schedule_outlined),
                    label: Text('Fin  ${_fin.format(context)}'),
                    onPressed: () async {
                      final t = await showTimePicker(
                          context: context, initialTime: _fin);
                      if (t != null) setState(() => _fin = t);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _ubicacion,
              decoration: const InputDecoration(
                  labelText: 'Aula / ubicación (opcional)'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!,
                  style: const TextStyle(color: MatixColors.red, fontSize: 12.5)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _guardando ? null : _guardar,
          child: _guardando
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2.2),
                )
              : const Text('Añadir'),
        ),
      ],
    );
  }
}
