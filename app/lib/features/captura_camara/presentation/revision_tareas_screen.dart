import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/matix_colors.dart';
import '../../../theme/matix_button_styles.dart';
import '../../../theme/matix_spacing.dart';
import '../../../theme/matix_typography.dart';
import '../../tareas/domain/selectores.dart';
import '../../tareas/providers/tareas_providers.dart';
import '../application/extraccion_tareas_controller.dart';

/// Hoja de revisión de las tareas que el cerebro propuso a partir del
/// texto (Capa 7-B). El usuario edita el título, ajusta o quita la
/// fecha, asigna un proyecto y borra las que no van. **Nada se crea
/// hasta que confirma** con el botón inferior.
///
/// Al confirmar, el controller crea las tareas con el CRUD de siempre
/// e invalida la lista; aparecen al instante en Tareas y en el "Hoy"
/// de Inicio si vencen hoy.
class RevisionTareasScreen extends ConsumerStatefulWidget {
  const RevisionTareasScreen({super.key});

  @override
  ConsumerState<RevisionTareasScreen> createState() =>
      _RevisionTareasScreenState();
}

class _RevisionTareasScreenState extends ConsumerState<RevisionTareasScreen> {
  /// Un controller de texto por fila, para editar el título sin perder
  /// el cursor en cada rebuild. Se mantiene en paralelo a las
  /// propuestas del estado; el único punto que cambia la longitud es
  /// el borrado, que actualiza ambas listas a la vez.
  late List<TextEditingController> _titulos;

  @override
  void initState() {
    super.initState();
    final propuestas =
        ref.read(extraccionTareasControllerProvider).propuestas;
    _titulos = [
      for (final p in propuestas) TextEditingController(text: p.titulo),
    ];
  }

  @override
  void dispose() {
    for (final c in _titulos) {
      c.dispose();
    }
    super.dispose();
  }

  ExtraccionTareasController get _ctrl =>
      ref.read(extraccionTareasControllerProvider.notifier);

  void _eliminar(int i) {
    if (i < 0 || i >= _titulos.length) return;
    _titulos[i].dispose();
    setState(() => _titulos.removeAt(i));
    _ctrl.eliminar(i);
  }

  Future<void> _elegirFecha(int i, DateTime? actual) async {
    final ahora = DateTime.now();
    final elegida = await showDatePicker(
      context: context,
      initialDate: actual ?? ahora,
      firstDate: DateTime(ahora.year - 1),
      lastDate: DateTime(ahora.year + 5),
    );
    if (elegida != null) _ctrl.ponerFecha(i, elegida);
  }

  void _volverATareas() {
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final estado = ref.watch(extraccionTareasControllerProvider);

    if (estado.fase == FaseExtraccion.creado) {
      return _PantallaCreado(
        creadas: estado.creadas,
        onVolver: _volverATareas,
      );
    }

    final propuestas = estado.propuestas;
    final creando = estado.fase == FaseExtraccion.creando;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Revisar tareas'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (estado.error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    MatixSpacing.xl, MatixSpacing.l, MatixSpacing.xl, 0),
                child: _BannerError(mensaje: estado.error!),
              ),
            Expanded(
              child: propuestas.isEmpty
                  ? const _SinPropuestas()
                  : ListView.separated(
                      padding: const EdgeInsets.all(MatixSpacing.xl),
                      itemCount: propuestas.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: MatixSpacing.l),
                      itemBuilder: (context, i) {
                        return _FilaPropuesta(
                          key: ValueKey(_titulos[i]),
                          controllerTitulo: _titulos[i],
                          venceEn: propuestas[i].venceEn,
                          proyectoId: propuestas[i].proyectoId,
                          habilitado: !creando,
                          onTituloCambia: (v) => _ctrl.editarTitulo(i, v),
                          onElegirFecha: () =>
                              _elegirFecha(i, propuestas[i].venceEn),
                          onQuitarFecha: () => _ctrl.quitarFecha(i),
                          onProyecto: (id) => _ctrl.asignarProyecto(i, id),
                          onEliminar: () => _eliminar(i),
                        );
                      },
                    ),
            ),
            if (propuestas.isNotEmpty)
              _BarraConfirmar(
                cantidad: propuestas.length,
                creando: creando,
                onConfirmar: () => _ctrl.crear(),
              ),
          ],
        ),
      ),
    );
  }
}

class _FilaPropuesta extends ConsumerWidget {
  const _FilaPropuesta({
    super.key,
    required this.controllerTitulo,
    required this.venceEn,
    required this.proyectoId,
    required this.habilitado,
    required this.onTituloCambia,
    required this.onElegirFecha,
    required this.onQuitarFecha,
    required this.onProyecto,
    required this.onEliminar,
  });

  final TextEditingController controllerTitulo;
  final DateTime? venceEn;
  final String? proyectoId;
  final bool habilitado;
  final ValueChanged<String> onTituloCambia;
  final VoidCallback onElegirFecha;
  final VoidCallback onQuitarFecha;
  final ValueChanged<String?> onProyecto;
  final VoidCallback onEliminar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final proyectosAsync = ref.watch(proyectosProvider);

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
              Expanded(
                child: TextField(
                  controller: controllerTitulo,
                  enabled: habilitado,
                  onChanged: onTituloCambia,
                  style: MatixText.body,
                  decoration: const InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: 'Título de la tarea',
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Quitar de la lista',
                onPressed: habilitado ? onEliminar : null,
                icon: const Icon(Icons.close, size: 20),
                color: MatixColors.muted,
              ),
            ],
          ),
          const SizedBox(height: MatixSpacing.m),
          Row(
            children: [
              _ChipFecha(
                venceEn: venceEn,
                habilitado: habilitado,
                onElegir: onElegirFecha,
                onQuitar: onQuitarFecha,
              ),
              const SizedBox(width: MatixSpacing.m),
              Expanded(
                child: proyectosAsync.when(
                  data: (proyectos) => _SelectorProyecto(
                    proyectos: proyectos,
                    seleccionado: proyectoId,
                    habilitado: habilitado,
                    onCambia: onProyecto,
                  ),
                  loading: () => const SizedBox(
                    height: 20,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ),
                  error: (err, st) => Text(
                    'Proyectos no disponibles',
                    style: MatixText.small,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ChipFecha extends StatelessWidget {
  const _ChipFecha({
    required this.venceEn,
    required this.habilitado,
    required this.onElegir,
    required this.onQuitar,
  });

  final DateTime? venceEn;
  final bool habilitado;
  final VoidCallback onElegir;
  final VoidCallback onQuitar;

  String get _texto {
    final v = venceEn;
    if (v == null) return 'Sin fecha';
    const meses = [
      'ene', 'feb', 'mar', 'abr', 'may', 'jun',
      'jul', 'ago', 'sep', 'oct', 'nov', 'dic',
    ];
    return '${v.day} ${meses[v.month - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    final tieneFecha = venceEn != null;
    return InkWell(
      onTap: habilitado ? onElegir : null,
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
            Icon(
              Icons.event_outlined,
              size: 16,
              color: tieneFecha ? MatixColors.accent : MatixColors.muted,
            ),
            const SizedBox(width: MatixSpacing.s),
            Text(
              _texto,
              style: MatixText.small.copyWith(
                color: tieneFecha ? MatixColors.text : MatixColors.muted,
              ),
            ),
            if (tieneFecha && habilitado) ...[
              const SizedBox(width: MatixSpacing.s),
              GestureDetector(
                onTap: onQuitar,
                child: const Icon(Icons.close,
                    size: 14, color: MatixColors.muted),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SelectorProyecto extends StatelessWidget {
  const _SelectorProyecto({
    required this.proyectos,
    required this.seleccionado,
    required this.habilitado,
    required this.onCambia,
  });

  final List<ProyectoRef> proyectos;
  final String? seleccionado;
  final bool habilitado;
  final ValueChanged<String?> onCambia;

  @override
  Widget build(BuildContext context) {
    // Solo los ids que existen son válidos para el dropdown; si la
    // propuesta apunta a uno desconocido, caemos a "Sin proyecto".
    final ids = proyectos.map((p) => p.id).toSet();
    final valor = (seleccionado != null && ids.contains(seleccionado))
        ? seleccionado
        : null;

    return DropdownButton<String?>(
      value: valor,
      isExpanded: true,
      isDense: true,
      underline: const SizedBox.shrink(),
      dropdownColor: MatixColors.cardHi,
      icon: const Icon(Icons.folder_outlined,
          size: 16, color: MatixColors.muted),
      hint: Text('Sin proyecto', style: MatixText.small),
      style: MatixText.small.copyWith(color: MatixColors.text),
      onChanged: habilitado ? onCambia : null,
      items: [
        DropdownMenuItem<String?>(
          value: null,
          child: Text('Sin proyecto', style: MatixText.small),
        ),
        for (final p in proyectos)
          DropdownMenuItem<String?>(
            value: p.id,
            child: Text(
              p.nombre,
              overflow: TextOverflow.ellipsis,
              style: MatixText.small.copyWith(color: MatixColors.text),
            ),
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
            : Text(cantidad == 1 ? 'Crear 1 tarea' : 'Crear $cantidad tareas'),
      ),
    );
  }
}

class _BannerError extends StatelessWidget {
  const _BannerError({required this.mensaje});
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

class _SinPropuestas extends StatelessWidget {
  const _SinPropuestas();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(MatixSpacing.xl4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.checklist_rtl_outlined,
                color: MatixColors.muted, size: 56),
            const SizedBox(height: MatixSpacing.xl),
            Text(
              'No encontré tareas claras',
              textAlign: TextAlign.center,
              style: MatixText.subtitle,
            ),
            const SizedBox(height: MatixSpacing.m),
            Text(
              'El texto no parece tener acciones concretas. Vuelve atrás '
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
  const _PantallaCreado({required this.creadas, required this.onVolver});
  final int creadas;
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
                const Icon(Icons.check_circle_outline,
                    color: MatixColors.green, size: 64),
                const SizedBox(height: MatixSpacing.xl),
                Text(
                  creadas == 1 ? 'Creé 1 tarea' : 'Creé $creadas tareas',
                  textAlign: TextAlign.center,
                  style: MatixText.title,
                ),
                const SizedBox(height: MatixSpacing.m),
                Text(
                  'Ya están en Tareas, y en el "Hoy" de Inicio si vencen hoy.',
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
                  child: const Text('Volver a Tareas'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
