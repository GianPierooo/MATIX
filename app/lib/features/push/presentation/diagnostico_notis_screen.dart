import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/notificaciones_service.dart';
import '../../../theme/matix_colors.dart';
import '../../wakeword/providers/wakeword_providers.dart' show wakeWordBgServiceProvider;
import '../application/confirmacion_service.dart';
import '../application/entrega_background_service.dart';
import '../domain/intensidad_notif.dart';

/// Pantalla de Diagnóstico de notificaciones.
///
/// El user usa Honor/MagicOS. Las notis se entregan tarde o nunca, y los
/// botones a veces no disparan. Esta pantalla **convierte "no sé por qué falla"
/// en "veo exactamente qué eslabón falla"**:
///
/// - Estado de cada permiso/restricción del SO (POST_NOTIFICATIONS, alarmas
///   exactas, batería sin restricciones, full-screen intent) con CTA que abre
///   el ajuste del sistema correspondiente.
/// - Botón "Enviar prueba con botones AHORA" que dispara una noti REAL con los
///   mismos botones que usa la rendición de cuentas/asistencia. Al tocarlos,
///   el handler de background hace POST al cerebro y guarda en el log local
///   evidencia (status + cuándo). Lo más cercano que se puede al chain real.
/// - Historial reciente del [ConfirmacionService] (último envío + status): ahí
///   se ve si la cadena botón→handler→cerebro funciona, y dónde se rompe.
///
/// El render nativo, los permisos del SO y la entrega real son de DISPOSITIVO:
/// no se prueban en unit local. Por eso esta pantalla EXISTE: para validar en
/// device en pasos pequeños.
class DiagnosticoNotisScreen extends ConsumerStatefulWidget {
  const DiagnosticoNotisScreen({super.key});

  @override
  ConsumerState<DiagnosticoNotisScreen> createState() =>
      _DiagnosticoNotisScreenState();
}

class _DiagnosticoNotisScreenState extends ConsumerState<DiagnosticoNotisScreen> {
  bool? _permisoNotifs;
  bool _trabajando = false;

  // Estado del último chequeo del canal nativo (full-screen intent).
  bool? _puedeFullScreen;

  // Log local de intentos de confirmación (evidencia del chain).
  List<EntradaConfirmacion> _log = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refrescar());
  }

  Future<void> _refrescar() async {
    final svc = ref.read(confirmacionServiceProvider);
    final log = await svc.leerLog();
    bool? fs;
    try {
      fs = await ref.read(wakeWordBgServiceProvider).puedeFullScreenIntent();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _log = log;
      _puedeFullScreen = fs;
    });
  }

  Future<void> _pedirPermiso() async {
    final ok = await ref.read(notificacionesServiceProvider).pedirPermisos();
    if (!mounted) return;
    setState(() => _permisoNotifs = ok);
  }

  Future<void> _pedirExactas() async {
    await ref.read(notificacionesServiceProvider).pedirPermisoAlarmasExactas();
    if (!mounted) return;
    _aviso('Si se abrió el ajuste del sistema, activa "Alarmas y recordatorios".');
  }

  Future<void> _pedirBateria() async {
    await ref.read(entregaBackgroundServiceProvider).pedirExencion();
    await _refrescar();
  }

  Future<void> _pedirFullScreen() async {
    try {
      await ref.read(wakeWordBgServiceProvider).pedirFullScreenIntent();
    } catch (_) {}
    await Future<void>.delayed(const Duration(milliseconds: 600));
    await _refrescar();
  }

  /// Dispara una notificación REAL con los botones de acción. Usa una "tarea
  /// fantasma" (`diag-ping`) para no tocar datos del usuario; el cerebro
  /// responderá 404 al recibir la acción y el log mostrará la evidencia de que
  /// el chain disparó. Si el cerebro está corriendo, además verás el `info` en
  /// los logs (`rc/accion recibida`).
  Future<void> _enviarPruebaConBotones() async {
    setState(() => _trabajando = true);
    try {
      final notif = ref.read(notificacionesServiceProvider);
      await notif.pedirPermisos();
      // Permite que el sistema "asiente" la creación de canales en MagicOS.
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await notif.mostrarConAcciones(
        id: 990500,
        titulo: '¿Hiciste tu tarea de prueba?',
        cuerpo: 'Toca un botón para verificar la cadena de acciones. '
            'Esto NO afecta tus datos.',
        acciones: const ['hecho', 'mas_tarde', 'manana'],
        payload: 'rc:diag-ping',
        intensidad: IntensidadNotif.intenso,
      );
      _aviso('Mandé la prueba. Bájala desde la barra de notificaciones y toca '
          'un botón. Vuelve aquí para ver el resultado.');
    } catch (e) {
      _aviso('No pude mostrar la prueba: $e');
    } finally {
      if (mounted) setState(() => _trabajando = false);
    }
  }

  Future<void> _limpiarLog() async {
    await ref.read(confirmacionServiceProvider).limpiarLog();
    await _refrescar();
  }

  void _aviso(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(t)));
  }

  @override
  Widget build(BuildContext context) {
    final batAsync = ref.watch(exencionBateriaProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Diagnóstico de notificaciones'),
        actions: [
          IconButton(
            tooltip: 'Refrescar',
            icon: const Icon(Icons.refresh),
            onPressed: _refrescar,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          const _Bloque(
            texto:
                'Los Honor/MagicOS son agresivos con las apps en segundo plano. '
                'Cada fila te dice si un eslabón está concedido y cómo darlo. '
                'Al final, una prueba real con botones.',
          ),
          const SizedBox(height: 12),
          const _Titulo('Permisos del sistema'),
          _Estado(
            label: 'Notificaciones (POST_NOTIFICATIONS)',
            ok: _permisoNotifs,
            cta: 'Pedir permiso',
            onCta: _pedirPermiso,
            ayuda:
                'Sin esto, ninguna notificación aparece. En Android 13+ se pide '
                'una sola vez; si lo niegas, abre Ajustes > Apps > Matix > '
                'Notificaciones.',
          ),
          _Estado(
            label: 'Alarmas exactas',
            ok: null, // el sistema no expone el getter; solo CTA
            cta: 'Abrir ajuste',
            onCta: _pedirExactas,
            ayuda:
                'Necesario para que las locales programadas disparen al minuto. '
                'Sin esto se atrasan o no llegan.',
          ),
          batAsync.when(
            data: (exenta) => _Estado(
              label: 'Batería sin restricciones',
              ok: exenta,
              cta: exenta ? null : 'Conceder',
              onCta: exenta ? null : _pedirBateria,
              ayuda:
                  'CRÍTICO en MagicOS. Sin la exención el SO mata la app y los '
                  'pushes/botones se vuelven poco confiables.',
            ),
            loading: () => const _Estado(
                label: 'Batería sin restricciones',
                ok: null,
                ayuda: 'Comprobando…'),
            error: (_, _) => const _Estado(
                label: 'Batería sin restricciones',
                ok: false,
                ayuda: 'No pude comprobar el estado.'),
          ),
          _Estado(
            label: 'Pantalla completa (full-screen intent)',
            ok: _puedeFullScreen,
            cta: _puedeFullScreen == true ? null : 'Conceder',
            onCta: _puedeFullScreen == true ? null : _pedirFullScreen,
            ayuda:
                'Habilita el modo "máximo": el aviso aparece sobre lo que uses, '
                'como una alarma. En Android 14+ requiere permiso explícito.',
          ),
          const SizedBox(height: 8),
          const _Bloque(
            texto:
                'Honor/MagicOS, además: Ajustes > Batería > Lanzamiento de apps '
                '→ Matix en MANUAL (Autoarranque + Ejecución en segundo plano). '
                'Sin esto el SO bloquea la entrega. No hay API para conceder '
                'esto desde la app — lo hace el usuario una sola vez.',
          ),
          const SizedBox(height: 16),
          const _Titulo('Prueba con botones (cadena completa)'),
          const _Bloque(
            texto:
                'Manda una notificación REAL con tres botones. Al tocar uno, '
                'el handler de background hace POST al cerebro y deja '
                'evidencia abajo (status + cuándo).',
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _trabajando ? null : _enviarPruebaConBotones,
              icon: const Icon(Icons.send_rounded),
              label: const Text('Enviar prueba con botones AHORA'),
              style: FilledButton.styleFrom(
                backgroundColor: MatixColors.accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const _Titulo('Historial de intentos'),
              const Spacer(),
              TextButton(
                onPressed: _log.isEmpty ? null : _limpiarLog,
                child: const Text('Limpiar'),
              ),
            ],
          ),
          if (_log.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Sin intentos registrados. Toca un botón de la prueba o de '
                'una noti real para empezar a ver evidencia.',
                style: TextStyle(fontSize: 12.5, color: MatixColors.muted),
              ),
            )
          else
            for (final e in _log.take(15)) _FilaLog(entrada: e),
        ],
      ),
    );
  }
}

class _Titulo extends StatelessWidget {
  const _Titulo(this.texto);
  final String texto;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
        child: Text(
          texto.toUpperCase(),
          style: const TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.0,
            color: MatixColors.muted,
          ),
        ),
      );
}

class _Bloque extends StatelessWidget {
  const _Bloque({required this.texto});
  final String texto;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: MatixColors.card,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          texto,
          style: const TextStyle(
            fontSize: 12.5, color: MatixColors.text, height: 1.4,
          ),
        ),
      );
}

class _Estado extends StatelessWidget {
  const _Estado({
    required this.label,
    required this.ok,
    this.cta,
    this.onCta,
    this.ayuda,
  });
  final String label;
  final bool? ok; // true=OK, false=falta, null=desconocido
  final String? cta;
  final VoidCallback? onCta;
  final String? ayuda;

  @override
  Widget build(BuildContext context) {
    final color = ok == true
        ? MatixColors.green
        : ok == false
            ? MatixColors.amber
            : MatixColors.muted;
    final icon = ok == true
        ? Icons.check_circle
        : ok == false
            ? Icons.error_outline
            : Icons.help_outline;
    final etiqueta = ok == true
        ? 'concedido'
        : ok == false
            ? 'pendiente'
            : '—';
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: MatixColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: MatixColors.text,
                  ),
                ),
              ),
              Text(
                etiqueta,
                style: TextStyle(
                  fontSize: 11.5, fontWeight: FontWeight.w700, color: color,
                ),
              ),
            ],
          ),
          if (ayuda != null) ...[
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 26),
              child: Text(
                ayuda!,
                style: const TextStyle(
                  fontSize: 11.5, color: MatixColors.muted, height: 1.4,
                ),
              ),
            ),
          ],
          if (cta != null && onCta != null) ...[
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(left: 18),
              child: TextButton(onPressed: onCta, child: Text(cta!)),
            ),
          ],
        ],
      ),
    );
  }
}

class _FilaLog extends StatelessWidget {
  const _FilaLog({required this.entrada});
  final EntradaConfirmacion entrada;

  @override
  Widget build(BuildContext context) {
    final hora = DateFormat('HH:mm:ss').format(entrada.cuando.toLocal());
    final fecha = DateFormat('d MMM', 'es').format(entrada.cuando.toLocal());
    final tipo = switch (entrada.tipo) {
      TipoConfirmacion.tarea => 'tarea',
      TipoConfirmacion.asistencia => 'evento',
      TipoConfirmacion.diagnostico => 'diag',
    };
    final color = entrada.ok ? MatixColors.green : MatixColors.red;
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: MatixColors.card,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(
            entrada.ok ? Icons.check_circle_outline : Icons.error_outline,
            color: color,
            size: 16,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$tipo · ${entrada.accion}',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: MatixColors.text,
                  ),
                ),
                Text(
                  [
                    '$fecha $hora',
                    if (entrada.statusCode != null)
                      'HTTP ${entrada.statusCode}',
                    if (entrada.error != null) entrada.error!,
                  ].join(' · '),
                  style: const TextStyle(
                    fontSize: 11, color: MatixColors.muted,
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
