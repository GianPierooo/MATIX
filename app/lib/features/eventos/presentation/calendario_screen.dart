import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../theme/matix_colors.dart';
import '../../cursos/domain/curso.dart';
import '../../cursos/domain/sesion_clase.dart';
import '../../universidad/providers/universidad_providers.dart';
import '../domain/choque.dart';
import '../domain/evento.dart';
import '../domain/recurrencia.dart';
import '../providers/eventos_providers.dart';
import 'nuevo_evento_screen.dart';

class CalendarioScreen extends ConsumerStatefulWidget {
  const CalendarioScreen({super.key});
  @override
  ConsumerState<CalendarioScreen> createState() => _CalendarioScreenState();
}

class _CalendarioScreenState extends ConsumerState<CalendarioScreen> {
  DateTime _mes =
      DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _dia = DateTime.now();

  @override
  Widget build(BuildContext context) {
    final eventos = ref.watch(eventosProvider);
    final cursos = ref.watch(cursosListProvider).valueOrNull ?? const <Curso>[];
    final cursosPorId = {for (final c in cursos) c.id: c};

    return Scaffold(
      appBar: AppBar(
        title: const Text('Calendario'),
        actions: [
          IconButton(
            tooltip: 'Hoy',
            onPressed: () => setState(() {
              final hoy = DateTime.now();
              _mes = DateTime(hoy.year, hoy.month, 1);
              _dia = hoy;
            }),
            icon: const Icon(Icons.today),
          ),
          IconButton(
            tooltip: 'Nuevo evento',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const NuevoEventoScreen()),
            ),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: eventos.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: MatixColors.accent),
        ),
        error: (e, _) => Center(child: Text(e.toString())),
        data: (todos) => Column(
          children: [
            _CabeceraMes(
              mes: _mes,
              onPrev: () => setState(() => _mes =
                  DateTime(_mes.year, _mes.month - 1, 1)),
              onNext: () => setState(() => _mes =
                  DateTime(_mes.year, _mes.month + 1, 1)),
            ),
            _GridMes(
              mes: _mes,
              diaSeleccionado: _dia,
              eventos: todos,
              onTap: (d) => setState(() => _dia = d),
            ),
            const Divider(color: MatixColors.hairline, height: 1),
            Expanded(
              child: _ListaDelDia(
                dia: _dia,
                eventos: todos.where((e) => e.ocurreEn(_dia)).toList()
                  ..sort((a, b) => a.iniciaEn.compareTo(b.iniciaEn)),
                clases: ref.watch(sesionesDelDiaProvider(_dia)),
                cursosPorId: cursosPorId,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CabeceraMes extends StatelessWidget {
  const _CabeceraMes({
    required this.mes,
    required this.onPrev,
    required this.onNext,
  });
  final DateTime mes;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              DateFormat.yMMMM('es').format(mes),
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: MatixColors.text,
              ),
            ),
          ),
          IconButton(
              onPressed: onPrev, icon: const Icon(Icons.chevron_left)),
          IconButton(
              onPressed: onNext, icon: const Icon(Icons.chevron_right)),
        ],
      ),
    );
  }
}

class _GridMes extends StatelessWidget {
  const _GridMes({
    required this.mes,
    required this.diaSeleccionado,
    required this.eventos,
    required this.onTap,
  });
  final DateTime mes;
  final DateTime diaSeleccionado;
  final List<Evento> eventos;
  final ValueChanged<DateTime> onTap;

  @override
  Widget build(BuildContext context) {
    // Semana empieza en lunes.
    final firstDayOfMonth = DateTime(mes.year, mes.month, 1);
    final diaSemanaPrimero = (firstDayOfMonth.weekday + 6) % 7; // L=0..D=6
    final diasEnMes =
        DateTime(mes.year, mes.month + 1, 0).day;
    final celdas = <DateTime?>[];
    for (var i = 0; i < diaSemanaPrimero; i++) {
      celdas.add(null);
    }
    for (var d = 1; d <= diasEnMes; d++) {
      celdas.add(DateTime(mes.year, mes.month, d));
    }
    while (celdas.length % 7 != 0) {
      celdas.add(null);
    }

    final hoy = DateTime.now();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        children: [
          Row(
            children: const ['L', 'M', 'X', 'J', 'V', 'S', 'D']
                .map((s) => Expanded(
                      child: Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 6),
                          child: Text(
                            s,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.8,
                              color: MatixColors.muted,
                            ),
                          ),
                        ),
                      ),
                    ))
                .toList(),
          ),
          for (var r = 0; r < celdas.length / 7; r++)
            Row(
              children: [
                for (var c = 0; c < 7; c++)
                  Expanded(
                    child: _CeldaDia(
                      dia: celdas[r * 7 + c],
                      esHoy: celdas[r * 7 + c] != null &&
                          _mismoDia(celdas[r * 7 + c]!, hoy),
                      seleccionado: celdas[r * 7 + c] != null &&
                          _mismoDia(
                              celdas[r * 7 + c]!, diaSeleccionado),
                      tieneEventos: celdas[r * 7 + c] != null &&
                          eventos.any(
                              (e) => e.ocurreEn(celdas[r * 7 + c]!)),
                      onTap: onTap,
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  bool _mismoDia(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

class _CeldaDia extends StatelessWidget {
  const _CeldaDia({
    required this.dia,
    required this.esHoy,
    required this.seleccionado,
    required this.tieneEventos,
    required this.onTap,
  });
  final DateTime? dia;
  final bool esHoy;
  final bool seleccionado;
  final bool tieneEventos;
  final ValueChanged<DateTime> onTap;

  @override
  Widget build(BuildContext context) {
    if (dia == null) {
      return const SizedBox(height: 42);
    }
    final bg = seleccionado
        ? MatixColors.accent
        : (esHoy ? MatixColors.accent.withValues(alpha: 0.16) : null);
    final fg = seleccionado
        ? Colors.white
        : (esHoy ? MatixColors.accent : MatixColors.text);
    return InkResponse(
      onTap: () => onTap(dia!),
      radius: 24,
      child: Container(
        height: 42,
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
        ),
        alignment: Alignment.center,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Text(
              '${dia!.day}',
              style: TextStyle(
                fontSize: 14,
                fontWeight: esHoy || seleccionado
                    ? FontWeight.w700
                    : FontWeight.w500,
                color: fg,
              ),
            ),
            if (tieneEventos)
              Positioned(
                bottom: 4,
                child: Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: seleccionado ? Colors.white : MatixColors.accent,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ListaDelDia extends StatelessWidget {
  const _ListaDelDia({
    required this.dia,
    required this.eventos,
    required this.clases,
    required this.cursosPorId,
  });
  final DateTime dia;
  final List<Evento> eventos;
  final List<(SesionClase, Curso?)> clases;
  final Map<String, Curso> cursosPorId;

  /// Una fila por cada vez que `e` ocurre en `dia`. Para un evento único es
  /// una sola fila con su hora real; para una serie recurrente, una fila por
  /// ocurrencia con la hora desplazada, pero conservando `evento: e` (la
  /// serie original) para que el tap edite el ancla.
  List<_Fila> _filasDeEvento(Evento e) {
    final color = _colorEvento(e, cursosPorId);
    final regla = e.regla;
    if (regla == null) {
      return [
        _Fila(
          inicio: e.iniciaEn.toLocal(),
          fin: e.terminaEn?.toLocal(),
          titulo: e.titulo,
          subtitulo: e.ubicacion,
          color: color,
          esClase: false,
          todoElDia: e.todoElDia,
          esRecurrente: false,
          evento: e,
        ),
      ];
    }
    final inicioSerie = e.iniciaEn.toLocal();
    final duracion = e.terminaEn?.toLocal().difference(inicioSerie);
    return [
      for (final occ in ocurrenciasEnDia(
        regla: regla,
        inicioSerie: inicioSerie,
        dia: dia,
      ))
        _Fila(
          inicio: occ,
          fin: duracion == null ? null : occ.add(duracion),
          titulo: e.titulo,
          subtitulo: e.ubicacion,
          color: color,
          esClase: false,
          todoElDia: e.todoElDia,
          esRecurrente: true,
          evento: e,
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    // Mezclamos eventos y clases recurrentes en una sola lista
    // ordenada por hora de inicio. Para series recurrentes mostramos la
    // ocurrencia de este día (hora desplazada), pero `evento` apunta a la
    // serie original para que al tocar se edite el ancla, no la instancia.
    final filas = <_Fila>[
      for (final e in eventos) ..._filasDeEvento(e),
      for (final entry in clases)
        _Fila(
          inicio: entry.$1.inicioEn(dia),
          fin: entry.$1.finEn(dia),
          titulo: '${entry.$2?.nombre ?? "Clase"} — Clase',
          subtitulo: entry.$1.ubicacion,
          color: _colorCurso(entry.$2?.color),
          esClase: true,
          todoElDia: false,
        ),
    ]..sort((a, b) => a.inicio.compareTo(b.inicio));

    // Detección de choques: para cada fila con hora fija, comprueba
    // si solapa con cualquier otra del mismo día.
    final choca = <bool>[for (var _ in filas) false];
    for (var i = 0; i < filas.length; i++) {
      final a = filas[i];
      if (a.todoElDia || a.fin == null) continue;
      for (var j = i + 1; j < filas.length; j++) {
        final b = filas[j];
        if (b.todoElDia || b.fin == null) continue;
        if (seSolapan(a.inicio, a.fin!, b.inicio, b.fin!)) {
          choca[i] = true;
          choca[j] = true;
        }
      }
    }

    if (filas.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            'No hay eventos para ${DateFormat.yMMMMEEEEd('es').format(dia)}.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              color: MatixColors.muted,
            ),
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: filas.length,
      itemBuilder: (context, i) {
        final f = filas[i];
        final tieneChoque = choca[i];
        final contenido = Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: tieneChoque
                  ? MatixColors.red.withValues(alpha: 0.10)
                  : MatixColors.card,
              borderRadius: BorderRadius.circular(12),
              border: tieneChoque
                  ? Border.all(color: MatixColors.red.withValues(alpha: 0.40))
                  : null,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 52,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        f.todoElDia
                            ? 'Todo el día'
                            : DateFormat.Hm().format(f.inicio),
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: MatixColors.text,
                        ),
                      ),
                      if (f.fin != null && !f.todoElDia)
                        Text(
                          DateFormat.Hm().format(f.fin!),
                          style: const TextStyle(
                            fontSize: 11,
                            color: MatixColors.muted,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  width: 4,
                  height: 38,
                  decoration: BoxDecoration(
                    color: f.color,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              f.titulo,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: MatixColors.text,
                              ),
                            ),
                          ),
                          if (f.esRecurrente)
                            const Padding(
                              padding: EdgeInsets.only(left: 6),
                              child: Icon(
                                Icons.repeat,
                                size: 14,
                                color: MatixColors.muted,
                              ),
                            ),
                          if (f.esClase)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: f.color.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text('SEMANAL',
                                  style: TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w700,
                                    color: f.color,
                                  )),
                            ),
                        ],
                      ),
                      if (f.subtitulo != null)
                        Text(
                          f.subtitulo!,
                          style: const TextStyle(
                            fontSize: 12,
                            color: MatixColors.muted,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          );
        // Las clases son recurrentes (se editan en Universidad); solo
        // los eventos abren el editor para corregir o borrar.
        if (f.evento == null) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: contenido,
          );
        }
        final ev = f.evento!;
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => NuevoEventoScreen(evento: ev),
                ),
              ),
              child: contenido,
            ),
          ),
        );
      },
    );
  }
}

class _Fila {
  _Fila({
    required this.inicio,
    required this.fin,
    required this.titulo,
    required this.subtitulo,
    required this.color,
    required this.esClase,
    required this.todoElDia,
    this.esRecurrente = false,
    this.evento,
  });
  final DateTime inicio;
  final DateTime? fin;
  final String titulo;
  final String? subtitulo;
  final Color color;
  final bool esClase;
  final bool todoElDia;
  /// `true` si la fila es una ocurrencia de un evento recurrente (no clase).
  final bool esRecurrente;
  /// El evento de origen, o `null` si la fila es una clase recurrente.
  final Evento? evento;
}

Color _colorCurso(String? hex) {
  if (hex == null || hex.length != 7) return MatixColors.accent;
  final v = int.tryParse(hex.substring(1), radix: 16);
  return v == null ? MatixColors.accent : Color(0xFF000000 | v);
}

/// Color de la barra de un evento: su color propio si lo trae (p.ej.
/// el heredado de Google), si no el del curso asociado, si no acento.
Color _colorEvento(Evento e, Map<String, Curso> cursos) {
  if (e.color != null && e.color!.length == 7) return _colorCurso(e.color);
  final curso = e.cursoId == null ? null : cursos[e.cursoId];
  if (curso?.color != null) return _colorCurso(curso!.color);
  return MatixColors.accent;
}
