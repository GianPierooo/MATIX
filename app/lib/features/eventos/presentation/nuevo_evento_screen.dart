import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../api/matix_client.dart';
import '../../../theme/matix_colors.dart';
import '../providers/eventos_providers.dart';

class NuevoEventoScreen extends ConsumerStatefulWidget {
  const NuevoEventoScreen({super.key});
  @override
  ConsumerState<NuevoEventoScreen> createState() =>
      _NuevoEventoScreenState();
}

class _NuevoEventoScreenState extends ConsumerState<NuevoEventoScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titulo = TextEditingController();
  final _ubicacion = TextEditingController();
  DateTime _inicia = DateTime.now().add(const Duration(hours: 1));
  DateTime? _termina;
  DateTime? _recordar;
  bool _todoElDia = false;
  bool _guardando = false;
  String? _error;

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
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
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
    try {
      await ref.read(eventosRepositoryProvider).crear(
            titulo: _titulo.text.trim(),
            iniciaEn: _inicia,
            terminaEn: _termina,
            todoElDia: _todoElDia,
            ubicacion: _ubicacion.text.trim().isEmpty
                ? null
                : _ubicacion.text.trim(),
            recordarEn: _recordar,
          );
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nuevo evento')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            children: [
              TextFormField(
                controller: _titulo,
                decoration: const InputDecoration(labelText: 'Título'),
                autofocus: true,
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
                  final d =
                      await _pickDateTime(_termina ?? _inicia);
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
                    : const Text('Crear evento'),
              ),
            ],
          ),
        ),
      ),
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
