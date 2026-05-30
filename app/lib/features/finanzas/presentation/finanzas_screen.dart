import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../theme/matix_colors.dart';
import '../../../theme/matix_spacing.dart';
import '../domain/movimiento.dart';
import '../providers/movimientos_providers.dart';
import 'editor_movimiento_screen.dart';
import 'formato_finanzas.dart';

/// Sección de Finanzas (Finanzas-1): la lista de movimientos del mes y un
/// resumen claro (ingresos, gastos, balance), con corte por mes. Vive
/// fuera de la barra inferior; se abre desde la tarjeta de Inicio.
class FinanzasScreen extends ConsumerStatefulWidget {
  const FinanzasScreen({super.key});

  @override
  ConsumerState<FinanzasScreen> createState() => _FinanzasScreenState();
}

class _FinanzasScreenState extends ConsumerState<FinanzasScreen> {
  late DateTime _mes;

  @override
  void initState() {
    super.initState();
    final hoy = DateTime.now();
    _mes = DateTime(hoy.year, hoy.month);
  }

  void _cambiarMes(int delta) {
    setState(() => _mes = DateTime(_mes.year, _mes.month + delta));
  }

  Future<void> _abrirEditor({String? id}) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EditorMovimientoScreen(movimientoId: id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final movimientosAsync = ref.watch(movimientosListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Finanzas'),
        actions: [
          IconButton(
            tooltip: 'Nuevo movimiento',
            icon: const Icon(Icons.add),
            onPressed: () => _abrirEditor(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: MatixColors.accent,
        foregroundColor: Colors.white,
        onPressed: () => _abrirEditor(),
        child: const Icon(Icons.add),
      ),
      body: movimientosAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: MatixColors.accent),
        ),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(MatixSpacing.xl4),
            child: Text(
              'No pude cargar tus movimientos.\n$e',
              textAlign: TextAlign.center,
              style: const TextStyle(color: MatixColors.muted),
            ),
          ),
        ),
        data: (todos) {
          final delMes = movimientosDeMes(todos, _mes.year, _mes.month);
          final resumen = resumenDeMes(todos, _mes.year, _mes.month);
          return RefreshIndicator(
            color: MatixColors.accent,
            onRefresh: () async => ref.invalidate(movimientosListProvider),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                  MatixSpacing.xl, MatixSpacing.l, MatixSpacing.xl, 96),
              children: [
                _SelectorMes(
                  mes: _mes,
                  onAnterior: () => _cambiarMes(-1),
                  onSiguiente: () => _cambiarMes(1),
                ),
                const SizedBox(height: MatixSpacing.l),
                _ResumenCard(resumen: resumen),
                const SizedBox(height: MatixSpacing.xl),
                if (delMes.isEmpty)
                  const _VacioMes()
                else
                  for (final m in delMes)
                    _MovimientoTile(
                      movimiento: m,
                      onTap: () => _abrirEditor(id: m.id),
                    ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SelectorMes extends StatelessWidget {
  const _SelectorMes({
    required this.mes,
    required this.onAnterior,
    required this.onSiguiente,
  });
  final DateTime mes;
  final VoidCallback onAnterior;
  final VoidCallback onSiguiente;

  @override
  Widget build(BuildContext context) {
    final etiqueta = DateFormat.yMMMM('es').format(mes);
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left, color: MatixColors.text),
          onPressed: onAnterior,
          tooltip: 'Mes anterior',
        ),
        Expanded(
          child: Text(
            // Capitaliza el mes ("mayo de 2026" → "Mayo de 2026").
            etiqueta.isEmpty
                ? etiqueta
                : etiqueta[0].toUpperCase() + etiqueta.substring(1),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: MatixColors.text,
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right, color: MatixColors.text),
          onPressed: onSiguiente,
          tooltip: 'Mes siguiente',
        ),
      ],
    );
  }
}

class _ResumenCard extends StatelessWidget {
  const _ResumenCard({required this.resumen});
  final ResumenFinanzas resumen;

  @override
  Widget build(BuildContext context) {
    final balance = resumen.balance;
    final colorBalance =
        balance >= 0 ? MatixColors.green : MatixColors.red;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(MatixSpacing.xl2),
      decoration: BoxDecoration(
        color: MatixColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MatixColors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'BALANCE DEL MES',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0,
              color: MatixColors.muted,
            ),
          ),
          const SizedBox(height: MatixSpacing.m),
          Text(
            montoSoles(balance),
            style: TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w800,
              color: colorBalance,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: MatixSpacing.xl),
          Row(
            children: [
              Expanded(
                child: _TotalMini(
                  etiqueta: 'Ingresos',
                  monto: resumen.ingresos,
                  color: MatixColors.green,
                  icono: Icons.north_east,
                ),
              ),
              const SizedBox(width: MatixSpacing.l),
              Expanded(
                child: _TotalMini(
                  etiqueta: 'Gastos',
                  monto: resumen.gastos,
                  color: MatixColors.red,
                  icono: Icons.south_west,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TotalMini extends StatelessWidget {
  const _TotalMini({
    required this.etiqueta,
    required this.monto,
    required this.color,
    required this.icono,
  });
  final String etiqueta;
  final double monto;
  final Color color;
  final IconData icono;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icono, size: 14, color: color),
            const SizedBox(width: MatixSpacing.s),
            Text(
              etiqueta,
              style: const TextStyle(fontSize: 12, color: MatixColors.muted),
            ),
          ],
        ),
        const SizedBox(height: MatixSpacing.xs),
        Text(
          montoSoles(monto),
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _MovimientoTile extends StatelessWidget {
  const _MovimientoTile({required this.movimiento, required this.onTap});
  final Movimiento movimiento;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final esIngreso = movimiento.tipo.esIngreso;
    final color = esIngreso ? MatixColors.green : MatixColors.red;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: MatixSpacing.xs),
      child: Material(
        color: MatixColors.card,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(MatixSpacing.lg),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    esIngreso ? Icons.north_east : Icons.south_west,
                    size: 18,
                    color: color,
                  ),
                ),
                const SizedBox(width: MatixSpacing.l),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        movimiento.categoria,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: MatixColors.text,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        movimiento.nota.trim().isNotEmpty
                            ? '${DateFormat("d MMM", 'es').format(movimiento.fecha)} · ${movimiento.nota}'
                            : DateFormat("d MMM", 'es').format(movimiento.fecha),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: MatixColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: MatixSpacing.l),
                Text(
                  montoConSigno(movimiento.monto, esIngreso: esIngreso),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _VacioMes extends StatelessWidget {
  const _VacioMes();
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(MatixSpacing.xl3),
      decoration: BoxDecoration(
        color: MatixColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MatixColors.hairline),
      ),
      child: const Column(
        children: [
          Icon(Icons.account_balance_wallet_outlined,
              color: MatixColors.muted, size: 28),
          SizedBox(height: MatixSpacing.l),
          Text(
            'No hay movimientos este mes.\nToca + para registrar un ingreso o un gasto.',
            textAlign: TextAlign.center,
            style: TextStyle(color: MatixColors.muted, height: 1.4),
          ),
        ],
      ),
    );
  }
}
