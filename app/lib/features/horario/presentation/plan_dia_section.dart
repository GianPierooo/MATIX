import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/hub_refresh.dart';
import '../../../theme/matix_colors.dart';
import '../../universidad/providers/universidad_providers.dart';
import '../domain/plan_dia.dart';
import '../providers/horario_providers.dart';

/// Vista «Hoy»: el plan del día como línea de tiempo. Distingue lo FIJO
/// (clases, gym, anclas — inmovible) de lo PLANIFICADO (trabajo/skill/tarea —
/// tentativo y ajustable). Muestra el tiempo libre como libre, sin culpa.
class PlanDiaSection extends ConsumerStatefulWidget {
  const PlanDiaSection({super.key});

  @override
  ConsumerState<PlanDiaSection> createState() => _PlanDiaSectionState();
}

class _PlanDiaSectionState extends ConsumerState<PlanDiaSection> {
  // Ediciones de hora locales (clave del bloque → inicio/fin nuevos).
  final Map<String, ({String inicio, String fin})> _overrides = {};
  // Bloques saltados localmente (skills/tareas sin id de set).
  final Set<String> _ocultos = {};
  // Sugerencias que el usuario aceptó en un hueco → bloques tentativos locales.
  final List<BloquePlan> _aceptadas = [];
  // Claves de sugerencias ya usadas (no volver a ofrecer la misma en otro hueco).
  final Set<String> _sugUsadas = {};
  // Huecos donde el usuario descartó la sugerencia (clave del bloque previo).
  final Set<String> _huecosSaltados = {};
  // "Otra": contador de rotación por hueco (clave del bloque previo).
  final Map<String, int> _huecoOtra = {};
  bool _trabajando = false;

  List<BloquePlan> _visibles(PlanDia plan) {
    final lista = [...plan.bloques, ..._aceptadas]
        .where((b) => !_ocultos.contains(b.clave))
        .map((b) {
      final o = _overrides[b.clave];
      return o == null ? b : b.conHoras(o.inicio, o.fin);
    }).toList()
      ..sort((a, b) => a.inicioMin.compareTo(b.inicioMin));
    return lista;
  }

  void _aceptarSugerencia(Sugerencia s, int iniMin, int hueco) {
    setState(() {
      _aceptadas.add(s.aBloque(iniMin, hueco));
      _sugUsadas.add(s.clave);
    });
    _aviso('Listo, lo metí al día. Si no, lo sueltas nomás.');
  }

  Future<void> _hecho(BloquePlan b) async {
    setState(() => _trabajando = true);
    try {
      if (b.tareaId != null || b.nodoId != null) {
        await ref
            .read(horarioRepositoryProvider)
            .completar(tareaId: b.tareaId, nodoId: b.nodoId);
        // Es la MISMA tarea que vive en /tareas y en el rollover: refrescamos
        // las tres vistas (antes solo el plan, así que la pestaña Tareas seguía
        // mostrando la tarea como pendiente).
        invalidarHub(ref);
      } else {
        // Skill u otro sin estado en el cerebro: lo cerramos en la vista.
        setState(() => _ocultos.add(b.clave));
      }
      _aviso('Listo, marqué «${b.titulo}». Bien ahí.');
    } on Object catch (e) {
      _aviso('No pude marcarlo: $e');
    } finally {
      if (mounted) setState(() => _trabajando = false);
    }
  }

  Future<void> _saltar(BloquePlan b) async {
    setState(() => _trabajando = true);
    try {
      if (b.setItemId != null) {
        await ref.read(horarioRepositoryProvider).saltar(b.setItemId!);
        // Saltar también cambia el rollover (este item ya no se va a arrastrar
        // como "no cumplido"); refrescamos todo el hub.
        invalidarHub(ref);
      } else {
        setState(() => _ocultos.add(b.clave));
      }
      _aviso('Lo salté por hoy, sin culpa.');
    } on Object catch (e) {
      _aviso('No pude saltarlo: $e');
    } finally {
      if (mounted) setState(() => _trabajando = false);
    }
  }

  Future<void> _editarHora(BloquePlan b) async {
    final actual = b.inicio.split(':');
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: int.tryParse(actual[0]) ?? 8,
        minute: int.tryParse(actual.length > 1 ? actual[1] : '0') ?? 0,
      ),
      helpText: 'Mover «${b.titulo}»',
    );
    if (picked == null) return;
    final dur = b.finMin - b.inicioMin; // conserva la duración del bloque
    final nuevoIni = picked.hour * 60 + picked.minute;
    setState(() {
      _overrides[b.clave] = (
        inicio: hhmmDesdeMin(nuevoIni),
        fin: hhmmDesdeMin(nuevoIni + (dur > 0 ? dur : 30)),
      );
    });
  }

  Future<void> _replanificar() async {
    setState(() {
      _overrides.clear();
      _ocultos.clear();
      _aceptadas.clear();
      _sugUsadas.clear();
      _huecosSaltados.clear();
      _huecoOtra.clear();
    });
    ref.read(replanActivoProvider.notifier).state = true;
    ref.invalidate(planDiaProvider);
  }

  void _verDiaCompleto() {
    ref.read(replanActivoProvider.notifier).state = false;
    ref.invalidate(planDiaProvider);
  }

  Future<void> _alCalendario(PlanDia plan) async {
    final tentativos = _visibles(plan).where((b) => b.tentativo).toList();
    if (tentativos.isEmpty) {
      _aviso('No hay bloques planificados para mandar.');
      return;
    }
    setState(() => _trabajando = true);
    try {
      final r = await ref.read(horarioRepositoryProvider).aCalendario(tentativos);
      final creados = (r['creados'] as num?)?.toInt() ?? 0;
      final omitidos = (r['omitidos'] as num?)?.toInt() ?? 0;
      _aviso(creados == 0
          ? 'Ya estaban en el calendario ($omitidos).'
          : 'Mandé $creados al calendario'
              '${omitidos > 0 ? ' ($omitidos ya estaban)' : ''}.');
    } on Object catch (e) {
      _aviso('No pude mandarlo al calendario: $e');
    } finally {
      if (mounted) setState(() => _trabajando = false);
    }
  }

  void _aviso(String texto) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(texto)));
  }

  /// Un hueco libre: si hay una sugerencia que cabe (y no fue descartada) la
  /// ofrece tocable; si no, lo muestra como tiempo libre, sin culpa. Dosifica:
  /// una sola sugerencia por hueco.
  Widget _huecoWidget(PlanDia plan, {required BloquePlan prev, required int hueco}) {
    final key = prev.clave;
    final descartado = _huecosSaltados.contains(key);
    final sug = descartado
        ? null
        : elegirSugerencia(
            plan.sugerencias,
            hueco,
            usadas: _sugUsadas,
            saltar: _huecoOtra[key] ?? 0,
          );
    if (sug == null) return _LibreFila(minutos: hueco);

    // ¿Hay otra alternativa distinta para este hueco? (para mostrar "Otra").
    final caben = plan.sugerencias
        .where((s) => !_sugUsadas.contains(s.clave) && s.durMin <= hueco)
        .length;
    return _SugerenciaFila(
      hueco: hueco,
      sugerencia: sug,
      hayOtra: caben > 1,
      habilitado: !_trabajando,
      onHacer: () => _aceptarSugerencia(sug, prev.finMin, hueco),
      onOtra: () => setState(() => _huecoOtra[key] = (_huecoOtra[key] ?? 0) + 1),
      onSaltar: () => setState(() => _huecosSaltados.add(key)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final planAsync = ref.watch(planDiaProvider);
    final cursos = ref.watch(cursosListProvider).valueOrNull ?? const [];
    final colorPorCurso = <String, int>{
      for (final c in cursos)
        if (c.color != null && argbDeHex(c.color) != null)
          c.nombre: argbDeHex(c.color)!,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Header(
          esReplan: planAsync.valueOrNull?.esReplan ?? false,
          onReplan: _trabajando ? null : _replanificar,
          onDiaCompleto: _verDiaCompleto,
          onCalendario: (_trabajando || planAsync.valueOrNull == null)
              ? null
              : () => _alCalendario(planAsync.value!),
        ),
        planAsync.when(
          loading: () => const _Loader(),
          error: (e, _) => _ErrorLinea(
            onReintentar: () => ref.invalidate(planDiaProvider),
          ),
          data: (plan) {
            final bloques = _visibles(plan);
            if (bloques.isEmpty) {
              return _Vacio(onGenerar: () => ref.invalidate(planDiaProvider));
            }
            return Column(
              children: [
                for (var i = 0; i < bloques.length; i++) ...[
                  if (i > 0 &&
                      huecoVisible(bloques[i - 1].fin, bloques[i].inicio))
                    _huecoWidget(
                      plan,
                      prev: bloques[i - 1],
                      hueco: huecoMin(bloques[i - 1].fin, bloques[i].inicio),
                    ),
                  _BloqueFila(
                    bloque: bloques[i],
                    colorCurso: colorPorCurso[bloques[i].titulo],
                    habilitado: !_trabajando,
                    onHecho: () => _hecho(bloques[i]),
                    onSaltar: () => _saltar(bloques[i]),
                    onEditarHora: () => _editarHora(bloques[i]),
                  ),
                ],
                if (plan.fuera.isNotEmpty) _FueraFila(fuera: plan.fuera),
              ],
            );
          },
        ),
      ],
    );
  }
}

// ── Sub-widgets ──────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({
    required this.esReplan,
    required this.onReplan,
    required this.onDiaCompleto,
    required this.onCalendario,
  });
  final bool esReplan;
  final VoidCallback? onReplan;
  final VoidCallback onDiaCompleto;
  final VoidCallback? onCalendario;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 18, 14, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            esReplan ? 'TU DÍA · RESTO' : 'TU DÍA',
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0,
              color: MatixColors.muted,
            ),
          ),
          const Spacer(),
          if (esReplan)
            _AccionTexto(label: 'Día completo', onTap: onDiaCompleto)
          else
            _AccionTexto(label: 'Replanifica', onTap: onReplan),
          _AccionTexto(label: 'Al calendario', onTap: onCalendario),
        ],
      ),
    );
  }
}

class _AccionTexto extends StatelessWidget {
  const _AccionTexto({required this.label, required this.onTap});
  final String label;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: onTap == null ? MatixColors.muted : MatixColors.accent,
          ),
        ),
      ),
    );
  }
}

Color _colorTipo(String tipo, int? colorCurso) {
  if (colorCurso != null) return Color(colorCurso);
  switch (tipo) {
    case 'clase':
      return MatixColors.teal;
    case 'evento':
      return MatixColors.purple;
    case 'ancla':
      return MatixColors.muted;
    case 'skill':
      return MatixColors.pink;
    case 'tarea':
      return MatixColors.amber;
    case 'trabajo':
    default:
      return MatixColors.accent;
  }
}

class _BloqueFila extends StatelessWidget {
  const _BloqueFila({
    required this.bloque,
    required this.colorCurso,
    required this.habilitado,
    required this.onHecho,
    required this.onSaltar,
    required this.onEditarHora,
  });
  final BloquePlan bloque;
  final int? colorCurso;
  final bool habilitado;
  final VoidCallback onHecho;
  final VoidCallback onSaltar;
  final VoidCallback onEditarHora;

  @override
  Widget build(BuildContext context) {
    final color = _colorTipo(bloque.tipo, colorCurso);
    final fijo = bloque.esFijo;
    final contexto = bloque.proyecto ?? bloque.skill;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 3, 16, 3),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: MatixColors.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: fijo ? MatixColors.hairline : color.withValues(alpha: 0.35),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Barra de color + horas.
            Container(width: 3, height: 38, color: color),
            const SizedBox(width: 10),
            SizedBox(
              width: 44,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    bloque.inicio,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: MatixColors.text,
                    ),
                  ),
                  Text(
                    bloque.fin,
                    style: const TextStyle(fontSize: 11, color: MatixColors.muted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    bloque.titulo,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: MatixColors.text,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(
                        fijo ? Icons.lock_outline : Icons.drag_indicator,
                        size: 12,
                        color: MatixColors.muted,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          fijo
                              ? 'fijo'
                              : (contexto != null
                                  ? '$contexto · tentativo'
                                  : 'tentativo'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            color: MatixColors.muted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Acciones solo para lo planificado (lo fijo no se toca aquí).
            if (!fijo) ...[
              _AccionIcono(
                icon: Icons.check_circle_outline,
                color: MatixColors.green,
                tooltip: 'Hecho',
                onTap: habilitado ? onHecho : null,
              ),
              _AccionIcono(
                icon: Icons.schedule,
                color: MatixColors.muted,
                tooltip: 'Cambiar hora',
                onTap: habilitado ? onEditarHora : null,
              ),
              _AccionIcono(
                icon: Icons.skip_next_outlined,
                color: MatixColors.muted,
                tooltip: 'Saltar',
                onTap: habilitado ? onSaltar : null,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AccionIcono extends StatelessWidget {
  const _AccionIcono({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onTap,
  });
  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      icon: Icon(icon, size: 20),
      color: color,
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
      padding: EdgeInsets.zero,
    );
  }
}

class _LibreFila extends StatelessWidget {
  const _LibreFila({required this.minutos});
  final int minutos;
  @override
  Widget build(BuildContext context) {
    final h = minutos ~/ 60;
    final m = minutos % 60;
    final txt = h > 0 ? '${h}h${m > 0 ? ' ${m}min' : ''}' : '${m}min';
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 2, 16, 2),
      child: Row(
        children: [
          const Icon(Icons.more_vert, size: 14, color: MatixColors.muted),
          const SizedBox(width: 6),
          Text(
            'Libre · $txt',
            style: const TextStyle(
              fontSize: 11.5,
              color: MatixColors.muted,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
}

/// Un hueco libre con UNA sugerencia tocable (skill o tarea de proyecto corto).
/// Es oferta, no relleno: el usuario la hace, pide otra, o la deja pasar.
class _SugerenciaFila extends StatelessWidget {
  const _SugerenciaFila({
    required this.hueco,
    required this.sugerencia,
    required this.hayOtra,
    required this.habilitado,
    required this.onHacer,
    required this.onOtra,
    required this.onSaltar,
  });
  final int hueco;
  final Sugerencia sugerencia;
  final bool hayOtra;
  final bool habilitado;
  final VoidCallback onHacer;
  final VoidCallback onOtra;
  final VoidCallback onSaltar;

  @override
  Widget build(BuildContext context) {
    final h = hueco ~/ 60;
    final m = hueco % 60;
    final libre = h > 0 ? '${h}h${m > 0 ? ' ${m}min' : ''}' : '${m}min';
    final contexto = sugerencia.proyecto ?? sugerencia.skill;
    final color = _colorTipo(sugerencia.tipo, null);

    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 4, 16, 4),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: MatixColors.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.30)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.more_vert, size: 14, color: MatixColors.muted),
                const SizedBox(width: 4),
                Text(
                  'Libre · $libre',
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: MatixColors.muted,
                    fontStyle: FontStyle.italic,
                  ),
                ),
                const Spacer(),
                Text(
                  'aprovecha si quieres',
                  style: TextStyle(
                    fontSize: 10.5,
                    color: MatixColors.muted.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Container(width: 3, height: 30, color: color),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        sugerencia.titulo,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: MatixColors.text,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        contexto != null
                            ? '$contexto · ~${sugerencia.durMin}min'
                            : '~${sugerencia.durMin}min',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: MatixColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _SugChip(
                  texto: 'Hacer',
                  primario: true,
                  enabled: habilitado,
                  onTap: onHacer,
                ),
                if (hayOtra)
                  _SugChip(
                    texto: 'Otra',
                    primario: false,
                    enabled: habilitado,
                    onTap: onOtra,
                  ),
                _SugChip(
                  texto: 'Ahora no',
                  primario: false,
                  enabled: habilitado,
                  onTap: onSaltar,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Chip tocable de la sugerencia (mismo lenguaje visual que las opciones de
/// Matix: pastilla redonda acento).
class _SugChip extends StatelessWidget {
  const _SugChip({
    required this.texto,
    required this.primario,
    required this.enabled,
    required this.onTap,
  });
  final String texto;
  final bool primario;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: primario
          ? MatixColors.accent
          : MatixColors.accent.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(99),
      child: InkWell(
        borderRadius: BorderRadius.circular(99),
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          child: Text(
            texto,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: primario ? Colors.white : MatixColors.accent,
            ),
          ),
        ),
      ),
    );
  }
}

class _FueraFila extends StatelessWidget {
  const _FueraFila({required this.fuera});
  final List<FueraPlan> fuera;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 2),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: MatixColors.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: MatixColors.amber.withValues(alpha: 0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.inbox_outlined,
                    size: 16, color: MatixColors.amber),
                const SizedBox(width: 8),
                Text(
                  'No entró hoy (${fuera.length})',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: MatixColors.text,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            for (final f in fuera)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  '· ${f.titulo}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5, color: MatixColors.muted),
                ),
              ),
            const SizedBox(height: 2),
            const Text(
              'Lo movemos a mañana, sin amontonar.',
              style: TextStyle(fontSize: 11.5, color: MatixColors.muted),
            ),
          ],
        ),
      ),
    );
  }
}

class _Vacio extends StatelessWidget {
  const _Vacio({required this.onGenerar});
  final VoidCallback onGenerar;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 2),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: MatixColors.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: MatixColors.hairline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Aún no hay plan para hoy.',
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: MatixColors.text,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Te lo armo con tus compromisos y lo que toca avanzar.',
              style: TextStyle(fontSize: 12.5, color: MatixColors.muted, height: 1.35),
            ),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: onGenerar,
              behavior: HitTestBehavior.opaque,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: MatixColors.accent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  'Generar plan de hoy',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Loader extends StatelessWidget {
  const _Loader();
  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 18),
      child: Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2.4, color: MatixColors.accent),
        ),
      ),
    );
  }
}

class _ErrorLinea extends StatelessWidget {
  const _ErrorLinea({required this.onReintentar});
  final VoidCallback onReintentar;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 2),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: MatixColors.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: MatixColors.hairline),
        ),
        child: Row(
          children: [
            const Expanded(
              child: Text(
                'No pude traer el plan de hoy.',
                style: TextStyle(fontSize: 13, color: MatixColors.muted),
              ),
            ),
            _AccionTexto(label: 'Reintentar', onTap: onReintentar),
          ],
        ),
      ),
    );
  }
}
