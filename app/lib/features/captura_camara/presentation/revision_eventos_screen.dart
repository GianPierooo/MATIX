import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../theme/matix_colors.dart';
import '../../../theme/matix_button_styles.dart';
import '../../../theme/matix_spacing.dart';
import '../../../theme/matix_typography.dart';
import '../../tareas/domain/selectores.dart';
import '../../tareas/providers/tareas_providers.dart';
import '../application/extraccion_eventos_controller.dart';
import '../domain/evento_propuesto.dart';

/// Hoja de revisión de los eventos que el cerebro propuso a partir del
/// sílabo (Cámara · sílabo). Mismo patrón que las tareas (7-B): editar
/// título, día/hora/fecha, asignar curso, quitar; **nada se crea hasta
/// confirmar**. Al confirmar, el controller los crea en el calendario
/// (recurrentes con recurrencia de Cal-3, únicos como eventos normales).
class RevisionEventosScreen extends ConsumerWidget {
  const RevisionEventosScreen({super.key});

  static const _diasLabel = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final estado = ref.watch(extraccionEventosControllerProvider);
    final ctrl = ref.read(extraccionEventosControllerProvider.notifier);
    final cursos =
        ref.watch(cursosProvider).valueOrNull ?? const <CursoRef>[];

    if (estado.fase == FaseEventos.creado) {
      return _PantallaCreado(
        creados: estado.creados,
        onVolver: () => Navigator.of(context).popUntil((r) => r.isFirst),
      );
    }

    final propuestas = estado.propuestas;
    final creando = estado.fase == FaseEventos.creando;

    return Scaffold(
      appBar: AppBar(title: const Text('Revisar eventos')),
      body: SafeArea(
        child: Column(
          children: [
            if (estado.error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    MatixSpacing.xl, MatixSpacing.l, MatixSpacing.xl, 0),
                child: _Banner(mensaje: estado.error!),
              ),
            Expanded(
              child: propuestas.isEmpty
                  ? const _SinEventos()
                  : ListView.separated(
                      padding: const EdgeInsets.all(MatixSpacing.xl),
                      itemCount: propuestas.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: MatixSpacing.l),
                      itemBuilder: (context, i) => _FilaEvento(
                        evento: propuestas[i],
                        cursos: cursos,
                        habilitado: !creando,
                        diasLabel: _diasLabel,
                        onTitulo: (v) => ctrl.editarTitulo(i, v),
                        onDia: (d) => ctrl.alternarDia(i, d),
                        onFecha: () => _elegirFecha(context, ctrl, i,
                            propuestas[i].fecha),
                        onHoraInicio: () => _elegirHora(context, ctrl, i,
                            propuestas[i].horaInicio, inicio: true),
                        onHoraFin: () => _elegirHora(context, ctrl, i,
                            propuestas[i].horaFin, inicio: false),
                        onCurso: (c) => ctrl.asignarCurso(i, c?.id, c?.color),
                        onEliminar: () => ctrl.eliminar(i),
                      ),
                    ),
            ),
            if (propuestas.isNotEmpty)
              _BarraConfirmar(
                cantidad: propuestas.length,
                creando: creando,
                onConfirmar: ctrl.crear,
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _elegirFecha(BuildContext context,
      ExtraccionEventosController ctrl, int i, DateTime? actual) async {
    final ahora = DateTime.now();
    final f = await showDatePicker(
      context: context,
      initialDate: actual ?? ahora,
      firstDate: DateTime(ahora.year - 1),
      lastDate: DateTime(ahora.year + 5),
    );
    if (f != null) ctrl.ponerFecha(i, f);
  }

  Future<void> _elegirHora(BuildContext context,
      ExtraccionEventosController ctrl, int i, String? actual,
      {required bool inicio}) async {
    final parsed = parseHora(actual);
    final t = await showTimePicker(
      context: context,
      initialTime: parsed != null
          ? TimeOfDay(hour: parsed.$1, minute: parsed.$2)
          : const TimeOfDay(hour: 8, minute: 0),
    );
    if (t == null) return;
    final hhmm =
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    if (inicio) {
      ctrl.ponerHoraInicio(i, hhmm);
    } else {
      ctrl.ponerHoraFin(i, hhmm);
    }
  }
}

class _FilaEvento extends StatelessWidget {
  const _FilaEvento({
    required this.evento,
    required this.cursos,
    required this.habilitado,
    required this.diasLabel,
    required this.onTitulo,
    required this.onDia,
    required this.onFecha,
    required this.onHoraInicio,
    required this.onHoraFin,
    required this.onCurso,
    required this.onEliminar,
  });

  final EventoPropuesto evento;
  final List<CursoRef> cursos;
  final bool habilitado;
  final List<String> diasLabel;
  final ValueChanged<String> onTitulo;
  final ValueChanged<int> onDia;
  final VoidCallback onFecha;
  final VoidCallback onHoraInicio;
  final VoidCallback onHoraFin;
  final ValueChanged<CursoRef?> onCurso;
  final VoidCallback onEliminar;

  @override
  Widget build(BuildContext context) {
    final esRec = evento.esRecurrente;
    return Container(
      padding: const EdgeInsets.all(MatixSpacing.l),
      decoration: BoxDecoration(
        color: MatixColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MatixColors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _TipoBadge(esRecurrente: esRec),
              const SizedBox(width: MatixSpacing.m),
              Expanded(
                child: TextFormField(
                  initialValue: evento.titulo,
                  enabled: habilitado,
                  onChanged: onTitulo,
                  style: MatixText.body,
                  decoration: const InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: 'Título del evento',
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Quitar',
                onPressed: habilitado ? onEliminar : null,
                icon: const Icon(Icons.close, size: 20),
                color: MatixColors.muted,
              ),
            ],
          ),
          const SizedBox(height: MatixSpacing.s),
          if (esRec)
            Wrap(
              spacing: 6,
              children: [
                for (var d = 1; d <= 7; d++)
                  _DiaChip(
                    label: diasLabel[d - 1],
                    activo: evento.diasSemana.contains(d),
                    onTap: habilitado ? () => onDia(d) : null,
                  ),
              ],
            )
          else
            _Pildora(
              icono: Icons.event_outlined,
              texto: evento.fecha == null
                  ? 'Elegir fecha'
                  : DateFormat('EEE d MMM', 'es').format(evento.fecha!),
              onTap: habilitado ? onFecha : null,
            ),
          const SizedBox(height: MatixSpacing.s),
          Row(
            children: [
              _Pildora(
                icono: Icons.schedule,
                texto: evento.horaInicio ?? 'Inicio',
                onTap: habilitado ? onHoraInicio : null,
              ),
              const SizedBox(width: MatixSpacing.s),
              _Pildora(
                icono: Icons.schedule_outlined,
                texto: evento.horaFin ?? 'Fin',
                onTap: habilitado ? onHoraFin : null,
              ),
            ],
          ),
          const SizedBox(height: MatixSpacing.s),
          _SelectorCurso(
            cursos: cursos,
            seleccionado: evento.cursoId,
            habilitado: habilitado,
            onCambia: onCurso,
          ),
        ],
      ),
    );
  }
}

class _TipoBadge extends StatelessWidget {
  const _TipoBadge({required this.esRecurrente});
  final bool esRecurrente;
  @override
  Widget build(BuildContext context) {
    final color = esRecurrente ? MatixColors.purple : MatixColors.teal;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        esRecurrente ? 'Recurrente' : 'Única',
        style: TextStyle(
            fontSize: 10.5, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }
}

class _DiaChip extends StatelessWidget {
  const _DiaChip({required this.label, required this.activo, this.onTap});
  final String label;
  final bool activo;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 30,
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: activo ? MatixColors.accent : MatixColors.cardHi,
          border: Border.all(
            color: activo ? MatixColors.accent : MatixColors.hairline,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: activo ? Colors.white : MatixColors.muted,
          ),
        ),
      ),
    );
  }
}

class _Pildora extends StatelessWidget {
  const _Pildora({required this.icono, required this.texto, this.onTap});
  final IconData icono;
  final String texto;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: MatixSpacing.l, vertical: MatixSpacing.m),
        decoration: BoxDecoration(
          color: MatixColors.cardHi,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: MatixColors.hairline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icono, size: 16, color: MatixColors.muted),
            const SizedBox(width: MatixSpacing.s),
            Text(texto, style: MatixText.small),
          ],
        ),
      ),
    );
  }
}

class _SelectorCurso extends StatelessWidget {
  const _SelectorCurso({
    required this.cursos,
    required this.seleccionado,
    required this.habilitado,
    required this.onCambia,
  });
  final List<CursoRef> cursos;
  final String? seleccionado;
  final bool habilitado;
  final ValueChanged<CursoRef?> onCambia;
  @override
  Widget build(BuildContext context) {
    final ids = cursos.map((c) => c.id).toSet();
    final valor = (seleccionado != null && ids.contains(seleccionado))
        ? seleccionado
        : null;
    return DropdownButton<String?>(
      value: valor,
      isExpanded: true,
      isDense: true,
      underline: const SizedBox.shrink(),
      dropdownColor: MatixColors.cardHi,
      icon: const Icon(Icons.school_outlined,
          size: 16, color: MatixColors.muted),
      hint: Text('Sin curso', style: MatixText.small),
      style: MatixText.small.copyWith(color: MatixColors.text),
      onChanged: habilitado
          ? (id) => onCambia(
                id == null
                    ? null
                    : cursos.firstWhere((c) => c.id == id),
              )
          : null,
      items: [
        DropdownMenuItem<String?>(
          value: null,
          child: Text('Sin curso', style: MatixText.small),
        ),
        for (final c in cursos)
          DropdownMenuItem<String?>(
            value: c.id,
            child: Text(c.nombre,
                overflow: TextOverflow.ellipsis,
                style: MatixText.small.copyWith(color: MatixColors.text)),
          ),
      ],
    );
  }
}

class _BarraConfirmar extends StatelessWidget {
  const _BarraConfirmar({
    required this.cantidad,
    required this.creando,
    required this.onConfirmar,
  });
  final int cantidad;
  final bool creando;
  final VoidCallback onConfirmar;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(MatixSpacing.xl),
      decoration: const BoxDecoration(
        color: MatixColors.bg,
        border: Border(top: BorderSide(color: MatixColors.hairline)),
      ),
      child: FilledButton(
        onPressed: creando ? null : onConfirmar,
        style: MatixButtonStyles.primarioAlto,
        child: creando
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2.4, color: Colors.white),
              )
            : Text(cantidad == 1
                ? 'Crear 1 evento'
                : 'Crear $cantidad eventos'),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.mensaje});
  final String mensaje;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(MatixSpacing.l),
      decoration: BoxDecoration(
        color: MatixColors.red.withValues(alpha: 0.12),
        border: Border.all(color: MatixColors.red.withValues(alpha: 0.45)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, color: MatixColors.red, size: 18),
          const SizedBox(width: MatixSpacing.m),
          Expanded(
            child: Text(mensaje,
                style: MatixText.small.copyWith(color: MatixColors.text)),
          ),
        ],
      ),
    );
  }
}

class _SinEventos extends StatelessWidget {
  const _SinEventos();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(MatixSpacing.xl4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.event_busy_outlined,
                color: MatixColors.muted, size: 56),
            const SizedBox(height: MatixSpacing.xl),
            Text('No encontré clases ni fechas',
                textAlign: TextAlign.center, style: MatixText.subtitle),
            const SizedBox(height: MatixSpacing.m),
            Text(
              'El texto no parece tener días/horas ni fechas. Vuelve atrás '
              'para editarlo y reintentar.',
              textAlign: TextAlign.center,
              style: MatixText.small,
            ),
          ],
        ),
      ),
    );
  }
}

class _PantallaCreado extends StatelessWidget {
  const _PantallaCreado({required this.creados, required this.onVolver});
  final int creados;
  final VoidCallback onVolver;
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(MatixSpacing.xl4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.event_available_outlined,
                    color: MatixColors.green, size: 64),
                const SizedBox(height: MatixSpacing.xl),
                Text(
                  creados == 1 ? 'Creé 1 evento' : 'Creé $creados eventos',
                  textAlign: TextAlign.center,
                  style: MatixText.title,
                ),
                const SizedBox(height: MatixSpacing.m),
                Text(
                  'Ya están en tu calendario. Las clases se repiten cada '
                  'semana; las fechas únicas quedan en su día.',
                  textAlign: TextAlign.center,
                  style: MatixText.small,
                ),
                const SizedBox(height: MatixSpacing.xl2),
                FilledButton(
                  onPressed: onVolver,
                  style: FilledButton.styleFrom(
                    backgroundColor: MatixColors.accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 32, vertical: 14),
                  ),
                  child: const Text('Listo'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
