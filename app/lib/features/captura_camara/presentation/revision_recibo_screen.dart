import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../theme/matix_colors.dart';
import '../../../theme/matix_spacing.dart';
import '../../finanzas/domain/movimiento.dart';
import '../../finanzas/providers/movimientos_providers.dart';
import '../application/extraccion_recibo_controller.dart';

/// Categorías de gasto sugeridas por defecto (texto libre editable).
const List<String> _categoriasDefault = [
  'Comida',
  'Transporte',
  'Hogar',
  'Salud',
  'Ocio',
  'Estudios',
  'Otros',
];

/// Hoja de revisión del recibo → gasto (Finanzas-2). Llega con lo que el
/// cerebro extrajo (monto, fecha, comercio, categoría); el usuario lo
/// edita y, al confirmar, se guarda como gasto en Finanzas. Si no hubo
/// monto claro, el campo arranca vacío con un aviso: se escribe a mano,
/// no se inventan cifras.
class RevisionReciboScreen extends ConsumerStatefulWidget {
  const RevisionReciboScreen({super.key});

  @override
  ConsumerState<RevisionReciboScreen> createState() =>
      _RevisionReciboScreenState();
}

class _RevisionReciboScreenState extends ConsumerState<RevisionReciboScreen> {
  final _monto = TextEditingController();
  final _categoria = TextEditingController();
  final _nota = TextEditingController();
  DateTime _fecha = DateTime.now();
  String? _errorLocal;
  bool _sinMonto = false;

  @override
  void initState() {
    super.initState();
    final p = ref.read(extraccionReciboControllerProvider).propuesta;
    _sinMonto = p?.monto == null;
    _monto.text = p?.monto != null ? p!.monto!.toStringAsFixed(2) : '';
    _categoria.text = p?.categoria ?? '';
    _nota.text = p?.comercio ?? '';
    _fecha = p?.fecha ?? DateTime.now();
  }

  @override
  void dispose() {
    _monto.dispose();
    _categoria.dispose();
    _nota.dispose();
    super.dispose();
  }

  Future<void> _elegirFecha() async {
    final elegida = await showDatePicker(
      context: context,
      initialDate: _fecha,
      firstDate: DateTime(2015),
      lastDate: DateTime(2100),
    );
    if (elegida != null) setState(() => _fecha = elegida);
  }

  double? _parseMonto() {
    final v = double.tryParse(_monto.text.trim().replaceAll(',', '.'));
    if (v == null || v <= 0) return null;
    return v;
  }

  void _guardar() {
    final monto = _parseMonto();
    if (monto == null) {
      setState(() => _errorLocal = 'Pon un monto mayor que 0.');
      return;
    }
    setState(() => _errorLocal = null);
    ref.read(extraccionReciboControllerProvider.notifier).crear(
          monto: monto,
          categoria: _categoria.text,
          fecha: _fecha,
          nota: _nota.text,
        );
  }

  @override
  Widget build(BuildContext context) {
    // Al guardar bien, volvemos a la raíz y confirmamos con un snackbar.
    ref.listen<EstadoRecibo>(extraccionReciboControllerProvider, (prev, next) {
      if (prev?.fase == next.fase) return;
      if (next.fase == FaseRecibo.creado) {
        Navigator.of(context).popUntil((r) => r.isFirst);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gasto guardado en Finanzas.')),
        );
      }
    });

    final estado = ref.watch(extraccionReciboControllerProvider);
    final guardando = estado.fase == FaseRecibo.creando;
    final error = _errorLocal ?? estado.error;

    final sugerencias = <String>{
      ...(ref.watch(movimientosListProvider).valueOrNull != null
          ? categoriasUsadas(ref.watch(movimientosListProvider).value!)
          : const <String>[]),
      ..._categoriasDefault,
    }.toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Revisar gasto')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(MatixSpacing.xl2),
          children: [
            if (_sinMonto) ...[
              _AvisoBanner(
                mensaje: 'No detecté un monto claro en el recibo. '
                    'Escríbelo a mano.',
              ),
              const SizedBox(height: MatixSpacing.l),
            ],
            TextField(
              controller: _monto,
              autofocus: _sinMonto,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              ],
              decoration: const InputDecoration(
                labelText: 'Monto',
                prefixText: 'S/ ',
              ),
            ),
            const SizedBox(height: MatixSpacing.xl),
            TextField(
              controller: _categoria,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Categoría',
                hintText: 'Comida, Transporte…',
              ),
            ),
            const SizedBox(height: MatixSpacing.m),
            Wrap(
              spacing: MatixSpacing.m,
              runSpacing: MatixSpacing.s,
              children: [
                for (final c in sugerencias)
                  ActionChip(
                    label: Text(c),
                    backgroundColor: MatixColors.card,
                    side: const BorderSide(color: MatixColors.hairline),
                    labelStyle: const TextStyle(
                        fontSize: 12, color: MatixColors.text),
                    onPressed: () => setState(() => _categoria.text = c),
                  ),
              ],
            ),
            const SizedBox(height: MatixSpacing.xl),
            _FilaFecha(fecha: _fecha, onTap: _elegirFecha),
            const SizedBox(height: MatixSpacing.xl),
            TextField(
              controller: _nota,
              decoration: const InputDecoration(
                labelText: 'Comercio / nota (opcional)',
              ),
              minLines: 1,
              maxLines: 3,
            ),
            if (error != null) ...[
              const SizedBox(height: MatixSpacing.xl),
              Text(error, style: const TextStyle(color: MatixColors.red)),
            ],
            const SizedBox(height: MatixSpacing.xl2),
            FilledButton.icon(
              onPressed: guardando ? null : _guardar,
              icon: guardando
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2.2),
                    )
                  : const Icon(Icons.savings_outlined, size: 18),
              label: Text(guardando ? 'Guardando…' : 'Guardar gasto'),
              style: FilledButton.styleFrom(
                backgroundColor: MatixColors.accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilaFecha extends StatelessWidget {
  const _FilaFecha({required this.fecha, required this.onTap});
  final DateTime fecha;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(MatixSpacing.lg),
        decoration: BoxDecoration(
          color: MatixColors.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: MatixColors.hairline),
        ),
        child: Row(
          children: [
            const Icon(Icons.calendar_today_outlined,
                size: 18, color: MatixColors.muted),
            const SizedBox(width: MatixSpacing.l),
            Text(
              DateFormat("d 'de' MMMM yyyy", 'es').format(fecha),
              style: const TextStyle(fontSize: 14, color: MatixColors.text),
            ),
            const Spacer(),
            const Text('Cambiar',
                style: TextStyle(fontSize: 12, color: MatixColors.accent)),
          ],
        ),
      ),
    );
  }
}

class _AvisoBanner extends StatelessWidget {
  const _AvisoBanner({required this.mensaje});
  final String mensaje;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(MatixSpacing.l),
      decoration: BoxDecoration(
        color: MatixColors.amber.withValues(alpha: 0.12),
        border: Border.all(color: MatixColors.amber.withValues(alpha: 0.45)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, color: MatixColors.amber, size: 18),
          const SizedBox(width: MatixSpacing.m),
          Expanded(
            child: Text(mensaje,
                style: const TextStyle(
                    fontSize: 13, color: MatixColors.text, height: 1.4)),
          ),
        ],
      ),
    );
  }
}
