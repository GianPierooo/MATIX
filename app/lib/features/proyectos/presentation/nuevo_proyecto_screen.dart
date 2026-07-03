import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../api/matix_client.dart';
import '../../../theme/matix_colors.dart';
import '../../../theme/matix_button_styles.dart';
import '../../matix/providers/matix_chat_providers.dart';
import '../../matix/providers/navegacion_matix_provider.dart';
import '../domain/proyecto.dart';
import '../providers/proyectos_providers.dart';

/// Crear proyecto. Si ya hay 3 activos, el cerebro devuelve 409 y la
/// pantalla muestra los 3 activos con acciones para liberar uno.
class NuevoProyectoScreen extends ConsumerStatefulWidget {
  const NuevoProyectoScreen({super.key});

  @override
  ConsumerState<NuevoProyectoScreen> createState() =>
      _NuevoProyectoScreenState();
}

class _NuevoProyectoScreenState extends ConsumerState<NuevoProyectoScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nombre = TextEditingController();
  final _desc = TextEditingController();
  final _linea = TextEditingController();
  EstadoProyecto _estado = EstadoProyecto.activo;
  int? _prioridad;
  bool _guardando = false;
  String? _error;

  @override
  void dispose() {
    _nombre.dispose();
    _desc.dispose();
    _linea.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      final creado = await ref.read(proyectosRepositoryProvider).crear(
            nombre: _nombre.text.trim(),
            descripcion:
                _desc.text.trim().isEmpty ? null : _desc.text.trim(),
            estado: _estado,
            prioridad: _prioridad,
            lineaMeta:
                _linea.text.trim().isEmpty ? null : _linea.text.trim(),
          );
      ref.invalidate(proyectosListProvider);
      if (!mounted) return;
      final estructurar = await _ofrecerEstructurar(creado.nombre);
      if (!mounted) return;
      if (estructurar) _lanzarIntake(creado.nombre);
      if (mounted) Navigator.of(context).pop();
    } on MatixApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  /// Tras crear, ofrece estructurarlo con Matix (intake guiado). El intake es
  /// opcional: el proyecto ya quedó creado.
  Future<bool> _ofrecerEstructurar(String nombre) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Lo estructuramos?'),
        content: Text(
          'Puedo hacerte unas preguntas para armar el plan de «$nombre»: '
          'objetivo, fases, próximos pasos, materiales y qué ya tienes hecho. '
          'Es guiado y lo puedes pausar.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Ahora no'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Sí, con Matix'),
          ),
        ],
      ),
    );
    return r ?? false;
  }

  /// Manda el mensaje de arranque del intake al chat y cambia a la pestaña de
  /// Matix. El cerebro lanza la entrevista + enganche de materiales.
  void _lanzarIntake(String nombre) {
    ref.read(chatMatixProvider.notifier).enviar(
          'Acabo de crear el proyecto «$nombre». Ayúdame a estructurarlo: '
          'hazme la entrevista para llenar su perfil (objetivo, fases, '
          'componentes, próximos pasos, materiales y qué ya está hecho) y arma '
          'el plan. Una pregunta a la vez.',
        );
    ref.read(objetivoNavegacionProvider.notifier).state = SeccionMatix.matix;
  }

  Future<void> _aparcarUno(Proyecto p) async {
    await ref
        .read(proyectosRepositoryProvider)
        .cambiarEstado(p.id, EstadoProyecto.aparcado);
    ref.invalidate(proyectosListProvider);
  }

  Future<void> _terminarUno(Proyecto p) async {
    await ref
        .read(proyectosRepositoryProvider)
        .cambiarEstado(p.id, EstadoProyecto.terminado);
    ref.invalidate(proyectosListProvider);
  }

  @override
  Widget build(BuildContext context) {
    final lista = ref.watch(proyectosListProvider);
    final activos = lista.maybeWhen(
      data: (xs) =>
          xs.where((p) => p.estado == EstadoProyecto.activo).toList(),
      orElse: () => const <Proyecto>[],
    );
    final topeAlcanzado =
        _estado == EstadoProyecto.activo && activos.length >= 3;

    return Scaffold(
      appBar: AppBar(title: const Text('Nuevo proyecto')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          children: [
            if (topeAlcanzado) ...[
              _BannerTope(),
              const SizedBox(height: 8),
              const Text(
                'ELIGE CUÁL LIBERAR',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0,
                  color: MatixColors.muted,
                ),
              ),
              const SizedBox(height: 6),
              for (final p in activos)
                Card(
                  color: MatixColors.card,
                  child: ListTile(
                    title: Text(p.nombre),
                    subtitle:
                        Text('Última: ${p.etiquetaCalor.toLowerCase()}'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Aparcar',
                          icon: const Icon(Icons.pause_circle_outline,
                              color: MatixColors.amber),
                          onPressed: () => _aparcarUno(p),
                        ),
                        IconButton(
                          tooltip: 'Terminar',
                          icon: const Icon(Icons.check_circle_outline,
                              color: MatixColors.green),
                          onPressed: () => _terminarUno(p),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 24),
            ],
            Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: _nombre,
                    decoration:
                        const InputDecoration(labelText: 'Nombre del proyecto'),
                    validator: (s) =>
                        (s == null || s.trim().isEmpty) ? 'Pon un nombre' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _desc,
                    decoration: const InputDecoration(
                        labelText: 'Descripción (opcional)'),
                    minLines: 1,
                    maxLines: 3,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _linea,
                    decoration: const InputDecoration(
                      labelText: 'Línea de meta (cuándo está terminado)',
                    ),
                    minLines: 1,
                    maxLines: 3,
                  ),
                  const SizedBox(height: 16),
                  const Text('ESTADO',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.0,
                        color: MatixColors.muted,
                      )),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    children: EstadoProyecto.values.map((e) {
                      final activo = e == _estado;
                      return ChoiceChip(
                        label: Text(e.label),
                        selected: activo,
                        onSelected: (_) => setState(() => _estado = e),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),
                  if (_estado == EstadoProyecto.activo) ...[
                    const Text('PRIORIDAD',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.0,
                          color: MatixColors.muted,
                        )),
                    const SizedBox(height: 2),
                    const Text(
                      'El número de orden entre tus activos. No puede '
                      'repetirse: los ya usados salen deshabilitados.',
                      style: TextStyle(fontSize: 12, color: MatixColors.muted),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [1, 2, 3].map((p) {
                        final sel = _prioridad == p;
                        // Números ya tomados por OTRO proyecto activo.
                        final tomado = activos.any((a) => a.prioridad == p);
                        return ChoiceChip(
                          label: Text(tomado ? '#$p (en uso)' : '#$p'),
                          selected: sel,
                          onSelected: tomado
                              ? null
                              : (_) =>
                                  setState(() => _prioridad = sel ? null : p),
                        );
                      }).toList(),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: MatixColors.red.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        _error!,
                        style: const TextStyle(
                            color: MatixColors.red, fontSize: 13),
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _guardando ? null : _guardar,
                    style: MatixButtonStyles.primarioAlto,
                    child: _guardando
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2.2,
                            ),
                          )
                        : const Text('Crear proyecto'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BannerTope extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: MatixColors.amber.withValues(alpha: 0.10),
        border: Border.all(color: MatixColors.amber.withValues(alpha: 0.40)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: MatixColors.amber),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Ya tienes 3 proyectos activos. Aparca o termina uno '
              'para abrir hueco.',
              style: TextStyle(fontSize: 13, color: MatixColors.text),
            ),
          ),
        ],
      ),
    );
  }
}
