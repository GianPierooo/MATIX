import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../api/matix_client.dart';
import '../../../theme/matix_colors.dart';
import '../../../theme/matix_spacing.dart';
import '../domain/movimiento.dart';
import '../providers/movimientos_providers.dart';

/// Categorías sugeridas por defecto. Son solo eso: sugerencias. El campo
/// es de texto libre — categorías simples y editables (Finanzas-1).
const List<String> _categoriasDefault = [
  'Comida',
  'Transporte',
  'Hogar',
  'Salud',
  'Ocio',
  'Estudios',
  'Sueldo',
  'Otros',
];

/// Crea o edita un movimiento. Sin `movimientoId` es alta; con él, edición
/// (y aparece el botón de borrar).
class EditorMovimientoScreen extends ConsumerStatefulWidget {
  const EditorMovimientoScreen({super.key, this.movimientoId});
  final String? movimientoId;

  @override
  ConsumerState<EditorMovimientoScreen> createState() =>
      _EditorMovimientoScreenState();
}

class _EditorMovimientoScreenState
    extends ConsumerState<EditorMovimientoScreen> {
  final _monto = TextEditingController();
  final _categoria = TextEditingController();
  final _nota = TextEditingController();

  TipoMovimiento _tipo = TipoMovimiento.gasto;
  DateTime _fecha = DateTime.now();
  bool _cargando = false;
  bool _guardando = false;
  String? _error;

  bool get _esEdicion => widget.movimientoId != null;

  @override
  void initState() {
    super.initState();
    if (_esEdicion) _cargar();
  }

  @override
  void dispose() {
    _monto.dispose();
    _categoria.dispose();
    _nota.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    try {
      final m = await ref
          .read(movimientosRepoProvider)
          .obtener(widget.movimientoId!);
      setState(() {
        _tipo = m.tipo;
        _monto.text = m.monto.toStringAsFixed(2);
        _categoria.text = m.categoria;
        _nota.text = m.nota;
        _fecha = m.fecha;
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
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
    final txt = _monto.text.trim().replaceAll(',', '.');
    final v = double.tryParse(txt);
    if (v == null || v <= 0) return null;
    return v;
  }

  Future<void> _guardar() async {
    final monto = _parseMonto();
    if (monto == null) {
      setState(() => _error = 'Pon un monto mayor que 0.');
      return;
    }
    final categoria = _categoria.text.trim().isEmpty
        ? 'General'
        : _categoria.text.trim();
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      final repo = ref.read(movimientosRepoProvider);
      if (_esEdicion) {
        await repo.actualizar(
          id: widget.movimientoId!,
          tipo: _tipo,
          monto: monto,
          categoria: categoria,
          fecha: _fecha,
          nota: _nota.text.trim(),
        );
      } else {
        await repo.crear(
          tipo: _tipo,
          monto: monto,
          categoria: categoria,
          fecha: _fecha,
          nota: _nota.text.trim(),
        );
      }
      ref.invalidate(movimientosListProvider);
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
      builder: (ctx) => AlertDialog(
        backgroundColor: MatixColors.card,
        title: const Text('Borrar movimiento'),
        content: const Text('¿Seguro que quieres borrar este movimiento?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Borrar',
                style: TextStyle(color: MatixColors.red)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _guardando = true);
    try {
      await ref.read(movimientosRepoProvider).borrar(widget.movimientoId!);
      ref.invalidate(movimientosListProvider);
      if (mounted) Navigator.of(context).pop();
    } on MatixApiException catch (e) {
      setState(() {
        _guardando = false;
        _error = e.message;
      });
    } catch (e) {
      setState(() {
        _guardando = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final sugerencias = <String>{
      ..._categoriasUsadas(),
      ..._categoriasDefault,
    }.toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(_esEdicion ? 'Editar movimiento' : 'Nuevo movimiento'),
        actions: [
          if (_esEdicion)
            IconButton(
              tooltip: 'Borrar',
              icon: const Icon(Icons.delete_outline),
              onPressed: _guardando ? null : _borrar,
            ),
        ],
      ),
      body: _cargando
          ? const Center(
              child: CircularProgressIndicator(color: MatixColors.accent),
            )
          : SafeArea(
              child: ListView(
                padding: const EdgeInsets.all(MatixSpacing.xl2),
                children: [
                  SegmentedButton<TipoMovimiento>(
                    segments: const [
                      ButtonSegment(
                        value: TipoMovimiento.gasto,
                        label: Text('Gasto'),
                        icon: Icon(Icons.south_west, size: 16),
                      ),
                      ButtonSegment(
                        value: TipoMovimiento.ingreso,
                        label: Text('Ingreso'),
                        icon: Icon(Icons.north_east, size: 16),
                      ),
                    ],
                    selected: {_tipo},
                    onSelectionChanged: (s) => setState(() => _tipo = s.first),
                    showSelectedIcon: false,
                  ),
                  const SizedBox(height: MatixSpacing.xl2),
                  TextField(
                    controller: _monto,
                    autofocus: !_esEdicion,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                          RegExp(r'[0-9.,]')),
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
                      hintText: 'Comida, Transporte, Sueldo…',
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
                            fontSize: 12,
                            color: MatixColors.text,
                          ),
                          onPressed: () => setState(() {
                            _categoria.text = c;
                          }),
                        ),
                    ],
                  ),
                  const SizedBox(height: MatixSpacing.xl),
                  _FilaFecha(fecha: _fecha, onTap: _elegirFecha),
                  const SizedBox(height: MatixSpacing.xl),
                  TextField(
                    controller: _nota,
                    decoration: const InputDecoration(
                      labelText: 'Nota (opcional)',
                      alignLabelWithHint: true,
                    ),
                    minLines: 2,
                    maxLines: 5,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: MatixSpacing.xl),
                    Text(_error!,
                        style: const TextStyle(color: MatixColors.red)),
                  ],
                  const SizedBox(height: MatixSpacing.xl2),
                  FilledButton(
                    onPressed: _guardando ? null : _guardar,
                    style: FilledButton.styleFrom(
                      backgroundColor: MatixColors.accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: _guardando
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2.2),
                          )
                        : Text(_esEdicion ? 'Guardar' : 'Registrar'),
                  ),
                ],
              ),
            ),
    );
  }

  List<String> _categoriasUsadas() {
    final lista = ref.read(movimientosListProvider).valueOrNull;
    if (lista == null) return const [];
    return categoriasUsadas(lista);
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
