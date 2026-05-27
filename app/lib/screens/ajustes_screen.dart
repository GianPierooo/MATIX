import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/matix_client.dart';
import '../config.dart';
import '../core/notificaciones_service.dart';
import '../core/providers.dart';
import '../features/papelera/presentation/papelera_screen.dart';
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

/// Id estable para la notificación diaria del cierre del día.
/// Estable entre runs para poder cancelarla sin guardar nada.
const _kNotifIdCierreDiario = 1001;
const _kHoraCierre = 21;
const _kMinutoCierre = 30;

class _AjustesScreenState extends ConsumerState<AjustesScreen> {
  String? _pingResultado;
  bool _pingando = false;

  int? _notifsPendientes;
  bool _consultandoNotifs = false;

  bool? _permisoNotifs;

  bool _cierreDiarioActivo = false;
  bool _toggleEnCurso = false;

  @override
  void initState() {
    super.initState();
    _cargarEstadoCierreDiario();
  }

  Future<void> _cargarEstadoCierreDiario() async {
    final pend = await ref
        .read(notificacionesServiceProvider)
        .pendientes();
    if (mounted) {
      setState(() =>
          _cierreDiarioActivo = pend.contains(_kNotifIdCierreDiario));
    }
  }

  Future<void> _toggleCierreDiario(bool v) async {
    setState(() => _toggleEnCurso = true);
    final svc = ref.read(notificacionesServiceProvider);
    try {
      if (v) {
        await svc.pedirPermisos();
        await svc.programarDiaria(
          id: _kNotifIdCierreDiario,
          titulo: 'Cierre del día',
          cuerpo: '3 cosas que sí hiciste hoy.',
          hora: _kHoraCierre,
          minuto: _kMinutoCierre,
        );
      } else {
        await svc.cancelar(_kNotifIdCierreDiario);
      }
      if (mounted) setState(() => _cierreDiarioActivo = v);
    } finally {
      if (mounted) setState(() => _toggleEnCurso = false);
    }
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
            label: _consultandoNotifs
                ? 'Consultando…'
                : 'Ver pendientes programadas',
            icon: Icons.list_alt,
            onTap: _consultandoNotifs ? null : _contarNotifs,
            subtitle: _notifsPendientes == null
                ? null
                : '$_notifsPendientes notificación(es) programada(s)',
          ),
          _Accion(
            label: 'Cancelar todas las programadas',
            icon: Icons.notifications_off_outlined,
            onTap: _cancelarTodas,
            destructive: true,
          ),

          const _Seccion('Rituales'),
          Container(
            margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            padding: const EdgeInsets.fromLTRB(14, 4, 8, 4),
            decoration: BoxDecoration(
              color: MatixColors.card,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.nightlight_outlined,
                    color: MatixColors.accent, size: 22),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Recordarme el cierre del día',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: MatixColors.text,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Aviso cada noche a las 21:30',
                        style: TextStyle(
                          fontSize: 12,
                          color: MatixColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _cierreDiarioActivo,
                  onChanged: _toggleEnCurso ? null : _toggleCierreDiario,
                ),
              ],
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
