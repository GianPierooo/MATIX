import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/matix_client.dart';
import '../config.dart';
import '../core/notificaciones_service.dart';
import '../core/providers.dart';
import '../features/autoupdate/data/update_service.dart';
import '../features/autoupdate/presentation/update_dialog.dart';
import '../features/autoupdate/providers/update_providers.dart';
import '../features/briefing/data/briefing_prefs.dart';
import '../features/briefing/presentation/briefing_screen.dart';
import '../features/briefing/providers/briefing_providers.dart';
import '../features/cierre/data/cierre_prefs.dart';
import '../features/cierre/presentation/cierre_dia_screen.dart';
import '../features/cierre/presentation/cierre_screen.dart';
import '../features/cierre/providers/cierre_providers.dart';
import '../features/google/presentation/conexion_google_tile.dart';
import '../features/nudges/providers/nudges_providers.dart';
import '../features/papelera/presentation/papelera_screen.dart';
import '../features/planificador/application/plan_dia_controller.dart';
import '../features/planificador/domain/disponibilidad.dart';
import '../features/push/data/push_repository.dart';
import '../features/repaso/presentation/repaso_semanal_screen.dart';
import '../features/repaso/providers/repaso_providers.dart';
import '../theme/matix_colors.dart';

/// Pantalla de Ajustes — informativa en Capa 1.
///
/// Los valores de conexión (URL del cerebro, API key, entorno) se
/// inyectan vía `--dart-define` en compile-time, así que aquí solo se
/// muestran como referencia, no se editan. Las acciones disponibles
/// son operativas: probar el ping al cerebro, pedir permiso de
/// notificaciones, ver/cancelar las programadas.
class AjustesScreen extends ConsumerStatefulWidget {
  const AjustesScreen({super.key});

  @override
  ConsumerState<AjustesScreen> createState() => _AjustesScreenState();
}

class _AjustesScreenState extends ConsumerState<AjustesScreen> {
  String? _pingResultado;
  bool _pingando = false;

  int? _notifsPendientes;
  bool _consultandoNotifs = false;

  bool? _permisoNotifs;
  String? _zonaNotifs;
  bool _probando = false;

  @override
  void initState() {
    super.initState();
    _cargarZonaNotifs();
  }

  Future<void> _cargarZonaNotifs() async {
    final svc = ref.read(notificacionesServiceProvider);
    // `pendientes()` fuerza la inicialización del servicio → la zona queda
    // resuelta y la mostramos en el diagnóstico.
    await svc.pendientes();
    if (mounted) setState(() => _zonaNotifs = svc.zonaHoraria);
  }

  Future<void> _ping() async {
    setState(() {
      _pingando = true;
      _pingResultado = null;
    });
    try {
      final info = await ref.read(matixClientProvider).health();
      _pingResultado = '${info["status"]} · env=${info["env"]}';
    } on MatixApiException catch (e) {
      _pingResultado = 'Error ${e.statusCode}: ${e.message}';
    } catch (e) {
      _pingResultado = 'Error: $e';
    } finally {
      if (mounted) setState(() => _pingando = false);
    }
  }

  Future<void> _contarNotifs() async {
    setState(() => _consultandoNotifs = true);
    try {
      final lista = await ref
          .read(notificacionesServiceProvider)
          .pendientes();
      _notifsPendientes = lista.length;
    } catch (e) {
      _notifsPendientes = -1;
    } finally {
      if (mounted) setState(() => _consultandoNotifs = false);
    }
  }

  Future<void> _cancelarTodas() async {
    await ref.read(notificacionesServiceProvider).cancelarTodo();
    await _contarNotifs();
  }

  Future<void> _pedirPermiso() async {
    final ok = await ref.read(notificacionesServiceProvider).pedirPermisos();
    if (!mounted) return;
    setState(() => _permisoNotifs = ok);
  }

  Future<void> _pedirExactas() async {
    await ref
        .read(notificacionesServiceProvider)
        .pedirPermisoAlarmasExactas();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Si se abrió la pantalla del sistema, activa "Alarmas y '
          'recordatorios" para Matix.',
        ),
      ),
    );
  }

  /// Aviso INMEDIATO. Si aparece → canal + permiso OK; el problema (si lo
  /// hay) está en el agendado, no en mostrar.
  Future<void> _probarAhora() async {
    final svc = ref.read(notificacionesServiceProvider);
    await svc.pedirPermisos();
    await svc.mostrarAhora(
      id: 990001,
      titulo: 'Prueba inmediata',
      cuerpo: 'Si ves esto, el canal y el permiso están bien.',
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Mandé una notificación AHORA. ¿La ves en la barra?'),
      ),
    );
  }

  /// Aviso PROGRAMADO a 1 minuto, con alarma exacta. Si la inmediata sí
  /// llega pero esta no → es alarma exacta / batería del OEM (Huawei).
  Future<void> _probarEn1Min() async {
    setState(() => _probando = true);
    final svc = ref.read(notificacionesServiceProvider);
    try {
      await svc.pedirPermisos();
      await svc.pedirPermisoAlarmasExactas();
      final cuando = DateTime.now().add(const Duration(minutes: 1));
      final ok = await svc.programar(
        id: 990002,
        titulo: 'Prueba programada (1 min)',
        cuerpo: 'Si ves esto, las alarmas programadas funcionan.',
        cuando: cuando,
        exacto: true,
      );
      final n = await svc.contarPendientes();
      if (!mounted) return;
      setState(() => _notifsPendientes = n);
      final hhmm =
          '${cuando.hour.toString().padLeft(2, '0')}:${cuando.minute.toString().padLeft(2, '0')}';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok
              ? 'Programada para las $hhmm (1 min). Pendientes: $n. Bloquea '
                  'la pantalla y espera; no cierres la app desde recientes.'
              : 'No se pudo programar (revisa el permiso de alarmas '
                  'exactas).'),
        ),
      );
    } finally {
      if (mounted) setState(() => _probando = false);
    }
  }

  /// Pide al cerebro un push REAL vía FCM. A diferencia de las locales,
  /// este debería llegar aunque el OEM (Honor/Huawei) mate la app.
  Future<void> _enviarPushPrueba() async {
    setState(() => _probando = true);
    String msg;
    try {
      final res = await ref.read(pushRepositoryProvider).probar();
      final enviados = (res['enviados'] as num?)?.toInt() ?? 0;
      final fallidos = (res['fallidos'] as num?)?.toInt() ?? 0;
      msg = enviados > 0
          ? 'Push enviado ($enviados ok). Bloquea la pantalla y espera unos '
              'segundos.'
          : 'No se envió ($fallidos fallidos). Revisa el service account en '
              'Railway.';
    } on MatixApiException catch (e) {
      msg = 'Error ${e.statusCode}: ${e.message}';
    } catch (e) {
      msg = 'Error: $e';
    }
    if (!mounted) return;
    setState(() => _probando = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(0, 8, 0, 24),
        children: [
          const _Seccion('Conexión'),
          _Fila(
            label: 'URL del cerebro',
            value: MatixConfig.apiUrl,
            mono: true,
          ),
          _Fila(label: 'Entorno', value: MatixConfig.env),
          _Fila(
            label: 'API key',
            value: MatixConfig.hasApiKey
                ? '••• configurada'
                : 'sin configurar',
            valueColor: MatixConfig.hasApiKey
                ? MatixColors.green
                : MatixColors.red,
          ),
          _Accion(
            label: _pingando ? 'Pinging…' : 'Reintentar ping',
            icon: Icons.wifi_find,
            onTap: _pingando ? null : _ping,
            subtitle: _pingResultado,
          ),

          const _Seccion('Hub'),
          _Accion(
            label: 'Papelera',
            icon: Icons.delete_outline,
            subtitle:
                'Lo que borres aparece acá. Restaurar o vaciar.',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const PapeleraScreen()),
            ),
          ),

          // Capa 4 dormida: la conexión con Google no se muestra. El
          // tile sigue vivo tras el flag para poder revivirla.
          if (MatixConfig.googleVisible) ...[
            const _Seccion('Conexiones'),
            const ConexionGoogleTile(),
          ],

          const _Seccion('Versión'),
          _BuscarActualizacionTile(),

          const _Seccion('Notificaciones'),
          _Accion(
            label: 'Pedir permiso (Android 13+)',
            icon: Icons.notifications_active_outlined,
            onTap: _pedirPermiso,
            subtitle: _permisoNotifs == null
                ? null
                : (_permisoNotifs! ? 'Concedido' : 'Denegado'),
            subtitleColor: _permisoNotifs == null
                ? null
                : (_permisoNotifs! ? MatixColors.green : MatixColors.red),
          ),
          _Accion(
            label: 'Permitir alarmas exactas (Android 12+)',
            icon: Icons.alarm_on_outlined,
            onTap: _pedirExactas,
            subtitle: 'Necesario para que las programadas disparen al minuto.',
          ),
          _Accion(
            label: _consultandoNotifs
                ? 'Consultando…'
                : 'Ver pendientes programadas',
            icon: Icons.list_alt,
            onTap: _consultandoNotifs ? null : _contarNotifs,
            subtitle: _notifsPendientes == null
                ? (_zonaNotifs == null ? null : 'Zona horaria: $_zonaNotifs')
                : '$_notifsPendientes programada(s) · zona: '
                    '${_zonaNotifs ?? "?"}',
          ),
          _Accion(
            label: 'Cancelar todas las programadas',
            icon: Icons.notifications_off_outlined,
            onTap: _cancelarTodas,
            destructive: true,
          ),

          const _Seccion('Probar notificaciones (diagnóstico)'),
          _Accion(
            label: 'Probar notificación AHORA',
            icon: Icons.notifications_paused_outlined,
            onTap: _probarAhora,
            subtitle: 'Aviso inmediato. Si aparece, el canal y el permiso '
                'están bien.',
          ),
          _Accion(
            label: _probando ? 'Programando…' : 'Probar EN 1 MINUTO',
            icon: Icons.timer_outlined,
            onTap: _probando ? null : _probarEn1Min,
            subtitle: 'Programada con alarma exacta. Si la inmediata llega '
                'pero esta no, es la batería del OEM (Huawei/Honor).',
          ),
          _Accion(
            label: _probando ? 'Enviando…' : 'Enviar push de prueba (FCM)',
            icon: Icons.cloud_outlined,
            onTap: _probando ? null : _enviarPushPrueba,
            subtitle: 'Push REAL desde el cerebro. Este SÍ debería llegar '
                'aunque el OEM mate la app.',
          ),

          const _Seccion('Nudges de urgencia'),
          const _NudgesTile(),

          const _Seccion('Disponibilidad'),
          const _DisponibilidadTile(),

          const _Seccion('Rituales'),
          _Accion(
            label: 'Hacer el cierre de hoy',
            icon: Icons.nightlight_outlined,
            subtitle: '3 cosas que sí hiciste + descarga mental.',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const CierreDiaScreen()),
            ),
          ),

          const _Seccion('Briefing matutino'),
          const _BriefingMatutinoTile(),
          _Accion(
            label: 'Ver briefing de hoy',
            icon: Icons.wb_sunny_outlined,
            subtitle: 'Resumen del día: eventos, tareas, alertas.',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const BriefingScreen()),
            ),
          ),

          const _Seccion('Cierre del día'),
          const _CierreDelDiaTile(),
          _Accion(
            label: 'Ver cierre de hoy',
            icon: Icons.nightlight_outlined,
            subtitle: 'Repaso: qué hiciste, qué queda, qué viene.',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const CierreScreen()),
            ),
          ),

          const _Seccion('Repaso semanal'),
          const _RepasoSemanalTile(),
          _Accion(
            label: 'Ver repaso de la semana',
            icon: Icons.calendar_view_week_outlined,
            subtitle: 'Balance de la semana con Matix: qué se hizo, qué '
                'quedó, qué priorizar.',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const RepasoSemanalScreen()),
            ),
          ),

          const _Seccion('Información'),
          const _Fila(label: 'Versión', value: '1.0.0+1'),
          const _Fila(label: 'Plataforma', value: 'Android'),
        ],
      ),
    );
  }
}

class _Seccion extends StatelessWidget {
  const _Seccion(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.0,
          color: MatixColors.muted,
        ),
      ),
    );
  }
}

class _Fila extends StatelessWidget {
  const _Fila({
    required this.label,
    required this.value,
    this.valueColor,
    this.mono = false,
  });
  final String label;
  final String value;
  final Color? valueColor;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: MatixColors.card,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                color: MatixColors.muted,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              color: valueColor ?? MatixColors.text,
              fontWeight: FontWeight.w600,
              fontFamily: mono ? 'JetBrainsMono' : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _Accion extends StatelessWidget {
  const _Accion({
    required this.label,
    required this.icon,
    required this.onTap,
    this.subtitle,
    this.subtitleColor,
    this.destructive = false,
  });
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final String? subtitle;
  final Color? subtitleColor;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? MatixColors.red : MatixColors.accent;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      decoration: BoxDecoration(
        color: MatixColors.card,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Row(
              children: [
                Icon(icon, color: color, size: 22),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: onTap == null ? MatixColors.muted : color,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          subtitle!,
                          style: TextStyle(
                            fontSize: 12,
                            color: subtitleColor ?? MatixColors.muted,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: MatixColors.muted,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Briefing matutino (Capa 8 reducida · Paso 1) ───────────────────

class _BriefingMatutinoTile extends ConsumerWidget {
  const _BriefingMatutinoTile();

  Future<void> _elegirHora(
    BuildContext context,
    WidgetRef ref,
    BriefingConfig actual,
  ) async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: actual.hora, minute: actual.minuto),
      helpText: 'Hora del briefing',
    );
    if (t == null) return;
    await ref
        .read(briefingConfigProvider.notifier)
        .cambiarHora(t.hour, t.minute);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cfg = ref.watch(briefingConfigProvider);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      padding: const EdgeInsets.fromLTRB(14, 4, 8, 4),
      decoration: BoxDecoration(
        color: MatixColors.card,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(
                Icons.wb_twilight,
                color: MatixColors.accent,
                size: 22,
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Activar briefing matutino',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: MatixColors.text,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Te aviso con el resumen del día.',
                      style: TextStyle(
                        fontSize: 12,
                        color: MatixColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: cfg.activo,
                onChanged: (v) =>
                    ref.read(briefingConfigProvider.notifier).activar(v),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(36, 4, 8, 8),
            child: Row(
              children: [
                const Icon(
                  Icons.access_time,
                  color: MatixColors.muted,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Text(
                  'Hora: ${cfg.horaFormateada}',
                  style: const TextStyle(
                    fontSize: 13,
                    color: MatixColors.text,
                  ),
                ),
                const SizedBox(width: 12),
                TextButton(
                  onPressed: () => _elegirHora(context, ref, cfg),
                  style: TextButton.styleFrom(
                    foregroundColor: MatixColors.accent,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    minimumSize: const Size(0, 32),
                  ),
                  child: const Text('Cambiar'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Ajuste del cierre del día (Capa 8 · Paso 2). Espejo del tile del
/// briefing pero apuntando al `cierreConfigProvider`.
class _CierreDelDiaTile extends ConsumerWidget {
  const _CierreDelDiaTile();

  Future<void> _elegirHora(
    BuildContext context,
    WidgetRef ref,
    CierreConfig actual,
  ) async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: actual.hora, minute: actual.minuto),
      helpText: 'Hora del cierre',
    );
    if (t == null) return;
    await ref
        .read(cierreConfigProvider.notifier)
        .cambiarHora(t.hour, t.minute);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cfg = ref.watch(cierreConfigProvider);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      padding: const EdgeInsets.fromLTRB(14, 4, 8, 4),
      decoration: BoxDecoration(
        color: MatixColors.card,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(
                Icons.nightlight_round,
                color: MatixColors.accent,
                size: 22,
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Activar cierre del día',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: MatixColors.text,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Repaso amable antes de dormir.',
                      style: TextStyle(
                        fontSize: 12,
                        color: MatixColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: cfg.activo,
                onChanged: (v) =>
                    ref.read(cierreConfigProvider.notifier).activar(v),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(36, 4, 8, 8),
            child: Row(
              children: [
                const Icon(
                  Icons.access_time,
                  color: MatixColors.muted,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Text(
                  'Hora: ${cfg.horaFormateada}',
                  style: const TextStyle(
                    fontSize: 13,
                    color: MatixColors.text,
                  ),
                ),
                const SizedBox(width: 12),
                TextButton(
                  onPressed: () => _elegirHora(context, ref, cfg),
                  style: TextButton.styleFrom(
                    foregroundColor: MatixColors.accent,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    minimumSize: const Size(0, 32),
                  ),
                  child: const Text('Cambiar'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Ajuste del repaso semanal (4º ritual, por push). Como briefing/cierre
/// pero SEMANAL: además de on/off y hora, deja elegir el DÍA. Default ON,
/// domingo 20:00 (hora de Lima). El push lo dispara el scheduler del
/// cerebro y abre la pantalla de repaso.
class _RepasoSemanalTile extends ConsumerWidget {
  const _RepasoSemanalTile();

  Future<void> _elegirHora(
    BuildContext context,
    WidgetRef ref,
    RepasoConfig actual,
  ) async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: actual.hora, minute: actual.minuto),
      helpText: 'Hora del repaso',
    );
    if (t == null) return;
    await ref.read(repasoConfigProvider.notifier).cambiarHora(t.hour, t.minute);
  }

  Future<void> _elegirDia(
    BuildContext context,
    WidgetRef ref,
    RepasoConfig actual,
  ) async {
    const dias = [
      (1, 'Lunes'),
      (2, 'Martes'),
      (3, 'Miércoles'),
      (4, 'Jueves'),
      (5, 'Viernes'),
      (6, 'Sábado'),
      (7, 'Domingo'),
    ];
    final elegido = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: MatixColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            for (final (iso, nombre) in dias)
              ListTile(
                title: Text(nombre),
                trailing: actual.diaSemana == iso
                    ? const Icon(Icons.check, color: MatixColors.accent)
                    : null,
                onTap: () => Navigator.pop(ctx, iso),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (elegido == null) return;
    await ref.read(repasoConfigProvider.notifier).cambiarDia(elegido);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cfg = ref.watch(repasoConfigProvider);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      padding: const EdgeInsets.fromLTRB(14, 4, 8, 4),
      decoration: BoxDecoration(
        color: MatixColors.card,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(
                Icons.calendar_view_week,
                color: MatixColors.accent,
                size: 22,
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Activar repaso semanal',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: MatixColors.text,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Te aviso una vez por semana para mirar atrás y '
                      'planear la próxima.',
                      style: TextStyle(
                        fontSize: 12,
                        color: MatixColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: cfg.activo,
                onChanged: (v) =>
                    ref.read(repasoConfigProvider.notifier).activar(v),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(36, 4, 8, 8),
            child: Row(
              children: [
                const Icon(
                  Icons.event_outlined,
                  color: MatixColors.muted,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${cfg.diaNombre} · ${cfg.horaFormateada}',
                    style: const TextStyle(
                      fontSize: 13,
                      color: MatixColors.text,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => _elegirDia(context, ref, cfg),
                  style: TextButton.styleFrom(
                    foregroundColor: MatixColors.accent,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 32),
                  ),
                  child: const Text('Día'),
                ),
                TextButton(
                  onPressed: () => _elegirHora(context, ref, cfg),
                  style: TextButton.styleFrom(
                    foregroundColor: MatixColors.accent,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 32),
                  ),
                  child: const Text('Hora'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Auto-actualización (Capa Infra · post-Firebase) ────────────────

/// Card diagnóstica de versión: muestra build instalado, build
/// disponible (cuando se pudo consultar), y estado claro con el
/// detalle del error si lo hubo.
///
/// Diseñado para no ser caja negra: si algo va mal, querés saber
/// si fue red, auth, parseo, o build local sin inyectar. Muestra
/// las tres líneas — instalado · disponible · estado — siempre
/// que sea posible, en vez de un mensaje único ambiguo.
class _BuscarActualizacionTile extends ConsumerWidget {
  const _BuscarActualizacionTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final estado = ref.watch(updateCheckProvider);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: MatixColors.card,
        borderRadius: BorderRadius.circular(12),
      ),
      child: estado.when(
        loading: () => const _DiagnosticoLoading(),
        error: (e, _) => _DiagnosticoFila(
          buildLocal: MatixConfig.buildNumber,
          buildRemoto: null,
          estadoLabel: 'Provider falló',
          estadoColor: MatixColors.red,
          detalle: e.toString(),
          onReintentar: () => ref.invalidate(updateCheckProvider),
        ),
        data: (result) {
          if (result is HayActualizacion) {
            return _DiagnosticoFila(
              buildLocal: result.buildLocal,
              buildRemoto: result.info.buildNumber,
              estadoLabel:
                  'Hay actualización · build ${result.info.buildNumber} (${result.info.version})',
              estadoColor: MatixColors.accent,
              detalle: result.info.notas,
              ctaLabel: 'Descargar e instalar',
              ctaIcon: Icons.system_update_alt,
              onCta: () => mostrarUpdateDialog(
                context,
                info: result.info,
                buildLocal: result.buildLocal,
              ),
              onReintentar: () => ref.invalidate(updateCheckProvider),
            );
          }
          if (result is Actualizado) {
            return _DiagnosticoFila(
              buildLocal: result.buildLocal,
              buildRemoto: result.buildRemoto,
              estadoLabel: 'Al día',
              estadoColor: MatixColors.green,
              detalle: result.buildRemoto == null
                  ? 'El servidor todavía no publicó ninguna versión.'
                  : null,
              onReintentar: () => ref.invalidate(updateCheckProvider),
            );
          }
          if (result is ChequeoFallido) {
            return _DiagnosticoFila(
              buildLocal: result.buildLocal,
              buildRemoto: null,
              estadoLabel: _labelDeRazon(result.razon),
              estadoColor: _colorDeRazon(result.razon),
              detalle: result.detalle,
              onReintentar: () => ref.invalidate(updateCheckProvider),
            );
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }

  String _labelDeRazon(RazonFallo r) => switch (r) {
        RazonFallo.sinRed => 'Sin conexión al cerebro',
        RazonFallo.authInvalida => 'Error de autenticación',
        RazonFallo.errorServidor => 'El cerebro devolvió error',
        RazonFallo.parseo => 'Respuesta inesperada del cerebro',
        RazonFallo.buildLocalAusente => 'Build local no inyectado',
        RazonFallo.otro => 'Falló el chequeo',
      };

  Color _colorDeRazon(RazonFallo r) => switch (r) {
        RazonFallo.sinRed => MatixColors.amber,
        RazonFallo.authInvalida => MatixColors.red,
        RazonFallo.errorServidor => MatixColors.red,
        RazonFallo.parseo => MatixColors.red,
        RazonFallo.buildLocalAusente => MatixColors.amber,
        RazonFallo.otro => MatixColors.amber,
      };
}

class _DiagnosticoLoading extends StatelessWidget {
  const _DiagnosticoLoading();
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: MatixColors.accent,
          ),
        ),
        const SizedBox(width: 12),
        Text(
          'Chequeando versión…',
          style: TextStyle(
            fontSize: 14,
            color: MatixColors.text,
          ),
        ),
      ],
    );
  }
}

class _DiagnosticoFila extends StatelessWidget {
  const _DiagnosticoFila({
    required this.buildLocal,
    required this.buildRemoto,
    required this.estadoLabel,
    required this.estadoColor,
    required this.onReintentar,
    this.detalle,
    this.ctaLabel,
    this.ctaIcon,
    this.onCta,
  });

  final int buildLocal;
  final int? buildRemoto;
  final String estadoLabel;
  final Color estadoColor;
  final String? detalle;
  final String? ctaLabel;
  final IconData? ctaIcon;
  final VoidCallback? onCta;
  final VoidCallback onReintentar;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.system_update_alt,
              color: MatixColors.accent,
              size: 20,
            ),
            const SizedBox(width: 10),
            Text(
              'Versión',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: MatixColors.text,
              ),
            ),
            const Spacer(),
            IconButton(
              tooltip: 'Reintentar',
              icon: const Icon(Icons.refresh, size: 18),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(
                minWidth: 32,
                minHeight: 32,
              ),
              onPressed: onReintentar,
            ),
          ],
        ),
        const SizedBox(height: 6),
        _linea(
          'Instalado',
          buildLocal == 0
              ? 'build 0 (no inyectado — build local)'
              : 'build $buildLocal',
          color: buildLocal == 0 ? MatixColors.muted : MatixColors.text,
        ),
        const SizedBox(height: 2),
        _linea(
          'Disponible',
          buildRemoto == null ? '—' : 'build $buildRemoto',
          color: buildRemoto == null ? MatixColors.muted : MatixColors.text,
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: estadoColor.withValues(alpha: 0.12),
            border: Border.all(
              color: estadoColor.withValues(alpha: 0.4),
            ),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            estadoLabel,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: estadoColor,
            ),
          ),
        ),
        if (detalle != null && detalle!.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            detalle!,
            style: const TextStyle(
              fontSize: 11.5,
              color: MatixColors.muted,
              height: 1.35,
            ),
          ),
        ],
        if (ctaLabel != null && onCta != null) ...[
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onCta,
              icon: Icon(ctaIcon ?? Icons.download_rounded, size: 18),
              label: Text(ctaLabel!),
              style: FilledButton.styleFrom(
                backgroundColor: MatixColors.accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _linea(String etiqueta, String valor, {required Color color}) {
    return Row(
      children: [
        SizedBox(
          width: 80,
          child: Text(
            etiqueta,
            style: TextStyle(fontSize: 12, color: MatixColors.muted),
          ),
        ),
        Text(
          valor,
          style: TextStyle(
            fontSize: 12.5,
            color: color,
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
  }
}

/// Disponibilidad POR DÍA (Fase 3): cuándo estás libre cada día de la
/// semana. Matix solo planifica en estos huecos, respetando tus eventos
/// y las horas de silencio. Lo consume el planificador del día hoy y el
/// de sesiones (Fase 4) mañana.
class _DisponibilidadTile extends ConsumerWidget {
  const _DisponibilidadTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final disp = ref.watch(disponibilidadProvider);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      decoration: BoxDecoration(
        color: MatixColors.card,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Disponibilidad por día',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: MatixColors.text,
            ),
          ),
          const SizedBox(height: 2),
          const Text(
            'Cuándo estás libre. Matix solo planifica en estos huecos: '
            'respeta tus eventos y las horas de silencio.',
            style: TextStyle(fontSize: 12, color: MatixColors.muted),
          ),
          const SizedBox(height: 6),
          for (var d = 1; d <= 7; d++)
            _FilaDisponibilidad(weekday: d, dia: disp.diaDe(d)),
        ],
      ),
    );
  }
}

class _FilaDisponibilidad extends ConsumerWidget {
  const _FilaDisponibilidad({required this.weekday, required this.dia});
  final int weekday;
  final DisponibilidadDia dia;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctrl = ref.read(disponibilidadProvider.notifier);
    String hh(int h) => '${h.toString().padLeft(2, '0')}:00';

    Future<void> elegir(bool inicio) async {
      final picked = await showTimePicker(
        context: context,
        initialTime: TimeOfDay(hour: inicio ? dia.inicio : dia.fin, minute: 0),
        helpText: inicio ? 'Libre desde' : 'Libre hasta',
      );
      if (picked == null) return;
      await ctrl.cambiarDia(
        weekday,
        inicio ? dia.copyWith(inicio: picked.hour) : dia.copyWith(fin: picked.hour),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 34,
            child: Text(
              nombresDiaCorto[weekday - 1],
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: MatixColors.text,
              ),
            ),
          ),
          Switch(
            value: dia.activo,
            onChanged: (v) => ctrl.cambiarDia(weekday, dia.copyWith(activo: v)),
          ),
          const SizedBox(width: 4),
          if (dia.activo)
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => elegir(true),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        visualDensity: VisualDensity.compact,
                      ),
                      child: Text(hh(dia.inicio)),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    child: Text('–', style: TextStyle(color: MatixColors.muted)),
                  ),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => elegir(false),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        visualDensity: VisualDensity.compact,
                      ),
                      child: Text(hh(dia.fin)),
                    ),
                  ),
                ],
              ),
            )
          else
            const Expanded(
              child: Text('No disponible',
                  style: TextStyle(fontSize: 12.5, color: MatixColors.muted)),
            ),
        ],
      ),
    );
  }
}

/// Ajustes de los nudges intensos de tareas (Push Capa 3b): interruptor
/// maestro + horas de silencio. Los manda el cerebro por push; son
/// intensos por defecto (sin selector Suave/Normal/Fuerte). El apagado
/// POR TAREA vive en el detalle de cada tarea, y la disponibilidad por
/// día en su propia sección.
class _NudgesTile extends ConsumerWidget {
  const _NudgesTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cfg = ref.watch(nudgesConfigProvider);
    final ctrl = ref.read(nudgesConfigProvider.notifier);

    String dosDigitos(int h) => '${h.toString().padLeft(2, '0')}:00';

    Future<void> elegirHora(bool inicio) async {
      final actual = inicio ? cfg.silencioInicio : cfg.silencioFin;
      final picked = await showTimePicker(
        context: context,
        initialTime: TimeOfDay(hour: actual, minute: 0),
        helpText: inicio ? 'Silencio desde' : 'Silencio hasta',
      );
      if (picked == null) return;
      if (inicio) {
        await ctrl.cambiarSilencio(picked.hour, cfg.silencioFin);
      } else {
        await ctrl.cambiarSilencio(cfg.silencioInicio, picked.hour);
      }
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
      decoration: BoxDecoration(
        color: MatixColors.card,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Avisos de urgencia',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: MatixColors.text,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Te empujo más seguido al acercarse el plazo de tus '
                      'tareas. Apágalo si no quieres ninguno.',
                      style: TextStyle(fontSize: 12, color: MatixColors.muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Switch(
                value: cfg.activo,
                onChanged: ctrl.cambiarActivo,
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Text(
            'Horas de silencio',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: MatixColors.text,
            ),
          ),
          const SizedBox(height: 2),
          const Text(
            'Acá no te aviso nunca. Un nudge que caiga adentro se '
            'corre al fin del silencio.',
            style: TextStyle(fontSize: 12, color: MatixColors.muted),
          ),
          const SizedBox(height: 10),
          Opacity(
            opacity: cfg.activo ? 1 : 0.4,
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: cfg.activo ? () => elegirHora(true) : null,
                    child: Text('Desde ${dosDigitos(cfg.silencioInicio)}'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed: cfg.activo ? () => elegirHora(false) : null,
                    child: Text('Hasta ${dosDigitos(cfg.silencioFin)}'),
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
