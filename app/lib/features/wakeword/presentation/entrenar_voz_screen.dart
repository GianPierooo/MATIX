import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../api/matix_client.dart';
import '../../../theme/matix_colors.dart';
import '../data/wakeword_muestras_grabador.dart';
import '../data/wakeword_muestras_guion.dart';
import '../data/wakeword_muestras_provider.dart';

/// Fase de la grabación de UN clip dentro de la pantalla.
enum _FaseClip { intro, listo, grabando, revisando, subiendo, hecho }

/// Pantalla "Entrenar mi voz": graba el guion (positivos "oye matix" +
/// negativos duros) y sube los clips al cerebro para reentrenar el wake word
/// afinado a la voz real del usuario.
///
/// Maneja permiso de micrófono, revisión/rehacer por clip, progreso de subida
/// y errores con degradación limpia (snackbar, nunca crash).
class EntrenarVozScreen extends ConsumerStatefulWidget {
  const EntrenarVozScreen({super.key});

  @override
  ConsumerState<EntrenarVozScreen> createState() => _EntrenarVozScreenState();
}

class _EntrenarVozScreenState extends ConsumerState<EntrenarVozScreen> {
  final _grabador = WakeWordMuestrasGrabador();
  final _player = AudioPlayer();
  late final List<MuestraGuion> _guion;
  late final int _totalPositivos;

  /// Clips grabados por índice global del guion.
  final Map<int, File> _grabadas = {};

  int _idx = 0;
  _FaseClip _fase = _FaseClip.intro;
  Timer? _topeGrabacion;

  // Subida
  int _subidas = 0;
  String? _errorSubida;

  /// Duración máxima de un clip: ~3 s alcanza de sobra para "oye matix" o una
  /// frase corta; corta solo si el usuario olvida parar.
  static const _maxClip = Duration(seconds: 3);

  @override
  void initState() {
    super.initState();
    _guion = construirGuion();
    _totalPositivos = _guion.where((m) => m.esPositivo).length;
  }

  @override
  void dispose() {
    _topeGrabacion?.cancel();
    _grabador.dispose();
    _player.dispose();
    super.dispose();
  }

  MuestraGuion get _actual => _guion[_idx];
  bool get _esUltimo => _idx == _guion.length - 1;
  int get _grabadasCount => _grabadas.length;
  bool get _todasGrabadas => _grabadasCount == _guion.length;

  /// Índice 1-based dentro de su tipo (para mostrar "Positivo 12 / 60").
  (int, int) get _posEnTipo {
    if (_actual.esPositivo) return (_idx + 1, _totalPositivos);
    return (_idx - _totalPositivos + 1, _guion.length - _totalPositivos);
  }

  Future<void> _empezar() async {
    setState(() => _fase = _FaseClip.listo);
  }

  Future<void> _iniciarGrabacion() async {
    try {
      await _player.stop();
      await _grabador.iniciar();
      setState(() => _fase = _FaseClip.grabando);
      _topeGrabacion?.cancel();
      _topeGrabacion = Timer(_maxClip, () {
        if (_fase == _FaseClip.grabando) _detenerGrabacion();
      });
    } on PermisoMicMuestrasDenegado catch (e) {
      if (!mounted) return;
      _snack(
        e.permanente
            ? 'Necesito el micrófono. Actívalo en Ajustes del sistema.'
            : 'Necesito permiso del micrófono para grabar.',
        accion: e.permanente
            ? SnackBarAction(label: 'Ajustes', onPressed: openAppSettings)
            : null,
      );
    } catch (e) {
      if (mounted) _snack('No pude abrir el micrófono: $e');
    }
  }

  Future<void> _detenerGrabacion() async {
    _topeGrabacion?.cancel();
    try {
      final f = await _grabador.detener();
      if (f != null) {
        _grabadas[_idx] = f;
        setState(() => _fase = _FaseClip.revisando);
      } else {
        setState(() => _fase = _FaseClip.listo);
      }
    } catch (e) {
      if (mounted) {
        _snack('Falló la grabación: $e');
        setState(() => _fase = _FaseClip.listo);
      }
    }
  }

  Future<void> _reproducir() async {
    final f = _grabadas[_idx];
    if (f == null) return;
    try {
      await _player.stop();
      await _player.play(DeviceFileSource(f.path));
    } catch (e) {
      if (mounted) _snack('No pude reproducir: $e');
    }
  }

  void _rehacer() {
    _grabadas.remove(_idx);
    setState(() => _fase = _FaseClip.listo);
  }

  void _siguiente() {
    if (_esUltimo) {
      setState(() {}); // refresca el footer (ya puede subir)
      return;
    }
    setState(() {
      _idx++;
      _fase = _grabadas.containsKey(_idx) ? _FaseClip.revisando : _FaseClip.listo;
    });
  }

  void _anterior() {
    if (_idx == 0) return;
    setState(() {
      _idx--;
      _fase = _grabadas.containsKey(_idx) ? _FaseClip.revisando : _FaseClip.listo;
    });
  }

  Future<void> _subir() async {
    final repo = ref.read(wakeWordMuestrasRepoProvider);
    setState(() {
      _fase = _FaseClip.subiendo;
      _subidas = 0;
      _errorSubida = null;
    });
    try {
      // Empezamos de cero en el servidor para que el lote sea consistente.
      await repo.borrarTodo();
      // Índices 1-based por tipo, en el orden del guion.
      var nPos = 0;
      var nNeg = 0;
      final entradas = _grabadas.entries.toList()
        ..sort((a, b) => a.key.compareTo(b.key));
      for (final e in entradas) {
        final g = _guion[e.key];
        final indice = g.esPositivo ? (++nPos) : (++nNeg);
        await repo.subir(wav: e.value, tipo: g.tipo, indice: indice);
        if (!mounted) return;
        setState(() => _subidas++);
      }
      if (mounted) setState(() => _fase = _FaseClip.hecho);
    } on MatixApiException catch (e) {
      if (mounted) {
        setState(() {
          _errorSubida = e.message;
          _fase = _FaseClip.revisando;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorSubida = '$e';
          _fase = _FaseClip.revisando;
        });
      }
    }
  }

  void _snack(String msg, {SnackBarAction? accion}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), action: accion),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MatixColors.bg,
      appBar: AppBar(
        title: const Text('Entrenar mi voz'),
        backgroundColor: MatixColors.bg,
      ),
      body: SafeArea(
        child: switch (_fase) {
          _FaseClip.intro => _Intro(onEmpezar: _empezar),
          _FaseClip.subiendo => _Subiendo(
              hechas: _subidas,
              total: _grabadasCount,
            ),
          _FaseClip.hecho => _Hecho(
              total: _grabadasCount,
              onCerrar: () => Navigator.of(context).pop(true),
            ),
          _ => _Grabador(
              guion: _actual,
              posEnTipo: _posEnTipo,
              idxGlobal: _idx,
              totalGlobal: _guion.length,
              grabadasCount: _grabadasCount,
              fase: _fase,
              tieneClip: _grabadas.containsKey(_idx),
              puedeAnterior: _idx > 0,
              esUltimo: _esUltimo,
              todasGrabadas: _todasGrabadas,
              errorSubida: _errorSubida,
              onGrabar: _iniciarGrabacion,
              onParar: _detenerGrabacion,
              onReproducir: _reproducir,
              onRehacer: _rehacer,
              onSiguiente: _siguiente,
              onAnterior: _anterior,
              onSubir: _grabadasCount > 0 ? _subir : null,
            ),
        },
      ),
    );
  }
}

class _Intro extends StatelessWidget {
  const _Intro({required this.onEmpezar});
  final VoidCallback onEmpezar;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.graphic_eq, color: MatixColors.purple, size: 48),
          const SizedBox(height: 16),
          const Text(
            'Enséñale a Matix tu voz',
            style: TextStyle(
              color: MatixColors.text,
              fontSize: 24,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Vas a grabar unas frases cortas. La mayoría son “oye matix” dicha '
            'de distintas formas (normal, suave, lejos, rápido) y unas pocas '
            'frases parecidas que NO deben despertarla.\n\n'
            'Con esto reentreno el modelo para que reconozca TU voz y tu '
            'micrófono. Son unos minutos. Puedes repetir cualquier clip antes '
            'de subir.',
            style: TextStyle(color: MatixColors.muted, fontSize: 15, height: 1.4),
          ),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onEmpezar,
              style: FilledButton.styleFrom(
                backgroundColor: MatixColors.purple,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: const Text('Empezar a grabar'),
            ),
          ),
        ],
      ),
    );
  }
}

class _Grabador extends StatelessWidget {
  const _Grabador({
    required this.guion,
    required this.posEnTipo,
    required this.idxGlobal,
    required this.totalGlobal,
    required this.grabadasCount,
    required this.fase,
    required this.tieneClip,
    required this.puedeAnterior,
    required this.esUltimo,
    required this.todasGrabadas,
    required this.errorSubida,
    required this.onGrabar,
    required this.onParar,
    required this.onReproducir,
    required this.onRehacer,
    required this.onSiguiente,
    required this.onAnterior,
    required this.onSubir,
  });

  final MuestraGuion guion;
  final (int, int) posEnTipo;
  final int idxGlobal;
  final int totalGlobal;
  final int grabadasCount;
  final _FaseClip fase;
  final bool tieneClip;
  final bool puedeAnterior;
  final bool esUltimo;
  final bool todasGrabadas;
  final String? errorSubida;
  final VoidCallback onGrabar;
  final VoidCallback onParar;
  final VoidCallback onReproducir;
  final VoidCallback onRehacer;
  final VoidCallback onSiguiente;
  final VoidCallback onAnterior;
  final VoidCallback? onSubir;

  @override
  Widget build(BuildContext context) {
    final esPos = guion.esPositivo;
    final color = esPos ? MatixColors.purple : MatixColors.amber;
    final grabando = fase == _FaseClip.grabando;

    return Column(
      children: [
        // Progreso global.
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${esPos ? "Positivo" : "Negativo"} ${posEnTipo.$1} / ${posEnTipo.$2}',
                    style: TextStyle(color: color, fontWeight: FontWeight.w600),
                  ),
                  Text(
                    '$grabadasCount / $totalGlobal grabadas',
                    style: const TextStyle(color: MatixColors.muted, fontSize: 13),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: totalGlobal == 0 ? 0 : grabadasCount / totalGlobal,
                  minHeight: 6,
                  backgroundColor: MatixColors.card,
                  valueColor: AlwaysStoppedAnimation(color),
                ),
              ),
            ],
          ),
        ),

        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    esPos ? 'Di:' : 'Di (NO debe despertarla):',
                    style: const TextStyle(color: MatixColors.muted),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '“${guion.frase}”',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: MatixColors.text,
                      fontSize: 34,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    guion.pista,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: MatixColors.muted, fontSize: 14),
                  ),
                  const SizedBox(height: 36),
                  // Botón grande de grabar / parar.
                  GestureDetector(
                    onTap: grabando ? onParar : onGrabar,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: grabando ? 108 : 96,
                      height: grabando ? 108 : 96,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: grabando ? MatixColors.red : color,
                        boxShadow: [
                          BoxShadow(
                            color: (grabando ? MatixColors.red : color)
                                .withValues(alpha: 0.4),
                            blurRadius: grabando ? 28 : 12,
                            spreadRadius: grabando ? 4 : 0,
                          ),
                        ],
                      ),
                      child: Icon(
                        grabando ? Icons.stop : Icons.mic,
                        color: Colors.white,
                        size: 44,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    grabando
                        ? 'Grabando… toca para parar'
                        : tieneClip
                            ? 'Grabado ✓ — puedes repetirlo'
                            : 'Toca para grabar',
                    style: const TextStyle(color: MatixColors.muted),
                  ),
                  const SizedBox(height: 20),
                  // Revisión del clip grabado.
                  if (tieneClip && !grabando)
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 10,
                      children: [
                        TextButton.icon(
                          onPressed: onReproducir,
                          icon: const Icon(Icons.play_arrow),
                          label: const Text('Escuchar'),
                        ),
                        TextButton.icon(
                          onPressed: onRehacer,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Repetir'),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),

        if (errorSubida != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'No se pudo subir: $errorSubida',
              style: const TextStyle(color: MatixColors.red, fontSize: 13),
            ),
          ),

        // Navegación + subir.
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: puedeAnterior ? onAnterior : null,
                      child: const Text('Anterior'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: tieneClip && !esUltimo ? onSiguiente : null,
                      style: FilledButton.styleFrom(
                        backgroundColor: MatixColors.accent,
                      ),
                      child: const Text('Siguiente'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: onSubir,
                  style: FilledButton.styleFrom(
                    backgroundColor:
                        todasGrabadas ? MatixColors.green : MatixColors.card,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  icon: const Icon(Icons.cloud_upload_outlined),
                  label: Text(
                    todasGrabadas
                        ? 'Subir mis grabaciones'
                        : 'Subir lo grabado ($grabadasCount)',
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Subiendo extends StatelessWidget {
  const _Subiendo({required this.hechas, required this.total});
  final int hechas;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: MatixColors.purple),
          const SizedBox(height: 24),
          Text(
            'Subiendo tus grabaciones…\n$hechas / $total',
            textAlign: TextAlign.center,
            style: const TextStyle(color: MatixColors.text, fontSize: 16),
          ),
        ],
      ),
    );
  }
}

class _Hecho extends StatelessWidget {
  const _Hecho({required this.total, required this.onCerrar});
  final int total;
  final VoidCallback onCerrar;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle, color: MatixColors.green, size: 64),
            const SizedBox(height: 20),
            Text(
              '¡Listo! Subí tus $total grabaciones.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: MatixColors.text,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Con esto voy a reentrenar “oye matix” afinado a tu voz. '
              'Te aviso cuando esté el modelo nuevo para actualizar la app.',
              textAlign: TextAlign.center,
              style: TextStyle(color: MatixColors.muted, fontSize: 15, height: 1.4),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: onCerrar,
                style: FilledButton.styleFrom(
                  backgroundColor: MatixColors.green,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('Terminar'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
