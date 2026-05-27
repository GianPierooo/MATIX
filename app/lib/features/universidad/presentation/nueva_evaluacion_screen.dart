import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../api/matix_client.dart';
import '../../../theme/matix_colors.dart';
import '../../evaluaciones/domain/evaluacion.dart';
import '../providers/universidad_providers.dart';

class NuevaEvaluacionScreen extends ConsumerStatefulWidget {
  const NuevaEvaluacionScreen({super.key, required this.cursoId});
  final String cursoId;
  @override
  ConsumerState<NuevaEvaluacionScreen> createState() =>
      _NuevaEvaluacionScreenState();
}

class _NuevaEvaluacionScreenState
    extends ConsumerState<NuevaEvaluacionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titulo = TextEditingController();
  final _peso = TextEditingController();
  TipoEvaluacion _tipo = TipoEvaluacion.entrega;
  DateTime _fecha = DateTime.now().add(const Duration(days: 7));
  DateTime? _recordar;
  bool _guardando = false;
  String? _error;

  @override
  void dispose() {
    _titulo.dispose();
    _peso.dispose();
    super.dispose();
  }

  Future<DateTime?> _pick(DateTime base) async {
    final f = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
    );
    if (f == null || !mounted) return null;
    final h = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(base),
    );
    if (h == null) return null;
    return DateTime(f.year, f.month, f.day, h.hour, h.minute);
  }

  Future<void> _guardar() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      await ref.read(evaluacionesRepoProvider).crear(
            cursoId: widget.cursoId,
            titulo: _titulo.text.trim(),
            tipo: _tipo,
            fecha: _fecha,
            peso: double.tryParse(_peso.text.replaceAll(',', '.')),
            recordarEn: _recordar,
          );
      ref.invalidate(evaluacionesListProvider);
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
    return Scaffold(
      appBar: AppBar(title: const Text('Nueva evaluación')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              TextFormField(
                controller: _titulo,
                decoration: const InputDecoration(labelText: 'Título'),
                autofocus: true,
                validator: (s) =>
                    (s == null || s.trim().isEmpty) ? 'Pon un título' : null,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: TipoEvaluacion.values
                    .map((t) => ChoiceChip(
                          label: Text(t.label),
                          selected: _tipo == t,
                          onSelected: (_) => setState(() => _tipo = t),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Fecha'),
                subtitle: Text(
                    DateFormat("EEE d MMM HH:mm", 'es').format(_fecha)),
                trailing: const Icon(Icons.event),
                onTap: () async {
                  final d = await _pick(_fecha);
                  if (d != null) setState(() => _fecha = d);
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Recordatorio'),
                subtitle: Text(_recordar == null
                    ? 'Sin recordatorio'
                    : DateFormat("EEE d MMM HH:mm", 'es')
                        .format(_recordar!)),
                trailing: _recordar == null
                    ? const Icon(Icons.notifications_none)
                    : IconButton(
                        onPressed: () => setState(() => _recordar = null),
                        icon: const Icon(Icons.close),
                      ),
                onTap: () async {
                  final d = await _pick(
                      _recordar ?? _fecha.subtract(const Duration(days: 1)));
                  if (d != null) setState(() => _recordar = d);
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _peso,
                decoration: const InputDecoration(
                    labelText: 'Peso % (opcional)'),
                keyboardType: TextInputType.number,
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(_error!,
                    style: const TextStyle(color: MatixColors.red)),
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
                    : const Text('Crear evaluación'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
