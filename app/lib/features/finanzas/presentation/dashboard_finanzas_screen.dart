import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../theme/matix_colors.dart';
import '../../../theme/matix_spacing.dart';
import '../domain/analitica_finanzas.dart';
import '../domain/movimiento.dart';
import '../providers/movimientos_providers.dart';
import 'formato_finanzas.dart';

/// Dashboard de Finanzas (Finanzas-3): pocos gráficos pero claros sobre
/// los movimientos ya registrados. Gastos por categoría (en qué se te va
/// la plata) e ingresos vs gastos por mes (evolución), con balance del
/// período y selector de período. Solo visualización: ninguna lógica
/// nueva ni persistencia.
class DashboardFinanzasScreen extends ConsumerStatefulWidget {
  const DashboardFinanzasScreen({super.key});

  @override
  ConsumerState<DashboardFinanzasScreen> createState() =>
      _DashboardFinanzasScreenState();
}

class _DashboardFinanzasScreenState
    extends ConsumerState<DashboardFinanzasScreen> {
  PeriodoFinanzas _periodo = PeriodoFinanzas.ultimos3;

  // Paleta para la torta de categorías (mismos colores del tema).
  static const _paleta = MatixColors.courseSwatches;

  @override
  Widget build(BuildContext context) {
    final movimientosAsync = ref.watch(movimientosListProvider);
    final ahora = DateTime.now();

    return Scaffold(
      appBar: AppBar(title: const Text('Dashboard')),
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
          final delPeriodo = movimientosDelPeriodo(todos, ahora, _periodo);
          final resumen = resumenDe(delPeriodo);
          final porCategoria = gastosPorCategoria(delPeriodo);
          final porMes =
              ingresosVsGastosPorMes(todos, ahora, _periodo.meses);

          return RefreshIndicator(
            color: MatixColors.accent,
            onRefresh: () async => ref.invalidate(movimientosListProvider),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                  MatixSpacing.xl, MatixSpacing.l, MatixSpacing.xl, 32),
              children: [
                _SelectorPeriodo(
                  periodo: _periodo,
                  onChanged: (p) => setState(() => _periodo = p),
                ),
                const SizedBox(height: MatixSpacing.l),
                _BalancePeriodoCard(resumen: resumen),
                const SizedBox(height: MatixSpacing.xl2),
                const _TituloSeccion('Gastos por categoría'),
                const SizedBox(height: MatixSpacing.l),
                _GastosPorCategoria(datos: porCategoria, paleta: _paleta),
                const SizedBox(height: MatixSpacing.xl2),
                const _TituloSeccion('Ingresos vs gastos por mes'),
                const SizedBox(height: MatixSpacing.l),
                _IngresosVsGastos(datos: porMes),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SelectorPeriodo extends StatelessWidget {
  const _SelectorPeriodo({required this.periodo, required this.onChanged});
  final PeriodoFinanzas periodo;
  final ValueChanged<PeriodoFinanzas> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: SegmentedButton<PeriodoFinanzas>(
        segments: const [
          ButtonSegment(
              value: PeriodoFinanzas.mesActual, label: Text('Este mes')),
          ButtonSegment(
              value: PeriodoFinanzas.ultimos3, label: Text('3 meses')),
          ButtonSegment(
              value: PeriodoFinanzas.ultimos6, label: Text('6 meses')),
        ],
        selected: {periodo},
        onSelectionChanged: (s) => onChanged(s.first),
        showSelectedIcon: false,
        style: const ButtonStyle(visualDensity: VisualDensity.compact),
      ),
    );
  }
}

class _BalancePeriodoCard extends StatelessWidget {
  const _BalancePeriodoCard({required this.resumen});
  final ResumenFinanzas resumen;

  @override
  Widget build(BuildContext context) {
    final color = resumen.balance >= 0 ? MatixColors.green : MatixColors.red;
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
            'BALANCE DEL PERÍODO',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0,
              color: MatixColors.muted,
            ),
          ),
          const SizedBox(height: MatixSpacing.m),
          Text(
            montoSoles(resumen.balance),
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: color,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: MatixSpacing.m),
          Row(
            children: [
              _Punto(color: MatixColors.green),
              const SizedBox(width: MatixSpacing.s),
              Text('Ingresos ${montoSoles(resumen.ingresos)}',
                  style: const TextStyle(
                      fontSize: 12.5, color: MatixColors.muted)),
              const SizedBox(width: MatixSpacing.xl),
              _Punto(color: MatixColors.red),
              const SizedBox(width: MatixSpacing.s),
              Text('Gastos ${montoSoles(resumen.gastos)}',
                  style: const TextStyle(
                      fontSize: 12.5, color: MatixColors.muted)),
            ],
          ),
        ],
      ),
    );
  }
}

class _TituloSeccion extends StatelessWidget {
  const _TituloSeccion(this.texto);
  final String texto;
  @override
  Widget build(BuildContext context) {
    return Text(
      texto.toUpperCase(),
      style: const TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.0,
        color: MatixColors.muted,
      ),
    );
  }
}

// ─── Gastos por categoría (torta + leyenda) ──────────────────────────
class _GastosPorCategoria extends StatelessWidget {
  const _GastosPorCategoria({required this.datos, required this.paleta});
  final List<CategoriaTotal> datos;
  final List<Color> paleta;

  @override
  Widget build(BuildContext context) {
    if (datos.isEmpty) {
      return const _CardVacia('No hay gastos en este período.');
    }
    final total = datos.fold<double>(0, (s, d) => s + d.total);
    return Container(
      padding: const EdgeInsets.all(MatixSpacing.xl),
      decoration: BoxDecoration(
        color: MatixColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MatixColors.hairline),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 180,
            child: PieChart(
              PieChartData(
                sectionsSpace: 2,
                centerSpaceRadius: 44,
                sections: [
                  for (var i = 0; i < datos.length; i++)
                    PieChartSectionData(
                      value: datos[i].total,
                      color: paleta[i % paleta.length],
                      radius: 46,
                      showTitle: false,
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: MatixSpacing.xl),
          for (var i = 0; i < datos.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  _Punto(color: paleta[i % paleta.length]),
                  const SizedBox(width: MatixSpacing.m),
                  Expanded(
                    child: Text(
                      datos[i].categoria,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13, color: MatixColors.text),
                    ),
                  ),
                  Text(
                    '${(datos[i].total / total * 100).round()}%',
                    style: const TextStyle(
                        fontSize: 12, color: MatixColors.muted),
                  ),
                  const SizedBox(width: MatixSpacing.l),
                  Text(
                    montoSoles(datos[i].total),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: MatixColors.text,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Ingresos vs gastos por mes (barras agrupadas) ───────────────────
class _IngresosVsGastos extends StatelessWidget {
  const _IngresosVsGastos({required this.datos});
  final List<MesTotales> datos;

  @override
  Widget build(BuildContext context) {
    final hayAlgo =
        datos.any((m) => m.ingresos > 0 || m.gastos > 0);
    if (!hayAlgo) {
      return const _CardVacia('No hay movimientos en este período.');
    }
    var maxY = 0.0;
    for (final m in datos) {
      if (m.ingresos > maxY) maxY = m.ingresos;
      if (m.gastos > maxY) maxY = m.gastos;
    }
    maxY = maxY <= 0 ? 10 : maxY * 1.2;

    return Container(
      padding: const EdgeInsets.fromLTRB(
          MatixSpacing.l, MatixSpacing.xl, MatixSpacing.l, MatixSpacing.l),
      decoration: BoxDecoration(
        color: MatixColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MatixColors.hairline),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 200,
            child: BarChart(
              BarChartData(
                maxY: maxY,
                alignment: BarChartAlignment.spaceAround,
                barTouchData: BarTouchData(enabled: false),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (_) => const FlLine(
                    color: MatixColors.hairline,
                    strokeWidth: 1,
                  ),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 44,
                      getTitlesWidget: (value, meta) => Text(
                        NumberFormat.compact().format(value),
                        style: const TextStyle(
                            fontSize: 9, color: MatixColors.muted),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 24,
                      getTitlesWidget: (value, meta) {
                        final i = value.toInt();
                        if (i < 0 || i >= datos.length) {
                          return const SizedBox.shrink();
                        }
                        final m = datos[i];
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            DateFormat('MMM', 'es')
                                .format(DateTime(m.anio, m.mes)),
                            style: const TextStyle(
                                fontSize: 10, color: MatixColors.muted),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                barGroups: [
                  for (var i = 0; i < datos.length; i++)
                    BarChartGroupData(
                      x: i,
                      barsSpace: 4,
                      barRods: [
                        BarChartRodData(
                          toY: datos[i].ingresos,
                          color: MatixColors.green,
                          width: 9,
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(3)),
                        ),
                        BarChartRodData(
                          toY: datos[i].gastos,
                          color: MatixColors.red,
                          width: 9,
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(3)),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: MatixSpacing.l),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _Punto(color: MatixColors.green),
              const SizedBox(width: MatixSpacing.s),
              const Text('Ingresos',
                  style: TextStyle(fontSize: 12, color: MatixColors.muted)),
              const SizedBox(width: MatixSpacing.xl),
              _Punto(color: MatixColors.red),
              const SizedBox(width: MatixSpacing.s),
              const Text('Gastos',
                  style: TextStyle(fontSize: 12, color: MatixColors.muted)),
            ],
          ),
        ],
      ),
    );
  }
}

class _Punto extends StatelessWidget {
  const _Punto({required this.color});
  final Color color;
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _CardVacia extends StatelessWidget {
  const _CardVacia(this.texto);
  final String texto;
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(MatixSpacing.xl2),
      decoration: BoxDecoration(
        color: MatixColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MatixColors.hairline),
      ),
      child: Text(
        texto,
        textAlign: TextAlign.center,
        style: const TextStyle(color: MatixColors.muted),
      ),
    );
  }
}
